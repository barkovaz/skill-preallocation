-- Tests of the native module (native/src), built for this computer by generator/build_native.py --test,
-- against the fake game folder in tests/fixtures/native (tests/make_native_fixtures.py).
-- From the project folder:   lua5.1f tests/test_native.lua
-- (lua5.1f: Lua 5.1 with 32-bit float numbers like the game's, the build the module links to)

local here = (arg and arg[0] or ""):match("^(.*)[/\\][^/\\]*$") or "."
-- (on Windows, e.g. under Wine with a Lua built for Windows: SPA_NATIVE_DIR = the folder of the DLL)
local windows = package.config:sub(1, 1) == "\\"
package.cpath = (os.getenv("SPA_NATIVE_DIR") or (here .. "/../build/test")) .. (windows and "/?.dll;" or "/?.so;") .. package.cpath

local passed, failed = 0, 0
local function check(cond, msg)
	if cond then passed = passed + 1 else failed = failed + 1; print("FAIL: " .. msg) end
end

local ok, N = pcall(require, "skill_preallocation_native")
if not ok or type(N) ~= "table" then
	print("FAIL: the module did not load: " .. tostring(N))
	os.exit(1)
end
check(N.version == "1.1.0" and N.api == 1, "version and api")
check(type(N.load_db) == "function" and type(N.mod_list) == "function", "functions")
local names = {}
for k in pairs(N) do names[#names + 1] = k end
table.sort(names)
check(table.concat(names, " ") == "api load_db mod_list platform version", "nothing else in the module: " .. table.concat(names, " "))

local fx = here .. "/fixtures/native"
local game = fx .. "/game"
local opts = { game_dir = game, cwd = game, command_line = '"' .. game .. '/Warhammer3.exe" used_mods.txt;' }

---------------------------------------------------------------- the mod list
-- (paths compared with "/" between folders: the Windows build joins them with "\\")
local function slashes(p) return p and (p:gsub("\\", "/")) end
local ml = N.mod_list(opts)
check(ml.ok == true, "mod_list ok")
check(slashes(ml.source) == game .. "/used_mods.txt", "mod list from the command line: " .. tostring(ml.source))
local names, kinds = {}, {}
for i, p in ipairs(ml.packs) do names[i] = p.name; kinds[i] = p.kind end
check(table.concat(names, ",") == "mod1.pack,mod2.pack,mod3.pack,missing.pack,movie_mod.pack,db.pack",
	"packs in priority order: " .. table.concat(names, ","))
check(table.concat(kinds, ",") == "mod,mod,mod,mod,movie,vanilla", "pack kinds: " .. table.concat(kinds, ","))
check(ml.packs[3].path and slashes(ml.packs[3].path):find("workshop/123/mod3.pack", 1, true) ~= nil, "mod3 found in the working directory")
check(ml.packs[4].path == nil, "a missing mod has no path")
local warned_missing = false
for _, w in ipairs(ml.warnings) do if w:find("missing.pack", 1, true) then warned_missing = true end end
check(warned_missing, "a missing mod is warned about")
check(#ml.working_dirs == 2 and slashes(ml.working_dirs[1]) == game .. "/data", "working directories: data first")

-- without a mod list on the command line: used_mods.txt in the game's folder
local ml2 = N.mod_list({ game_dir = game, cwd = game, command_line = '"' .. game .. '/Warhammer3.exe"' })
check(#ml2.packs == 6, "used_mods.txt found without the command line naming it (" .. #ml2.packs .. " packs)")
local fallback_warned = false
for _, w in ipairs(ml2.warnings) do if w:find("no mod list on the command line", 1, true) then fallback_warned = true end end
check(fallback_warned, "falling back to used_mods.txt is warned about")

-- a folder without a mod list: the game's own packs only
local ml3 = N.mod_list({ game_dir = fx .. "/workshop", cwd = fx .. "/workshop", command_line = "x.exe" })
check(ml3.source == "no mod list: the game's own packs only", "no mod list: " .. tostring(ml3.source))

-- a mod list named in quotes on the command line, its path with a space; a folder with "#" in its name
local ml4 = N.mod_list({ game_dir = game, cwd = game,
	command_line = '"' .. game .. '/Warhammer3.exe" "my lists/mods list.txt";' })    -- (relative to the game's folder)
local n4 = {}
for i, p in ipairs(ml4.packs) do n4[i] = p.name .. (p.path and "" or "?") end
check(slashes(ml4.source) == game .. "/my lists/mods list.txt", "a quoted mod list path with a space: " .. tostring(ml4.source))
check(table.concat(n4, ",") == "mod4.pack,mod1.pack,mod2.pack,movie_mod.pack,db.pack",
	"its mods, the one in the folder with \"#\" found: " .. table.concat(n4, ","))
-- mod statements on the command line itself come first
local ml5 = N.mod_list({ game_dir = game, cwd = game, command_line = '"' .. game .. '/Warhammer3.exe" mod "mod2.pack"; used_mods.txt;' })
local n5 = {}
for i, p in ipairs(ml5.packs) do n5[i] = p.name end
check(table.concat(n5, ",") == "mod2.pack,mod1.pack,mod3.pack,missing.pack,movie_mod.pack,db.pack",
	"a mod on the command line, then the list's: " .. table.concat(n5, ","))

---------------------------------------------------------------- merged tables
local req = {
	game_dir = opts.game_dir, cwd = opts.cwd, command_line = opts.command_line,
	tables = {
		character_skill_nodes = { "key", "tier", "character_skill_key", "no_such_column" },
		character_skills = { "key", "unlocked_at_rank" },
	},
}
local res, err = N.load_db(req)
check(res ~= nil, "load_db: " .. tostring(err))
if res then
	local t = res.tables.character_skill_nodes
	local rows = {}
	for i = 0, t.n - 1 do rows[#rows + 1] = t.data[i * 4 + 1] .. "=" .. t.data[i * 4 + 2] end
	check(table.concat(rows, " ") == "n_b=5 n_d=3 n_a=11 n_h=8 n_c=2 n_f=2 n_m=6 n_e=4",
		"nodes merged in file name order (bytes: a capital before data__), first key wins: " .. table.concat(rows, " "))
	check(t.found.key == true and t.found.no_such_column == false, "found columns")
	check(t.data[4] == nil, "a missing column gives nil")
	local files = {}
	for _, f in ipairs(t.files) do files[#files + 1] = f.name .. "@" .. f.pack .. ":" .. f.kept .. "/" .. f.rows .. (f.problem and "!" or "") end
	check(table.concat(files, " ") == "!!mod1@mod1.pack:2/2 Mod1_Upper@mod1.pack:2/2 data__@db.pack:1/3 mod3@mod3.pack:1/1 mod3_future@mod3.pack:0/1! movie@movie_mod.pack:1/1 zz_mod1@mod1.pack:1/2",
		"files read: " .. table.concat(files, " "))
	local v5
	for _, f in ipairs(t.files) do if f.name == "mod3" then v5 = f.version end end
	check(v5 == 5, "the older layout (version 5) is read")
	local s = res.tables.character_skills
	check(s.n == 1 and s.data[1] == "s_x" and s.data[2] == 9, "a mod's data__ replaces the game's file of the same name")
	local warned_version = false
	for _, w in ipairs(res.warnings) do if w:find("version 99", 1, true) then warned_version = true end end
	check(warned_version, "a file of an unknown version is left out with a warning")
	check(type(res.digest) == "string" and #res.digest == 16, "digest")
	local again = N.load_db(req)
	check(again and again.digest == res.digest, "the digest is the same for the same files")
end

-- the packs given directly
local res2 = N.load_db({ packs = { game .. "/data/mod1.pack", game .. "/data/db.pack" }, tables = { character_skill_nodes = { "key" } } })
check(res2 and res2.tables.character_skill_nodes.n == 6, "explicit packs: " .. tostring(res2 and res2.tables.character_skill_nodes.n))

-- bad requests
local r, e = N.load_db()
check(r == nil and type(e) == "string", "no request")
r, e = N.load_db({ tables = {} })
check(r == nil and type(e) == "string", "no tables")
r = N.load_db({ packs = { game .. "/data/db.pack" }, tables = { not_a_table = { "key" } } })
check(r and r.tables.not_a_table.n == 0, "an unknown table gives no rows")

print(passed .. " passed, " .. failed .. " failed")
if failed > 0 then os.exit(1) end
