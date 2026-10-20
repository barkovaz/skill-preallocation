# The native module: what it is, and how to check it

Skill Pre-Allocation comes with a small Windows DLL, `skill_preallocation_native.dll`. I know a DLL in
a mod is unusual, and you shouldn't have to take my word for it, so this page explains why it's there,
exactly what it does, and how to check it yourself.

## In short

- It **reads**:
  - the game's mod list;
  - the game's `.pack` files (their file lists and ten skill tables).
- It **doesn't**:
  - write, change or delete any file;
  - use the network;
  - start programs, touch the registry, or hook or patch the game.

  Windows' functions for those things are neither in its import table nor looked up while it runs
  ([what it uses](#every-windows-function-it-uses), [check 4](#check-4-see-what-it-links-to-and-looks-up)).
- The mod loads it only inside the game, when a campaign starts.
- Its source code is in [`native/src`](native/src). The build is reproducible: you can rebuild it, and the
  whole pack, and get the very same files. GitHub does that on every change, on Windows and on Linux
  ([check 3](#check-3-rebuild-it-from-the-source)).
- The SHA-256 checksums of the DLL and the pack are in [`SHA256SUMS.txt`](SHA256SUMS.txt).
- You can [turn it off](#turning-it-off). The mod then uses the vanilla skill data it carries.

## Why there is a DLL

The game's mod scripts (Lua) can see a character's skills, but not the rules of a skill tree:
- which skills a skill needs before it;
- which skills lock each other out;
- the rank each level needs;
- how many points each rank gives.

Those rules are in the game's database tables, inside its compressed `.pack` files. That's also where
other mods put their changes to skill trees. The game gives its scripts no way to read those tables.
Reading the pack files directly isn't practical from its Lua either: the tables are compressed, and its
numbers are 32-bit floats, which can't hold the sizes and positions inside a large file exactly.

So the mod has a small module of its own, in C, that reads those tables.

Without it, the mod works from a copy of the vanilla rules made in advance, which it carries as the
fallback. Skill trees that other mods add or change can't be planned then.

## How it gets onto your PC

1. The mod's pack, `skill_preallocation.pack`, carries the DLL as data.
   `script/skill_preallocation/native_bin.lua` holds its bytes as a Lua string, together with its version,
   size and SHA-256. The game doesn't run that file by itself, and nothing runs the DLL until step 4.
2. When a campaign starts (about six seconds after its first tick, or sooner if you open a skills panel
   first), `LIVE.load_native()` in
   [`src/script/campaign/mod/skill_preallocation_live.lua`](src/script/campaign/mod/skill_preallocation_live.lua)
   reads that file with the game's own file loader.
3. If `skill_preallocation_native.dll` in the game folder (next to `Warhammer3.exe`) is missing or
   different, the loader writes it there, then reads it back to check.
4. It loads that file with `package.loadlib(".\skill_preallocation_native.dll", ...)`, or with `require` if
   that doesn't work. It doesn't leave the module in Lua's list of loaded modules.
5. It writes `skill_preallocation_native.txt` next to the DLL. This short note says what the DLL is and
   where this page is, and gives its state and the checksum the pack gives for it.

The mod doesn't write or load the DLL at all in these cases. At most, it updates the state in
`skill_preallocation_native.txt`.
- On the game's macOS version, which can't load a Windows DLL.
- While `skill_preallocation_no_native.txt` is in the game folder ([turning it off](#turning-it-off)).
- Once the DLL has been removed after the mod wrote it, or couldn't be written
  ([see below](#if-your-antivirus-removed-it)).
- Once it has been changed after the mod wrote it, or Windows refused to load it
  ([Smart App Control](#if-windows-smart-app-control-blocked-it), for example), until a mod update brings
  a new DLL.

## What the DLL does

When loaded, it asks Windows for the addresses of the game's Lua functions, by name (`GetProcAddress` on
`Warhammer3.exe`, which exports them as any Lua host must for C modules). That's 22 names, all `lua_...`,
listed in [`native/src/lua_api.h`](native/src/lua_api.h). It then gives the mod two functions:

- `mod_list()`: the packs the game loaded. It reads them from the mod list named on the game's command
  line, or from `used_mods.txt` in the game folder, and from the folders that list names
  (`add_working_directory`).
- `load_db(tables)`: the rows of the skill tables the mod asks for. It reads them from those packs, the
  game's own `db.pack` and its movie packs, and merges them the way the game does.

### The files it opens

All of them are opened read-only:
- the mod list;
- the `.pack` files the mod list names, the game's `db.pack`, and its movie packs: their file lists and
  ten skill tables;
- the first 8 bytes of every other `.pack` in the game's `data` folder, to find the movie packs the game
  loads without a mod list entry.

`mod_list()` and `load_db()` also take options that the offline tests use to point them at test folders:
`packs`, `game_dir`, `command_line` and `cwd`. The mod never passes them. Any Lua script could use them
to have the DLL read other files, read-only, which the game's Lua can already do with `io.open`.

### Every Windows function it uses

This is its whole import table:

| From | Functions | What for |
|---|---|---|
| `KERNEL32.dll` | `CreateFileW`, `ReadFile`, `SetFilePointerEx`, `GetFileSizeEx`, `CloseHandle`, `GetFileAttributesW`, `FindFirstFileW`, `FindNextFileW`, `FindClose` | open and read files, list the `data` folder |
| `KERNEL32.dll` | `GetModuleFileNameW`, `GetCurrentDirectoryW`, `GetCommandLineW` | find the game's folder and its mod list |
| `KERNEL32.dll` | `GetModuleHandleW`, `GetProcAddress` | find the game's Lua functions |
| `KERNEL32.dll` | `MultiByteToWideChar`, `WideCharToMultiByte` | convert file names between UTF-8 and Windows' UTF-16 |
| `ucrtbase.dll`, Windows' C runtime | `malloc`, `calloc`, `realloc`, `free`, `qsort`, `strlen`, `strcmp`, `strncmp`, `strchr`, `__stdio_common_vsprintf` (behind `snprintf`) | memory, sorting, text |

There's no function in it to write or delete files (`WriteFile`, `DeleteFileW`), no network library, no
process or memory function (`CreateProcessW`, `VirtualProtect`, `ReadProcessMemory`), and nothing for the
registry. `CreateFileW` is also how Windows opens files for reading. The module opens only existing files,
for reading: `GENERIC_READ` and `OPEN_EXISTING` in [`native/src/spa_platform.c`](native/src/spa_platform.c).
The build stops if the DLL would import anything not in this table
([`generator/build_native.py`](generator/build_native.py)).

A DLL can also look up a function by name while it runs, as this one does with `GetProcAddress`. It does
that only for the game's 22 Lua functions, in `Warhammer3.exe`
([`native/src/spa_lua.c`](native/src/spa_lua.c)). No other Windows function name is in the file
([check 4](#check-4-see-what-it-links-to-and-looks-up)).

The import table is a quick check, but not the whole proof. Native code could also find Windows'
functions without importing or naming them, by walking Windows' own tables in memory, as malware does.
The source shows this module doesn't, and [check 3](#check-3-rebuild-it-from-the-source) proves the DLL
is built from that source. The only code in it that isn't in this repository is the compiler's own:
Zig 0.13.0 adds `memcpy`, `memmove`, `memset` and `memcmp` from its runtime library (compiler-rt).

## The files in your game folder

| File | What it is |
|---|---|
| `skill_preallocation_native.dll` | The module. Written by the mod on the first campaign start; rewritten only when an update changes it. |
| `skill_preallocation_native.txt` | The mod's note about it. It says what the DLL is and links to this page. It gives the module's version, the checksum the pack gives for the DLL, and a state: `written`, `removed`, `changed`, `blocked` (couldn't be written), `refused` (Windows didn't load it) or `off`. |
| `skill_preallocation_no_native.txt` | Only if you make it: [turns the module off](#turning-it-off). |

The other two files are not new: `skill_preallocation_presets.lua` holds your presets, and
`skill_preallocation_log.txt` is the log the mod writes when something goes wrong. It also writes the log
on each campaign start while the module is off, to say why.

## Check it yourself

### Check 1: the DLL's checksum (two minutes, nothing to install)

1. In Steam, right-click Total War: WARHAMMER III, then **Manage**, then **Browse local files**. This
   opens the game folder.
2. Click the folder's address bar, type `powershell` and press Enter. A PowerShell window opens in that
   folder.
3. Type `Get-FileHash skill_preallocation_native.dll` and press Enter.
4. Compare the long code under **Hash** with the `dll` line in [`SHA256SUMS.txt`](SHA256SUMS.txt). It
   must be identical; upper or lower case doesn't matter. The line also gives the mod version (shown on
   the Workshop page) and the native module version (written in `skill_preallocation_native.txt`).

Or let PowerShell compare it with the list on GitHub. This prints `True` when the checksum is in it:
```
(Invoke-WebRequest -UseBasicParsing https://raw.githubusercontent.com/barkovaz/skill-preallocation/main/SHA256SUMS.txt).Content -match (Get-FileHash skill_preallocation_native.dll).Hash
```
In Command Prompt instead of PowerShell: `certutil -hashfile skill_preallocation_native.dll SHA256`.

If it doesn't match:
1. Create `skill_preallocation_no_native.txt` in the game folder, or disable the mod in the launcher. If
   you skip this step, the mod would write its DLL again.
2. Delete `skill_preallocation_native.dll` and `skill_preallocation_native.txt`.
3. [Report it](#reporting-a-concern).

### Check 2: the Workshop download, before you play

[`generator/verify_native.py`](generator/verify_native.py) checks the whole pack the Workshop gave you,
and the DLL inside it, without running anything.
- **The pack:** if its checksum matches a published `pack` line, every file in it is the published one,
  including the loader script.
- **The DLL inside:** it must be exactly the published DLL, written exactly as the build writes it.

It's a short script that needs Python 3 ([python.org](https://www.python.org/downloads/)) and nothing
else; read it first if you like.

1. Open PowerShell in an empty folder (as in check 1) and download the script and the checksum list:
   ```
   Invoke-WebRequest -UseBasicParsing https://raw.githubusercontent.com/barkovaz/skill-preallocation/main/generator/verify_native.py -OutFile verify_native.py
   Invoke-WebRequest -UseBasicParsing https://raw.githubusercontent.com/barkovaz/skill-preallocation/main/SHA256SUMS.txt -OutFile SHA256SUMS.txt
   ```
2. Run it on the pack:
   ```
   py verify_native.py "C:\Program Files (x86)\Steam\steamapps\workshop\content\1142710\3819368555\skill_preallocation.pack"
   ```
   If your Steam library is elsewhere, use that path. `3819368555` is this mod's Workshop item. If `py`
   isn't found, try `python`.
3. It prints:
   - the pack's checksum and the checksum of the DLL in it, and whether each is published;
   - every Windows function the DLL imports, and the names it can look up while running.

   It ends with `All good` only when everything matches.

The DLL in your game folder can be checked the same way:
```
py verify_native.py "C:\Program Files (x86)\Steam\steamapps\common\Total War WARHAMMER III\skill_preallocation_native.dll"
```
With `--extract mymodule.dll` it writes the DLL carried in the pack out as a file, to look at it with
other tools ([check 4](#check-4-see-what-it-links-to-and-looks-up)).

### Check 3: rebuild it from the source

You get the identical DLL and the identical pack, byte for byte.

1. Install Python 3. For the source, install [Git](https://git-scm.com/downloads), or download the code
   as a ZIP (on this repository's page: **Code**, then **Download ZIP**) and unpack it.
2. In PowerShell (with the ZIP, open PowerShell in the unpacked folder and skip the first two lines):
   ```
   git clone https://github.com/barkovaz/skill-preallocation
   cd skill-preallocation
   py -m pip install ziglang==0.13.0
   py generator\build_native.py
   py generator\build_pack.py
   ```
   `ziglang` is the [Zig](https://ziglang.org) compiler packaged for pip, so no Visual Studio is needed.
   The build takes about a minute.
3. The two builds print their results' SHA-256:
   - `build_native.py` for `build\native\skill_preallocation_native.dll`;
   - `build_pack.py` for `build\skill_preallocation.pack`.

   Compare them with the `dll` and `pack` lines of `SHA256SUMS.txt`. `build_native.py` also rewrites
   `src\script\skill_preallocation\native_bin.lua`, the copy the pack carries, so a matching pack checksum
   also means that copy is your build.

The files come out identical for three reasons:
- the build zeroes the time the linker writes into the DLL;
- the pack's header has a fixed time;
- the DLL embeds no folder names.

The same source and the same compiler version give the same bytes.

GitHub runs the same rebuild on every change, on Windows and on Linux, and compares both files with
`SHA256SUMS.txt` ([`.github/workflows/rebuild.yml`](.github/workflows/rebuild.yml)). Its runs are public
under the repository's [Actions](https://github.com/barkovaz/skill-preallocation/actions) tab, and each
keeps the files it built for a while.

### Check 4: see what it links to and looks up

`py verify_native.py <the DLL>` lists:
- its whole import table: every Windows function it uses;
- the one function it offers;
- the names it can look up while running: the game's 22 Lua functions;
- any other Windows-style function name it finds in the file: none.

To see the same with another tool, any PE viewer works: `dumpbin /imports` (Visual Studio) or
[PE-bear](https://github.com/hasherezade/pe-bear). For every text in the file, use
[Sysinternals Strings](https://learn.microsoft.com/sysinternals/downloads/strings). You should see exactly
the table in [every Windows function it uses](#every-windows-function-it-uses).

The DLL is linked without the usual C runtime start-up code and has its own, empty entry point
([`native/src/spa_dllmain.c`](native/src/spa_dllmain.c)). That's why its import table holds only what the
module's code calls, and nothing a compiler adds on its own.

### Check 5: read the code

- **The loader (Lua):** `LIVE.load_native` in
  [`src/script/campaign/mod/skill_preallocation_live.lua`](src/script/campaign/mod/skill_preallocation_live.lua).
- **The module (C):** [`native/src`](native/src).
  - `spa_lua.c`: what the mod can call, and the look-up of the game's Lua functions.
  - `spa_packs.c`: the mod list and the packs.
  - `spa_db.c`: reading and merging the tables.
  - `spa_platform.c`: files. Its POSIX half is only for the offline tests.
  - `spa_dllmain.c`: the entry point.
  - `spa_util.c`: helpers.
  - `spa_schema.h`: the table layouts, generated.
- **Third party:** [`native/vendor`](native/vendor) holds zstd's decoder 1.5.6 (BSD licence), used to
  decompress the game's tables, and the Lua 5.1 headers (MIT licence).

## Turning it off

Create an empty file named `skill_preallocation_no_native.txt` in the game folder, next to
`Warhammer3.exe`. Windows often hides the `.txt` ending, so a file that shows as
`skill_preallocation_no_native` works too, and so does `skill_preallocation_no_native.txt.txt`.

The mod then never writes or loads the DLL. Make the file before your first campaign start with the mod,
and the DLL is never written at all. If it was written already, you can now delete
`skill_preallocation_native.dll`.

What changes: the mod uses its built-in vanilla skill data, so skill trees that other mods add or change
can't be planned. Points you already planned on those mods' skills stay in the plan, and are learned once
the module is back.

To turn the module back on, delete the file. The mod writes the DLL again if it's missing.

## If your antivirus removed it

The mod notices when the DLL it wrote is removed, changed, or couldn't be written, and doesn't write it
again, so you don't get the same alert every session:
- a removed DLL, or one that couldn't be written, stays off until you act;
- a changed DLL is left as it is until a mod update brings a new one.

Meanwhile the mod runs with vanilla skill data, and its log says why.

To get the DLL back after checking it:
1. Restore it from quarantine and allow it in your antivirus.
2. Or delete `skill_preallocation_native.txt`, and the mod writes the DLL again on the next campaign
   start.

## If Windows Smart App Control blocked it

Smart App Control, in Windows 11, blocks files that aren't signed, unless Microsoft's cloud service
already knows them as safe. This DLL isn't signed: a certificate is too big a yearly expense for a mod. So
while Smart App Control is on, Windows refuses to load the DLL and says it blocked part of the game.
Smart App Control has no exceptions for single files.

The mod then works as when it's [turned off](#turning-it-off), says why in its log, and doesn't try that
DLL again until a mod update brings a different one. If you turn Smart App Control off later, delete
`skill_preallocation_native.txt` from the game folder, and the mod tries again on the next campaign start.

## Unsubscribing

Removing the mod leaves `skill_preallocation_native.dll` and `skill_preallocation_native.txt` in the game
folder. Nothing uses them any more, and you can delete both.

## Reporting a concern

[Open an issue](https://github.com/barkovaz/skill-preallocation/issues) here, or comment on the
[Workshop page](https://steamcommunity.com/sharedfiles/filedetails/?id=3819368555). If a checksum didn't
match, say where the file came from and paste the checksum you got.

## The published files

[`SHA256SUMS.txt`](SHA256SUMS.txt) is the reference list, and
[`generator/verify_native.py`](generator/verify_native.py) reads it.

| Mod | Native module | SHA-256 of `skill_preallocation_native.dll` | SHA-256 of `skill_preallocation.pack` |
|---|---|---|---|
| 0.19.2 | 1.1.0 | `40cd6888a3c4f813e9bd7dfe0429b2539ea15f39a9a023800ba96b5381fbe2b9` | `6d91b82e677b4f4c69a6ffeabaeb59c54c9ecf59f7d080d3cea31eac620d4182` |
