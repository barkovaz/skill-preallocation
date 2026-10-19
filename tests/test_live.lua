-- The live data (skill_preallocation_live.lua, read through the native module) against the baked data
-- (skill_preallocation_data.lua, made by generator/build_data.py from the same db.pack): every tree, node,
-- rank, lock and variant must come out the same. Then the same with a mod pack on top.
--
-- From the project folder, after generator/build_native.py --test:
--   SPA_GAME_DATA="<game>/data" lua5.1f tests/test_live.lua
-- SPA_GAME_DATA: a folder with the game's db.pack (the baked data must have been made from that same
-- db.pack); SPA_MOD_PACK (optional): a mod pack with skill tables to test on top (default: the folder's
-- no_random_backgrounds.pack, when it is there).

local here = (arg and arg[0] or ""):match("^(.*)[/\\][^/\\]*$") or "."
local root = here .. "/.."
local windows = package.config:sub(1, 1) == "\\"
package.cpath = (os.getenv("SPA_NATIVE_DIR") or (root .. "/build/test")) .. (windows and "/?.dll;" or "/?.so;") .. package.cpath

local game_data = os.getenv("SPA_GAME_DATA")
if not game_data then
	print("SKIP: set SPA_GAME_DATA to the game's data folder")
	return
end
local function exists(p) local f = io.open(p, "rb") if f then f:close() return true end return false end
if not exists(game_data .. "/db.pack") then
	print("SKIP: no db.pack in " .. game_data)
	return
end

dofile(root .. "/src/script/campaign/mod/skill_preallocation_data.lua")
dofile(root .. "/src/script/campaign/mod/skill_preallocation_rules.lua")
dofile(root .. "/src/script/campaign/mod/skill_preallocation_live.lua")
local R, LIVE, BAKED = SKILL_PREALLOCATION_RULES, SKILL_PREALLOCATION_LIVE, SKILL_PREALLOCATION_DATA

local passed, failed = 0, 0
local function check(cond, msg)
	if cond then passed = passed + 1 else failed = failed + 1; print("FAIL: " .. msg) end
end

local N = require("skill_preallocation_native")

local function read(packs)
	local t0 = os.clock()
	local res = assert(N.load_db({ packs = packs, tables = LIVE.TABLES }))
	local t1 = os.clock()
	local data, why = LIVE.build(res)
	local t2 = os.clock()
	assert(data, why)
	return data, res, t1 - t0, t2 - t1
end

local live, res, t_read, t_build = read({ game_data .. "/db.pack" })
for _, w in ipairs(res.warnings) do print("warning: " .. w) end
print(string.format("live data: read %.3f s, built %.3f s", t_read, t_build))

---------------------------------------------------------------- the same as the baked data
local function same_list(a, b)
	if #a ~= #b then return false end
	for i = 1, #a do if a[i] ~= b[i] then return false end end
	return true
end

local function describe_node(n)
	local locks = {}
	for _, lk in ipairs(n.locks) do locks[#locks + 1] = tostring(lk.skill) .. ":" .. tostring(lk.level) end
	return table.concat({ tostring(n.skill), tostring(n.tier), tostring(n.indent), tostring(n.rnp), tostring(n.poc),
		tostring(n.visible), n.faction, n.subculture, n.campaign, table.concat(n.req, "+"), table.concat(n.sub, "+"),
		table.concat(locks, "+"), n.variant and (n.variant.group .. "." .. n.variant.branch .. "." .. n.variant.pos) or "" }, "|")
end

local function decode_all(source)
	R.use_source(source)
	local out = {}
	for key in pairs((source or BAKED).sets) do out[key] = R.decode_set(key) end
	return out
end

local baked_sets = decode_all(nil)
local t0 = os.clock()
local live_sets = decode_all(live)
print(string.format("decoded %d live sets in %.3f s", (function() local n = 0 for _ in pairs(live_sets) do n = n + 1 end return n end)(), os.clock() - t0))

local set_count, node_count, diff_sets = 0, 0, 0
for key, b in pairs(baked_sets) do
	set_count = set_count + 1
	local l = live_sets[key]
	local h, lh = BAKED.sets[key], live.sets[key]
	local ok = l ~= nil and lh ~= nil and h.subtype == lh.subtype and h.agent == lh.agent and h.faction == lh.faction
		and h.subculture == lh.subculture and h.campaign == lh.campaign and #l.nodes == #b.nodes
	if ok then
		for i, n in ipairs(b.nodes) do
			node_count = node_count + 1
			if describe_node(n) ~= describe_node(l.nodes[i]) then
				ok = false
				if diff_sets < 3 then print("  " .. key .. " node " .. i .. ":\n    baked " .. describe_node(n) .. "\n    live  " .. describe_node(l.nodes[i])) end
				break
			end
		end
	end
	if not ok then diff_sets = diff_sets + 1 end
end
for key in pairs(live_sets) do check(baked_sets[key] ~= nil, "a live set the baked data doesn't have: " .. key) end
check(diff_sets == 0, diff_sets .. " of " .. set_count .. " trees differ from the baked data")
check(set_count > 500 and node_count > 30000, "trees compared: " .. set_count .. " (" .. node_count .. " nodes)")

-- per skill: max level, ranks, rank filters, automatic unlocks, Influence, background, for the skills of
-- the trees (the generator bakes ranks only for those: other skills only matter through a tree)
local used = {}
for _, b in pairs(baked_sets) do for _, n in ipairs(b.nodes) do used[n.skill] = true end end
local function by_key(d, field)
	local out = {}
	for i, key in ipairs(d.skills) do
		local v = d[field][i]
		if v ~= nil and used[key] then out[key] = v end
	end
	return out
end
for _, field in ipairs({ "maxlv", "ranks", "rank_filters", "auto", "influence" }) do
	local b, l = by_key(BAKED, field), by_key(live, field)
	local bad, n = 0, 0
	for key, v in pairs(b) do
		n = n + 1
		if l[key] ~= v then
			bad = bad + 1
			if bad <= 3 then print("  " .. field .. " " .. key .. ": baked " .. tostring(v) .. ", live " .. tostring(l[key])) end
		end
	end
	for key, v in pairs(l) do
		if b[key] == nil then
			bad = bad + 1
			if bad <= 3 then print("  " .. field .. " " .. key .. ": baked nil, live " .. tostring(v)) end
		end
	end
	check(bad == 0, field .. ": " .. bad .. " of " .. n .. " skills differ")
end
do
	local b, l = by_key(BAKED, "background"), by_key(live, "background")
	local bad = 0
	for key in pairs(b) do if not l[key] then bad = bad + 1 end end
	check(bad == 0, "background: " .. bad .. " skills differ")
end
do
	local bad = 0
	for agent, camps in pairs(BAKED.tiers) do
		for camp, t in pairs(camps) do
			local lt = live.tiers[agent] and live.tiers[agent][camp]
			if not lt or lt.first ~= t.first or lt.points ~= t.points then bad = bad + 1 end
		end
	end
	for agent, camps in pairs(live.tiers) do
		for camp in pairs(camps) do if not (BAKED.tiers[agent] and BAKED.tiers[agent][camp]) then bad = bad + 1 end end
	end
	check(bad == 0, "tiers: " .. bad .. " differ")
end

---------------------------------------------------------------- trees built from either source
-- every character type's tree, built by the rules from each source, plans the same
local function tree_text(source, subtype, agent, faction, subculture)
	R.use_source(source)
	local set_key = R.pick_set(subtype, agent, faction, subculture, "main_warhammer")
	local set = set_key and R.decode_set(set_key)
	if not set then return "none" end
	local live_skills = {}
	for _, n in ipairs(set.nodes) do
		if (n.faction == "" or n.faction == faction) and (n.subculture == "" or n.subculture == subculture) then
			live_skills[#live_skills + 1] = { key = n.skill, level = 0 }
		end
	end
	local tree = R.build_tree({ cqi = 1, subtype = subtype, agent = agent, faction = faction, subculture = subculture,
		campaign = "main_warhammer", rank = 1, points = 0, skills = live_skills })
	local parts = { set_key, tostring(tree.known), tostring(R.capacity(tree)) }
	for _, k in ipairs(tree.order) do
		local s = tree.skills[k]
		parts[#parts + 1] = k .. ":" .. tostring(s.plannable) .. ":" .. table.concat(s.req, ",") .. ":" .. table.concat(s.sub, ",")
			.. ":" .. table.concat(s.ranks or {}, ",") .. ":" .. tostring(s.total)
	end
	return table.concat(parts, ";")
end
local tested, differ = 0, 0
for key, s in pairs(BAKED.sets) do
	if s.subtype ~= "" then
		tested = tested + 1
		local a = tree_text(nil, s.subtype, s.agent, s.faction, s.subculture)
		local b = tree_text(live, s.subtype, s.agent, s.faction, s.subculture)
		if a ~= b then
			differ = differ + 1
			if differ <= 2 then print("  tree of " .. key .. " differs") end
		end
	end
end
check(differ == 0 and tested > 400, "rules trees from both sources: " .. differ .. " of " .. tested .. " differ")

---------------------------------------------------------------- with a mod on top
local mod_pack = os.getenv("SPA_MOD_PACK") or (game_data .. "/no_random_backgrounds.pack")
if exists(mod_pack) then
	local modded, mres = read({ mod_pack, game_data .. "/db.pack" })
	local from_mod = 0
	for _, t in pairs(mres.tables) do
		for _, f in ipairs(t.files) do if f.pack ~= "db.pack" then from_mod = from_mod + f.kept end end
	end
	check(from_mod > 0, "the mod pack's rows are read: " .. from_mod)
	R.use_source(modded)
	local fewer, more = 0, 0
	for key in pairs(BAKED.sets) do
		local m = R.decode_set(key)
		local b = baked_sets[key]
		if m and b then
			if #m.nodes < #b.nodes then fewer = fewer + 1 elseif #m.nodes > #b.nodes then more = more + 1 end
		end
	end
	print("with " .. mod_pack .. ": " .. fewer .. " trees have fewer nodes, " .. more .. " more")
	check(fewer > 0 or more > 0, "the mod changes some trees")
	R.use_source(nil)
else
	print("(no mod pack to test on top: " .. mod_pack .. ")")
end

---------------------------------------------------------------- the checks before the live data is used
-- a copy of the result whose tables (rows count, columns found, files) the test may change
local function variant(edit)
	local c = {}
	for k, v in pairs(res) do c[k] = v end
	c.packs = {}
	for i, p in ipairs(res.packs) do c.packs[i] = p end
	c.tables = {}
	for name, t in pairs(res.tables) do
		local tc = {}
		for k, v in pairs(t) do tc[k] = v end
		tc.found = {}
		for k, v in pairs(t.found) do tc.found[k] = v end
		tc.files = {}
		for i, f in ipairs(t.files) do
			local fc = {}
			for k, v in pairs(f) do fc[k] = v end
			tc.files[i] = fc
		end
		c.tables[name] = tc
	end
	if edit then edit(c) end
	return c
end
local function add_file(c, table_name, file)
	local files = c.tables[table_name].files
	files[#files + 1] = file
end
local function add_mod(c) c.packs[#c.packs + 1] = { name = "test_mod.pack", path = "test_mod.pack", kind = "mod" } end

check(LIVE.unusable(res) == nil, "the game's packs alone are usable")
local why = LIVE.unusable(variant(function(c) c.tables.character_skills.files[1].problem = "an unknown table version (99)" end))
check(why and string.find(why, "character_skills/data__ in db.pack couldn't be read", 1, true) ~= nil,
	"a table file of the game's own packs that couldn't be read: the baked data (" .. tostring(why) .. ")")
check(LIVE.unusable(variant(function(c)
	add_mod(c)
	add_file(c, "character_skills", { name = "!!test", pack = "test_mod.pack", version = 99, rows = 0, kept = 0, problem = "an unknown table version (99)" })
end)) == nil, "a mod's own table file that couldn't be read: the rest is still used (a warning)")
why = LIVE.unusable(variant(function(c)
	add_mod(c)
	add_file(c, "character_skill_nodes", { name = "data__", pack = "test_mod.pack", version = 99, rows = 0, kept = 0, problem = "an unknown table version (99)" })
end))
check(why and string.find(why, "character_skill_nodes/data__ in test_mod.pack", 1, true) ~= nil,
	"a mod's data__ (it replaces the game's own) that couldn't be read: the baked data (" .. tostring(why) .. ")")

-- every table needs rows and the columns the trees use
for name in pairs(LIVE.TABLES) do
	local d, w = LIVE.build(variant(function(c) c.tables[name].n = 0 end))
	check(d == nil and w == name .. " has no rows", "no rows in " .. name .. ": " .. tostring(w))
end
for name, cols in pairs(LIVE.NEEDED) do
	local col = cols[#cols]
	local d, w = LIVE.build(variant(function(c) c.tables[name].found[col] = nil end))
	check(d == nil and w == name .. " has no column " .. col, "no column " .. col .. " in " .. name .. ": " .. tostring(w))
end

-- the game's own file listing (common.filesystem_lookup), against the files the module read
local listing
local function list_as_read(c, extra_names, drop)
	listing = {}
	for name, t in pairs(c.tables) do
		local parts = {}
		for _, f in ipairs(t.files) do
			if not (drop and drop[name .. "/" .. f.name]) then parts[#parts + 1] = "db/" .. name .. "_tables/" .. f.name end
		end
		for _, n in ipairs(extra_names and extra_names[name] or {}) do parts[#parts + 1] = "db/" .. name .. "_tables/" .. n end
		listing["/db/" .. name .. "_tables/"] = table.concat(parts, ",")
	end
end
common = { filesystem_lookup = function(path, pattern) return listing[path] or "" end }
list_as_read(res)
local missing, extra = LIVE.compare_files(res)
check(#missing == 0 and #extra == 0, "the game lists the files the module read: " .. #missing .. " missing, " .. #extra .. " extra")
list_as_read(res, { character_skills = { "!!other_mod" } })
missing, extra = LIVE.compare_files(res)
check(#missing == 1 and missing[1] == "character_skills/!!other_mod" and #extra == 0,
	"a table file the game has that the module didn't find: " .. table.concat(missing, ", "))
local with_mod = variant(function(c)
	add_mod(c)
	add_file(c, "character_skills", { name = "!!Not_Loaded", pack = "test_mod.pack", version = 5, rows = 3, kept = 3 })
end)
list_as_read(with_mod, nil, { ["character_skills/!!Not_Loaded"] = true })
missing, extra = LIVE.compare_files(with_mod)
check(#missing == 0 and #extra == 1 and extra[1] == "character_skills/!!Not_Loaded",
	"a table file the module read that the game didn't load: " .. table.concat(extra, ", "))
listing = {}
for name, t in pairs(with_mod.tables) do listing["/db/" .. name .. "_tables/"] = "db/" .. name .. "_tables/!!some_mod" end
missing, extra = LIVE.compare_files(with_mod)
check(#missing == 0 and #extra == 0, "a listing without the game's own data__ isn't compared (it doesn't list everything)")
list_as_read(res)
listing["/db/character_skills_tables/"] = string.upper(listing["/db/character_skills_tables/"])
missing, extra = LIVE.compare_files(res)
check(#missing == 0 and #extra == 0, "the listing is compared without case")
common = nil
missing, extra = LIVE.compare_files(with_mod)
check(#missing == 0 and #extra == 0, "no listing (no common.filesystem_lookup): nothing compared")

-- LIVE.load with these results (a stand-in for the module that gives them)
local given
local saved = { LIVE.native, LIVE.native_tried, LIVE.native_problem }
LIVE.native_tried, LIVE.native, LIVE.native_problem = true, { version = "test", load_db = function() return given end }, nil
common = { filesystem_lookup = function(path, pattern) return listing[path] or "" end }
given = res
list_as_read(res, { character_skill_nodes = { "!!loaded_another_way" } })
local d, w = LIVE.load()
check(d ~= nil and #d.report.unseen == 1 and d.report.unseen[1] == "character_skill_nodes/!!loaded_another_way",
	"LIVE.load: a file the game has that the module didn't read is reported (" .. tostring(w) .. ")")
given = with_mod
list_as_read(with_mod, nil, { ["character_skills/!!Not_Loaded"] = true })
d, w = LIVE.load()
check(d == nil and string.find(tostring(w), "didn't load", 1, true) ~= nil and string.find(tostring(w), "character_skills/!!Not_Loaded", 1, true) ~= nil,
	"LIVE.load: files the game didn't load mean the baked data (" .. tostring(w) .. ")")
given = variant(function(c) c.tables.character_skill_node_links.files[1].problem = "cut short" end)
list_as_read(given)
d, w = LIVE.load()
check(d == nil and string.find(tostring(w), "couldn't be read", 1, true) ~= nil, "LIVE.load: an unreadable game table means the baked data (" .. tostring(w) .. ")")
given = variant(function(c) c.tables.character_experience_skill_tiers.n = 0 end)
list_as_read(given)
d, w = LIVE.load()
check(d == nil and w == "character_experience_skill_tiers has no rows", "LIVE.load: an empty table means the baked data (" .. tostring(w) .. ")")
common = nil
LIVE.native, LIVE.native_tried, LIVE.native_problem = saved[1], saved[2], saved[3]

print(passed .. " passed, " .. failed .. " failed")
if failed > 0 then os.exit(1) end
