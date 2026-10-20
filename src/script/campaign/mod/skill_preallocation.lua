-- Skill Pre-Allocation for Total War: WARHAMMER III
--
-- Click skills in a lord's or hero's skill tree while they have no free points and the points are
-- pre-allocated: as the character ranks up, the points are spent on them in that order, each as soon as
-- it comes (a skill can only be planned where its rank is reached by then, so no point is left unspent
-- while pre-allocations remain), following the same rules as a normal allocation (the "Allocate now"
-- button spends free points on them too).
-- Presets of a whole tree are kept in a file shared by all campaigns.
--
-- Files:
--   skill_preallocation_data.lua   rules baked from the game's database (generated; used when the live
--                                  data can't be read)
--   skill_preallocation_live.lua   the live rules: read from the packs the game loaded, mods included,
--                                  through the mod's own native module (script/skill_preallocation/native_bin.lua)
--   skill_preallocation_rules.lua  rules engine (pure logic)
--   skill_preallocation.lua        this file: game integration, saving, spending, logging
--   skill_preallocation_text.lua   the mod's texts in the game's 13 languages
--   skill_preallocation_ui.lua     the skills panel integration
--
-- Notes on the game's scripting environment learned the hard way:
--   * string.find is plain-text only here (CA's own scripts call string.find(s, "%")): never give
--     it a pattern; use string.match / string.gmatch for patterns.
--   * do nothing heavy while a campaign is starting up (no context-system reads, no UI triggers).
--   * keep context-system reads few: the character's tree is read once (skill keys + levels) and
--     then kept up to date from game events.
--   * the context system's AddPoint/CommitSkillChoices belong to the skills panel's own "choices
--     not confirmed yet" state: called from a script they swallowed the point without learning the
--     skill. Points are spent with the game's add_skill instead (what CA's own scripts use).
--   * CA's out() can fail in some setups, so the mod calls cm.game_interface directly.
--   * the CharacterSkillPointAllocated event comes straight away (inside add_skill).

SKILL_PREALLOCATION = SKILL_PREALLOCATION or {}
local SPA = SKILL_PREALLOCATION
SPA.VERSION = "0.19.2"

local T_CHAR = "CcoCampaignCharacter"
local PRESET_FILE = "skill_preallocation_presets.lua"
local LOG_FILE = "skill_preallocation_log.txt"
local MSG = "spa2|"                      -- prefix of this mod's UI trigger messages (spa2: skill keys)
local SAVE_KEY = "skill_preallocation_state_v1"

local function R() return SKILL_PREALLOCATION_RULES end
local function D() return SKILL_PREALLOCATION_RULES.data() end   -- the rules' data (live, or else baked)
local function BAKED() return SKILL_PREALLOCATION_DATA end

---------------------------------------------------------------- logging
-- Everything goes to skill_preallocation_log.txt in the game folder, written so that normal play does
-- no file writes at all:
--   * SPA.log(...) keeps the last LOG_KEEP events in memory, as raw values (no text is built). They are
--     written only when something goes wrong: an error or a warning is written with the events that led
--     up to it, in one go.
--   * Debug mode also writes every event, in batches (one write about a second after the first line
--     waiting). It is on with SPA.debug = true in this file, or when a file named
--     skill_preallocation_debug.txt exists in the game folder (checked once, when the scripts load).
--   * Guards: the same message is written once (repeats are counted: a note at the 10th, 100th, ...),
--     at most LOG_MAX_ERRORS errors and LOG_MAX_WARNINGS warnings per session; the first write of a
--     session starts with a header line; a log bigger than LOG_MAX_BYTES starts over.
-- Nothing runs periodically: the only timer is the one-off batch write in debug mode.
SPA.debug = false
local DEBUG_FLAG_FILE = "skill_preallocation_debug.txt"
local LOG_KEEP = 200
local LOG_MAX_ERRORS, LOG_MAX_WARNINGS = 30, 10
local LOG_MAX_BYTES = 1000000
local LOG_FLUSH_MS = 1000

-- os may be partly missing in some setups: only what exists is used
local clock = type(os) == "table" and type(os.clock) == "function" and os.clock or nil
local now_time = type(os) == "table" and type(os.time) == "function" and os.time or nil
local traceback = type(debug) == "table" and type(debug.traceback) == "function" and debug.traceback or nil
local clock_at_load = clock and clock() or 0

function SPA.read_debug_flag()
	local ok, f = pcall(io.open, DEBUG_FLAG_FILE, "r")
	if ok and f then
		pcall(function() f:close() end)
		return true
	end
	return false
end
SPA.debug = SPA.debug or SPA.read_debug_flag()

local recent, recent_n = {}, 0       -- the last LOG_KEEP events (a ring); recent_n = events kept so far
local written_upto = 0               -- events up to this number are in the file already
local pending = {}                   -- debug lines waiting for the batch write
local flush_due = false
local counts, budget = {}, { ERROR = LOG_MAX_ERRORS, WARNING = LOG_MAX_WARNINGS }
SPA.log_session_open = false         -- the session's header is written (false again = a new session, for tests)
SPA.started = false                  -- the first tick has come (timers can be used)

local function keep(level, ...)
	recent_n = recent_n + 1
	local n = select("#", ...)
	local e = { level, now_time and now_time() or 0, clock and clock() or 0, n, ... }
	for i = 5, 4 + n do                -- plain values are kept as they are; game objects as text only
		local t = type(e[i])
		if t ~= "string" and t ~= "number" and t ~= "boolean" and t ~= "nil" then e[i] = tostring(e[i]) end
	end
	recent[(recent_n - 1) % LOG_KEEP + 1] = e
	return e
end

local function format_entry(e)
	local parts = {}
	for i = 5, 4 + e[4] do parts[#parts + 1] = tostring(e[i]) end
	local ok, t = pcall(os.date, "%Y-%m-%d %H:%M:%S", e[2] ~= 0 and e[2] or nil)
	return string.format("[%s +%.3fs] %s%s", ok and t or "?", e[3] - clock_at_load,
		e[1] ~= "" and (e[1] .. ": ") or "", table.concat(parts, " "))
end

local function header()
	local function get(fn)
		local ok, v = pcall(fn)
		return (ok and v ~= nil and v ~= "") and tostring(v) or "?"
	end
	return "==== Skill Pre-Allocation " .. SPA.VERSION
		.. " | data " .. get(function() return D().version end)
		.. " | native " .. get(function() return SPA.native_state() end)
		.. " | campaign " .. get(function() return SPA.campaign_key() end)
		.. " | faction " .. get(function() return SPA.local_faction_name() end)
		.. " | multiplayer " .. get(function() return cm:is_multiplayer() end)
		.. " | language " .. get(function() return SPA.text.lang end)
		.. " | debug " .. tostring(SPA.debug) .. " ===="
end

local function file_size(path)
	local ok, size = pcall(function()
		local f = io.open(path, "r")
		if not f then return 0 end
		local s = f:seek("end")
		f:close()
		return s or 0
	end)
	return ok and size or 0
end

-- One write for all `lines` (the session's header first, the first time).
local function write_lines(lines)
	if #lines == 0 then return end
	pcall(function()
		local mode = "a"
		if not SPA.log_session_open then
			SPA.log_session_open = true
			if file_size(LOG_FILE) > LOG_MAX_BYTES then mode = "w" end
			table.insert(lines, 1, header())
		end
		local f = io.open(LOG_FILE, mode)
		if not f then return end
		f:write(table.concat(lines, "\n"), "\n")
		f:close()
	end)
end

-- Write the debug lines waiting (debug mode).
function SPA.flush_log()
	flush_due = false
	if #pending == 0 then return end
	local lines = pending
	pending = {}
	write_lines(lines)
end

local function flush_soon()
	if flush_due or #pending == 0 or not SPA.started then return end   -- before the first tick: taken along later
	flush_due = true
	local ok = pcall(function() cm:real_callback(SPA.flush_log, LOG_FLUSH_MS, "spa_log_flush") end)
	if not ok then SPA.flush_log() end
end
SPA.flush_log_soon = flush_soon

function SPA.log(...)
	local e = keep("", ...)
	if SPA.debug then
		pending[#pending + 1] = format_entry(e)
		written_upto = recent_n
		flush_soon()
	end
end
local log = SPA.log

-- An error or warning: written straight away, with the events before it that aren't in the file yet.
local function report(level, ...)
	local parts = {}
	for i = 1, select("#", ...) do parts[#parts + 1] = tostring((select(i, ...))) end
	local msg = table.concat(parts, " ")
	local e = keep(level, msg)
	local n = (counts[msg] or 0) + 1
	counts[msg] = n
	if n > 1 then
		local k = n
		while k % 10 == 0 do k = k / 10 end
		if k == 1 then write_lines({ format_entry(e) .. "  (the same " .. string.lower(level) .. " " .. n .. " times so far)" }) end
		return
	end
	if (budget[level] or 0) <= 0 then return end
	budget[level] = budget[level] - 1
	local lines = pending                -- debug lines waiting go first, so the file stays in order
	pending = {}
	lines[#lines + 1] = string.gsub(format_entry(e), "^(%[[^%]]*%] )", "%1Skill Pre-Allocation " .. SPA.VERSION .. " ")
	local first = math.max(written_upto + 1, recent_n - LOG_KEEP + 1)
	if first < recent_n then
		lines[#lines + 1] = "  what happened before it (oldest first):"
		for seq = first, recent_n - 1 do lines[#lines + 1] = "    " .. format_entry(recent[(seq - 1) % LOG_KEEP + 1]) end
	end
	if budget[level] == 0 then
		lines[#lines + 1] = "  (no more " .. string.lower(level) .. "s are written this session)"
	end
	written_upto = recent_n
	write_lines(lines)
end

function SPA.error(...) report("ERROR", ...) end
function SPA.warn(...) report("WARNING", ...) end

-- Run fn(...); an error in it is written to the log (with a stack trace when the game's Lua has one)
-- instead of stopping the caller. Returns fn's results, or nil after an error.
local function on_error(err)
	if traceback then
		local ok, tb = pcall(traceback, tostring(err), 3)      -- (from where the error was raised)
		if ok and type(tb) == "string" then return tb end
	end
	return tostring(err)
end

local function pack(...) return { n = select("#", ...), ... } end

function SPA.safe(label, fn, ...)
	local args = pack(...)
	local res = pack(xpcall(function() return fn(unpack(args, 1, args.n)) end, on_error))
	if not res[1] then
		SPA.error("in " .. label .. ": " .. tostring(res[2]))
		return nil
	end
	return unpack(res, 2, res.n)
end
local safe = SPA.safe

local function read_file(path)
	local ok, text = pcall(function()
		local f = io.open(path, "r")
		if not f then return nil end
		local t = f:read("*a")
		f:close()
		return t
	end)
	return ok and text or nil
end

local function write_file(path, text)
	local ok, written = pcall(function()
		local f = io.open(path, "w")
		if not f then return false end
		f:write(text)
		f:close()
		return true
	end)
	return ok and written
end

---------------------------------------------------------------- context system
local context_calls = 0

local function ccv(obj_type, id, expr)
	context_calls = context_calls + 1
	local ok, v = pcall(common.get_context_value, obj_type, id, expr)
	if ok then return v end
	return nil
end
SPA.ccv = ccv

function SPA.points(cqi)
	return ccv(T_CHAR, tostring(cqi), "SkillPointsAvailable") or 0
end

---------------------------------------------------------------- characters
function SPA.character(cqi)
	local ok, c = pcall(function() return cm:get_character_by_cqi(cqi) end)
	if ok and c and not c:is_null_interface() then return c end
	return nil
end

function SPA.local_faction_name()
	local ok, name = pcall(function() return cm:get_local_faction_name(true) end)
	return ok and name or nil
end

function SPA.is_local_character(char)
	return char ~= nil and char:faction():name() == SPA.local_faction_name()
end

function SPA.campaign_key()
	local ok, k = pcall(function() return cm:model():campaign_name_key() end)
	return ok and k or ""
end

-- Read a character's skills from the game: only the skill keys and their levels (two reads per
-- skill). Everything else comes from the baked data.
function SPA.read_live(char)
	local cqi = char:command_queue_index()
	local id = tostring(cqi)
	local before = context_calls
	local live = {
		cqi = cqi, subtype = char:character_subtype_key(), agent = char:character_type_key(),
		faction = char:faction():name(), subculture = char:faction():subculture(), campaign = SPA.campaign_key(),
		rank = char:rank(), points = ccv(T_CHAR, id, "SkillPointsAvailable") or 0, skills = {}, hidden = {},
	}
	local n = ccv(T_CHAR, id, "SkillList.Size") or 0
	for i = 0, n - 1 do
		local key = ccv(T_CHAR, id, "SkillList.At(" .. i .. ").Key")
		if key then
			live.skills[#live.skills + 1] = { key = key, list_index = i, level = ccv(T_CHAR, id, "SkillList.At(" .. i .. ").Level") or 0 }
		end
	end
	log("read", cqi, live.subtype, "skills=" .. #live.skills, "points=" .. live.points, "rank=" .. live.rank,
		"context reads=" .. (context_calls - before))
	return live
end

-- Trees are cached per character; levels and points are kept up to date from game events.
SPA.live_cache, SPA.tree_cache = {}, {}

-- Choices the player clicked in the skills panel that the game has not applied yet (it applies them
-- when the panel closes): cqi -> { [skill] = points }. The rules count them as learned already.
SPA.pending_choices = {}

function SPA.has_unconfirmed(cqi)
	local p = SPA.pending_choices[cqi]
	return p ~= nil and next(p) ~= nil
end

local function rebuild(cqi)
	local live = SPA.live_cache[cqi]
	if not live then return nil end
	local src = live
	if SPA.has_unconfirmed(cqi) then
		local pend = SPA.pending_choices[cqi]
		src = {}
		for k, v in pairs(live) do src[k] = v end
		src.skills = {}
		for i, s in ipairs(live.skills) do
			local c = {}
			for k, v in pairs(s) do c[k] = v end
			c.level = (s.level or 0) + (pend[s.key] or 0)
			src.skills[i] = c
		end
	end
	local tree = R().build_tree(src)
	-- without the live data (not read yet, or off) points on skills the baked data doesn't know are kept
	-- (R.kept)
	tree.keep_unknown = SPA.live_state ~= "live"
	SPA.tree_cache[cqi] = tree
	return tree
end

function SPA.tree(cqi, reread)
	if not SPA.live_tried and SPA.started then SPA.activate_live() end   -- (needed before the mod is ready)
	if not reread and SPA.tree_cache[cqi] then return SPA.tree_cache[cqi] end
	local char = SPA.character(cqi)
	if not char then return nil end
	SPA.live_cache[cqi] = SPA.read_live(char)
	return rebuild(cqi)
end

-- Cheap refresh: rank from the model, points with one read.
function SPA.refresh_points(cqi)
	local live = SPA.live_cache[cqi]
	local char = SPA.character(cqi)
	if not live or not char then return end
	live.rank = char:rank()
	live.points = SPA.points(cqi)
	rebuild(cqi)
end

-- The cached entry of one skill of a character (nil if the tree was never read).
function SPA.live_skill(cqi, key)
	local live = SPA.live_cache[cqi]
	if not live then return nil end
	for _, s in ipairs(live.skills) do
		if s.key == key then return s end
	end
	return nil
end

-- A point landed on `skill` (by this mod, by hand or granted by the game).
local function bump_level(cqi, skill)
	local s = SPA.live_skill(cqi, skill)
	if not s then return end
	s.level = (s.level or 0) + 1
	SPA.refresh_points(cqi)
end

function SPA.forget(cqi)
	SPA.live_cache[cqi] = nil
	SPA.tree_cache[cqi] = nil
end

---------------------------------------------------------------- live data (the rules read from the game's packs)
-- The rules come from the packs the game loaded (skill_preallocation_live.lua, through the mod's own
-- native module) once they are read: when the mod gets ready, or the first time a tree is needed before
-- that. Until then, and whenever they can't be read, the baked data is used (vanilla trees only).
SPA.live_state = "not read yet"            -- "live", "baked: <why>"

function SPA.native_state()
	local L = SKILL_PREALLOCATION_LIVE
	if not L then return "no live module" end
	if L.native then
		local notes = { L.native_how }                              -- (package.loadlib, or require)
		if L.native_written then notes[#notes + 1] = "written now" end
		return "loaded " .. tostring(L.native_version) .. (#notes > 0 and (" (" .. table.concat(notes, ", ") .. ")") or "")
	end
	if L.native_problem then return "off: " .. tostring(L.native_problem) end
	return "not loaded yet"
end

-- The native module (once a session, by SPA.activate_live): the log says how it was loaded, or why not.
function SPA.load_native()
	local L = SKILL_PREALLOCATION_LIVE
	if not L or not L.load_native then return nil end
	local mod, why = L.load_native()
	if mod then log("native module " .. SPA.native_state()) else log("native module off: " .. tostring(why)) end
	return mod
end

-- Read the live data and make it the rules' source. Returns whether it is in use. Without it, a plan made
-- with it keeps its points on skills the baked data doesn't know (see R.kept).
function SPA.activate_live()
	if SPA.live_tried then return SPA.live_state == "live" end
	SPA.live_tried = true
	local L = SKILL_PREALLOCATION_LIVE
	local data, why
	SPA.load_native()
	if L and L.load then
		local ok, d, w = pcall(L.load, log)
		if ok then data, why = d, w else why = tostring(d) end
	else
		why = "skill_preallocation_live.lua is missing"
	end
	if not data then
		SPA.live_state = "baked: " .. tostring(why)
		SPA.warn("live skill data off (" .. tostring(why) .. "): the baked vanilla data is used, so skill trees that other mods"
			.. " add or change can't be planned; points already planned on their skills are kept, and wait for the live data")
		return false
	end
	R().use_source(data)
	SPA.tree_cache = {}                      -- trees made from the baked data are made again
	SPA.live_state = "live"
	local rep = data.report or {}
	if rep.warnings and #rep.warnings > 0 then
		SPA.warn("live skill data: " .. table.concat(rep.warnings, "; "))
	end
	if rep.unseen and #rep.unseen > 0 then
		SPA.warn("live skill data: the game has table files the mod didn't find in its packs (a pack loaded another way?): "
			.. table.concat(rep.unseen, ", "))
	end
	return true
end

-- Run fn(item) for each item, one every 200 ms, so nothing stalls the game; then done().
function SPA.run_staggered(list, fn, done)
	local i = 0
	local function step()
		i = i + 1
		local item = list[i]
		if item == nil then
			if done then safe("staggered done", done) end
			return
		end
		safe("staggered", fn, item)
		cm:real_callback(step, 200)
	end
	step()
end

---------------------------------------------------------------- plan state (saved with the campaign)
-- SPA.plans[cqi]   = { keys = { skill, skill, ... }, preset = "name" or nil }
--                    (kept with no keys while the character is linked to a preset)
-- SPA.history[cqi] = { skill, ... }  order in which points were spent while the mod was active
SPA.plans, SPA.history = {}, {}
SPA.ready = false       -- nothing reacts to game events until the campaign has fully started

-- UI triggers carry the skill keys themselves: the players' games may read the rules from different
-- sources (one with the live data, one with the baked data), whose skill numbers differ.
local function encode_keys(keys)
	return table.concat(keys, ",")
end

local function decode_keys(s)
	local keys = {}
	for _, k in ipairs(R().split(s or "", ",")) do
		if k ~= "" then keys[#keys + 1] = k end
	end
	return keys
end

local function clean_name(name)
	name = tostring(name or "")
	name = string.gsub(name, "[|;:,\n\r\t]", " ")
	name = string.gsub(name, "^%s+", "")
	name = string.gsub(name, "%s+$", "")
	if #name > 40 then name = string.sub(name, 1, 40) end
	return name
end
SPA.clean_name = clean_name

-- Saves hold the skill keys themselves (through a small dictionary), so a save stays valid when
-- the baked data is rebuilt after a game patch.
--   v2;K:0::key,key,...;P:<cqi>:<preset>:<i>,<i>,...;H:<cqi>::<i>,...
function SPA.serialize_state()
	local dict, index = {}, {}
	local function enc(keys)
		local out = {}
		for _, k in ipairs(keys) do
			if not index[k] then dict[#dict + 1] = k; index[k] = #dict end
			out[#out + 1] = tostring(index[k])
		end
		return table.concat(out, ",")
	end
	local rows = {}
	for cqi, p in pairs(SPA.plans) do
		if #p.keys > 0 or p.preset then rows[#rows + 1] = "P:" .. cqi .. ":" .. clean_name(p.preset) .. ":" .. enc(p.keys) end
	end
	for cqi, h in pairs(SPA.history) do
		if #h > 0 then rows[#rows + 1] = "H:" .. cqi .. "::" .. enc(h) end
	end
	table.sort(rows)
	return "v2;K:0::" .. table.concat(dict, ",") .. (#rows > 0 and (";" .. table.concat(rows, ";")) or "")
end

function SPA.deserialize_state(s)
	SPA.plans, SPA.history = {}, {}
	if not s or s == "" then return end
	local parts = R().split(s, ";")
	local v2 = parts[1] == "v2"
	if not v2 and parts[1] ~= BAKED().version then
		log("the saved pre-allocations were made with other game data (" .. tostring(parts[1]) .. ") - they are dropped")
		return
	end
	local dict = {}
	local function dec(payload)
		local keys = {}
		for _, i in ipairs(R().split(payload or "", ",")) do
			local k
			if v2 then k = dict[tonumber(i)] else k = BAKED().skills[tonumber(i)] end
			if k then keys[#keys + 1] = k end
		end
		return keys
	end
	for i = 2, #parts do
		local kind, cqi, name, payload = string.match(parts[i], "^(%a):(%d+):([^:]*):(.*)$")
		cqi = tonumber(cqi)
		if kind == "K" then
			dict = R().split(payload, ",")
		elseif kind == "P" and cqi then
			local keys = dec(payload)
			local preset = name ~= "" and name or nil
			if #keys > 0 or preset then SPA.plans[cqi] = { keys = keys, preset = preset } end
		elseif kind == "H" and cqi then
			SPA.history[cqi] = dec(payload)
		end
	end
end

function SPA.plan(cqi)
	return SPA.plans[cqi] or { keys = {} }
end

---------------------------------------------------------------- plans are personal
-- A plan lives only on the machine of the player who owns the character (and in that player's save).
-- Nothing about plans or presets is sent to other players: in multiplayer the only thing every machine
-- must do is the spending itself, which goes through a UI trigger (see "spending").
function SPA.set_plan(cqi, keys, preset)
	preset = preset and clean_name(preset) or nil
	if preset == "" then preset = nil end
	if #keys == 0 and not preset then
		SPA.plans[cqi] = nil
	else
		SPA.plans[cqi] = { keys = keys, preset = preset }
	end
	log("plan set", cqi, "points=" .. #keys, "preset=" .. tostring(preset))
	if SPA.ui and SPA.ui.on_plan_changed then safe("ui.on_plan_changed", SPA.ui.on_plan_changed, cqi) end
end

local function send_trigger(msg)
	local faction = cm:get_local_faction(true)
	CampaignUI.TriggerCampaignScriptEvent(faction:command_queue_index(), msg)
end

---------------------------------------------------------------- keeping the plan in line with the game
local function same_list(a, b)
	if #a ~= #b then return false end
	for i = 1, #a do if a[i] ~= b[i] then return false end end
	return true
end

-- Re-check a character's pre-allocations against its tree as it is now. A plan that still fits is
-- left exactly as it is (the order is the order of allocation). If something no longer fits (a
-- prerequisite gone, the other variant taken, ...), points move to the first place where they are
-- legal, or are removed. Returns dropped, changed.
-- Without the live data, a plan that holds points the baked data can't check (R.kept) is left exactly as
-- it is: those rules can't tell what really fits on that tree.
SPA.kept_logged = {}
function SPA.revalidate(cqi)
	local plan = SPA.plans[cqi]
	if not plan or #plan.keys == 0 then return 0, false end
	local char = SPA.character(cqi)
	if not char or not SPA.is_local_character(char) then return 0, false end
	local tree = SPA.tree(cqi)
	if not tree or not tree.known then return 0, false end
	local fits, bad, why = R().plan_fits(tree, plan.keys)
	if fits then return 0, false end
	local kept = R().count_kept(tree, plan.keys)
	if kept > 0 then
		if not SPA.kept_logged[cqi] then
			SPA.kept_logged[cqi] = true
			log("plan kept as it is", cqi, "(" .. kept .. " points on skills the baked data doesn't know; live skill data off)")
		end
		return 0, false
	end
	log("plan no longer fits at", tostring(bad), "(" .. tostring(why) .. ")", cqi)
	local res = R().replay(tree, plan.keys)
	if same_list(res.plan, plan.keys) then return #res.dropped, false end
	log("plan re-checked", cqi, "kept=" .. #res.plan, "dropped=" .. #res.dropped)
	SPA.set_plan(cqi, res.plan, plan.preset)
	return #res.dropped, true
end

-- Read a character's tree from the game again. A planned-for skill that lost levels means the
-- skills were reset: the pre-allocations are dropped (the preset link stays). Otherwise the plan
-- is re-checked against the fresh tree.
function SPA.reread(cqi)
	local old = SPA.live_cache[cqi]
	local tree = SPA.tree(cqi, true)
	if not tree then return nil end
	if old and tree.known then
		local prev = {}
		for _, s in ipairs(old.skills) do prev[s.key] = s.level or 0 end
		for _, s in ipairs(SPA.live_cache[cqi].skills) do
			local ts = tree.skills[s.key]
			if ts and ts.plannable and (s.level or 0) < (prev[s.key] or 0) then
				log("skill reset detected", cqi, s.key, prev[s.key], "->", s.level or 0)
				SPA.history[cqi] = nil
				local plan = SPA.plans[cqi]
				if plan and #plan.keys > 0 and SPA.is_local_character(SPA.character(cqi)) then
					SPA.set_plan(cqi, {}, plan.preset)
					log("skill reset: pre-allocations cleared", cqi)
				end
				return tree
			end
		end
	end
	SPA.revalidate(cqi)
	return SPA.tree_cache[cqi]
end

-- The skills panel reported a change of free points after a click on `skill`: `delta` points were
-- chosen (positive) or un-chosen (negative) there, waiting for the game to apply them.
-- Returns how many pre-allocated points no longer fit and were removed.
function SPA.note_choice(cqi, skill, delta)
	if delta == 0 then return 0 end
	local pend = SPA.pending_choices[cqi] or {}
	local n = math.max(0, (pend[skill] or 0) + delta)
	pend[skill] = n > 0 and n or nil
	SPA.pending_choices[cqi] = pend
	SPA.refresh_points(cqi)
	return (SPA.revalidate(cqi))
end

---------------------------------------------------------------- spending
-- Points are spent at two moments only: when a character gains skill points (a rank-up) and when the
-- player clicks the "Allocate now" button. Each time, as many pre-allocations as the free points cover
-- are learned in one go, in plan order. (Every pre-allocation fits the rank its point comes at; a point
-- granted without a rank-up can come before the next one's rank: then it waits, see R.wait_rank.)
--
-- Multiplayer: every machine runs the same game and only commands travel between them, so a change
-- a script makes on one machine only would make the games drift apart (a desync). The decision to
-- spend comes from this player's own plan and UI (a timer, the local faction), so the owner's machine
-- sends it as a UI trigger, "spa2|spend|<cqi>||<skill key>", which reaches every machine; each one
-- then calls add_skill. One point per character is in flight at a time, and the messages are short
-- (UI triggers carry at most 255 characters and go out a few times a second).

-- cqi -> skill: a point of that skill was asked for and its allocation event has not come yet. In
-- single player that is only during the add_skill call (the event comes inside it); in multiplayer it
-- covers the UI trigger's round trip, and no other point is asked for meanwhile.
SPA.spending = {}

-- cqi -> points this mod spent in the current pass. The game's skills panel doesn't show them while it
-- is open, so the UI has it redrawn when the pass is over (UI.on_points_spent).
SPA.unshown = {}

-- Learn one point of `key` through the game: the game checks the skill's requirements and uses one
-- skill point, the same call CA's own scripts make to spend points they grant.
function SPA.add_skill(cqi, key)
	local char = SPA.character(cqi)
	if not char then return false, "character not found" end
	local ok, err = pcall(function() cm.game_interface:add_skill(char, key, false, false) end)
	if not ok then return false, tostring(err) end
	return true
end

-- The next point could not be spent: the stored tree may be out of date (e.g. the skills were
-- reset), so it is read again, which also re-checks the plan. Returns true if the plan changed (its
-- new first point can be tried straight away).
local function spend_failed(cqi, key)
	log("spend: no point spent on", key, "- reading the tree again", cqi)
	SPA.spending[cqi] = nil
	local plan = SPA.plans[cqi]
	SPA.reread(cqi)
	return SPA.plans[cqi] ~= plan
end

local function remove_first(list, value)
	for i, v in ipairs(list) do
		if v == value then table.remove(list, i) return true end
	end
	return false
end

local function add_history(cqi, skill)
	local tree = SPA.tree_cache[cqi]
	local s = tree and tree.skills[skill]
	if s and s.plannable then
		SPA.history[cqi] = SPA.history[cqi] or {}
		table.insert(SPA.history[cqi], skill)
	end
end

-- A point was spent on `skill` and the cached tree already shows it: move the plan on.
local function advance_plan(char, cqi, skill)
	add_history(cqi, skill)
	local tree = SPA.tree_cache[cqi]
	local s = tree and tree.skills[skill]
	if SPA.is_local_character(char) then
		local plan = SPA.plans[cqi]
		if plan and #plan.keys > 0 then
			local keys = {}
			for i, k in ipairs(plan.keys) do keys[i] = k end
			if keys[1] == skill then
				table.remove(keys, 1)
				SPA.set_plan(cqi, keys, plan.preset)
			elseif s and tree and (s.plannable or R().kept(tree, skill)) then
				-- a point spent off-plan (by hand or granted): if it was planned later it is done now, and
				-- the rest is put back in order (e.g. without the other variant, or a point less for it). A
				-- plan holding points the baked data can't check (R.kept) only loses that point.
				local found = remove_first(keys, skill)
				if R().count_kept(tree, keys) > 0 then
					if found then SPA.set_plan(cqi, keys, plan.preset) end
				else
					local res = R().replay(tree, keys)
					if #res.dropped > 0 then log("plan re-checked after off-plan point", cqi, "dropped=" .. #res.dropped) end
					SPA.set_plan(cqi, res.plan, plan.preset)
				end
			end
		end
	end
	if SPA.ui and SPA.ui.on_character_changed then safe("ui.on_character_changed", SPA.ui.on_character_changed, cqi) end
end

-- Spend one free point on the next pre-allocated skill. Returns true when the next one can be tried
-- straight away (the point landed, or the plan was re-checked and changed), else false: nothing more
-- to spend now, or a multiplayer spend is on its way (its allocation event carries on from there).
local function spend_next(cqi)
	local plan = SPA.plans[cqi]
	if not plan or #plan.keys == 0 then return false end
	if SPA.spending[cqi] then return false end           -- a multiplayer spend is on its way
	if SPA.has_unconfirmed(cqi) then return false end    -- choices made by hand in the panel come first
	local char = SPA.character(cqi)
	if not char or not SPA.is_local_character(char) then return false end
	if SPA.points(cqi) <= 0 then return false end
	if ccv(T_CHAR, tostring(cqi), "HasUncommitedSkills") == true then return false end
	local tree = SPA.tree(cqi)
	if not tree then return false end
	local key, rank = plan.keys[1], char:rank()
	local ok_rules, code, detail = R().check(tree, R().new_state(tree), key, rank)
	if not ok_rules then
		if code == "rank" then
			-- (only a point that came before the plan expected it: granted without a rank-up)
			log("spend: the next point waits for rank", tostring(detail), cqi, key)
			return false
		end
		if R().kept(tree, key) then
			-- (without the live data: nothing is spent on it, nor after it, until the live data is back)
			log("spend: the next point waits for the live skill data", cqi, key)
			return false
		end
		log("spend: by the stored tree", key, "can't be taken (" .. tostring(code) .. " " .. tostring(detail or "") .. ")", cqi)
		return spend_failed(cqi, key)
	end
	log("spend:", cqi, key, "rank=" .. rank)
	SPA.spending[cqi] = key
	if cm:is_multiplayer() then
		send_trigger(MSG .. "spend|" .. cqi .. "||" .. encode_keys({ key }))
		return false
	end
	local ok, err = SPA.add_skill(cqi, key)
	if not ok then SPA.error("add_skill " .. key .. ": " .. tostring(err)) end
	if SPA.spending[cqi] then return spend_failed(cqi, key) end    -- no allocation event: not taken
	return true
end

-- Spend the free points on the pre-allocated skills, in plan order, as far as the points and the
-- character's rank allow.
function SPA.try_spend(cqi)
	for _ = 1, 100 do
		if not spend_next(cqi) then break end
	end
	-- the pass is over (in multiplayer: no point on its way any more)
	if not SPA.spending[cqi] and (SPA.unshown[cqi] or 0) > 0 then
		SPA.unshown[cqi] = nil
		if SPA.ui and SPA.ui.on_points_spent then safe("ui.on_points_spent", SPA.ui.on_points_spent, cqi) end
	end
end

-- "Allocate now" in the skills panel.
function SPA.allocate_now(cqi)
	SPA.request_spend(cqi, 0)
end

-- How many pre-allocated points "Allocate now" would spend: the leading ones the free points cover
-- at the character's current rank (up to one that waits for the live data, see R.kept).
function SPA.spendable_now(cqi)
	local plan = SPA.plans[cqi]
	if not plan or #plan.keys == 0 or SPA.has_unconfirmed(cqi) then return 0 end
	if not SPA.live_cache[cqi] then SPA.tree(cqi) end
	SPA.refresh_points(cqi)
	local tree = SPA.tree_cache[cqi]
	if not tree or not tree.known then return 0 end
	local ranks = R().plan_ranks(tree, plan.keys)
	local n = 0
	for i = 1, math.min(#plan.keys, tree.points or 0) do
		if not ranks[i] or ranks[i] > tree.rank or R().kept(tree, plan.keys[i]) then break end
		n = n + 1
	end
	return n
end

-- One spending pass a moment later. A rank-up sends several events (one per point gained, then the
-- rank-up itself): they share a single pass.
function SPA.request_spend(cqi, delay)
	if not SPA.ready then return end
	local name = "spa_spend_" .. tostring(cqi)
	cm:remove_real_callback(name)
	cm:real_callback(function() safe("try_spend", SPA.try_spend, cqi) end, delay or 250, name)
end

-- "spa2|spend|<cqi>||<skill key>" arrives on every machine (the sender's too): each one makes the
-- same call, so the games stay the same. Only the owner of a character can spend its points.
local function on_ui_trigger(context)
	local op, cqi, payload = string.match(context:trigger(), "^spa2|(%a+)|(%d+)|[^|]*|(.*)$")
	cqi = tonumber(cqi)
	if op ~= "spend" or not cqi then return end
	local char = SPA.character(cqi)
	local key = decode_keys(payload)[1]
	if not (char and key and char:faction():command_queue_index() == context:faction_cqi()) then return end
	local ok, err = SPA.add_skill(cqi, key)
	if not ok then SPA.error("add_skill " .. key .. ": " .. tostring(err)) end
	-- on the owner's machine the allocation event asked for the next point; no event means the point
	-- was not taken
	if SPA.spending[cqi] == key and spend_failed(cqi, key) then SPA.request_spend(cqi) end
end

---------------------------------------------------------------- reacting to the game
-- A point was spent on `skill` (by this mod, by the player, or granted by the game).
local function on_skill_allocated(char, skill)
	local cqi = char:command_queue_index()
	local ours = SPA.spending[cqi] == skill                   -- the point this mod asked for landed
	if ours then
		SPA.spending[cqi] = nil
		SPA.unshown[cqi] = (SPA.unshown[cqi] or 0) + 1
	end
	local pend = SPA.pending_choices[cqi]
	if pend and (pend[skill] or 0) > 0 then
		-- a choice made in the skills panel, now applied: the rules counted it already
		pend[skill] = pend[skill] > 1 and pend[skill] - 1 or nil
		bump_level(cqi, skill)
		add_history(cqi, skill)
		if SPA.ui and SPA.ui.on_character_changed then safe("ui.on_character_changed", SPA.ui.on_character_changed, cqi) end
		return
	end
	if SPA.live_cache[cqi] then
		bump_level(cqi, skill)
	elseif SPA.plans[cqi] and #SPA.plans[cqi].keys > 0 then
		SPA.tree(cqi)                      -- not read yet this session: read it now (it shows this point)
	end
	advance_plan(char, cqi, skill)
	-- multiplayer: on to the next point (in single player the spending loop goes on by itself)
	if ours and cm:is_multiplayer() then SPA.request_spend(cqi) end
end

-- Everything the mod keeps for characters the game no longer has (dead, or gone some other way) is
-- dropped: plans, allocation history and what is cached for this session.
local function cleanup_dead()
	local seen = {}
	for _, t in ipairs({ SPA.plans, SPA.history, SPA.live_cache, SPA.tree_cache, SPA.pending_choices, SPA.unshown, SPA.drafts }) do
		for cqi in pairs(t) do seen[cqi] = true end
	end
	local n = 0
	for cqi in pairs(seen) do
		if not SPA.character(cqi) then
			SPA.plans[cqi], SPA.history[cqi], SPA.pending_choices[cqi], SPA.unshown[cqi], SPA.drafts[cqi] = nil, nil, nil, nil, nil
			SPA.forget(cqi)
			n = n + 1
		end
	end
	if n > 0 then log("turn start: dropped what was kept for", n, "characters the game no longer has") end
end

local function turn_start()
	safe("cleanup_dead", cleanup_dead)
	SPA.spending = {}                  -- (a multiplayer spend whose trigger never came back)
end

-- After the skills panel closed: the game has applied the choices made there (their events came
-- in) or dropped them. A character with choices that never came through, or whose skill reset
-- button was clicked (`reset`: cqi -> true), is read again.
function SPA.after_panel_closed(reset)
	local queue, queued = {}, {}
	local function add(cqi)
		if not queued[cqi] and SPA.character(cqi) then queued[cqi] = true; queue[#queue + 1] = cqi end
	end
	for cqi in pairs(SPA.pending_choices) do
		if SPA.has_unconfirmed(cqi) then
			log("choices still waiting after the panel closed", cqi)
			add(cqi)
		end
	end
	for cqi in pairs(reset or {}) do add(cqi) end
	SPA.pending_choices = {}
	SPA.run_staggered(queue, SPA.reread)
end

local function track(context)
	local cqi = context:character():command_queue_index()
	return SPA.ready and (SPA.plans[cqi] ~= nil or SPA.live_cache[cqi] ~= nil)
end

function SPA.add_listeners()
	core:add_listener("spa_ui_trigger", "UITrigger",
		function(context) return string.sub(context:trigger(), 1, #MSG) == MSG end,
		function(context) safe("on_ui_trigger", on_ui_trigger, context) end, true)

	core:add_listener("spa_point_available", "CharacterSkillPointAvailable", track,
		function(context)
			local cqi = context:character():command_queue_index()
			SPA.refresh_points(cqi)
			SPA.request_spend(cqi)
		end, true)

	core:add_listener("spa_rank_up", "CharacterRankUp", track,
		function(context)
			local cqi = context:character():command_queue_index()
			log("rank up", cqi, "rank=" .. tostring(context:character():rank()))
			SPA.refresh_points(cqi)
			SPA.request_spend(cqi)
		end, true)

	core:add_listener("spa_allocated", "CharacterSkillPointAllocated", track,
		function(context)
			local char, skill = context:character(), context:skill_point_spent_on()
			log("allocated", char:command_queue_index(), skill)
			safe("on_skill_allocated", on_skill_allocated, char, skill)
		end, true)

	core:add_listener("spa_turn_start", "FactionTurnStart",
		function(context) return SPA.ready and context:faction():name() == SPA.local_faction_name() end,
		function() safe("turn_start", turn_start) end, true)
end

---------------------------------------------------------------- presets (one file for all campaigns)
-- { version = 1, presets = { [subtype] = { { name = "...", seq = { skill, ... } }, ... } } }
SPA.presets = nil

local function serialize_value(v, indent)
	indent = indent or ""
	if type(v) == "string" then return string.format("%q", v) end
	if type(v) == "number" or type(v) == "boolean" then return tostring(v) end
	if type(v) ~= "table" then return "nil" end
	local keys = {}
	for k in pairs(v) do keys[#keys + 1] = k end
	table.sort(keys, function(a, b)
		if type(a) == type(b) then return a < b end
		return type(a) == "number"
	end)
	local inner = indent .. "\t"
	local parts = {}
	for _, k in ipairs(keys) do
		local ks = type(k) == "number" and ("[" .. k .. "]") or ("[" .. string.format("%q", k) .. "]")
		parts[#parts + 1] = inner .. ks .. " = " .. serialize_value(v[k], inner)
	end
	if #parts == 0 then return "{}" end
	return "{\n" .. table.concat(parts, ",\n") .. "\n" .. indent .. "}"
end

function SPA.load_presets()
	SPA.presets = { version = 1, presets = {} }
	local text = read_file(PRESET_FILE)
	if not text then return SPA.presets end
	local ok, err = pcall(function()
		local fn, perr = loadstring(text)
		if not fn then error(perr or "not valid Lua") end
		setfenv(fn, {})
		local t = fn()
		if type(t) ~= "table" or type(t.presets) ~= "table" then error("no preset list in it") end
		SPA.presets = t
	end)
	if not ok then
		-- keep a copy: the next save would replace the file
		write_file(PRESET_FILE .. ".unreadable", text)
		SPA.error("could not read " .. PRESET_FILE .. " (a copy was kept as " .. PRESET_FILE .. ".unreadable): " .. tostring(err))
	end
	return SPA.presets
end

function SPA.save_presets()
	local out = { version = SPA.presets.version or 1, presets = {} }
	for subtype, list in pairs(SPA.presets.presets) do
		if #list > 0 then out.presets[subtype] = list end
	end
	local ok = write_file(PRESET_FILE, "-- Skill Pre-Allocation presets (shared by all campaigns). Safe to back up or share.\nreturn "
		.. serialize_value(out) .. "\n")
	if not ok then SPA.error("could not write " .. PRESET_FILE) end
	return ok
end

function SPA.preset_list(subtype)
	if not SPA.presets then SPA.load_presets() end
	SPA.presets.presets[subtype] = SPA.presets.presets[subtype] or {}
	return SPA.presets.presets[subtype]
end

function SPA.find_preset(subtype, name)
	for i, p in ipairs(SPA.preset_list(subtype)) do
		if p.name == name then return p, i end
	end
	return nil
end

---------------------------------------------------------------- plan mode
-- Plan mode is a neutral planning view: a whole build from rank 1 (a draft) for the character's type,
-- planned on an empty tree. Nothing about the character is used (the draft is checked from scratch,
-- R.from_scratch) and nothing is learned while it is on (the skills panel's cards don't take the clicks:
-- see the UI). The draft starts empty, or as a preset picked in the dropdown. When plan mode ends with a
-- build in the draft, the build becomes the pre-allocations the way a preset is loaded: what the
-- character learned is skipped, a variant it can't take any more is mapped onto the one it owns. Ending
-- it with an empty draft changes nothing. Plan mode belongs to the open skills panel: one character at a
-- time, never saved.
SPA.drafts = {}                        -- cqi -> { keys = { skill, ... }, preset = name or nil }

function SPA.in_plan_mode(cqi) return SPA.drafts[cqi] ~= nil end

-- What a character's points are planned as: the draft in plan mode, else its pre-allocations.
function SPA.working(cqi)
	return SPA.drafts[cqi] or SPA.plan(cqi)
end

-- The tree those points are checked against: from scratch in plan mode.
function SPA.rules_tree(cqi)
	local tree = SPA.tree(cqi)
	if tree and SPA.drafts[cqi] then return R().from_scratch(tree) end
	return tree
end

-- Change the draft (plan mode) or the pre-allocations.
local function set_working(cqi, keys, preset)
	local d = SPA.drafts[cqi]
	if not d then return SPA.set_plan(cqi, keys, preset) end
	preset = preset and clean_name(preset) or nil
	d.keys, d.preset = keys, (preset ~= "" and preset or nil)
	log("draft set", cqi, "points=" .. #keys, "preset=" .. tostring(d.preset))
	if SPA.ui and SPA.ui.on_plan_changed then safe("ui.on_plan_changed", SPA.ui.on_plan_changed, cqi) end
end

function SPA.enter_plan_mode(cqi)
	if SPA.drafts[cqi] then return true end
	local tree = SPA.tree(cqi)
	if not tree or not tree.known then return false end
	SPA.drafts[cqi] = { keys = {}, preset = nil }
	log("plan mode on", cqi)
	if SPA.ui and SPA.ui.on_plan_changed then safe("ui.on_plan_changed", SPA.ui.on_plan_changed, cqi) end
	return true
end

-- Returns the replay result (what became the pre-allocations), or nil when nothing changed: the
-- character wasn't in plan mode, or the draft is empty (the pre-allocations stay as they were).
function SPA.leave_plan_mode(cqi)
	local d = SPA.drafts[cqi]
	if not d then return nil end
	SPA.drafts[cqi] = nil
	if #d.keys == 0 then
		log("plan mode off", cqi, "nothing planned: the pre-allocations stay as they were")
		if SPA.ui and SPA.ui.on_plan_changed then safe("ui.on_plan_changed", SPA.ui.on_plan_changed, cqi) end
		return nil
	end
	local tree = SPA.tree(cqi)
	if not tree or not tree.known then return nil end
	local res = R().replay(tree, d.keys, { full_build = true })
	log("plan mode off", cqi, "planned=" .. #res.plan, "dropped=" .. #res.dropped, "remapped=" .. #res.remapped)
	SPA.set_plan(cqi, res.plan, d.preset)
	return res
end

-- The whole build of a character (learned points in order + pre-allocations) as a preset sequence;
-- in plan mode, the draft.
function SPA.character_sequence(cqi)
	local d = SPA.drafts[cqi]
	if d then
		local seq = {}
		for i, k in ipairs(d.keys) do seq[i] = k end
		return seq
	end
	local tree = SPA.tree(cqi)
	if not tree then return nil end
	return R().full_sequence(tree, SPA.history[cqi], SPA.plan(cqi).keys)
end

function SPA.save_preset_as(cqi, name)
	local char = SPA.character(cqi)
	name = clean_name(name)
	if not char or name == "" then return false, "name" end
	local subtype = char:character_subtype_key()
	if SPA.find_preset(subtype, name) then return false, "exists" end
	local seq = SPA.character_sequence(cqi)
	table.insert(SPA.preset_list(subtype), { name = name, seq = seq })
	SPA.save_presets()
	set_working(cqi, SPA.working(cqi).keys, name)
	return true
end

function SPA.overwrite_preset(cqi, name)
	local char = SPA.character(cqi)
	local p = char and SPA.find_preset(char:character_subtype_key(), name)
	if not p then return false end
	p.seq = SPA.character_sequence(cqi)
	SPA.save_presets()
	set_working(cqi, SPA.working(cqi).keys, name)
	return true
end

function SPA.rename_preset(cqi, old_name, new_name)
	local char = SPA.character(cqi)
	new_name = clean_name(new_name)
	if not char or new_name == "" then return false, "name" end
	local subtype = char:character_subtype_key()
	local p = SPA.find_preset(subtype, old_name)
	if not p then return false, "missing" end
	if new_name ~= old_name and SPA.find_preset(subtype, new_name) then return false, "exists" end
	p.name = new_name
	SPA.save_presets()
	for _, t in ipairs({ SPA.plans, SPA.drafts }) do
		for _, plan in pairs(t) do
			if plan.preset == old_name then plan.preset = new_name end
		end
	end
	return true
end

function SPA.delete_preset(cqi, name)
	local char = SPA.character(cqi)
	if not char then return false end
	local list = SPA.preset_list(char:character_subtype_key())
	for i, p in ipairs(list) do
		if p.name == name then
			table.remove(list, i)
			SPA.save_presets()
			for c, plan in pairs(SPA.plans) do
				if plan.preset == name then
					plan.preset = nil
					if #plan.keys == 0 then SPA.plans[c] = nil end
				end
			end
			for _, d in pairs(SPA.drafts) do
				if d.preset == name then d.preset = nil end
			end
			return true
		end
	end
	return false
end

-- Load a preset onto a character: what it already learned is recognised, a variant it can no
-- longer take is mapped onto the one it owns, and the rest becomes its pre-allocations (free points are
-- spent on them by "Allocate now" or at the next rank-up). In plan mode the preset becomes the draft, as
-- it is (checked from scratch). Returns the replay result.
function SPA.apply_preset(cqi, name)
	local char = SPA.character(cqi)
	local p = char and SPA.find_preset(char:character_subtype_key(), name)
	if not p then return nil end
	local res
	if SPA.drafts[cqi] then
		res = R().replay(SPA.rules_tree(cqi), p.seq)
	else
		res = R().replay(SPA.tree(cqi), p.seq, { full_build = true })
	end
	set_working(cqi, res.plan, name)
	log("preset applied", cqi, name, "planned=" .. #res.plan, "dropped=" .. #res.dropped, "remapped=" .. #res.remapped)
	return res
end

-- Clear the pre-allocations (in plan mode: the whole draft, to start from scratch).
function SPA.clear_plan(cqi)
	set_working(cqi, {}, nil)
end

---------------------------------------------------------------- pre-allocation edits (from the UI)
-- These work on the draft in plan mode (see "plan mode"), else on the pre-allocations.
-- Returns ok, code, detail (see SKILL_PREALLOCATION_RULES.check for codes)
function SPA.preallocate(cqi, skill)
	local tree = SPA.rules_tree(cqi)
	if not tree then return false, "unknown" end
	local plan = SPA.working(cqi)
	local ok, code, detail = R().can_append(tree, plan.keys, skill)
	if not ok then return false, code, detail end
	local keys = {}
	for i, k in ipairs(plan.keys) do keys[i] = k end
	keys[#keys + 1] = skill
	set_working(cqi, keys, plan.preset)
	return true
end

function SPA.unallocate(cqi, skill)
	local tree = SPA.rules_tree(cqi)
	local plan = SPA.working(cqi)
	if not tree then return false end
	local res = R().remove_last(tree, plan.keys, skill)
	if not res then return false end
	set_working(cqi, res.plan, plan.preset)
	return true, res
end

-- Remove the most recent pre-allocated point (nothing before it depends on it).
function SPA.undo_last(cqi)
	local plan = SPA.working(cqi)
	local n = #plan.keys
	if n == 0 then return false end
	local keys = {}
	for i = 1, n - 1 do keys[i] = plan.keys[i] end
	set_working(cqi, keys, plan.preset)
	return true, plan.keys[n]
end

---------------------------------------------------------------- saving
cm:add_saving_game_callback(function(context)
	safe("save", function()
		cm:save_named_value(SAVE_KEY, SPA.serialize_state(), context)
	end)
	SPA.flush_log()                    -- (debug lines waiting, if any)
end)

cm:add_loading_game_callback(function(context)
	safe("load", function()
		local s = cm:load_named_value(SAVE_KEY, "", context)
		if not SKILL_PREALLOCATION_DATA or not SKILL_PREALLOCATION_RULES then return end
		SPA.deserialize_state(s)
	end)
end)

---------------------------------------------------------------- start
cm:add_first_tick_callback(function()
	SPA.started = true
	SPA.flush_log_soon()               -- (debug lines from before the first tick, if any)
	if not SKILL_PREALLOCATION_DATA or not SKILL_PREALLOCATION_RULES then
		SPA.error("data or rules script missing - mod disabled")
		return
	end
	local n = 0
	for _ in pairs(SPA.plans) do n = n + 1 end
	log("Skill Pre-Allocation " .. SPA.VERSION .. " started; data " .. D().version .. "; campaign " .. SPA.campaign_key()
		.. "; local faction " .. tostring(SPA.local_faction_name()) .. "; plans " .. n)
	safe("add_listeners", SPA.add_listeners)
	safe("load_presets", SPA.load_presets)
	if SPA.ui and SPA.ui.init then safe("ui.init", SPA.ui.init) end
	-- nothing reacts to the game while the campaign is starting up; then the live data is read (through
	-- the native module)
	cm:real_callback(function()
		safe("activate_live", SPA.activate_live)
		SPA.ready = true
		log("ready; skill data " .. tostring(SPA.live_state) .. ": " .. tostring(D().version))
	end, 6000)
end)
