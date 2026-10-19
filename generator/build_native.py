"""Build the mod's native module (native/src) and put it into the mod.

  python generator/build_native.py            Windows DLL (for the game) -> build/native/skill_preallocation_native.dll,
                                              embedded in src/script/skill_preallocation/native_bin.lua
  python generator/build_native.py --test     the same code for this computer -> build/test/skill_preallocation_native.so
                                              (for tests/test_native.lua; needs gcc and the lua5.1f headers' Lua)

The Windows build uses Zig's C compiler, which cross-compiles from any system and needs no Visual
Studio:  pip install ziglang==0.13.0
The DLL links to nothing of the game's: it finds the game's Lua functions by name when it loads (they
are exported by Warhammer3.exe). Only Windows' own DLLs are imported (checked after the build).

The game loads the DLL from its own folder: native_bin.lua holds its bytes, and the mod's loader
(skill_preallocation_live.lua) writes them there as skill_preallocation_native.dll when the file is
missing or different, then loads it with package.loadlib. SECURITY.md has the whole story.

The build is reproducible: the same source and Zig 0.13.0 give the same DLL, byte for byte, on any
computer (the build time the linker writes is zeroed; no folder names are embedded).
"""
import argparse
import hashlib
import os
import shutil
import struct
import subprocess
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import verify_native  # noqa: E402

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
NATIVE = os.path.join(ROOT, "native")
SOURCES = ["spa_util.c", "spa_platform.c", "spa_packs.c", "spa_db.c", "spa_lua.c", "spa_dllmain.c"]
ZSTD = os.path.join(NATIVE, "vendor", "zstd", "zstddeclib.c")
INCLUDES = [os.path.join(NATIVE, "src"), os.path.join(NATIVE, "vendor", "lua-5.1"), os.path.join(NATIVE, "vendor", "zstd")]
MODULE = "skill_preallocation_native"
BIN_LUA = os.path.join(ROOT, "src", "script", "skill_preallocation", "native_bin.lua")
# Everything the DLL may import, all from Windows' own DLLs (ucrtbase.dll, the C runtime, comes with
# Windows 10 and later). SECURITY.md lists the same functions: the build stops if the DLL needs another.
ALLOWED_IMPORTS = {
    "ucrtbase.dll": {"malloc", "calloc", "realloc", "free", "qsort", "strlen", "strcmp", "strncmp", "strchr",
                     "__stdio_common_vsprintf"},
    "kernel32.dll": {"CreateFileW", "ReadFile", "SetFilePointerEx", "GetFileSizeEx", "CloseHandle",
                     "GetFileAttributesW", "FindFirstFileW", "FindNextFileW", "FindClose",
                     "GetModuleFileNameW", "GetCurrentDirectoryW", "GetCommandLineW",
                     "GetModuleHandleW", "GetProcAddress", "MultiByteToWideChar", "WideCharToMultiByte"},
}


def sources():
    return [os.path.join(NATIVE, "src", s) for s in SOURCES]


def flags():
    out = ["-O2", "-std=c99", "-Wall", "-Wextra", "-Wno-unused-parameter", "-Wno-implicit-fallthrough"]
    for inc in INCLUDES:
        out += ["-I", inc]
    return out


def run(cmd):
    print(" ".join(cmd))
    subprocess.check_call(cmd)


def write_bin_lua(dll_path, version):
    """native_bin.lua: the DLL as a Lua string (the format verify_native.py checks, from its bin_lua_text)."""
    data = open(dll_path, "rb").read()
    os.makedirs(os.path.dirname(BIN_LUA), exist_ok=True)
    with open(BIN_LUA, "wb") as f:
        f.write(verify_native.bin_lua_text(data, version))
    print(f"wrote {BIN_LUA}: {len(data)} bytes")
    print(f"SHA-256 of build/native/{MODULE}.dll: {hashlib.sha256(data).hexdigest()}")


def native_version():
    for line in open(os.path.join(NATIVE, "src", "spa_native.h"), encoding="utf-8"):
        if line.startswith("#define SPA_NATIVE_VERSION"):
            return line.split('"')[1]
    sys.exit("SPA_NATIVE_VERSION not found")


def build_windows():
    out_dir = os.path.join(ROOT, "build", "native")
    obj_dir = os.path.join(out_dir, "obj")
    os.makedirs(obj_dir, exist_ok=True)
    dll = os.path.join(out_dir, MODULE + ".dll")
    zig = [sys.executable, "-m", "ziglang", "cc", "-target", "x86_64-windows-gnu"]
    objs = []
    for src in sources() + [ZSTD]:
        obj = os.path.join(obj_dir, os.path.splitext(os.path.basename(src))[0] + ".obj")
        run(zig + ["-c"] + flags() + ["-o", obj, src])
        objs.append(obj)
    # Linked without MinGW-w64's C runtime (-nostdlib): its start-up code isn't in the DLL, the entry point
    # is the module's own (spa_dllmain.c), and the DLL imports only what the module calls, from Windows'
    # own ucrtbase.dll and kernel32.dll.
    run(zig + ["-shared", "-s", "-nostdlib", "-Wl,--entry,spa_dll_entry", "-o", dll] + objs
        + ["-lucrtbase", "-lkernel32"])
    shutil.rmtree(obj_dir)
    for name in os.listdir(out_dir):             # (import libraries the linker leaves behind)
        if name.endswith((".lib", ".pdb", ".exp")):
            os.remove(os.path.join(out_dir, name))
    # the same bytes for the same code (the linker writes the build time into the header): the DLL in the
    # game's folder is only rewritten when the module changes
    data = bytearray(open(dll, "rb").read())
    pe = struct.unpack_from("<I", data, 0x3C)[0]
    struct.pack_into("<I", data, pe + 8, 0)
    open(dll, "wb").write(bytes(data))
    _, imports, exports = verify_native.pe_tables(bytes(data))
    for library, functions in imports:
        print("imports from %s: %s" % (library, ", ".join(functions)))
    bad = [library + " " + f for library, functions in imports for f in functions
           if f not in ALLOWED_IMPORTS.get(library.lower(), ())]
    if bad:
        sys.exit("the DLL imports what SECURITY.md doesn't list (update both if that's intended): " + ", ".join(bad))
    print("exports:", ", ".join(exports))
    if "luaopen_" + MODULE not in exports:
        sys.exit("luaopen_" + MODULE + " is not exported")
    write_bin_lua(dll, native_version())


def build_test():
    out_dir = os.path.join(ROOT, "build", "test")
    os.makedirs(out_dir, exist_ok=True)
    so = os.path.join(out_dir, MODULE + ".so")
    cmd = ["gcc", "-g", "-fPIC", "-shared", "-DSPA_LUA_DIRECT"] + flags() + ["-o", so] + sources() + ["-x", "c", ZSTD]
    run(cmd)
    print("wrote", so)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--test", action="store_true", help="build for this computer, for the tests")
    a = ap.parse_args()
    if a.test:
        build_test()
    else:
        build_windows()


if __name__ == "__main__":
    main()
