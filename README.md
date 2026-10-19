# Skill Pre-Allocation

[![Rebuild and compare](https://github.com/barkovaz/skill-preallocation/actions/workflows/rebuild.yml/badge.svg)](https://github.com/barkovaz/skill-preallocation/actions/workflows/rebuild.yml)

A mod for **Total War: WARHAMMER III**. Plan your lords' and heroes' skill trees ahead of time: the
points are spent automatically, in your order, every time the character levels up.

- With no free skill points, left-click skills to pre-allocate them. Click the rank numbers on a card to
  remove a point.
- Presets for each lord or hero type, shared by all your campaigns.
- Plan mode: plan a whole build from rank 1, even on a character who has already learned skills.
- Every point follows the game's own rules: prerequisites, either/or choices, rank requirements, the
  rank cap.
- Works with mods that add or change skill trees, overhauls included, and with UI mods that change the
  skills panel.

**Steam Workshop:** https://steamcommunity.com/sharedfiles/filedetails/?id=3819368555

## About the DLL

To read skill trees from the game's files, vanilla and modded alike, the mod uses a small native module
of its own, `skill_preallocation_native.dll`, which it writes into your game folder. The DLL only reads
the game's mod list and pack files. It doesn't write files, use the internet, or hook or patch the game.
It isn't signed, so when Windows Smart App Control is on, it blocks the DLL; the mod then works with
vanilla skill trees only.

I know a DLL in a mod is unusual, so **[SECURITY.md](SECURITY.md)** explains exactly what it does, how
it gets there, and how to check it yourself, from a two-minute checksum to rebuilding it from this
source. It also explains how to turn it off.

Quick check: open PowerShell in the game folder and run `Get-FileHash skill_preallocation_native.dll`.
The hash must match your version's line in [SHA256SUMS.txt](SHA256SUMS.txt).

The badge at the top shows GitHub rebuilding the DLL and the pack from this source on every change, on
Windows and on Linux, and comparing them with `SHA256SUMS.txt`. Green means they match.

## What's in here

| Folder | What |
|---|---|
| [`src/`](src) | the mod: everything that goes into `skill_preallocation.pack` (Lua scripts, a UI layout, images, the DLL carried as data, and the licence notices) |
| [`native/`](native) | the native module's C source, plus the zstd decoder and Lua 5.1 headers it builds with |
| [`generator/`](generator) | build tools in Python: the DLL, the pack, the baked vanilla data, and `verify_native.py` (checks a DLL or pack against `SHA256SUMS.txt`) |
| [`tests/`](tests) | offline tests (Lua 5.1, Python) and the mock game they run against |
| [`docs/DESIGN.md`](docs/DESIGN.md) | how the mod works, in detail, and how to build and test it |

## Building

```
py -m pip install ziglang==0.13.0
py generator\build_native.py      # the DLL, carried in src/script/skill_preallocation/native_bin.lua
py generator\build_pack.py        # build/skill_preallocation.pack
```

Both print the SHA-256 of what they built. The rest (the baked data, the UI layout, the tests) is in
[docs/DESIGN.md](docs/DESIGN.md#build-install-test).

## Licence and credits

The mod is under the [MIT License](LICENSE).

The third-party code in [`native/vendor`](native/vendor) keeps its own licence: zstd's decoder (BSD, by
Meta) and the Lua 5.1 headers (MIT, by Lua.org, PUC-Rio). The pack carries their notices in
`script/skill_preallocation/LICENSES.txt`, since the DLL is built with them.

Thanks to [RPFM](https://github.com/Frodo45127/rpfm), whose schema the tools use to read the game's
tables, and to memreader Plus, where the idea of carrying a DLL inside a pack as a Lua file comes from.

Total War: WARHAMMER III and its data belong to Creative Assembly and SEGA. The baked vanilla skill data
in `src/` and the test fixtures are generated from the game's files, for use with the game.
