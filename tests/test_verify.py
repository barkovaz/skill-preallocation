"""generator/verify_native.py against good and bad inputs: it must say "All good" only for the published
pack, DLL and native_bin.lua, and fail (without a traceback) for anything else.

Run from the project folder, after generator/build_native.py:  python tests/test_verify.py
It builds the pack from src/ the way build_pack.py does, in a temporary folder, with a checksum list
that names it (as the release's SHA256SUMS.txt will).
"""
import hashlib
import os
import shutil
import struct
import subprocess
import sys
import tempfile

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.join(ROOT, "generator"))
import tw_pack  # noqa: E402
import verify_native  # noqa: E402
import build_pack  # noqa: E402

BIN = "script/skill_preallocation/native_bin.lua"
passed = failed = 0


def check(cond, msg):
    global passed, failed
    if cond:
        passed += 1
    else:
        failed += 1
        print("FAIL: " + msg)


def src_files():
    return build_pack.collect(os.path.join(ROOT, "src"))


def raw_pack(path, entries, magic=b"PFH5"):
    """A pack written by hand: entries [(path, data)] in this order (duplicates allowed)."""
    index = bytearray()
    for p, d in entries:
        index += struct.pack("<I", len(d)) + (b"\0" if magic == b"PFH5" else b"") + p.encode("latin-1") + b"\0"
    with open(path, "wb") as f:
        f.write(magic + struct.pack("<6I", 3, 0, 0, len(entries), len(index), 0) + index + b"".join(d for _, d in entries))


def main():
    tmp = tempfile.mkdtemp(prefix="spa_verify_")
    try:
        files = src_files()
        good_bin = files[BIN]
        dll, version = verify_native.from_bin_lua(good_bin)
        good = os.path.join(tmp, "skill_preallocation.pack")
        tw_pack.write_mod_pack(good, files, timestamp=build_pack.PACK_TIME)
        pack_sha = hashlib.sha256(open(good, "rb").read()).hexdigest()
        dll_sha = hashlib.sha256(dll).hexdigest()
        sums = os.path.join(tmp, "SHA256SUMS.txt")
        with open(sums, "w") as f:
            f.write("# test\ndll 0.19.0 %s %s\npack 0.19.0 %s\n" % (version, dll_sha, pack_sha))
        tool = os.path.join(ROOT, "generator", "verify_native.py")

        def verdict(*args, sums_file=sums):
            cmd = [sys.executable, tool] + list(args) + (["--sums", sums_file] if sums_file else [])
            r = subprocess.run(cmd, capture_output=True, text=True)
            out = r.stdout + r.stderr
            return r.returncode == 0 and "All good" in out, out

        def path(name):
            return os.path.join(tmp, name)

        # the published files
        dll_file = path("skill_preallocation_native.dll")
        open(dll_file, "wb").write(dll)
        open(path("native_bin.lua"), "wb").write(good_bin)
        for f in (good, dll_file, path("native_bin.lua")):
            ok, out = verdict(f)
            check(ok and "Traceback" not in out, "the published " + os.path.basename(f) + " is all good:\n" + out)
        ok, out = verdict(good, "--extract", path("out.dll"))
        check(ok and open(path("out.dll"), "rb").read() == dll, "--extract writes the DLL carried in the pack")
        # the same pack built twice: the same bytes (the header's time is fixed)
        again = path("again.pack")
        tw_pack.write_mod_pack(again, files, timestamp=build_pack.PACK_TIME)
        check(open(again, "rb").read() == open(good, "rb").read(), "the pack builds to the same bytes")

        bad = {}
        # one byte of the DLL changed, in the DLL file and in native_bin.lua (with its checksum fields made to fit)
        evil = bytearray(dll)
        evil[5000] ^= 1
        evil = bytes(evil)
        open(path("evil.dll"), "wb").write(evil)
        bad["a changed DLL"] = path("evil.dll")
        open(path("evil_bin.lua"), "wb").write(verify_native.bin_lua_text(evil, version))
        bad["native_bin.lua with a changed DLL"] = path("evil_bin.lua")
        fs = dict(files)
        fs[BIN] = verify_native.bin_lua_text(evil, version)
        tw_pack.write_mod_pack(path("evil_dll.pack"), fs, timestamp=build_pack.PACK_TIME)
        bad["a pack with a changed DLL"] = path("evil_dll.pack")
        # decoys: the genuine file in a comment, then another DLL
        evil_text = verify_native.bin_lua_text(evil, version)
        decoy = b"--[==[\n" + good_bin + b"]==]\n" + evil_text.split(b"\n", 3)[3]
        open(path("decoy_bin.lua"), "wb").write(decoy)
        bad["native_bin.lua with the genuine file in a comment"] = path("decoy_bin.lua")
        ret = [l for l in good_bin.split(b"\n") if l.startswith(b"return")][0]
        decoy2 = b"-- " + ret + b"\n" + evil_text.split(b"\n", 3)[3]
        open(path("decoy2_bin.lua"), "wb").write(decoy2)
        bad["native_bin.lua with the genuine data in a line comment"] = path("decoy2_bin.lua")
        fs = dict(files)
        fs[BIN] = decoy
        tw_pack.write_mod_pack(path("decoy.pack"), fs, timestamp=build_pack.PACK_TIME)
        bad["a pack with a decoy native_bin.lua"] = path("decoy.pack")
        appended = good_bin + b"os.execute('calc')\n"
        open(path("appended_bin.lua"), "wb").write(appended)
        bad["native_bin.lua with code added"] = path("appended_bin.lua")
        # a pack whose loader script was changed (the DLL genuine)
        fs = dict(files)
        fs["script/campaign/mod/skill_preallocation_live.lua"] += b"\n-- changed\n"
        tw_pack.write_mod_pack(path("changed_script.pack"), fs, timestamp=build_pack.PACK_TIME)
        bad["a pack with a changed script (genuine DLL)"] = path("changed_script.pack")
        # the module twice, missing, or moved
        entries = sorted(((p.replace("/", "\\"), d) for p, d in files.items()), key=lambda x: x[0].lower())
        dup = []
        for p, d in entries:
            dup.append((p, d))
            if p.replace("\\", "/") == BIN:
                dup.append((p, evil_text))
        raw_pack(path("duplicate.pack"), dup)
        bad["a pack with the module twice"] = path("duplicate.pack")
        raw_pack(path("missing.pack"), [(p, d) for p, d in entries if p.replace("\\", "/") != BIN])
        bad["a pack without the module"] = path("missing.pack")
        raw_pack(path("moved.pack"), [(p.replace("native_bin", "other_bin"), d) for p, d in entries])
        bad["a pack with the module moved"] = path("moved.pack")
        raw_pack(path("slashes.pack"), [(p.replace("\\", "/"), d) for p, d in entries])
        bad["a pack written with / (not the published bytes)"] = path("slashes.pack")
        raw_pack(path("pfh4.pack"), entries, magic=b"PFH4")
        bad["a PFH4 pack (not the published bytes)"] = path("pfh4.pack")
        # broken input
        data = open(good, "rb").read()
        open(path("truncated.pack"), "wb").write(data[:len(data) // 2])
        bad["a pack cut short"] = path("truncated.pack")
        open(path("truncated_bin.lua"), "wb").write(good_bin[:len(good_bin) // 2])
        bad["native_bin.lua cut short"] = path("truncated_bin.lua")
        open(path("empty"), "wb").close()
        bad["an empty file"] = path("empty")
        bad["a file that isn't there"] = path("not_there.dll")
        for what, f in bad.items():
            ok, out = verdict(f)
            check(not ok and "Traceback" not in out, what + " must fail, without a traceback:\n" + out[-600:])
        # the PFH4 pack is still read: the module in it is recognised
        ok, out = verdict(path("pfh4.pack"))
        check("MATCHES" in out and "the native module" in out, "a PFH4 pack is read:\n" + out)
        # several files: one bad one makes the whole run fail, and the others are still checked
        ok, out = verdict(good, path("evil.dll"), dll_file)
        check(not ok and out.count("MATCHES") >= 3, "a bad file among good ones fails the run, the others still checked:\n" + out)
        # nothing to compare with: fail
        alone = path("alone/inside")              # (a folder whose parent has no SHA256SUMS.txt either)
        os.makedirs(alone)
        shutil.copy(tool, alone)
        r = subprocess.run([sys.executable, os.path.join(alone, "verify_native.py"), dll_file], capture_output=True, text=True)
        check(r.returncode != 0 and "Can't check" in (r.stdout + r.stderr), "without SHA256SUMS.txt it can't say all good:\n" + r.stdout + r.stderr)
        other = path("other_format.txt")
        open(other, "w").write("%s  skill_preallocation_native.dll\n" % dll_sha)
        ok, out = verdict(dll_file, sums_file=other)
        check(not ok and "Can't check" in out, "a checksum file of another format can't vouch for anything:\n" + out)
        ok, out = verdict(dll_file, sums_file=path("nothere.txt"))
        check(not ok, "a --sums file that isn't there fails")
        # the repository's own SHA256SUMS.txt names the DLL that src/ carries
        ok, out = verdict(path("native_bin.lua"), sums_file=os.path.join(ROOT, "SHA256SUMS.txt"))
        check(ok, "SHA256SUMS.txt names the DLL in src/ (run build_native.py and update it):\n" + out)
    finally:
        shutil.rmtree(tmp)
    print("%d passed, %d failed" % (passed, failed))
    sys.exit(1 if failed else 0)


if __name__ == "__main__":
    main()
