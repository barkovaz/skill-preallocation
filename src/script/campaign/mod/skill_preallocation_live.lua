-- Skill Pre-Allocation: live skill data, read from the packs the game loaded.
--
-- The rules engine needs the rules behind each skill tree (which parents a skill needs, "N points in
-- these", which variants lock each other out, rank requirements, points per rank). The game's scripts
-- can read a character's skills but not those rules, so the mod used to bake them from the game's
-- db.pack (skill_preallocation_data.lua): vanilla trees only. This file reads them from the game's own
-- packs instead, mods included, through the mod's native module (native/src, a DLL the mod writes into
-- the game's folder and loads with package.loadlib, else require; it only reads files), and builds the same
-- data the baked file holds. Without the module (another platform, the DLL blocked, an unknown table
-- layout) the baked data is used, as before.
--
--   LIVE.load_native()   the module, or nil and why (once a session)
--   LIVE.load()          the live data, or nil and why: { version, skills, maxlv, ranks, rank_filters,
--                        auto, influence, background, tiers, sets, decode_set(set key), report }
--                        (the shape of SKILL_PREALLOCATION_DATA; sets have no `nodes` text: decode_set
--                        builds a set's nodes when the rules first need them)
--   LIVE.build(result)   that data from the module's result (also used by the offline tests)

SKILL_PREALLOCATION_LIVE = SKILL_PREALLOCATION_LIVE or {}
local LIVE = SKILL_PREALLOCATION_LIVE

LIVE.MODULE = "skill_preallocation_native"
LIVE.API = 1
LIVE.BIN = { "/script/skill_preallocation/native_bin", "script/skill_preallocation/native_bin.lua" }

-- The columns read from each table (the same ones generator/build_data.py uses).
local NODES = { "key", "character_skill_key", "tier", "indent", "required_num_parents", "points_on_creation",
	"visible_in_ui", "faction_key", "subculture", "campaign_key" }
local LINKS = { "child_key", "parent_key", "link_type" }
local LOCKS = { "character_skill_node", "character_skill", "level" }
local SETS = { "key", "agent_subtype_key", "agent_key", "faction_key", "subculture", "campaign_key" }
local ITEMS = { "set", "item", "mod_disabled" }
local SKILLS = { "key", "unlocked_at_rank", "is_background_skill", "influence_cost" }
local CRITERIA = { "character_skill", "character_level", "upgrade_to_skill_level" }
local TIERS = { "agent_key", "optional_campaign_key", "skill_rank", "skill_points" }
local DETAILS = { "skill_key", "level", "unlocked_at_rank", "faction_key", "subculture_key", "campaign_key" }
local EFFECTS = { "character_skill_key", "level" }
LIVE.TABLES = {
	character_skill_nodes = NODES,
	character_skill_node_links = LINKS,
	character_skill_nodes_skill_locks = LOCKS,
	character_skill_node_sets = SETS,
	character_skill_node_set_items = ITEMS,
	character_skills = SKILLS,
	character_skills_to_level_reached_criterias = CRITERIA,
	character_experience_skill_tiers = TIERS,
	character_skill_level_details = DETAILS,
	character_skill_level_to_effects_junctions = EFFECTS,
}
-- Every table must have rows (the game's own have), and these columns: without them the trees would be
-- wrong, so the live data isn't used.
local NEEDED = {
	character_skill_nodes = { "key", "character_skill_key", "tier", "indent", "required_num_parents",
		"points_on_creation", "visible_in_ui" },
	character_skill_node_links = { "child_key", "parent_key", "link_type" },
	character_skill_nodes_skill_locks = { "character_skill_node", "character_skill", "level" },
	character_skill_node_sets = { "key", "agent_subtype_key", "agent_key" },
	character_skill_node_set_items = { "set", "item" },
	character_skills = { "key", "unlocked_at_rank", "is_background_skill" },
	character_skills_to_level_reached_criterias = { "character_skill", "character_level", "upgrade_to_skill_level" },
	character_experience_skill_tiers = { "agent_key", "skill_rank", "skill_points" },
	character_skill_level_details = { "skill_key", "level", "unlocked_at_rank" },
	character_skill_level_to_effects_junctions = { "character_skill_key", "level" },
}
LIVE.NEEDED = NEEDED

---------------------------------------------------------------- helpers
-- Keys are compared byte by byte: the game's Lua compares strings with the computer's locale, which
-- could order "_" or capitals differently from the generator (the trees must come out the same).
local byte = string.byte
local function key_less(a, b)
	if a == b then return false end
	local n = #a < #b and #a or #b
	for i = 1, n do
		local x, y = byte(a, i), byte(b, i)
		if x ~= y then return x < y end
	end
	return #a < #b
end
LIVE.key_less = key_less

local function columns(t, names)
	local at = {}
	for i, c in ipairs(t.columns or {}) do at[c] = i end
	local out = {}
	for i, c in ipairs(names) do out[i] = at[c] end
	return out
end

local function read_binary(path)
	local ok, data = pcall(function()
		local f = io.open(path, "rb")
		if not f then return nil end
		local d = f:read("*a")
		f:close()
		return d
	end)
	return ok and data or nil
end

---------------------------------------------------------------- the native module
-- The DLL's bytes come in a Lua file of the pack (native_bin.lua, made by generator/build_native.py).
-- They are written into the game's folder (the current folder, next to Warhammer3.exe) when the file
-- there is missing or different, and that very file is loaded (package.loadlib, or else require); the
-- module isn't left in package.loaded: it belongs to this mod.
--
-- Two small files in the game's folder keep that honest (SECURITY.md):
--   skill_preallocation_no_native.txt  made by the player: the mod never writes or loads the DLL
--   skill_preallocation_native.txt     written by the mod next to the DLL: what it is, where to read
--                                      about it, and its state. Once the mod has written the DLL it
--                                      doesn't put it back if it goes missing (an antivirus, the player),
--                                      nor write over a file someone changed, nor try again where it
--                                      couldn't write; a DLL Windows refused isn't tried again until the
--                                      mod brings another. Deleting this file lets the mod start over.
LIVE.OPT_OUT = "skill_preallocation_no_native.txt"
LIVE.OPT_OUT_NAMES = { LIVE.OPT_OUT, LIVE.OPT_OUT .. ".txt", "skill_preallocation_no_native" }   -- (Windows hides extensions)
LIVE.MARKER = "skill_preallocation_native.txt"
LIVE.INFO_URL = "https://github.com/barkovaz/skill-preallocation/blob/main/SECURITY.md"

local function file_exists(path)
	local ok, found = pcall(function()
		local f = io.open(path, "rb")
		if f then f:close() return true end
		return false
	end)
	return ok and found
end

-- A file's bytes; or nil and "missing" (it isn't there) or "unreadable" (it is, but can't be read now).
local function read_file(path)
	local ok, data, why = pcall(function()
		local f, err, code = io.open(path, "rb")
		if not f then
			local missing = code == 2 or string.match(tostring(err), "No such file") ~= nil
			return nil, missing and "missing" or "unreadable"
		end
		local d = f:read("*a")
		f:close()
		return d
	end)
	if not ok then return nil, "unreadable" end
	return data, why
end

-- The marker: { state, version, sha256 }, or nil. States: "written" (the mod wrote the DLL, or found it
-- there), "removed" (gone since), "changed" (someone changed it since), "blocked" (couldn't be written),
-- "refused" (Windows didn't load it), "off" (the player turned the module off).
local function read_marker()
	local text = read_binary(LIVE.MARKER)
	if not text then return nil end
	local state = string.match(text, 'state%s*=%s*"(%a+)"')
	if not state then return nil end
	return { state = state, version = string.match(text, 'version%s*=%s*"([^"]*)"'), sha256 = string.match(text, 'sha256%s*=%s*"(%x*)"') }
end

local function write_marker(state, info)
	pcall(function()
		local f = io.open(LIVE.MARKER, "wb")
		if not f then return end
		f:write("-- Skill Pre-Allocation: its native module, skill_preallocation_native.dll, in this folder.\n",
			"-- It reads the game's mod list and pack files (the skill tables), nothing else.\n",
			"-- What it is and how to check it: ", LIVE.INFO_URL, "\n",
			"-- If the DLL is removed (by you or an antivirus) the mod doesn't write it again, and says so in\n",
			"-- skill_preallocation_log.txt. Delete this file to let the mod write it again.\n",
			"-- To turn the module off, create an empty skill_preallocation_no_native.txt here.\n",
			'state = "', state, '"\n',
			'version = "', tostring(info and info.version or "?"), '"     -- (the native module\'s version)\n',
			'sha256 = "', tostring(info and info.sha256 or ""), '"\n')
		f:close()
	end)
end

local STOPPED = {
	removed = "was removed from the game's folder after the mod wrote it (by an antivirus, or by hand)",
	changed = "was changed in the game's folder after the mod wrote it (by an antivirus?)",
	blocked = "couldn't be written into the game's folder in an earlier session (an antivirus?)",
}

function LIVE.load_native()
	if LIVE.native_tried then return LIVE.native, LIVE.native_problem end
	LIVE.native_tried = true
	local function fail(why)
		LIVE.native_problem = why
		return nil, why
	end
	if type(package) ~= "table" or type(require) ~= "function" or type(io) ~= "table" then
		return fail("this game's Lua can't load a native module")
	end
	if type(package.config) == "string" and string.sub(package.config, 1, 1) ~= "\\" then
		return fail("not Windows: the native module is a Windows DLL")
	end
	local marker = read_marker()
	for _, name in ipairs(LIVE.OPT_OUT_NAMES) do
		if file_exists(name) then
			if marker and marker.state ~= "off" then write_marker("off", marker) end
			return fail("turned off: " .. name .. " is in the game's folder")
		end
	end
	if marker and marker.state == "off" then marker = nil end      -- (turned on again: as on a first start)
	local chunk, why
	for _, path in ipairs(LIVE.BIN) do
		local ok, c, e = pcall(loadfile, path)
		if ok and c then chunk = c break end
		why = ok and e or c
	end
	if not chunk then return fail("the module's file is missing from the pack: " .. tostring(why)) end
	local okb, bin = pcall(chunk)
	if not okb or type(bin) ~= "table" or type(bin.data) ~= "string" or type(bin.module) ~= "string" then
		return fail("the module's file in the pack is broken: " .. tostring(bin))
	end
	if bin.size and #bin.data ~= bin.size then
		return fail("the module's file in the pack is cut short (" .. #bin.data .. " of " .. tostring(bin.size) .. " bytes)")
	end
	local file = bin.module .. ".dll"
	local again = ", so the mod leaves it be; to let it write the DLL again, delete " .. LIVE.MARKER .. " from the game's folder"
	local existing, state = read_file(file)
	if existing == nil and state == "unreadable" then
		return fail("can't read " .. file .. " in the game's folder now (in use? blocked?)")
	end
	if existing == nil and marker then
		-- it was there, or the mod tried, and now it isn't: don't put it back
		if not STOPPED[marker.state] then
			marker.state = "removed"
			write_marker("removed", marker)
		end
		return fail(file .. " " .. STOPPED[marker.state] .. again)
	end
	if existing and existing ~= bin.data and marker and (marker.state == "written" or marker.state == "changed")
		and marker.sha256 == bin.sha256 then
		-- the mod wrote this very DLL and something else is there now: don't write over it
		if marker.state ~= "changed" then write_marker("changed", bin) end
		return fail(file .. " " .. STOPPED.changed .. again)
	end
	-- Windows refused this very DLL before: don't ask again until the mod brings another
	if marker and marker.state == "refused" and existing == bin.data and marker.sha256 == bin.sha256 then
		return fail("Windows refused to load " .. file .. " in an earlier session, so the mod doesn't try again until it"
			.. " updates the DLL; to try now, delete " .. LIVE.MARKER .. " from the game's folder")
	end
	if existing ~= bin.data then
		local okw, err = pcall(function()
			local f, e = io.open(file, "wb")
			if not f then error(e or "can't open it", 0) end
			f:write(bin.data)
			f:close()
		end)
		if not okw then
			if existing then
				return fail("the game's folder has another version of " .. file .. ", which can't be replaced now (another game running?): " .. tostring(err))
			end
			write_marker("blocked", bin)
			return fail("can't write " .. file .. " into the game's folder (" .. tostring(err) .. ")" .. again)
		end
		if read_binary(file) ~= bin.data then
			write_marker("changed", bin)
			return fail(file .. " in the game's folder isn't what was written (an antivirus?)" .. again)
		end
		LIVE.native_written = true
	end
	-- load that very file (package.loadlib), or let require find it (the game's Lua might lack loadlib)
	local mod, lerr, how
	if type(package.loadlib) == "function" then
		local okl, f, e = pcall(package.loadlib, ".\\" .. file, "luaopen_" .. bin.module)
		if okl and type(f) == "function" then
			local okc, m = pcall(f, bin.module)
			if okc then mod, how = m, "package.loadlib" else lerr = m end
		else
			lerr = okl and e or f
		end
	end
	if mod == nil then
		local okr, m = pcall(require, bin.module)
		if type(package.loaded) == "table" then package.loaded[bin.module] = nil end
		if okr then
			mod, how, lerr = m, lerr and ("require; package.loadlib: " .. tostring(lerr)) or "require", nil
		elseif lerr == nil then
			lerr = m
		end
	end
	if mod == nil and lerr then
		write_marker("refused", bin)
		return fail("Windows refused to load " .. file .. ": " .. tostring(lerr))
	end
	if not (marker and marker.state == "written" and marker.sha256 == bin.sha256) then write_marker("written", bin) end
	if type(mod) ~= "table" then return fail(file .. " loaded but didn't find the game's Lua functions") end
	if mod.api ~= LIVE.API then
		return fail(file .. " is version " .. tostring(mod.version) .. " (interface " .. tostring(mod.api) .. "), this mod needs interface " .. LIVE.API)
	end
	LIVE.native = mod
	LIVE.native_version = mod.version
	LIVE.native_how = how
	return mod
end

---------------------------------------------------------------- building the data
-- `res` is load_db's result. Returns the data, or nil and why it can't be used.
function LIVE.build(res)
	if type(res) ~= "table" or type(res.tables) ~= "table" then return nil, "no tables in the result" end
	for name, cols in pairs(NEEDED) do
		local t = res.tables[name]
		if not t or (t.n or 0) == 0 then return nil, name .. " has no rows" end
		for _, c in ipairs(cols) do
			if not (t.found and t.found[c]) then return nil, name .. " has no column " .. c end
		end
	end
	local T = res.tables

	-- nodes: key -> row (0-based), fields read from the module's flat rows
	local nt = T.character_skill_nodes
	local nd, nc = nt.data, #nt.columns
	local NC = columns(nt, NODES)
	local node_row = {}
	for r = 0, nt.n - 1 do
		local key = nd[r * nc + NC[1]]
		if key ~= nil then node_row[key] = r end
	end
	local function nf(r, i) local c = NC[i] return c and nd[r * nc + c] end

	-- parents of each node: child -> { parent, link type, ... } (pairs, in table order)
	local lt = T.character_skill_node_links
	local LC = columns(lt, LINKS)
	local parents = {}
	do
		local d, c = lt.data, #lt.columns
		for r = 0, lt.n - 1 do
			local child, parent = d[r * c + LC[1]], d[r * c + LC[2]]
			if child and parent then
				local p = parents[child]
				if not p then p = {} parents[child] = p end
				p[#p + 1] = parent
				p[#p + 1] = d[r * c + LC[3]] or ""
			end
		end
	end

	-- locks of each node: node -> { skill, level, ... }
	local locks = {}
	do
		local t = T.character_skill_nodes_skill_locks
		if t and (t.n or 0) > 0 then
			local KC = columns(t, LOCKS)
			local d, c = t.data, #t.columns
			for r = 0, t.n - 1 do
				local node, skill = d[r * c + KC[1]], d[r * c + KC[2]]
				if node and skill then
					local l = locks[node]
					if not l then l = {} locks[node] = l end
					l[#l + 1] = skill
					l[#l + 1] = d[r * c + KC[3]] or 0
				end
			end
		end
	end

	-- the nodes of each set (set items not switched off, whose node exists), without repeats
	local members = {}
	do
		local t = T.character_skill_node_set_items
		local IC = columns(t, ITEMS)
		local d, c = t.data, #t.columns
		local seen = {}
		for r = 0, t.n - 1 do
			local set, item = d[r * c + IC[1]], d[r * c + IC[2]]
			local off = IC[3] and d[r * c + IC[3]]
			if set and item and off ~= true and node_row[item] then
				local s = seen[set]
				if not s then s = {} seen[set] = s; members[set] = {} end
				if not s[item] then
					s[item] = true
					local m = members[set]
					m[#m + 1] = item
				end
			end
		end
	end

	-- skills: index -> key, and key -> index
	local skills, index = {}, {}
	local function sidx(key)
		local i = index[key]
		if not i then
			i = #skills + 1
			skills[i] = key
			index[key] = i
		end
		return i
	end
	local skill_rows = {}
	local st = T.character_skills
	local SC = columns(st, SKILLS)
	do
		local d, c = st.data, #st.columns
		for r = 0, st.n - 1 do
			local key = d[r * c + SC[1]]
			if key then
				skill_rows[key] = r
				sidx(key)
			end
		end
	end
	for r = 0, nt.n - 1 do
		local key = nd[r * nc + NC[2]]
		if key then sidx(key) end
	end
	local function sf(key, i)
		local r = skill_rows[key]
		local col = SC[i]
		if not r or not col then return nil end
		return st.data[r * #st.columns + col]
	end

	-- max level per skill (the effects of each level, and the level details)
	local maxlvl = {}
	local function raise(key, lv)
		if key and type(lv) == "number" and lv > (maxlvl[key] or 1) then maxlvl[key] = lv end
	end
	local et = T.character_skill_level_to_effects_junctions
	if et and (et.n or 0) > 0 then
		local EC = columns(et, EFFECTS)
		local d, c = et.data, #et.columns
		for r = 0, et.n - 1 do raise(d[r * c + EC[1]], d[r * c + EC[2]]) end
	end
	local generic, filtered = {}, {}
	local dt = T.character_skill_level_details
	if dt and (dt.n or 0) > 0 then
		local DC = columns(dt, DETAILS)
		local d, c = dt.data, #dt.columns
		for r = 0, dt.n - 1 do
			local key, lv = d[r * c + DC[1]], d[r * c + DC[2]]
			raise(key, lv)
			if key and type(lv) == "number" then
				local fac, sub, camp = DC[4] and d[r * c + DC[4]], DC[5] and d[r * c + DC[5]], DC[6] and d[r * c + DC[6]]
				local rank = d[r * c + DC[3]] or 0
				if (fac and fac ~= "") or (sub and sub ~= "") or (camp and camp ~= "") then
					local l = filtered[key]
					if not l then l = {} filtered[key] = l end
					l[#l + 1] = { level = lv, rank = rank, faction = fac or "", subculture = sub or "", campaign = camp or "", row = r }
				else
					local g = generic[key]
					if not g then g = {} generic[key] = g end
					g[lv] = rank
				end
			end
		end
	end

	local data = { live = true, skills = skills, maxlv = {}, ranks = {}, rank_filters = {}, auto = {}, influence = {},
		background = {}, tiers = {}, sets = {} }
	for i, key in ipairs(skills) do
		local total = maxlvl[key] or 1
		if total ~= 1 then data.maxlv[i] = total end
		-- rank needed per level: its level details row, else the skill's unlocked_at_rank for level 1, else
		-- what the level below needed (as the generator bakes it)
		local n = total < 1 and 1 or (total > 60 and 60 or total)
		local out, prev, any = {}, 0, false
		local g = generic[key]
		local first = sf(key, 2)
		for lv = 1, n do
			local r = g and g[lv]
			if r == nil then
				if lv == 1 and skill_rows[key] then r = first or 0 else r = prev end
			end
			prev = r
			out[lv] = tostring(r)
			if r ~= 0 then any = true end
		end
		if any then data.ranks[i] = table.concat(out, ",") end
		local f = filtered[key]
		if f then
			table.sort(f, function(a, b)
				if a.level ~= b.level then return a.level < b.level end
				if a.faction ~= b.faction then return key_less(a.faction, b.faction) end
				if a.subculture ~= b.subculture then return key_less(a.subculture, b.subculture) end
				return a.row < b.row
			end)
			local parts = {}
			for j, e in ipairs(f) do
				parts[j] = e.level .. ":" .. e.rank .. ":" .. e.faction .. ":" .. e.subculture .. ":" .. e.campaign
			end
			data.rank_filters[i] = table.concat(parts, ";")
		end
		local bg = sf(key, 3) == true
		if bg then data.background[i] = true end
		local cost = sf(key, 4)
		if not bg and type(cost) == "number" and cost ~= 0 then data.influence[i] = true end
	end

	-- skills that unlock by themselves at a rank (mounts)
	local ct = T.character_skills_to_level_reached_criterias
	if ct and (ct.n or 0) > 0 then
		local CC = columns(ct, CRITERIA)
		local d, c = ct.data, #ct.columns
		local lists = {}
		for r = 0, ct.n - 1 do
			local key = d[r * c + CC[1]]
			if key then
				local i = sidx(key)
				local l = lists[i]
				if not l then l = {} lists[i] = l end
				l[#l + 1] = tostring(d[r * c + CC[2]] or 0) .. ":" .. tostring(d[r * c + CC[3]] or 0)
			end
		end
		for i, l in pairs(lists) do data.auto[i] = table.concat(l, "+") end
	end

	-- skill points per rank, per agent type and campaign ("*": any campaign)
	local tt = T.character_experience_skill_tiers
	if tt and (tt.n or 0) > 0 then
		local TC = columns(tt, TIERS)
		local d, c = tt.data, #tt.columns
		local by = {}
		for r = 0, tt.n - 1 do
			local agent, rank = d[r * c + TC[1]], d[r * c + TC[3]]
			if agent and type(rank) == "number" then
				local camp = (TC[2] and d[r * c + TC[2]]) or "*"
				if camp == "" then camp = "*" end
				by[agent] = by[agent] or {}
				by[agent][camp] = by[agent][camp] or {}
				by[agent][camp][rank] = d[r * c + TC[4]] or 0
			end
		end
		for agent, camps in pairs(by) do
			data.tiers[agent] = {}
			for camp, ranks in pairs(camps) do
				local list = {}
				for rank in pairs(ranks) do list[#list + 1] = rank end
				table.sort(list)
				local pts = {}
				for j, rank in ipairs(list) do pts[j] = tostring(ranks[rank]) end
				data.tiers[agent][camp] = { first = list[1], points = table.concat(pts, ",") }
			end
		end
	end

	-- the sets (skill trees) with at least one node, and their filters
	local et2 = T.character_skill_node_sets
	local EC2 = columns(et2, SETS)
	do
		local d, c = et2.data, #et2.columns
		for r = 0, et2.n - 1 do
			local key = d[r * c + EC2[1]]
			if key and members[key] then
				local function g(i) local col = EC2[i] local v = col and d[r * c + col] return v or "" end
				data.sets[key] = { subtype = g(2), agent = g(3), faction = g(4), subculture = g(5), campaign = g(6) }
			end
		end
	end

	-- A set's nodes, built when the rules first need them (R.decode_set), as the generator bakes them:
	-- members in tier / indent / key order; per node its REQUIRED and SUBSET_REQUIRED parents in the set
	-- (by position), its locks, and its place in a variant group (see generator/build_data.py).
	function data.decode_set(set_key)
		local h = data.sets[set_key]
		local list = members[set_key]
		if not h or not list then return nil end
		local m = {}
		for i, k in ipairs(list) do m[i] = k end
		local tier, indent = {}, {}
		for _, k in ipairs(m) do
			local r = node_row[k]
			tier[k], indent[k] = nf(r, 3) or 0, nf(r, 4) or 0
		end
		local function order(a, b)
			if tier[a] ~= tier[b] then return tier[a] < tier[b] end
			if indent[a] ~= indent[b] then return indent[a] < indent[b] end
			return key_less(a, b)
		end
		table.sort(m, order)
		local pos = {}
		for i, k in ipairs(m) do pos[k] = i end
		local member_skills = {}
		for _, k in ipairs(m) do
			local sk = nf(node_row[k], 2)
			member_skills[sk] = member_skills[sk] or {}
			table.insert(member_skills[sk], k)
		end
		-- parents inside the set (any link type), in table order
		local in_set = {}
		for _, k in ipairs(m) do
			local l, p = parents[k], {}
			if l then
				for j = 1, #l, 2 do if pos[l[j]] then p[#p + 1] = l[j] end end
			end
			in_set[k] = p
		end
		-- variant groups: nodes connected by locks
		local adj, has_adj = {}, {}
		for _, k in ipairs(m) do
			local l = locks[k]
			if l then
				for j = 1, #l, 2 do
					for _, o in ipairs(member_skills[l[j]] or {}) do
						adj[k] = adj[k] or {}
						adj[o] = adj[o] or {}
						adj[k][o] = true
						adj[o][k] = true
						has_adj[k], has_adj[o] = true, true
					end
				end
			end
		end
		local variant, seen, group_no = {}, {}, 0
		for _, k in ipairs(m) do
			if has_adj[k] and not seen[k] then
				local comp, stack = {}, { k }
				while #stack > 0 do
					local v = table.remove(stack)
					if not comp[v] then
						comp[v] = true
						for o in pairs(adj[v] or {}) do stack[#stack + 1] = o end
					end
				end
				for v in pairs(comp) do seen[v] = true end
				group_no = group_no + 1
				local comp_list = {}
				for _, v in ipairs(m) do if comp[v] then comp_list[#comp_list + 1] = v end end
				local heads = {}
				for _, v in ipairs(comp_list) do
					local top = true
					for _, p in ipairs(in_set[v]) do if comp[p] then top = false break end end
					if top then heads[#heads + 1] = v end
				end
				table.sort(heads, order)
				local branch_of = {}
				for b, head in ipairs(heads) do
					local frontier = { head }
					while #frontier > 0 do
						local v = table.remove(frontier)
						if not branch_of[v] then
							branch_of[v] = b
							for _, c in ipairs(comp_list) do
								for _, p in ipairs(in_set[c]) do
									if p == v then frontier[#frontier + 1] = c break end
								end
							end
						end
					end
				end
				-- a variant line goes on through children that only hang below that one branch
				local changed = true
				while changed do
					changed = false
					for _, v in ipairs(m) do
						if not branch_of[v] and #in_set[v] > 0 then
							local b, same = nil, true
							for _, p in ipairs(in_set[v]) do
								local pb = branch_of[p]
								if pb == nil or (b ~= nil and pb ~= b) then same = false break end
								b = pb
							end
							if same and b then
								branch_of[v] = b
								changed = true
							end
						end
					end
				end
				local depth = {}
				for v, b in pairs(branch_of) do
					local d, cur = 0, v
					for _ = 1, 60 do                -- (as the generator: at most 60 steps up)
						local best
						for _, p in ipairs(in_set[cur]) do
							if branch_of[p] == b and (best == nil or key_less(p, best)) then best = p end
						end
						if not best then break end
						cur = best
						d = d + 1
					end
					depth[v] = d
				end
				local by_branch = {}
				for v, b in pairs(branch_of) do
					by_branch[b] = by_branch[b] or {}
					table.insert(by_branch[b], v)
				end
				for b, l in pairs(by_branch) do
					table.sort(l, function(x, y)
						if depth[x] ~= depth[y] then return depth[x] < depth[y] end
						return order(x, y)
					end)
					for p_i, v in ipairs(l) do variant[v] = { group = group_no, branch = b, pos = p_i } end
				end
			end
		end
		local set = { key = set_key, subtype = h.subtype, agent = h.agent, faction = h.faction, subculture = h.subculture,
			campaign = h.campaign, nodes = {} }
		for i, k in ipairs(m) do
			local r = node_row[k]
			local node = {
				index = i, skill = nf(r, 2), tier = tier[k], indent = indent[k],
				rnp = nf(r, 5) or 0, poc = nf(r, 6) or 0, visible = nf(r, 7) == true,
				faction = nf(r, 8) or "", subculture = nf(r, 9) or "", campaign = nf(r, 10) or "",
				req = {}, sub = {}, locks = {}, variant = variant[k],
			}
			local l = parents[k]
			if l then
				for j = 1, #l, 2 do
					local p = pos[l[j]]
					if p then
						if l[j + 1] == "REQUIRED" then node.req[#node.req + 1] = p
						elseif l[j + 1] == "SUBSET_REQUIRED" then node.sub[#node.sub + 1] = p end
					end
				end
			end
			table.sort(node.req)
			table.sort(node.sub)
			local lk = locks[k]
			if lk then
				for j = 1, #lk, 2 do node.locks[#node.locks + 1] = { skill = lk[j], level = lk[j + 1] } end
				table.sort(node.locks, function(a, b)
					if a.skill ~= b.skill then return key_less(a.skill, b.skill) end
					return a.level < b.level
				end)
			end
			set.nodes[i] = node
		end
		return set
	end

	local nsets = 0
	for _ in pairs(data.sets) do nsets = nsets + 1 end
	data.version = "live " .. string.sub(tostring(res.digest or "?"), 1, 12)
	data.built_from = "the game's packs"
	data.report = { sets = nsets, skills = #skills, nodes = nt.n }
	return data
end

---------------------------------------------------------------- reading and checking
-- The table files the game has (its own file listing), per table: name -> true. nil when the game's
-- Lua has no common.filesystem_lookup.
local function game_files(folder)
	if type(common) ~= "table" or type(common.filesystem_lookup) ~= "function" then return nil end
	local ok, found = pcall(common.filesystem_lookup, "/db/" .. folder .. "/", "*")
	if not ok or type(found) ~= "string" then return nil end
	local names = {}
	for entry in string.gmatch(found, "[^,]+") do
		local name = string.match(entry, "([^/\\]+)$")
		if name and name ~= "" then names[string.lower(name)] = name end
	end
	return names
end

-- What the module read against what the game lists, for the tables whose listing works (it names the
-- game's own data__): `missing`, table files the game has that the module didn't find (a pack it doesn't
-- know about); `extra`, files the module read that the game doesn't have (packs the game didn't load: a
-- wrong mod list). Lists of "table/file" texts.
function LIVE.compare_files(res)
	local missing, extra = {}, {}
	for name, t in pairs(res.tables or {}) do
		local listed = game_files(name .. "_tables")
		if listed and listed["data__"] then
			local read = {}
			for _, f in ipairs(t.files or {}) do read[string.lower(f.name)] = f.name end
			for low, file in pairs(listed) do
				if not read[low] then missing[#missing + 1] = name .. "/" .. file end
			end
			for low, file in pairs(read) do
				if not listed[low] then extra[#extra + 1] = name .. "/" .. file end
			end
		end
	end
	table.sort(missing)
	table.sort(extra)
	return missing, extra
end

-- Why the module's result can't be used, or nil: a table file of the game's own packs, or one named
-- data__ (it hides the game's own), that couldn't be read: the game's rows would be missing.
function LIVE.unusable(res)
	local kind = {}
	for _, p in ipairs(res.packs or {}) do kind[p.name] = p.kind end
	for name, t in pairs(res.tables or {}) do
		for _, f in ipairs(t.files or {}) do
			if f.problem and (kind[f.pack] == "vanilla" or string.lower(f.name) == "data__") then
				return name .. "/" .. f.name .. " in " .. tostring(f.pack) .. " couldn't be read (" .. tostring(f.problem)
					.. "): the game's own rows would be missing"
			end
		end
	end
	return nil
end

-- The live data, or nil and why. `log` (optional) gets the summary lines.
function LIVE.load(log)
	log = log or function() end
	local native, why = LIVE.load_native()
	if not native then return nil, why end
	local clock = type(os) == "table" and type(os.clock) == "function" and os.clock or function() return 0 end
	local t0 = clock()
	local ok, res, err = pcall(native.load_db, { tables = LIVE.TABLES })
	if not ok then return nil, "the module failed: " .. tostring(res) end
	if not res then return nil, "the module read nothing: " .. tostring(err) end
	local bad = LIVE.unusable(res)
	if bad then return nil, bad end
	local missing, extra = LIVE.compare_files(res)
	if #extra > 0 then
		return nil, "the mod read table files the game didn't load (the mod list " .. tostring(res.source)
			.. " isn't the game's?): " .. table.concat(extra, ", ")
	end
	local t1 = clock()
	local okb, data, berr = pcall(LIVE.build, res)
	if not okb then return nil, "building the trees failed: " .. tostring(data) end
	if not data then return nil, berr end
	local t2 = clock()
	local mods, movies = 0, 0
	for _, p in ipairs(res.packs or {}) do
		if p.kind == "mod" and p.path then mods = mods + 1 elseif p.kind == "movie" then movies = movies + 1 end
	end
	local files = {}
	for name, t in pairs(res.tables) do
		for _, f in ipairs(t.files or {}) do
			if f.pack ~= "db.pack" then files[#files + 1] = name .. "/" .. f.name .. " (" .. f.pack .. ", " .. tostring(f.kept) .. " rows)" end
		end
	end
	table.sort(files)
	data.report.mods, data.report.movies, data.report.files = mods, movies, files
	data.report.warnings = res.warnings or {}
	data.report.source = res.source
	data.report.read_s, data.report.build_s = t1 - t0, t2 - t1
	data.report.unseen = missing
	data.built_from = "the game's packs: " .. mods .. " mods (" .. tostring(res.source) .. ")"
	log(string.format("live skill data %s: module %s, %d skill trees, %d skills from db.pack and %d mods, read in %.2f s + %.2f s",
		data.version, tostring(native.version), data.report.sets, data.report.skills, mods, data.report.read_s, data.report.build_s))
	if #files > 0 then log("skill tables from mods: " .. table.concat(files, "; ")) end
	return data
end
