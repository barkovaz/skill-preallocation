# Skill Pre-Allocation: how it works

The technical description of the mod, version 0.19.2: what the player sees, how the code works, the game
facts it relies on, and how to build and test it. The native module's safety, and how to check it, is in
[SECURITY.md](../SECURITY.md).

Plan a lord's or hero's skill tree ahead of time. While a character has no free skill points,
left-clicking a skill in the normal skill tree **pre-allocates** it. At every rank-up the new points are
spent on those skills, in order, each as soon as it comes, through the game's own skill system and with
the same rules as a normal allocation. **Plan mode** is a neutral planning view: the character type's tree
as at rank 1 with nothing learned, where every click plans, free points or not (also on a character whose
tree is half or fully learned).

It reads the skill rules from the packs the game loaded, vanilla and mods, through its native module, and
replaces no game file. Tested offline and in game in October 2026, in single player, with Mixer, Cheat
Menu, No Random Backgrounds, [Ui] Clean Skill Trees and Expanded Hero Skill Trees. Multiplayer is built
for but untested.

## The main parts

- **Live skill rules.** The rules come from the packs the game actually loaded: vanilla `db.pack` and every
  mod in the launcher's mod list, merged the way the game merges them. Lords and heroes from other mods,
  overhauls that change trees, mods that change rank caps or points per rank: all plannable, with their
  real prerequisites, "N points in these" rules, variant locks and rank requirements. Vanilla trees stay
  right after a game patch too, without rebuilding the mod. The game's scripts can't read these rules
  (the context system gives a character's skills, parents and levels, but not the rule behind a link, the
  locks or the points per rank), so a small native module of the mod's own reads them from the pack files.
- **No game file replaced.** The skills panel layout is the game's (or a UI mod's). What the mod adds to
  the panel, its script makes on the panel the game builds:
  - the badges on the skill cards (the ranks of the planned points): a click on one removes a point (the
    badge takes the click, the game's card doesn't see it);
  - plan mode's shields: made on each card from the mod's own layout file
    (`ui/skill_preallocation/spa_shield`), sized to the card and placed over its level pips, with the
    card's skill given by `SetContextObject`.
- **The native module** (`native/`, C, built into `skill_preallocation_native.dll`): used by this mod only
  (no global, not left in `package.loaded`). It ships the way memreader Plus ships its DLL (the DLL's bytes
  in a Lua file of the pack, written into the game's folder when missing or different) and is loaded from
  that very file with `package.loadlib` (else `require`). It only reads files: it never
  reads or changes the game's memory or code, so a game patch can't break it the way it breaks memory
  offsets or code patterns. It finds the game's Lua functions by name in `Warhammer3.exe` (which exports
  them) when it loads. Once written it isn't written again if it goes missing (an antivirus, the player),
  and `skill_preallocation_no_native.txt` in the game's folder turns it off: see
  [SECURITY.md](../SECURITY.md).
- **Fallback.** Without the module (the game's macOS version, Windows or an antivirus blocking the DLL,
  the player turning it off, a table layout it doesn't know) the mod works from the vanilla data baked
  into it (`skill_preallocation_data.lua`), so trees that other mods add or change can't be planned. A
  plan made with the live data keeps its points on skills the baked data doesn't know (another mod's):
  they wait for the live data. The log says why.
- **Multiplayer**: the spend messages carry skill keys (`spa2|spend|<cqi>||<key>`), not positions in the
  baked data, since two players' games may read the rules from different sources.

## What the player sees

- **Pre-allocate:** with 0 free points, left-click a skill. Its card gets a badge with the rank it will
  be learned at, in yellow (`7`; one number per planned level, e.g. `7 12 15`). A point the free points
  already cover (*Allocate now* learns it) shows its place in the order instead, in green: `1`, `2`, `3`…
  (e.g. after loading a preset on a lord recruited at rank 14).
- **Strict order:** a skill can only be pre-allocated where its point comes at its rank or later (before
  that the click does nothing; the game's tooltip shows the rank it needs). So the points are always
  learned in the order planned, each as soon as it comes, and none is left unspent while pre-allocations
  remain: no "unspent skill points" reminder to ignore. A character with nothing (left) pre-allocated
  gets the game's reminder as usual.
- **Remove:** a left click on a skill's badge (its numbers) removes its last pre-allocated point, with or
  without free points, in plan mode too; the badge's tooltip says so. The badge takes the click, so the
  game's card doesn't see it. Learned points are never touched. Right-click stays the game's own (it opens
  the spell book on spells).
- **With free points** the tree works as normal (the game's own allocation, applied when the panel
  closes); the mod counts those choices while you keep planning. To plan instead, use plan mode.
- **Plan mode** (the first round button, an on/off button): a neutral planning view, where nothing of the
  character is shown or used. The tree looks like the character type's tree at rank 1 with nothing learned:
  every card in the game's locked look, planned skills too (their badges show the plan), a mount in its
  "unlocks at rank" look, no learned ticks, no sparkles. The build (a draft) starts empty,
  or as a preset picked in the dropdown. Every left click adds a point to it, even with free points: a
  transparent shield over each card takes the click, so the game's card doesn't react (no choice, no
  animation). Its tooltip is neutral too: the skill's name, description and the effects of its first
  level, from the game's database (nothing the character learned), and under the description the rank it
  asks for in the game's own words ("Available at rank 10." in red, or "Automatically granted at rank 10."
  for a mount), as the game shows it to a character of a lower rank; should the game not make that, it
  shows the skill as on the character rather than nothing. The small level circles on the card's right
  keep tooltips of their own, each for its level ("<skill> (2)": the effects at level 2, and the rank that
  level asks for), and a click on them plans like one on the card. There is no stats preview in plan mode (the game computes it for the
  character's real next level). A click on a badge removes a point (the badges lie above the shields), Clear empties the draft,
  New/Overwrite save it. Badges show the rank each point comes at from rank 1 (never green: there is no
  "now" in a build from rank 1). Leaving plan mode (the button, closing the panel, showing another
  character) with a build in the draft turns it into the pre-allocations the way a preset is loaded:
  learned points are skipped, a variant the character can't take any more is mapped onto the one it
  owns, free points go with *Allocate now* or the next rank-up. Leaving with an empty draft changes
  nothing. After the game's *Reset all skills* in plan mode the character is read again before that, so
  the whole build gets pre-allocated. Choices made with free points before plan mode stay chosen (the
  game learns them when the panel closes). Allocate now is off in plan mode. The cards get their own looks
  back when plan mode ends.
- **Rules:** every pre-allocated point must be a legal allocation when it is learned: prerequisites (all
  required parents, or N points in the skills before it), variants that lock each other out, max levels,
  points left before the rank cap. Impossible plans can't be made. Rank requirements decide *where*: a
  point's rank must be reached by the time its point comes (see *Strict order*); a skill above the rank
  cap can't be planned. (A skill point granted without a rank-up can come before the next skill's rank:
  then that point waits for it, the order kept.)
- **Spending** happens only (a) when the character gains skill points (a rank-up) and (b) when the player
  clicks *Allocate now*. Each time every point that can be spent goes out at once, in plan order.
  Closing the panel, turn start and loading a game spend nothing. The
  panel's own *Undo assigned skill points* button drops choices made with free points; the
  pre-allocations follow at once (one planned on top of such a choice is re-checked).
- **Presets row** at the top right of the skill tree (under the skill points counter): a dropdown and
  seven round buttons.
  - The dropdown shows the selected preset, *Select preset*, or *No presets* (greyed out). Its list holds
    this character type's presets (the selected one marked `> `); picking one replaces the
    pre-allocations with it and makes it the selected preset.
  - Buttons, left to right (the game's own icons): *Plan mode* (pencil, on/off), *Save as new preset*
    (+, asks a name), *Overwrite the selected preset*, *Rename the selected preset* (asks a name), *Delete
    the selected preset*, *Clear pre-allocations* (x), *Allocate now* (tick; tooltip "Allocate N points
    now"). A button is greyed out when it can't be used: Plan mode needs a skill tree the rules know;
    New needs a build (pre-allocations or learned skills; in plan mode the draft); Overwrite needs a
    selected preset and a build; Clear needs pre-allocations (in plan mode the draft); Rename and Delete
    need a selected preset; Allocate now needs free points the plan can use and is off in plan mode.
    Overwrite, Delete, Clear and Allocate now ask first (the game's yes/no dialog).
- **Presets** are per character type (agent subtype), shared by all campaigns, stored in
  `skill_preallocation_presets.lua` in the game folder. A preset is the whole build (learned points in
  order + pre-allocations); loading it skips what the character already has, and if the character took
  the other side of a variant choice the preset follows that side.
- After *Allocate now* the open panel is redrawn (the game doesn't redraw points a script spends).
- All texts in the game's 13 languages. Pre-allocations are saved with the campaign. The game's skill
  reset clears that character's pre-allocations (the preset link stays). Removing the mod changes
  nothing in a save: pre-allocations are forgotten, presets stay in their file.
- **Personal:** pre-allocations and presets belong to the player who made them. In multiplayer nothing
  about them is sent to the other player; only the skill points spent reach both games.

## Folder layout

| Path | What |
|---|---|
| `src/script/campaign/mod/` | the mod's six scripts (see below) |
| `src/script/skill_preallocation/LICENSES.txt` | the licence notices the pack carries: the mod's, and those of the third-party code built into the DLL (zstd's BSD licence requires its notice with every copy of the binary) |
| `src/script/skill_preallocation/native_bin.lua` | the native module's DLL as a Lua string (made by `generator/build_native.py`; not run when the campaign loads, read by the loader) |
| `src/ui/skill_preallocation/spa_shield.twui.xml` | plan mode's shield, the mod's own layout (made by `generator/build_ui.py` from the game's skill card) |
| `src/ui/skins/default/spa_dropdown_*.png` | the dropdown's images (made by `generator/build_dropdown_art.py`) |
| `native/src/` | the native module in C: `spa_lua.c` (what Lua sees), `spa_packs.c` (mod list, packs, table files), `spa_db.c` (reading and merging tables), `spa_platform.c` (files; Windows, and POSIX for the tests), `spa_dllmain.c` (the DLL's entry point), `spa_util.c`, `lua_api.h` (the game's Lua functions, found by name), `spa_schema.h` (table layouts, generated) |
| `native/vendor/` | Lua 5.1 headers with 32-bit float numbers like the game's (MIT, from memreader Plus), zstd's decoder 1.5.6 (BSD, its `LICENSE` there) |
| `generator/` | Python tools: `tw_pack.py` (read/write .pack files), `tw_db.py` + `ron.py` + `schema_wh3.ron` (read db tables; the schema is [RPFM's](https://github.com/Frodo45127/rpfm-schemas), not in the repository: download it into `generator/` for the tools that need it), `build_data.py` (the baked fallback data), `build_ui.py`, `build_dropdown_art.py`, `build_native_schema.py`, `build_native.py`, `build_pack.py`, `verify_native.py` (checks a pack or DLL against `SHA256SUMS.txt`) |
| `tests/` | offline tests (Lua 5.1; `test_verify.py` in Python) and the mock game they run against; `fixtures/native/` a fake game folder for the native module (made by `make_native_fixtures.py`) |
| `SECURITY.md`, `SHA256SUMS.txt` | the native module explained, how to check it, and the checksums of each version's DLL and pack |
| `.github/workflows/rebuild.yml` | GitHub's rebuild of the DLL and the pack on Windows and Linux, compared with `SHA256SUMS.txt` |
| `LICENSE` | MIT, for the mod (`native/vendor` keeps its own licences) |
| `build/` (not in the repository) | `skill_preallocation.pack`, the latest build of `src/`; `native/` the DLL; `test/` the module built for the tests |
| `workshop/`, `releases/` (not in the repository) | the Steam page material; the packs published |

## How the code works

The game loads every `script/campaign/mod/*.lua` when a campaign starts. The six scripts share one
global table, `SKILL_PREALLOCATION` (called `SPA` in the code); the data, the live data and the rules have
their own globals.

### `skill_preallocation_data.lua`: generated, never edited by hand
`SKILL_PREALLOCATION_DATA`, baked from the game's `db.pack` by `generator/build_data.py`: the rules' source
when the live data can't be read (and until it is, the mod's first 6 seconds). Re-run after big
patches/DLCs; `version` is a digest of the tables used. The live data has the same shape:
- `skills`: index → skill key (everything else refers to skills by index).
- `sets`: every skill node set (skill tree) with its filters (subtype, agent, faction, subculture,
  campaign) and its nodes as one compact string per set:
  `skill|tier|indent|required_num_parents|points_on_creation|visible|faction|subculture|campaign|REQUIRED parents|SUBSET_REQUIRED parents|locks|variant group.branch.pos`.
- `maxlv` (max level per skill), `ranks` (rank required per level, as stored in the db), `rank_filters`
  (faction/subculture-specific rank requirements), `auto` (skills unlocked automatically at a rank,
  e.g. mounts), `influence` (skills that cost Influence), `background` (hidden background skills),
  `tiers` (skill points gained per rank, per agent type and campaign → rank cap).

### `skill_preallocation_live.lua`: the live rules (`SKILL_PREALLOCATION_LIVE`, `LIVE`)
- `LIVE.load_native()`: the native module, once a session. Reads `script/skill_preallocation/native_bin`
  with the game's `loadfile` (`{ module, version, sha256, size, data }`), writes `data` into the game's
  folder (the current folder) as `skill_preallocation_native.dll` when the file there is missing or
  differs, reads it back, and loads that very file: `package.loadlib(".\\<module>.dll",
  "luaopen_<module>")`, else `require` (then taken off `package.loaded`: the module stays the mod's own).
  `LIVE.native_how` says which, in the log's `native module loaded ...` line. Not on a game whose Lua isn't
  the Windows one (`package.config`), nor while `LIVE.OPT_OUT_NAMES` (`skill_preallocation_no_native.txt`,
  also without `.txt` or with it twice: Windows hides extensions) is in the game's folder.
- `LIVE.MARKER`, `skill_preallocation_native.txt` next to the DLL: a note for the player (what the DLL is,
  `LIVE.INFO_URL`, how to turn it off) with a `state`, the module's `version` and the `sha256` the pack
  gives. The states keep the loader from fighting an antivirus or the player:
  - `written`: the mod wrote the DLL (or found it there) and loaded it;
  - `removed`: the marker is there and the DLL isn't; it isn't written again, whatever the version;
  - `changed`: the DLL differs from the one the mod wrote (same `sha256`), or wasn't what was written when
    read back; it isn't written over;
  - `blocked`: it couldn't be written; not tried again;
  - `refused`: Windows didn't load it; not tried again while it's the same DLL (its `sha256`);
  - `off`: the opt-out file was there; once it's gone, the loader starts as on a first start.

  Deleting the marker starts over too; a DLL restored from quarantine (the very one) is loaded and is
  `written` again. Every refusal is a reason in the log (and in `LIVE.native_problem`): no loader, the
  file missing or cut short, the DLL unreadable now, can't be written (another version in use by a second
  game: no marker then), not what was written, removed, changed, blocked, refused, the game's Lua functions
  not found, another interface number. `tests/test_loader.lua` plays the main cases.
- `LIVE.load(log)`: the module's `load_db` for the ten tables of `build_data.py` (`LIVE.TABLES`: the
  columns used), then `LIVE.build`; the summary (trees, skills, mods, time, the mods' table files) goes
  to the log. Before building, `LIVE.unusable` refuses a result in which a table file of the game's own
  packs, or any file named `data__` (it replaces the game's own), couldn't be read: the game's rows would
  be missing. `LIVE.compare_files` compares the table files read with the game's own listing
  (`common.filesystem_lookup("/db/<table>_tables/", "*")`, for the tables whose listing names `data__`):
  a file the module read that the game doesn't have (packs the game didn't load: another mod list than
  the game's) means the baked data; a file the game has that the module didn't find (a pack loaded
  another way) is a warning.
- `LIVE.build(result)`: the port of `build_data.py`'s `build()` to Lua: `skills`, `maxlv`, `ranks`,
  `rank_filters`, `auto`, `influence`, `background`, `tiers` and the sets' filters, built at once (a few
  hundredths of a second), and `decode_set(key)`, which builds a set's nodes (members in tier/indent/key
  order, REQUIRED/SUBSET_REQUIRED parents by position, locks, variant groups: the same algorithm) when the
  rules first need it. Keys are compared byte by byte (`LIVE.key_less`): the game's Lua compares strings
  with the computer's locale. `tests/test_live.lua` checks that it equals the baked data for every tree.
- Any of the ten tables without rows, or without a column the trees need (`LIVE.NEEDED`): the live data isn't used.

### The native module (`native/`, `skill_preallocation_native.dll`)
- Lua: `version`, `api` (1), `platform`, `mod_list([options])`,
  `load_db(request)` (`request.tables`: table name -> columns; per table the result has `n` rows, `columns`, `found`, `data` (the rows' values one after
  another, `nil` for no value) and `files` (each: name, pack, version, rows, kept, problem); and `digest`,
  `source`, `packs`, `warnings`). Tests can give `packs`, `game_dir`, `command_line`, `cwd`.
- **The packs:** the mod list file named on the game's command line (a `.txt` argument; else
  `used_mods.txt` in the game's folder, with a warning): `mod "<pack>";` in priority order (first =
  highest), looked for in `data` then in each `add_working_directory "<folder>";`; then the movie packs of
  `data` (they load without being listed; type 4 in the pack header) and the game's `db.pack`.
- **A table:** every `db/<table>_tables/<file>` in those packs; a path in a higher pack hides the same path
  lower down (a mod's `data__` replaces the game's). The files are read in the game's order, by the bytes
  of their names (capitals before small letters), and the first row with a key wins (`!!my_mod` and
  `SFO_vanilla` override `data__`; key columns from the schema). A
  file of a version `spa_schema.h` doesn't have, or that doesn't fit its layout, is left out whole (a
  warning).
- **Pack files:** PFH5 (and PFH4) headers with the extended-header and index-timestamp flags; encrypted
  packs are skipped. Compressed files (vanilla): `u32` size + a zstd frame. The game's packs are opened
  with full sharing while it has them open.
- Every read is bounds-checked; nothing is hooked, patched or read from memory. About 170 KB. It is linked
  without MinGW-w64's C runtime (`-nostdlib`, its own entry point in `spa_dllmain.c`, `snprintf` on the
  UCRT's `__stdio_common_vsprintf`), so it imports only the functions it calls, from `kernel32.dll` and
  `ucrtbase.dll` (the list is in [SECURITY.md](../SECURITY.md); `build_native.py` stops
  if the DLL imports anything else, `ALLOWED_IMPORTS`). The build is deterministic (the PE time stamp
  zeroed, no paths in the file), so the DLL in the game's folder is only rewritten when the module
  changes, and anyone can rebuild it to the same bytes.

### `skill_preallocation_rules.lua`: the rules engine, pure logic (`SKILL_PREALLOCATION_RULES`, `R`)
- `R.data()` / `R.use_source(data)`: the rules' source (the live data, or `nil` for the baked data); a
  source switch drops the decoded sets. `R.decode_set` asks the source's `decode_set` when it has one.
- `R.build_tree(live)`: merges a live read of a character (skill keys and levels, rank, free points,
  subtype/agent/faction/subculture/campaign) with the node set `R.pick_set` chooses from the source (the
  most specific set whose filters match; a tie goes to the key first in byte order, `R.key_less`) into a `tree`: per skill its parents, locks, rank per level, max
  level, plus `order` and `known`. A tree whose skills mostly aren't in the data (a lord added by another
  mod) is not plannable at all.
- `R.check(tree, state, key, rank)`: can the next point of `key` be taken at `rank` → `ok, code`
  (missing parent, rank too low, locked by a variant, maxed, …). `R.required_rank` converts the db's rank
  requirement (one lower than the rank the game shows).
- `R.slot_rank` / `R.arrival_ranks`: the rank at which each next point arrives (free points now, then
  the points gained per rank).
- `R.simulate` / `R.plan_ranks`: strict order. Entry i is learned when the i-th point comes, never before
  the entry ahead of it. Every entry of a plan fits that rank; only a point granted without a rank-up can
  come before an entry's rank, and then that entry waits (`R.wait_rank`, and the ones after it).
- `R.can_append` (the skill must be learnable at the rank its point comes at: refused for a rank not
  reached by then (`rank`, detail = the rank it needs), parents, variants, max level, no points left, a rank
  beyond the cap), `R.remove_last`, `R.replay` (re-simulate a list of points in order; an entry that
  doesn't fit its place (rank not reached by then, parent later in the list) moves to the first place
  where it fits, one that never fits is dropped), `R.plan_fits` (ranks aside),
  `R.kept` / `R.count_kept` (on a tree built without the live data, `tree.keep_unknown`, a skill the
  character's tree shows but the baked data doesn't know: a plan holding such points isn't re-checked,
  `R.remove_last` leaves the rest of it as it is, and spending stops at the first one),
  `R.counterpart` / `R.variant_blocked` (map a preset onto the variant a character owns),
  `R.full_sequence` (learned points in order + plan = a preset), `R.from_scratch` (the character at rank
  1 with nothing spent: what a whole build is checked against), `R.capacity`, `R.spent_levels`.

### `skill_preallocation.lua`: the core (`SPA`)
- **Live data:** `SPA.activate_live()` when the mod gets ready (6 s after the first tick), or the first
  time a tree is needed before that: `SPA.load_native()` (the module; the log says how it was loaded, or
  why not), then `LIVE.load` -> `R.use_source`, the cached trees dropped (made again from the live rules).
  Trees built without the live data are marked `keep_unknown` (see `R.kept`). `SPA.live_state` (`live`,
  `baked: <why>`) and `SPA.native_state()` are in the log's session header.
- **Reading the game:** `SPA.read_live(char)` reads only `SkillPointsAvailable`, `SkillList.Size` and, per
  skill, `SkillList.At(i).Key` and `.Level` through
  `common.get_context_value("CcoCampaignCharacter", cqi, …)`; everything else comes from the data.
  `SPA.tree(cqi[, reread])` caches the tree per character and keeps it up to date from game events. A
  tree is read again when the character is shown in the panel, after its skill reset button was
  clicked, when choices made in the panel never came through, and when a point can't be spent.
- **State:** `SPA.plans[cqi] = { keys = { skill, … }, preset = name or nil }` and `SPA.history[cqi]` (the
  order points were spent in). Saved in the campaign save (`cm:save_named_value`, key
  `skill_preallocation_state_v1`, text `v2;K:0::<dictionary>;P:<cqi>:<preset>:<i,…>;H:<cqi>::<i,…>`:
  skill keys through a small dictionary, so rebuilt data can't scramble a save). Plans are personal: they
  live only on the machine of the player who owns the character, and in that player's save. At each of
  the player's turn starts everything kept for characters the game no longer finds (plans, history,
  session caches) is dropped.
- **Editing a plan:** `SPA.preallocate`, `SPA.unallocate`, `SPA.undo_last`, `SPA.clear_plan`,
  `SPA.apply_preset`; they work on plan mode's draft when the character is in plan mode, else on the
  pre-allocations, whose changes go through `SPA.set_plan` (local only: nothing is sent to other
  players). `SPA.revalidate` / `SPA.reread`: a plan that still fits is kept, otherwise it is replayed
  (without the live data, a plan holding `R.kept` points is left as it is, written to the log once per
  character); a planned-for skill that lost levels means a skill reset → plan cleared, preset link kept.
- **Plan mode:** `SPA.drafts[cqi] = { keys, preset }` (one character at a time, while the panel is open;
  never saved). `SPA.enter_plan_mode`: an empty draft. `SPA.working(cqi)` (the draft or the plan) and
  `SPA.rules_tree(cqi)` (`R.from_scratch` in plan mode: nothing of the character is used) are what
  editing, badges, the cards' plan look and the presets row use. `SPA.leave_plan_mode`: a draft with a
  build, replayed on the character like a preset (`full_build`), becomes the plan; an empty draft changes
  nothing. `SPA.character_sequence` (what presets save) is the draft in plan mode.
- **Spending:** `SPA.request_spend` (250 ms debounce) → `SPA.try_spend` → `SPA.add_skill` =
  `cm.game_interface:add_skill(char, key, false, false)` (the game checks the requirements and uses one
  point). `CharacterSkillPointAllocated` fires *inside* that call, so the loop goes on synchronously; no
  event means the point wasn't taken → the tree is read again and the loop stops. Each point goes to the
  plan's first entry (a refusal other than a rank not reached yet means the stored tree is out of date →
  it is read again; an `R.kept` point waits for the live data, and the points after it with it). Started by `CharacterSkillPointAvailable` / `CharacterRankUp` and by
  `SPA.allocate_now`; `SPA.spendable_now` = how many leading entries the free points cover now.
  Multiplayer: every machine runs the same game and only commands travel between them, so a spend
  decided on one machine (from its timer, its plan, its local faction) would desync the games. The
  owner's machine sends the UI trigger `spa2|spend|<cqi>||<skill key>`, which reaches every machine,
  and each one calls `add_skill` (a trigger from another faction for this character is ignored). One
  point in flight per character; the messages stay far below the 255-character limit of UI triggers.
- **Choices made by hand in the panel** stay unapplied until the panel closes (the game's
  `SkillPointsAvailable` already subtracts them): `SPA.pending_choices` makes the rules count them, and
  `SPA.after_panel_closed` re-reads characters whose choices never came through or whose reset button
  was clicked.
- **Presets:** `SPA.load_presets` / `SPA.save_presets` (file `{ version = 1, presets = { [subtype] = {
  { name =, seq = { skill, … } }, … } } }`, read with `loadstring` + `setfenv`; an unreadable file is
  copied to `skill_preallocation_presets.lua.unreadable` before anything overwrites it),
  `save_preset_as`, `overwrite_preset`, `rename_preset`, `delete_preset`, `apply_preset` (replays the
  preset on the character), `clear_plan`, `preset_list`, `find_preset`.
- **Logging** (`skill_preallocation_log.txt` in the game folder), with no file writes in normal play:
  - `SPA.log(...)` keeps the last 200 events in memory as raw values (no text built). `SPA.error` /
    `SPA.warn` write the message straight away together with the events before it that aren't in the
    file yet, in one write. `SPA.safe` adds a stack trace when the game's Lua has `debug.traceback`.
  - Debug mode (`SPA.debug = true`, or a file named `skill_preallocation_debug.txt` in the game folder,
    checked once when the scripts load) also writes every event: clicks (component path and state),
    reads, spends, the presets row. Lines are batched: one write about a second after the first line
    waiting (`SPA.flush_log`, also on saving). `build_pack.py` prints a note when `SPA.debug = true`.
  - Guards: the same message is written once (a note at its 10th, 100th, … time), at most 30 errors and
    10 warnings a session, a header line (versions, campaign, faction, multiplayer, language, debug)
    starts each session's first write, and a log over 1 MB starts over.
- **Start:** first tick → listeners, presets, `SPA.ui.init()`; `SPA.ready` only 6 s later (heavy work at
  the first tick broke new campaigns).

### `skill_preallocation_ui.lua`: the skills panel (`SPA.ui`)
- Listens to `PanelOpenedCampaign` / `PanelClosedCampaign` for `character_details_panel` and to
  `ComponentLClickUp` while it is open. The panel builds itself over a moment and tells scripts nothing
  about tab or character switches, so after each click `UI.refresh_soon` refreshes at 50, 150, 400 and
  1000 ms. Nothing runs periodically. The panel is rebuilt by the game on every open, so the mod's
  components are made again each time.
- **Skill cards** are the `card` components under the skills `listview` (the whole skills panel without
  one); a card's skill is its parent's id, or else its context object's `Key` (a UI mod that names things
  differently); skills the character doesn't have are left out. Left click → `UI.add_point` (with free
  points the click was the game's own allocation and the mod only notes the choice; in plan mode it
  plans). A left click on the card's badge (`spa_badge`, kind `"badge"`) → `UI.remove_point`. The clicks
  on one skill are gathered for 150 ms: n clicks on the card plan n points, n on its badge remove n. A
  click on the panel's own `button_stats_reset` drops `SPA.pending_choices` and the
  plan is re-checked 200 ms later.
- **Plan mode's view** (`UI.update_plan_view`, part of every refresh): each card's shield `spa_shield` is
  shown. The first time on a card it is made with `card:CreateComponent("spa_shield",
  "ui/skill_preallocation/spa_shield")`, then sized to the card and docked at its top left (`place`: dock
  offsets and `Resize` in layout units, screen pixels / `UI.scale`, which `place_toolbar` reads from the
  dropdown's size); priority card + 1 (`PropagatePriority`), above the card's own parts, below the presets
  row. A shield that can't be made is a warning; plan mode then undoes the game's choices. Clicks land on it
  (`ComponentLClickUp` with the shield, kind `"shield"`), so the game's card never sees them. Its callbacks:
  a neutral `ContextLayoutTooltip` on the card's `CcoCampaignCharacterSkill` (the context the card's own
  tooltip uses) whose function (`UI.TOOLTIP_FUNCTION`, the same text as `TOOLTIP_FUNCTION` in
  `build_ui.py`) is `(r = DatabaseRecordContext("CcoCharacterSkillRecord", Key), k =
  RoundFloat(ToNumber(self.GetProperty("spa_rank"))), t = GetIfElse(k > 1,
  Format(Loc(GetIfElse(self.GetProperty("spa_auto") == "1", "skill_locked_auto_unlock",
  "skill_locked_rank")), k), ""), n = GetIf(IsContextValid(r), CcoCampaignCharacterSkill(Name:this.Name,
  Description:this.Description + t, EffectList:r.EffectListForLevel(1)))) => GetIfElse(IsContextValid(n), n,
  this)`, shown with `ui/common ui/character_background_skill_tooltip` and placed like the card's; the
  card's `ContextEventBroadcaster` (`clear_preview`). `t` is the game's own line for a skill locked by rank
  (`random_localisation_strings`: `skill_locked_rank` "\n\n[[col:red]]Available at rank %d.[[/col]]",
  `skill_locked_auto_unlock` "…Automatically granted at rank %d…"), the one the card's tooltip adds under
  the description while the character's rank is lower. When a shield is shown, `give_rank` sets its
  properties (`SetProperty`) `spa_rank` (the rank its level asks for: `R.required_rank` of the level's
  `ranks`, or of its automatic unlock for a mount; `"0"` for rank 1 or a level learned from the start) and
  `spa_auto` (`"1"` for a mount); the function reads them with `self.GetProperty` (the component that
  shows the tooltip, as in the game's layouts: `RoundFloat(ToNumber(...GetProperty("unlocked_at_rank")))`
  in `dlc26_fragments_ability_slot`). No
  `ContextPropagator` to `stats_effects_holder`, so no stats preview. When shown
  the shield is given the card's skill (`SetContextObject(card:GetContextObject(...))`, else `cco(...)`
  from the card's id) and it is read back (`:Call("Key")`): a shield without it is a warning in the log
  (once a session). `Key` is the only expression the script evaluates with `:Call` (the tests fail on any
  other): in game, a script's `:Call` of `Format(Loc("skill_locked_rank"), 10)` on a card's skill broke
  the game's interface right after. No component could be made ("no shield could be made" in the log,
  the shields after the first missing, so a click in plan mode did nothing), the panel's character
  couldn't be read, and closing or switching the skills panel then crashed the game. With debug on, the
  log says how many shields each refresh made (`plan mode: shields made on N of M cards`). The shield holds the level pips' shields `spa_pip_shield1`..`3`
  (16×20, hidden in the layout, priority card + 2, its children: drawn above it), each with the tooltip
  `UI.tooltip_function(n, true)` (title `this.Name + " (n)"`, `EffectListForLevel(n)`, the rank of level
  n in its own properties) and `clear_preview`. `sync_pip_shields` shows those whose pip the card shows (`level_parent` and `leveln`
  visible), on every refresh, places each over its pip (the pip's position and size, as offsets from the
  card) and gives it the card's skill; a click on one is kind `"shield"` for the card. When plan mode ends the shields are hidden again. The cards are painted with `SetState` as the
  skill is at rank 1 (`R.from_scratch`; the plan doesn't change the look): card `locked` /
  `locked_auto_unlock` (or `complete` / `maxed` for points from creation), `dy_skill` `locked` /
  `locked_auto_unlock` / `active`, pips `level1-3` `locked` (or lit for points from creation);
  `icon_check` and `particle_emitter` hidden.
  What each wore is kept (a state the game draws over the plan look meanwhile is the newer one and is
  kept instead) and put back when plan mode ends, except when the panel shows another character (the game
  draws its cards afresh). Three checks in a row finding the game's looks over the plan look (refreshes,
  and 100 ms after a `ComponentMouseOn` while plan mode's view is on) turn the plan look off for the
  session (a warning in the log); the shields stay. Should a click reach a card in plan mode all the same
  (no shield on it), `UI.undo_game_choices` presses the panel's `button_stats_reset` with
  `SimulateLClick`, only if the click made a choice (fewer free points), and writes a warning if the game
  still holds one 200 ms later.
- **Badges:** a copy (`CopyComponent`) of the card's `dy_skill` text, docked at the bottom centre of the
  card: `[[col:yellow]]` ranks, and for a point the free points cover now its place in the plan in
  `[[col:green]]` (1, 2, 3…). In plan mode the ranks are counted from rank 1 and never green; nor is a
  point that waits behind an `R.kept` one. A badge takes clicks (lifted to the card's priority + 3, above
  plan mode's shield, + 1, and its pips' shields, + 2, then adopted again by its card, which moves it
  among the card's parts by that priority; also after the shields are shown), with the tooltip
  `badge_tip` and `badge_tip_click`. Its box is as wide as its numbers: 8 layout units a character and 4
  each side, at most 120. `dy_skill` centres its text (font 12) and shrinks it rather than wrapping it
  when it doesn't fit the box it is set in, and keeps that size, so the box is resized first and the text
  set after; the width is reckoned generously. The badge is docked again after each resize.
- **Plan mode button:** `spa_btn_plan`, made from `round_small_button_toggle` (states `active` /
  `selected`, and their `_inactive`), icon `icon_edit.png`. `UI.set_plan_mode` turns it on/off;
  `UI.leave_plan_mode` also runs when the panel closes or shows another character (it takes the view off
  the cards, and re-reads the character first if a reset button was clicked).
- **Presets row:** `UI.ensure_toolbar` makes `spa_presets` (a `square_medium_text_button`, 320×34, its
  five images swapped for the dropdown art with `SetImagePath`) and seven round buttons
  `spa_btn_<plan|new|overwrite|rename|delete|clear|spend>` (icon = image 0), as direct children of the skill
  points counter's parent, lifted with `PropagatePriority(highest panel priority + 1)` (at least the
  badges' priority + 1: the list opens over the tree) so they get clicks. `place_toolbar`: right edge = the counter's right edge − 24, top = `skills_subpanel` top + 6,
  all × the UI scale (dropdown width / 320). `UI.update_toolbar` sets texts, tooltips and enabled
  states; `set_enabled` remembers what it set and calls `SetDisabled` **and** `SetState("active" /
  "inactive")` (`"selected"` / `"selected_inactive"` for the plan mode button when on); it never asks
  `IsDisabled`. The list `spa_menu` (a `script_dummy` with `spa_opt_<i>`
  text-button rows) opens under the dropdown.
- **Questions:** `UI/Common UI/dialogue_box` under the UI root (priority 1000), text in `DY_text`,
  answered by clicks on `button_tick` / `button_cancel` inside it. Names: `UI.ask_text` with
  `UI/Common UI/popup_text_input`. The action only runs if the panel still shows the same character.
- **Redraw after spending:** `UI.on_points_spent` calls
  `common.call_context_command("CcoCampaignCharacter", cqi, 'SelectAndShowDetailsForCharacter(this, "skills")')`,
  which redraws the open panel in place; if the points counter still shows the old number 200 ms later,
  the panel is closed (its OK button) and opened again.
- **Checks written to the log once:** `UI.check_panel` (1.5 s after a click in the panel, until it has run
  once a session with the player's character on the Skills tab: are `character_context_parent`,
  `skills_subpanel`, `listview`, `card`, `dy_skill`, `skill_pts_holder`, `dy_pts` and `button_stats_reset`
  there?) and
  `UI.check_tree` (a character whose tree isn't in the data, once per type).

### `skill_preallocation_text.lua`: texts (`SPA.text`)
`SPA.text.get(key, ...)` in 13 languages (en fr ge it sp pl ru cz tr br kr cn zh), plural pairs
`{ one, other }`, English fallback per key. The game's language is read once from the context value
`LocLanguage`.

## Game facts the code relies on (found in game with the original)
- WH3's Lua: `string.find` is plain-text only (use `string.match` / `gmatch` for patterns);
  `string.len` / `string.sub` count UTF-8 characters, `#` counts bytes.
- The context system's `AddPoint` + `CommitSkillChoices` called from a script swallow the point without
  learning the skill; `add_skill(char, key, false, false)` works.
- Right-clicks on skill cards never reach scripts, and scripts can't read the keyboard.
- Components made by a script get no clicks in this panel until they are lifted with
  `PropagatePriority` above the panel's own components.
- `SetDisabled` sets a flag (mouse-over but no clicks); the greyed look is the template's `inactive`
  state; set both.
- `square_medium_text_button`: its art is 34 high (taller repeats the top edge), its images are tiled
  between 26-unit margins and it uses pixel collision. `round_small_button`: 38×38, icon = image 0.
- The open panel doesn't redraw points a script spends; `SelectAndShowDetailsForCharacter(this,
  "skills")` redraws it.
- `CharacterSkillPointAvailable` fires once per point gained; `CharacterRankUp` once (`ranks_gained`);
  `CharacterSkillPointAllocated` also fires for automatic grants at rank-up.
- The db stores rank requirements one lower than the game shows ("unlocked at 11" = "Available at rank
  12").
- The panel's `button_stats_reset` (in `skill_pts_holder` › `skill_pts` › `reset_buttons_holder`) is
  *Undo assigned skill points* ("Any skill points that have been assigned but not yet confirmed will be
  undone"), handled by game code; `button_stats_reset_all` is *Reset all skills* (`ResetAllSkills`, after
  a prompt). `SimulateLClick` on the first undoes the choices (confirmed in game).
- Layouts make invisible click areas and tooltip holders as components with an interactive state and no
  image (e.g. `hitbox`, `tooltip_handler_effect_*`); hit-testing uses the component's box unless a state
  asks for `pixelcollision`. A layout made with `CreateComponent` yields its root's child.
- The skill card (`card`, 185×67, priority 20) has the states `available`, `hover`, `complete`(`_hover`),
  `maxed`(`_hover`), `locked` (greyscale + padlock), `locked_rank`, `locked_upgrade_rank`,
  `locked_auto_unlock` and `researching`; its pips `level1-3` have `active` (lit), `inactive`, `locked`
  and `locked_rank`; `dy_skill` has `active`, `locked`, `locked_auto_unlock` and `locked_rank`.
- In game the painted card states hold while planning: plan mode shows the rank 1 look with the
  badges.
- A component a script makes with `CreateComponent` gets no context object of its own: CA's scripts give it
  one (`uic:SetContextObject(cco("CcoBattleUnit", id))`, `lib_battle_script_unit.lua`). In game, a shield
  made that way from a separate layout file and given no context object shows neither a tooltip nor the
  stats preview.
  `uic:GetContextObject(type)` returns a component's context object (`:Call(expression)`), and `cco(type,
  id)` makes one (CA's scripts make record contexts by key the same way: `cco("CcoMissionRecord", key)`,
  `cco("CcoAncillaryRecord", key)`).
- In game, a shield made as a part of the card shows the card's tooltip, but that tooltip describes the
  skill on the character (current and next level); the stats preview (the card's `ContextPropagator` to
  `stats_effects_holder`) doesn't show. The preview's numbers are computed by game code for the
  character's real next level (`CharacterDetailsPanelCallback`), so it can't be made neutral.
- The neutral tooltip's recipe is the game's own: the character selection panel shows a candidate's
  background skill with `ui/common ui/character_background_skill_tooltip` on a `CcoCampaignCharacterSkill`
  built from the skill's record (`CcoCampaignCharacterSkill(Name:DefaultLocalisedName,
  Description:DefaultLocalisedDescription, EffectList:EffectListForLevel(1))`, through a
  `ContextPropagator`; the game's text has a stray "`" after `EffectListForLevel(1)`, left out here). A
  `ContextLayoutTooltip` can transform its context with a `context_function_id` (143 uses in the game's
  layouts), constructors included (`chd_end_game_teleport` builds a `CcoEffectBundle(Name:..,
  Description:.., EffectList:..)` from a record). Layouts look records up by key with
  `DatabaseRecordContext("CcoXRecord", key)` (91 uses, also with keys from the context, e.g.
  `DatabaseRecordContext("CcoDilemmaRecord", MissionRecordContext.Key)`), and use `(a = .., b = ..) => ..`
  bindings, `GetIf`, `GetIfElse`, `IsContextValid` and `this` in context functions. Scripts read contexts
  with `uic:GetContextObject(type)` and `obj:Call(expression)` (a number for `.Size`, a boolean for a test,
  a table of objects for a list; `campaign_tours.lua`, `episode_nagash_endgame.lua`).
- In game, a shield's tooltip on `CcoCharacterSkillRecord`, given by the script
  (`SetContextObject(cco("CcoCharacterSkillRecord", key))`), doesn't show. On the card's skill, with the
  record looked up in its function (`DatabaseRecordContext`), it shows, neutral.
- On the card each level pip (`level1-3`, callback `SkillLevelPip`) has a tooltip of its own for its
  level; the card's tooltip lists `level_parent` as `additional_hoverables_root`. A shield over the whole
  card covers them (only its own tooltip shows there), hence the pips' shields.
- Draw order: a child is drawn above its parent, and siblings in priority order. The game's layouts give
  children lower priorities than their parents in 898 places (e.g. a button's text 10 under its button
  60), which only works that way; so a part of `level_parent` (priority 20) stays under the card's shield
  (21) whatever its own priority, and the pips' shields are the shield's children. In game the pips'
  shields sit over the pips and show their levels' tooltips.
- `PropagatePriority` alone doesn't move a component among its siblings: CA's scripts adopt it again
  after it (`lib_core.lua`, `cache_and_set_advisor_priority`: `PropagatePriority`, then
  `ui_root:Adopt(uic_advisor:Address())`). In game, a badge that isn't adopted again stays under plan
  mode's shield, and a click on it doesn't reach it.
- A text with `text_clip_behaviour` `shrink_then_ellipsis_no_tooltip` (`dy_skill`) is shrunk to the box
  it is set in, and setting the same text again doesn't change it. So a badge is resized before its text
  is set; the other way round, its numbers get smaller as points are added.
- `round_small_button_toggle` is the game's on/off round button (states `active`, `selected`, each with
  `_hover`, `_down`, `_down_off`, `_inactive` variants).
- Game files: `db.pack` (tables), `ui2.pack` (`ui/skins/default/*.png`), `ui3.pack` (`*.twui.xml`
  templates and layouts, plain XML); `generator/tw_pack.py` reads them (needs `zstandard`).

### What it relies on as well
Found offline (in the game's files, the 15 Oct 2026 build):
- `Warhammer3.exe` exports the whole Lua 5.1 API by name (123 functions, `luaopen_bit` too); its Lua uses
  32-bit float numbers. memreader Plus loads its DLL this way: `loadfile` of a Lua file in the pack (a
  path without `.lua`), `io.open(name, "wb")` in the game's folder, `require(name)` (Lua's C loader,
  `.\?.dll`). This mod loads its DLL with `package.loadlib` and the file's own path instead (the file it
  wrote, whatever `package.cpath` says), and with `require` only if that fails.
- The exe holds the context system's function names and descriptions (pairs of strings referenced side by
  side by the code that registers them). For skills: `CcoCampaignCharacter` `SkillList`, `HiddenSkillList`,
  `SkillPointsAvailable`, `HasUncommitedSkills`, `SkillTree`, `BackgroundSkillContext`;
  `CcoCampaignCharacterSkill` `Key`, `Name`, `Level`, `TotalLevels` (max level), `Status`, `Tier` (y grid
  position), `Indent` (x), `ParentSkillsList`, `ChildSkillsList`, `LevelsDetailsList`,
  `CurrentLevelContext`, `NextLevelContext`, `IsBackgroundSkill`, `AddPoint`, `RemovePoint`;
  `CcoCampaignCharacterSkillLevelDetails` `RankRequired`, `IsLocked`, `EffectList`;
  `CcoCharacterSkillRecord` `UnlockedAtRank`, `DefaultLocalisedName`, `RecordList`, `EffectListForLevel`.
  Nothing gives a link's type, how many parents a skill needs, the locks, Influence costs or points per
  rank: hence the native module.
- Of the game's packs only `db.pack` holds tables (all `data__`, zstd-compressed: `u32` size + frame).
  Vanilla: 594 node sets, 26,640 nodes, 33,171 set items, 22,440 links; 10% of the nodes have
  SUBSET_REQUIRED parents with `required_num_parents`, 4% have locks.
- Table files load by name, the first with a key wins ("!" beats "a", the modding wiki); a mod's
  `!!_name` file overrides `data__` rows (how `no_random_backgrounds` works: in the live data its 4,460
  switched-off set items leave 316 trees with fewer nodes). Names compare by their bytes, so a capital
  first letter sorts before `data__` too (the wiki's list, read as case-insensitive, says otherwise): mods
  rely on it. SFO's changes to the game's own rows (3,165 set items switched off, 422 skills, 135 nodes,
  every rank's XP) are in `SFO_...` files; Less Lethal Autoresolve (two campaign variables) and Free Cult
  Demolish (56 building levels) hold nothing but changes to the game's rows, in files named with a capital.
- CA's launcher writes `used_mods.txt` (`add_working_directory "<workshop folder>";`, `mod "<pack>";`)
  in the game's folder; the game is assumed to get its name on the command line (as memreader Plus
  reads it), else the module reads it from the game's folder.

Seen in game (October 2026): the mod writes the DLL and `package.loadlib` loads it (the log's `native
module loaded 1.1.0 (package.loadlib)` line); the live data is built from the game's packs and the mods'
(Mixer, Cheat Menu, No Random Backgrounds, Expanded Hero Skill Trees); plan mode's shields, made with
`CreateComponent` from the mod's layout, sit exactly over the cards and their pips (the log's `plan mode
shield:` line), also with [Ui] Clean Skill Trees' panel, and their tooltips show the skills' effects and
the rank line; a click on the numbers removes a point, in plan mode too, and the numbers keep their size;
switching characters in plan mode works, again and again; clicks work the same with free points, and at
a UI scale other than 100%. With the DLL removed, the mod doesn't put it back and runs on the baked data,
saying so in the log.

## Build, install, test

```
pip install zstandard pillow ziglang==0.13.0
python generator/build_data.py --game-data "<game>/data" --out src         # the baked fallback data, after big patches
python generator/build_ui.py --game-data "<game>/data" --out src            # the shield layout, after patches that change the skills panel
python generator/build_dropdown_art.py --game-data "<game>/data" --out src   # only if the game's dropdown art changes
python generator/build_native_schema.py     # native/src/spa_schema.h, after a patch that changes a skill table's layout (fresh schema_wh3.ron first)
python generator/build_native.py            # the DLL (Zig's C compiler: no Visual Studio needed), into src/script/skill_preallocation/native_bin.lua
python generator/build_pack.py --install "<game>/data"   # --release also refuses a build that isn't ready to publish
python generator/verify_native.py build/skill_preallocation.pack   # the pack and its DLL against SHA256SUMS.txt
```

Both builds print the SHA-256 of what they made. They are reproducible: the DLL's PE time stamp is
zeroed, and the pack's header time is fixed (`PACK_TIME` in `build_pack.py`; `SOURCE_DATE_EPOCH`
overrides it), so the same source gives the same bytes on any computer. `.gitattributes` keeps the text
files' LF endings in every checkout, and the layout's CRLF and the test fixtures as they are.
`.github/workflows/rebuild.yml` rebuilds both on Windows and Linux at every push and compares them with
`SHA256SUMS.txt`.

**A release:** set `SPA.VERSION`; after a change to the native module, `SPA_NATIVE_VERSION`. Build with
`build_pack.py --release`. In `SHA256SUMS.txt`, the new version's `dll` line (mod version, module
version, SHA-256) and `pack` line (mod version, SHA-256) take the place of the old ones; the same in
SECURITY.md's table. Run the tests, push, and upload the very pack that was hashed.

`build_data.py`, `build_native_schema.py` and `tests/make_*.py` need `generator/schema_wh3.ron`, RPFM's
schema for the game (download it from [rpfm-schemas](https://github.com/Frodo45127/rpfm-schemas); it isn't
in the repository).

`<game>` = `C:/Program Files (x86)/Steam/steamapps/common/Total War WARHAMMER III`. The game must be
closed to replace the pack (it locks the file). The launcher uploads the pack from the `data` folder.
The DLL needs no install: the mod writes `skill_preallocation_native.dll` into the game's folder itself.

Tests (from the project folder; `lua5.1f` is Lua 5.1 built with 32-bit float numbers like the game's,
from the Lua sources in memreader Plus's `vendor/lua-5.1`):

```
lua5.1 tests/test_rules.lua        # rules over every vanilla tree (also passes in lua5.1f)
lua5.1 tests/test_text.lua         # texts: all languages complete, placeholders, UTF-8
mkdir -p tests/run && cd tests/run && lua5.1 ../test_integration.lua && lua5.1 ../test_fallback.lua && lua5.1 ../test_loader.lua && cd ../..
python generator/build_native.py --test                     # the module for this computer (gcc), into build/test
lua5.1f tests/test_native.lua                              # the module on tests/fixtures/native (python tests/make_native_fixtures.py)
SPA_GAME_DATA="<game>/data" lua5.1f tests/test_live.lua     # live data = baked data for every tree, then with a mod pack on top
SPA_RULES_SOURCE=live SPA_GAME_DATA="<game>/data" lua5.1f tests/test_rules.lua   # the rules tests on the live data
python tests/test_verify.py                                 # verify_native.py: good files pass, changed ones fail
```

`test_live.lua` needs the baked data made from that same `db.pack`. The Windows DLL itself was tested
under Wine with a Lua 5.1 built for Windows that exports its API like `Warhammer3.exe` (zig cc with
`-DLUA_BUILD_AS_DLL -DLUA_CORE`): `tests/test_native.lua` (`SPA_NATIVE_DIR` = the DLL's folder), the
vanilla tables against `tw_db.py` row by row, and the loader end to end (`native_bin.lua` written as the
DLL, `package.loadlib`, the mod list from `used_mods.txt`, `db.pack` plus a mod pack).

The mock game can treat the game's disabled flag three ways (env `SPA_DISABLE_MODE` = `flag` (default),
`state` or `both`), and place a component a script adds among its siblings two ways (env
`SPA_ORDER_MODE` = `priority` (default: by its priority then) or `append` (last)); the end-to-end test
should pass in all of them. `tests/skill_fixture.lua` (trees for
the rules test) was made by `tests/make_fixtures.py` from a JSON dump of the db.

## Testing in game

1. Close the game, copy `build/skill_preallocation.pack` into `data` (or `build_pack.py --install`), and
   enable it in the launcher.
2. For a first run, create an empty `skill_preallocation_debug.txt` in the game's folder (debug log).
3. Start or load a campaign, wait 10 seconds, open a lord's skills. Then check
   `skill_preallocation_log.txt` in the game's folder:
   - `native module loaded 1.1.0 (package.loadlib, written now)` (the next sessions: without "written
     now"; `require; package.loadlib: <why>` instead means `loadlib` didn't load it and `require` did);
   - `live skill data live <digest>: module 1.1.0, 594 skill trees, ...` and `ready; skill data live`;
   - no WARNING lines. A warning about the live data says why it's off (the mod then runs on the baked
     data); `skill_preallocation_native.dll` and `skill_preallocation_native.txt` should be in the game's
     folder.
4. Hover a pre-allocated skill's numbers (their tooltip), then click them: its last point goes. With free
   points too: no point is chosen or spent by that click. Plan a skill's levels one by one: the numbers
   keep their size.
5. Plan mode: the cards go to the rank 1 look; hover a card and a level pip (the neutral tooltips; on a
   skill that asks for a rank, "Available at rank N." in red under the description, as outside plan mode;
   on a mount, "Automatically granted at rank N."); click to plan, click the numbers to remove, with free points too; leave plan mode. The log's
   `plan mode shield:` line gives the card's, the shield's and the first pip shield's positions and sizes,
   and the UI scale: they should match (at 100% and at another UI scale, if you use one).
6. A mod with its own lords or skill trees (enable it too): such a lord's tree can be planned; the log's
   `skill tables from mods:` line names its files.
7. A UI mod that changes the skills panel: the presets row, badges and plan mode still work.
8. Without the DLL: create an empty `skill_preallocation_no_native.txt` in the game's folder and load a
   campaign. The log says the live data is off; a plan made with the live data keeps its points on another
   mod's skills (they wait), and everything else works on the vanilla trees. Delete the file afterwards
   (and `skill_preallocation_native.txt`, if the DLL was removed by hand, to let the mod write it again).

## Limits
- The live data needs the native module: Windows (or Proton) only. On the game's macOS version, or with
  the DLL blocked or turned off, the mod uses the baked vanilla data: skills that other mods add or change
  can't be pre-allocated there, and points already planned on them wait for the live data. A plan on a
  vanilla tree that a mod changes without adding skills (other links or ranks) is checked by the vanilla
  rules.
- A skill table file of a layout version `spa_schema.h` doesn't know is left out (a warning): after a
  patch that changes one of the ten tables, rebuild the schema and the module.
- The table merge follows the game's rules as the modding community knows them (file name order, first
  key wins, pack priority by the mod list); a tree the game builds otherwise would show up as skills the
  rules don't know (written to the log once per character type).
- The DLL isn't signed. An antivirus can flag it (memreader Plus had a McAfee false positive), and
  Windows' Smart App Control, when it's on, refuses to load it: the mod then falls back as above, says so
  in the log, and doesn't write or load that DLL again.
- The file order of a table is proven only for capitals against small letters (mods rely on it); for
  symbols such as `_` against small letters, and digits against `;`, `=` and `@`, it follows the bytes,
  where the modding wiki's list differs. Mods rarely start names that way.
- UI mods: the mod finds the game's component names (`character_details_panel`, `skills_subpanel`,
  `listview`, `card`, `dy_skill`, `level_parent`/`level1-3`, `skill_pts_holder`, `button_stats_reset`); a
  mod that renames them can still break parts of it (checked once per session, written to the log).
- Multiplayer untested. Pre-allocations are kept in each player's own save: if the game resumes a
  multiplayer campaign from the host's copy of the save, the other player's pre-allocations are lost
  (their presets aren't: those are in each player's own presets file).
