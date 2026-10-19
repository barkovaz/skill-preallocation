-- End-to-end run of the mod (core + rules + UI) against the mock game.
-- Run from tests/run:  lua5.1 ../test_integration.lua
package.path = "../?.lua;" .. package.path
local MOD = "../../src/script/campaign/mod/"
dofile(MOD .. "skill_preallocation_data.lua")
dofile(MOD .. "skill_preallocation_rules.lua")
local R, D = SKILL_PREALLOCATION_RULES, SKILL_PREALLOCATION_DATA
local FIX = dofile("../skill_fixture.lua")
local H = require("live_helper")
local M = require("mock_game")

os.remove("skill_preallocation_presets.lua")
os.remove("skill_preallocation_log.txt")
local live = H.make_live(R, D, FIX, "wh_main_emp_lord", { faction = "wh_main_emp_empire", subculture = "wh_main_sc_emp_empire" })
M.setup(live, R)
local initial_levels = {}
for k, v in pairs(M.levels) do initial_levels[k] = v end
M.build_ui()
M.install()
dofile(MOD .. "skill_preallocation.lua")
dofile(MOD .. "skill_preallocation_live.lua")
dofile(MOD .. "skill_preallocation_text.lua")
dofile(MOD .. "skill_preallocation_ui.lua")
local SPA = SKILL_PREALLOCATION
SPA.debug = true
-- the native module: the mock's; the live data: the baked data
-- under another name (tests/test_live.lua checks that the two are the same)
M.live_loads = 0
do
	local LIVE = SKILL_PREALLOCATION_LIVE
	LIVE.native_tried, LIVE.native, LIVE.native_version = true, M.native, M.native.version
	LIVE.load = function(log)
		M.live_loads = M.live_loads + 1
		local d = {}
		for k, v in pairs(D) do d[k] = v end
		d.version, d.report = "live test", { sets = 594, skills = #D.skills, warnings = {}, unseen = {} }
		log("live skill data " .. d.version)
		return d
	end
end
-- the mod's own shield layout, and its shields' tooltip functions
local function read_layout()
	local f = io.open("../../src/ui/skill_preallocation/spa_shield.twui.xml", "rb")
	local t = f and f:read("*a") or ""
	if f then f:close() end
	return t
end
local function xml_unescape(v)
	v = string.gsub(v, "&quot;", '"')
	v = string.gsub(v, "&gt;", ">")
	v = string.gsub(v, "&lt;", "<")
	return (string.gsub(v, "&amp;", "&"))
end
local function layout_tip_function(component)      -- the tooltip function of one of the mod's components
	return xml_unescape(string.match(read_layout(), '\t\t<' .. component
		.. '\r\n.-callback_id="ContextLayoutTooltip"%s+context_object_id="[^"]*"%s+context_function_id="([^"]*)"') or "")
end
local LAYOUT_TIP_FUNCTION = layout_tip_function("spa_shield")
local LAYOUT_PIP_FUNCTIONS = {}
for i = 1, 3 do LAYOUT_PIP_FUNCTIONS[i] = layout_tip_function("spa_pip_shield" .. i) end

local passed, failed = 0, 0
local verbose = os.getenv("SPA_TEST_VERBOSE")
local function check(c, msg)
	if c then passed = passed + 1; if verbose then print("ok: " .. msg) end else failed = failed + 1 print("FAIL: " .. msg) end
end
local function find(...) return M.find_uicomponent(M.root, ...) end
local function plain(text) return text and (string.gsub(text, "%[%[.-%]%]", "")) or nil end
local function status()
	local label = find("spa_status")
	local t = label and label:Find("button_txt")
	return t and t.text or ""
end
local function badge(key) local b = M.cards[key]:Find("spa_badge") return b and b.visible and b.text or nil end
-- a click on a skill's numbers (its badge), when the card shows them
local function click_badge(key) local b = M.cards[key]:Find("spa_badge") if b and b.visible then M.click(b) end end
local function keys() return SPA.plan(1).keys end
-- a point that can be planned and is learned when it arrives, without waiting for its skill's rank
-- (what the tests click to fill a plan; points that wait have tests of their own)
local function fits_now(t, plan, k)
	local ok, _, _, at = R.can_append(t, plan, k)
	if not ok then return false end
	local arrive = R.slot_rank(t, #plan + 1)
	local prev = R.plan_ranks(t, plan)[#plan]
	if prev and prev > arrive then arrive = prev end
	return at == arrive
end
local function count(key) local n = 0 for _, k in ipairs(keys()) do if k == key then n = n + 1 end end return n end
local function open_panel() M.fire("PanelOpenedCampaign", { string = "character_details_panel" }); M.drain() end
local function cache_matches_game()
	for _, s in ipairs(SPA.live_cache[1].skills) do
		if (s.level or 0) ~= (M.levels[s.key] or 0) then return false, s.key .. " cached " .. tostring(s.level) .. " game " .. tostring(M.levels[s.key]) end
	end
	return true
end
local function plan_greedy(n)
	for _ = 1, n do
		local t = SPA.tree(1)
		for _, k in ipairs(t.order) do
			if fits_now(t, keys(), k) then M.click(M.cards[k]) break end
		end
	end
end

for _, fn in ipairs(M.first_tick) do fn() end
M.drain()
open_panel()
local btn = find("spa_presets")
local function icon(name) return find("spa_btn_" .. name) end
local ICONS = { "plan", "new", "overwrite", "rename", "delete", "clear", "spend" }
-- a button that takes clicks: not flagged disabled and not in its inactive state (see M.disable_mode)
local function works(b) return b ~= nil and not b.disabled and b.state ~= "inactive" end
local function greyed(b) return b ~= nil and b.disabled == true and b.state == "inactive" end
local function row_visible(v)
	if btn.visible ~= v then return false end
	for _, name in ipairs(ICONS) do if icon(name).visible ~= v then return false end end
	return true
end
check(btn ~= nil, "presets dropdown created")
-- no container between the buttons and the mouse: direct children of the counter's parent
local holder_parent = find("skill_pts_holder").parent
local direct = btn and btn.parent == holder_parent
for _, name in ipairs(ICONS) do if not (icon(name) and icon(name).parent == holder_parent) then direct = false end end
check(direct and find("spa_bar") == nil, "dropdown and icons sit directly in the counter's parent")
check(btn and btn.w == 320 and btn.h == 34, "dropdown is 320x34, the height of the button art (" .. tostring(btn and btn.w) .. "x" .. tostring(btn and btn.h) .. ")")
check(btn and btn.images and btn.images[1] == "ui/skins/default/spa_dropdown_active.png" and btn.images[4] == "ui/skins/default/spa_dropdown_underlay.png",
	"dropdown wears the mod's copy of the game's dropdown art")
-- one row at the top right of the skill tree: the icons end 24 inside the counter's right edge (2186),
-- the dropdown left of them; just under the top bar
local icons_left = 2186 - 24 - (7 * 38 + 6 * 4)
check(btn and btn.x == icons_left - 10 - 320 and btn.y == 148 + 6, "dropdown placed left of the icons (" .. tostring(btn and btn.x) .. "," .. tostring(btn and btn.y) .. ")")
local row_ok = true
for i, name in ipairs(ICONS) do
	local b = icon(name)
	if not (b and b.x == icons_left + (i - 1) * 42 and b.y == 154 - 2 and b.images and b.images[0]) then row_ok = false end
end
check(row_ok, "seven round icon buttons in a row, centred on the dropdown")
check(icon("new").images[0] == "ui/skins/default/icon_add.png" and icon("spend").images[0] == "ui/skins/default/icon_check.png"
	and icon("plan").images[0] == "ui/skins/default/icon_edit.png", "the game's icons")
check(M.created and (function() for _, c in ipairs(M.created) do if c == "ui/templates/round_small_button_toggle" then return true end end end)(),
	"the plan mode button is the game's on/off round button")
check(btn and btn.priority == 61 and icon("spend").priority == 61, "lifted above the panel frame (" .. tostring(btn and btn.priority) .. ")")
-- nothing planned, no presets yet: the dropdown says so and only works with presets; no icon works
check(plain(btn:Find("button_txt").text) == "No presets" and greyed(btn), "no presets: the dropdown is greyed out (flag and look)")
local none_on = true
for _, name in ipairs(ICONS) do if name ~= "plan" and not greyed(icon(name)) then none_on = false end end
check(none_on and works(icon("plan")), "nothing planned or learned: every icon but plan mode is greyed out")
check(icon("rename").tooltip == "Rename the selected preset" and btn.tooltip ~= nil, "tooltips")
M.click(btn)
check(find("spa_menu") == nil, "a greyed-out dropdown doesn't open")

-- texts in the game's language, read once
check(SPA.text.lang == "en" and SPA.text.raw == "EN" and M.lang_reads == 1, "game language read once (" .. tostring(SPA.text.raw) .. ", " .. tostring(M.lang_reads) .. " reads)")
M.lang, SPA.text.lang = "GE", nil
SPA.ui.refresh()
check(btn:Find("button_txt").text == "Keine Vorlagen", "German dropdown: " .. tostring(btn:Find("button_txt").text))
check(icon("new").tooltip == "Als neue Vorlage speichern", "German tooltip: " .. tostring(icon("new").tooltip))
M.lang, SPA.text.lang = "zh-CN", nil
SPA.ui.refresh()
check(btn:Find("button_txt").text == "无预设", "Simplified Chinese dropdown: " .. tostring(btn:Find("button_txt").text))
M.lang, SPA.text.lang = nil, nil
SPA.ui.refresh()
check(btn:Find("button_txt").text == "No presets" and SPA.text.lang == "en", "back to English")
check(find("spa_status") == nil, "no message line")
local function repeating_timers()
	local n = 0
	for _, tm in ipairs(M.timers) do if tm.interval then n = n + 1 end end
	return n
end
check(repeating_timers() == 0, "nothing runs periodically while the panel is open")

---------------------------------------------------------------- clicking
local tree = SPA.tree(1, true)
local first
for _, k in ipairs(tree.order) do
	if fits_now(tree, {}, k) then first = k break end
end
check(first ~= nil, "found a skill for the first point")
M.click(M.cards[first])
check(#keys() == 1 and keys()[1] == first, "left click pre-allocates")
check(plain(badge(first)) == "2", "badge shows just the rank number: " .. tostring(badge(first)))

-- switching tabs: the button and the badges follow within ~50 ms
local sub = find("skills_subpanel")
local function tab_click() M.fire("ComponentLClickUp", { component = find("tab_panels"), string = "tab_panels" }) end
sub.visible = false
tab_click()
M.advance(60)
check(row_visible(false), "presets row hidden ~50 ms after leaving the skills tab")
M.drain()
for _, card in pairs(M.cards) do
	local b = card:Find("spa_badge")
	if b then b:Destroy() end                        -- the game builds new cards for the tab
end
sub.visible = true
tab_click()
M.advance(60)
check(row_visible(true) and plain(badge(first)) == "2", "presets row and badge back ~50 ms after entering the skills tab")
M.drain()

-- a multi-level skill: left clicks add levels, never cycle; clicks on its badge remove them one by one
local multi, multi_parent
for _, k in ipairs(tree.order) do
	local s = tree.skills[k]
	if s.plannable and (s.total or 1) == 3 and #s.req == 1 and #s.sub == 0 then
		local p = s.req[1]
		local plan = { first }
		local ok = p == first or fits_now(tree, plan, p)
		if ok and p ~= first then plan[#plan + 1] = p end
		for _ = 1, 3 do
			if not ok or not fits_now(tree, plan, k) then ok = false break end
			plan[#plan + 1] = k
		end
		if ok then multi, multi_parent = k, p break end
	end
end
check(multi ~= nil, "found a 3-level skill")
if multi then
	if multi_parent ~= first then M.click(M.cards[multi_parent]) end
	local base = #keys()
	local shrunk = false
	for _ = 1, 3 do
		M.click(M.cards[multi])
		if M.cards[multi]:Find("spa_badge").shrunk then shrunk = true end
	end
	check(count(multi) == 3, "every level pre-allocated (" .. count(multi) .. "/3)")
	local b = plain(badge(multi))
	local expect = string.format("%d %d %d", base + 2, base + 3, base + 4)
	check(b == expect, "badge lists one rank per level: " .. tostring(b) .. " (expected " .. expect .. ")")
	check(not shrunk, "the numbers keep their size as levels are added one by one")
	M.click(M.cards[multi])
	check(count(multi) == 3, "clicking a fully planned skill does not cycle (" .. count(multi) .. ")")
	click_badge(multi)
	check(count(multi) == 2, "a click on the badge removes one level")
	for _ = 1, 3 do click_badge(multi) end
	check(count(multi) == 0 and #keys() == base, "clicks on the badge remove every level, nothing else (" .. #keys() .. ")")
	check(badge(multi) == nil, "badge hidden when nothing is planned")
	if multi_parent ~= first then
		click_badge(multi_parent)
		check(#keys() == 1, "parent removed again")
	end
end

-- a click on the first skill's badge removes its point; with nothing planned the card shows no badge
click_badge(first)
check(#keys() == 0 and badge(first) == nil, "a click on the badge removes the pre-allocated point of the first skill, and the badge goes")
M.click(M.cards[first])

-- strict order: a rank-locked skill can't be planned where its point would come before its rank (the
-- game shows "Available at rank r + 1" for a stored requirement of r), so no point ever waits; once
-- enough points come before it, it fits
local high
for _, k in ipairs(tree.order) do
	local s = tree.skills[k]
	if not high and s.plannable and (s.ranks[1] or 0) >= 6 and #s.req == 0 and #s.sub == 0 then high = k end
end
check(high ~= nil, "found a rank-locked skill")
if high then
	local stored = tree.skills[high].ranks[1]
	M.click(M.cards[high])
	check(#keys() == 1 and badge(high) == nil, "a rank-locked skill is refused as the second point (" .. #keys() .. ")")
	for _ = 1, 20 do
		local t = SPA.tree(1)
		if R.can_append(t, keys(), high) then break end
		for _, k in ipairs(t.order) do
			if k ~= high and fits_now(t, keys(), k) then M.click(M.cards[k]) break end
		end
	end
	M.click(M.cards[high])
	check(keys()[#keys()] == high and #keys() == stored, "it fits as point " .. stored .. ", which comes at its rank (" .. #keys() .. ")")
	check(plain(badge(high)) == tostring(stored + 1), "its badge shows the rank the game shows (" .. tostring(badge(high)) .. ", expected " .. (stored + 1) .. ")")
	-- back to one point
	while #keys() > 1 do SPA.undo_last(1) end
	M.drain()
end

-- plan 5 more points greedily through clicks
plan_greedy(5)
check(#keys() == 6, "six points pre-allocated (" .. #keys() .. ")")

-- a click on a skill's badge removes the last point of that skill; a click elsewhere on the card adds one.
-- The badge takes clicks above the card, its tooltip says so, and its box is as wide as its numbers
-- (8 a character and 4 each side, in the layout's units), docked again at the card's bottom centre.
do
	local last = keys()[6]
	local lb = M.cards[last]:Find("spa_badge")
	check(lb and lb.visible and lb.interactive == true and (lb.priority or 0) == M.cards[last]:Priority() + 3
		and string.find(lb.tooltip or "", SPA.text.get("badge_tip_click"), 1, true) ~= nil,
		"a planned skill's badge takes clicks, above its card, and its tooltip says so")
	check(lb and lb.w == (string.len(plain(lb.text)) * 8 + 8) * M.scale and lb.h == 16 * M.scale and lb.dock == 8
		and lb.dock_x == 0 and lb.dock_y == -1, "the badge is as wide as its numbers: " .. tostring(lb and lb.w) .. " for " .. tostring(lb and plain(lb.text)))
	click_badge(last)
	check(#keys() == 5, "a click on the badge removed the point")
	M.click(M.cards[last])
	check(#keys() == 6 and keys()[6] == last, "and a click on the card adds it again")
	for _ = 1, 2 do M.click(M.cards[last]) end
	local n_more = count(last)
	click_badge(last)
	check(count(last) == n_more - 1, "one click on the badge removes one point (" .. count(last) .. " left of " .. n_more .. ")")
end
while #keys() > 6 do SPA.undo_last(1) end
M.drain()

---------------------------------------------------------------- spending
-- Ranks are gained with the skills panel closed (as in the game); it is opened again afterwards.
local function close_panel() M.close_panel(); M.tick(3000) end
local function level_up(n)
	close_panel()
	M.level_up(n)
	M.drain()
	open_panel()
end
local function ranks_now()
	local out = {}
	for i, r in ipairs(R.plan_ranks(SPA.tree(1), keys())) do out[i] = r end
	return out
end
local before = ranks_now()
local planned_first = keys()[1]
level_up(1)
check(M.add_skill_calls[#M.add_skill_calls] == planned_first, "spent through the game's add_skill")
check(M.levels[planned_first] >= 1, "first planned skill learned")
check(#keys() == 5 and M.points == 0, "plan moved on after the level-up (" .. #keys() .. " left, points " .. M.points .. ")")
local after = ranks_now()
local stable = true
for i = 1, #after do if after[i] ~= before[i + 1] then stable = false end end
check(stable, "the other pre-allocations keep their ranks after the level-up")
check(plain(badge(keys()[1])) ~= nil and string.match(plain(badge(keys()[1])), tostring(before[2])) ~= nil,
	"badge of the next point still shows rank " .. tostring(before[2]) .. ": " .. tostring(badge(keys()[1])))

level_up(2)
check(#keys() == 3 and M.points == 0, "two more level-ups spent two more points (" .. #keys() .. " left, points " .. M.points .. ")")

check(cache_matches_game(), "stored levels match the game")

-- a free point that came without a rank-up: the turn start spends nothing (and reads nothing), the
-- next rank-up spends it with the new one
close_panel()
M.points = M.points + 1
local reads = M.tree_reads
local calls_ts = #M.add_skill_calls
M.fire("FactionTurnStart", { faction = function() return M.faction end })
M.drain()
check(#keys() == 3 and M.points == 1 and #M.add_skill_calls == calls_ts, "turn start: nothing spent (" .. #keys() .. " left, points " .. M.points .. ")")
check(M.tree_reads == reads, "turn start: no tree read (" .. (M.tree_reads - reads) .. ")")
M.level_up(1)
M.drain()
check(#keys() == 1 and M.points == 0, "the next rank-up spends both points (" .. #keys() .. " left, points " .. M.points .. ")")
open_panel()

-- the game refuses: tried once per rank-up (the tree is read again), and again at the next one
plan_greedy(3)
local n_before = #keys()
close_panel()
M.refuse_add_skill = true
local calls = #M.add_skill_calls
reads = M.tree_reads
M.level_up(1)
M.drain()
check(#M.add_skill_calls == calls + 1, "a refused point is tried once per rank-up (" .. (#M.add_skill_calls - calls) .. ")")
check(M.tree_reads == reads + 1, "and the tree is read again once (" .. (M.tree_reads - reads) .. ")")
M.refuse_add_skill = false
M.level_up(1)
M.drain()
check(#keys() == n_before - 2 and M.points == 0, "after the next rank-up both waiting points are spent (" .. #keys() .. " left, points " .. M.points .. ")")
open_panel()

-- an extra point that arrives before the next skill's rank: it waits, the order is kept
SPA.clear_plan(1)
M.drain()
local t6 = SPA.tree(1)
local locked6
for _, k in ipairs(t6.order) do
	local s = t6.skills[k]
	local need6 = R.required_rank(s.ranks[1])
	if s.plannable and (M.levels[k] or 0) == 0 and #s.req == 0 and #s.sub == 0 and need6 > M.rank + 1 and need6 <= M.rank + 6 then
		locked6 = k
		break
	end
end
check(locked6 ~= nil, "found a skill that needs a few more ranks")
if locked6 then
	local need = R.required_rank(t6.skills[locked6].ranks[1])
	-- plan cheap points until the rank-locked skill fits, then it
	for _ = 1, 10 do
		local t = SPA.tree(1)
		if fits_now(t, keys(), locked6) then break end
		for _, k in ipairs(t.order) do
			if k ~= locked6 and fits_now(t, keys(), k) then M.click(M.cards[k]) break end
		end
	end
	M.click(M.cards[locked6])
	check(keys()[#keys()] == locked6, "rank-locked skill planned last")
	-- spend everything before it
	close_panel()
	for _ = 1, #keys() - 1 do M.level_up(1); M.drain() end
	check(#keys() == 1 and keys()[1] == locked6 and M.rank < need, "only the rank-locked skill is left (rank " .. M.rank .. ", needs " .. need .. ")")
	local calls6 = #M.add_skill_calls
	M.points = M.points + 1                      -- a point without a rank-up
	SPA.refresh_points(1)
	SPA.request_spend(1)
	M.drain()
	check(#M.add_skill_calls == calls6 and #keys() == 1, "the early point waits instead of breaking the order")
	open_panel()
	check(plain(badge(locked6)) == tostring(need), "badge shows the rank it will really be learned at: " .. tostring(badge(locked6)))
	close_panel()
	while M.rank < need do M.level_up(1); M.drain() end
	check(M.levels[locked6] == 1 and #keys() == 0, "learned as soon as the rank is reached")
	M.points = 0                                 -- the leftover point is not needed below
	SPA.refresh_points(1)
	open_panel()
end

-- strict order: a rank-locked skill goes where its point comes at its rank; each rank-up then learns the
-- next point, and no point is left unspent. (On a fresh character at rank 1; put back afterwards.)
SPA.clear_plan(1)
close_panel()
local saved9 = { levels = {}, rank = M.rank, points = M.points, history = SPA.history[1] }
for k, v in pairs(M.levels) do saved9.levels[k] = v end
for k, v in pairs(initial_levels) do M.levels[k] = v end
M.rank, M.points = 1, 0
SPA.plans[1], SPA.history[1] = nil, nil
SPA.forget(1)
open_panel()
local t9 = SPA.tree(1)
local locked9
for _, k in ipairs(t9.order) do
	local s = t9.skills[k]
	local need9 = R.required_rank(s.ranks[1])
	if s.plannable and #s.req == 0 and #s.sub == 0 and #s.locks == 0 and need9 >= 4 and need9 <= 6 then
		locked9 = k
		break
	end
end
check(locked9 ~= nil, "found a skill that needs rank 4 to 6")
if locked9 then
	local need9 = R.required_rank(t9.skills[locked9].ranks[1])
	M.click(M.cards[locked9])
	check(#keys() == 0, "planned first it is refused: its point would come before its rank")
	for _ = 1, 10 do
		local t = SPA.tree(1)
		if R.can_append(t, keys(), locked9) then break end
		for _, k in ipairs(t.order) do
			if k ~= locked9 and fits_now(t, keys(), k) then M.click(M.cards[k]) break end
		end
	end
	M.click(M.cards[locked9])
	plan_greedy(1)
	local plan9 = {}
	for i, k in ipairs(keys()) do plan9[i] = k end
	check(#plan9 == need9 and plan9[need9 - 1] == locked9, "it fits as point " .. (need9 - 1) .. ", which comes at its rank " .. need9 .. " (" .. #plan9 .. " planned)")
	local grow = true
	for i, k in ipairs(plan9) do
		if not string.match(plain(badge(k)) or "", "%f[%d]" .. (i + 1) .. "%f[%D]") then grow = false end
	end
	check(grow, "the badges follow the plan: ranks 2, 3, 4, ...")
	close_panel()
	local calls9 = #M.add_skill_calls
	local unspent = 0
	for _ = 1, #plan9 do
		M.level_up(1)
		M.drain()
		unspent = unspent + M.points
	end
	local in_order = true
	for i, k in ipairs(plan9) do if M.add_skill_calls[calls9 + i] ~= k then in_order = false end end
	check(in_order and #keys() == 0, "each rank-up learned the next point, in plan order")
	check(unspent == 0, "no point was left unspent after any rank-up")
	local ok9, why9 = cache_matches_game()
	check(ok9, "stored levels match the game " .. tostring(why9))
end
close_panel()
for k, v in pairs(saved9.levels) do M.levels[k] = v end
M.rank, M.points = saved9.rank, saved9.points
SPA.plans[1], SPA.history[1] = nil, saved9.history
SPA.forget(1)
open_panel()

-- three points at once on a skill planned twice with another in between: all spent, in order
SPA.clear_plan(1)
M.drain()
local t4 = SPA.tree(1)
local twice
for _, k in ipairs(t4.order) do
	local s = t4.skills[k]
	if s.plannable and (s.total or 1) >= 2 and (M.levels[k] or 0) == 0 and fits_now(t4, {}, k) and fits_now(t4, { k }, k) then
		twice = k
		break
	end
end
check(twice ~= nil, "found a skill that can take two points in a row")
if twice then
	local filler
	for _, k in ipairs(t4.order) do
		if k ~= twice and fits_now(t4, { twice }, k) and fits_now(t4, { twice, k }, twice) then filler = k break end
	end
	for _, k in ipairs({ twice, filler, twice }) do M.click(M.cards[k]) end
	check(#keys() == 3, "planned " .. twice .. ", another skill, " .. twice .. " again (" .. #keys() .. ")")
	local first_call = #M.add_skill_calls + 1
	level_up(3)
	check(#keys() == 0 and M.points == 0, "all three spent, nothing dropped (" .. #keys() .. " left, points " .. M.points .. ")")
	check(M.add_skill_calls[first_call] == twice and M.add_skill_calls[first_call + 1] == filler
		and M.add_skill_calls[first_call + 2] == twice, "spent in plan order")
	check(M.levels[twice] == 2, "the skill planned twice has two levels (" .. tostring(M.levels[twice]) .. ")")
	local ok, why = cache_matches_game()
	check(ok, "stored levels still match the game " .. tostring(why))
end

---------------------------------------------------------------- free points: the game's own allocation
local function find_parent_and_child()
	local t = SPA.tree(1)
	for _, k in ipairs(t.order) do
		local s = t.skills[k]
		if s.plannable and M.levels[k] == 0 and fits_now(t, {}, k) then
			for _, c in ipairs(t.order) do
				local cs = t.skills[c]
				if cs.plannable and #cs.req == 1 and cs.req[1] == k and #cs.sub == 0 and M.levels[c] == 0 and fits_now(t, { k }, c) then
					return k, c
				end
			end
		end
	end
end

SPA.clear_plan(1)
M.drain()
M.points = 1                                     -- exactly one free point
SPA.refresh_points(1)
local manual, child_skill = find_parent_and_child()
check(manual ~= nil and child_skill ~= nil, "found a skill and a child of it")
if manual then
	local calls_before = #M.add_skill_calls
	M.click(M.cards[manual])
	check(#keys() == 0, "with a free point the click is a normal allocation, not a pre-allocation")
	check(#M.pending == 1, "the game holds the choice until the panel closes")
	check(SPA.has_unconfirmed(1), "the mod noticed the unconfirmed choice")
	check(SPA.tree(1).skills[manual].level == 1, "and counts it as learned for the rules")
	M.click(M.cards[child_skill])
	check(count(child_skill) == 1, "the child of the unconfirmed choice can be pre-allocated")
	M.level_up(1)
	M.drain()
	check(#M.add_skill_calls == calls_before and M.levels[child_skill] == 0, "nothing is spent while the choice is unconfirmed")
	M.close_panel()
	M.tick(3000)
	check(M.levels[manual] == 1, "closing the panel applies the choice")
	check(not SPA.has_unconfirmed(1), "no unconfirmed choice left after the panel closed")
	check(M.levels[child_skill] == 0 and #keys() == 1 and M.points == 1,
		"closing the panel spends nothing: the free point waits (" .. #keys() .. " planned, points " .. M.points .. ")")
	M.level_up(1)
	M.drain()
	check(M.levels[child_skill] == 1 and #keys() == 0, "the next rank-up spends the waiting pre-allocation (" .. #keys() .. " left)")
	local ok_cache, why_cache = cache_matches_game()
	check(ok_cache, "stored levels match the game after the panel closed " .. tostring(why_cache))
	open_panel()
end

-- the game drops an unconfirmed choice: the plan that relied on it is re-checked, nothing stalls
M.points = 1
SPA.refresh_points(1)
local m2, c2 = find_parent_and_child()
check(m2 ~= nil, "found another skill and child")
if m2 then
	M.click(M.cards[m2])
	M.click(M.cards[c2])
	check(count(c2) == 1, "child planned on top of an unconfirmed choice")
	M.close_panel(true)                          -- the game drops the choice
	M.tick(3000)
	check(M.levels[m2] == 0 and count(c2) == 0, "dropped choice: the child that needed it is no longer planned")
	open_panel()
end

-- the panel's undo button drops an unconfirmed choice: the plan follows straight away
M.points = 1
SPA.refresh_points(1)
local m3, c3 = find_parent_and_child()
check(m3 ~= nil, "found a third skill and child")
if m3 then
	M.click(M.cards[m3])
	M.click(M.cards[c3])
	check(count(c3) == 1 and SPA.has_unconfirmed(1), "child planned on top of an unconfirmed choice, again")
	M.click(find("skill_pts_holder", "button_stats_reset"))
	M.tick(300)
	check(#M.pending == 0 and not SPA.has_unconfirmed(1) and count(c3) == 0 and SPA.tree(1).points == 1,
		"the undo button drops the choice; the child that needed it is no longer planned (" .. #keys() .. ")")
end

---------------------------------------------------------------- presets
M.points = 0
SPA.refresh_points(1)
plan_greedy(3)
check(#keys() == 3, "three points planned again (" .. #keys() .. ")")

-- the old menu's actions are now icon buttons; overwrite, delete, clear and allocate now ask first
local ICON_OF = { spa_act_save = "new", spa_act_overwrite = "overwrite", spa_act_rename = "rename",
	spa_act_delete = "delete", spa_act_clear = "clear", spa_act_spend = "spend" }
local ASKS = { overwrite = true, delete = true, clear = true, spend = true }
local function menu(item)
	local name = ICON_OF[item]
	if name then
		SPA.ui.refresh()                         -- (the bar as the panel shows it now)
		local b = icon(name)
		if not works(b) then return false end
		M.click(b)
		if ASKS[name] then
			local tick = find("spa_confirm", "both_group", "button_tick")
			if not tick then return false end
			M.click(tick)
		end
		return true
	end
	-- a preset in the dropdown's list
	if not find("spa_menu") then M.click(find("spa_presets")) end
	local it = find("spa_menu", item)
	if it then M.click(it:Find("button_txt") or it) end
	return it ~= nil
end
local function enabled(name) return works(icon(name)) end

check(enabled("new") and enabled("clear") and not enabled("overwrite") and not enabled("rename") and not enabled("delete"),
	"three points planned, no preset: New and Clear work, Overwrite / Rename / Delete don't")
check(not enabled("spend") and icon("spend").tooltip == "Allocate free skill points to the pre-allocated skills now", "no free points: Allocate now doesn't work")
-- a question first: cancel keeps everything
M.click(icon("clear"))
local ask = find("spa_confirm", "DY_text")
check(ask and ask.text == "Clear all pre-allocations?" and find("spa_confirm").priority == 1000, "Clear asks first: " .. tostring(ask and ask.text))
M.click(find("spa_confirm", "both_group", "button_cancel"))
check(find("spa_confirm") == nil and #keys() == 3, "cancel: nothing cleared")

menu("spa_act_save")
local input = find("spa_popup", "text_input")
check(input ~= nil, "save popup opened")
check(input and input.text == "Lord 1", "popup suggests a name: " .. tostring(input and input.text))
input.text = "Tank build"
M.tick(300)
M.click(find("character_details_panel", "button_bottom_holder", "button_ok"))
check(find("spa_popup") ~= nil and SPA.find_preset("wh_main_emp_lord", "Tank build") == nil, "the panel's OK button does not confirm the popup")
M.click(find("spa_popup", "button_ok"))
check(find("spa_popup") == nil, "popup closed")
check(SPA.find_preset("wh_main_emp_lord", "Tank build") ~= nil and SPA.plan(1).preset == "Tank build", "preset saved and linked")
check(plain(find("spa_presets"):Find("button_txt").text) == "Tank build" and works(btn), "the dropdown shows the selected preset")
check(enabled("overwrite") and enabled("rename") and enabled("delete"), "with a selected preset: Overwrite / Rename / Delete work")
local seq = SPA.find_preset("wh_main_emp_lord", "Tank build").seq
local learned_total = select(2, R.spent_levels(SPA.tree(1)))
check(#seq == learned_total + 3, "preset holds learned + planned points (" .. #seq .. " = " .. learned_total .. " + 3)")

menu("spa_act_clear")
check(#keys() == 0 and SPA.plan(1).preset == nil, "Clear removes the plan and the link")
check(plain(btn:Find("button_txt").text) == "Select preset" and works(btn), "the dropdown asks for a preset")
check(learned_total > 0 and enabled("new") and not enabled("clear"),
	"nothing planned: Clear doesn't work; New does (a preset is the whole build, learned skills included)")
M.click(find("spa_presets"))
local opt1 = find("spa_menu", "spa_opt_1")
check(opt1 and plain(opt1:Find("button_txt").text) == "Tank build" and find("spa_menu").x == btn.x, "the list shows the presets under the dropdown")
M.click(find("spa_presets"))
check(menu("spa_opt_1"), "the preset is in the list")
check(#keys() == 3 and SPA.plan(1).preset == "Tank build", "picking it loads it (" .. #keys() .. ")")
check(find("spa_menu") == nil, "list closed after picking")
M.click(find("spa_presets"))
check(plain(find("spa_menu", "spa_opt_1"):Find("button_txt").text) == "> Tank build", "the selected preset is marked")
M.click(find("spa_presets"))

menu("spa_act_rename")
find("spa_popup", "text_input").text = "Tank v2"
M.click(find("spa_popup", "button_ok"))
check(SPA.find_preset("wh_main_emp_lord", "Tank v2") ~= nil and SPA.plan(1).preset == "Tank v2", "renamed")
plan_greedy(1)
M.click(icon("overwrite"))
check(find("spa_confirm", "DY_text").text == 'Overwrite the preset "Tank v2"?', "Overwrite asks first")
M.click(find("spa_confirm", "both_group", "button_tick"))
check(#SPA.find_preset("wh_main_emp_lord", "Tank v2").seq == learned_total + 4, "overwritten with the current build")
M.click(icon("delete"))
check(find("spa_confirm", "DY_text").text == 'Delete the preset "Tank v2"?', "Delete asks first")
M.click(find("spa_confirm", "both_group", "button_tick"))
check(SPA.find_preset("wh_main_emp_lord", "Tank v2") == nil and SPA.plan(1).preset == nil, "deleted")
check(#keys() == 4, "deleting a preset keeps the character's plan")
while #keys() > 3 do SPA.undo_last(1) end
M.drain()

-- nothing pre-allocated but skills learned: the learned build can be saved (and overwritten, renamed,
-- deleted) as a preset
menu("spa_act_clear")
check(menu("spa_act_save") and find("spa_popup") ~= nil, "nothing pre-allocated, skills learned: New asks for a name")
find("spa_popup", "text_input").text = "Learned only"
M.click(find("spa_popup", "button_ok"))
check(SPA.plan(1).preset == "Learned only" and #keys() == 0 and #SPA.find_preset("wh_main_emp_lord", "Learned only").seq == learned_total,
	"the learned build saved and linked, with an empty plan")
SPA.ui.refresh()
check(enabled("rename") and enabled("delete") and enabled("overwrite"), "rename, delete and overwrite work")
check(menu("spa_act_rename"), "rename offered for it")
find("spa_popup", "text_input").text = "Learned v2"
M.click(find("spa_popup", "button_ok"))
check(SPA.plan(1).preset == "Learned v2", "renamed with an empty plan")

---------------------------------------------------------------- saving
plan_greedy(2)
local plan_before = {}
for i, k in ipairs(keys()) do plan_before[i] = k end
check(#plan_before == 2, "two points planned for the save test")
local preset_before = SPA.plan(1).preset
M.save_cb({})
local saved = M.saved and M.saved["skill_preallocation_state_v1"]
check(saved and string.sub(saved, 1, 3) == "v2;", "state saved in the v2 format")
check(saved and string.match(saved, plan_before[1], 1, true) ~= nil, "the save holds skill keys, not data indices")
local hist_n = SPA.history[1] and #SPA.history[1] or 0
SPA.plans, SPA.history = {}, {}
M.load_cb({})
local same = #keys() == #plan_before
for i, k in ipairs(plan_before) do if keys()[i] ~= k then same = false end end
check(same and SPA.plan(1).preset == preset_before, "state restored from the save (" .. #keys() .. " planned, preset " .. tostring(SPA.plan(1).preset) .. ")")
check(SPA.history[1] and #SPA.history[1] == hist_n, "allocation history restored (" .. tostring(SPA.history[1] and #SPA.history[1]) .. ")")
-- an old (v1) save made with other data is dropped, one made with this data still loads
M.saved["skill_preallocation_state_v1"] = "0123456789ab;P:1::5,6,7"
M.load_cb({})
check(SPA.plans[1] == nil, "old save from other game data dropped")
local idx = R.skill_index(plan_before[1])
M.saved["skill_preallocation_state_v1"] = D.version .. ";P:1:Old:" .. idx
M.load_cb({})
check(SPA.plan(1).keys[1] == plan_before[1] and SPA.plan(1).preset == "Old", "old save from this data still loads")
M.saved["skill_preallocation_state_v1"] = saved
M.load_cb({})

---------------------------------------------------------------- skill reset
-- the game's reset button: every learned point refunded
M.close_panel()
M.tick(3000)
local refunded = 0
for k, v in pairs(M.levels) do
	local s = SPA.tree(1).skills[k]
	if s and s.plannable and v > 0 then refunded = refunded + v; M.levels[k] = 0 end
end
M.points = M.points + refunded
check(refunded > 0, "skills to refund")
open_panel()
check(#keys() == 0, "reset noticed when the tree is read again: pre-allocations cleared (" .. #keys() .. ")")
check(SPA.plan(1).preset == preset_before, "the preset link stays after a reset")

-- the reset button in the panel: the tree is read again when the panel closes, before any spending
M.points = 0
SPA.refresh_points(1)
plan_greedy(3)
level_up(1)                                      -- one of them learned
check(#keys() == 2, "two points planned before the reset button test (" .. #keys() .. ")")
local refunded2 = 0
for k, v in pairs(M.levels) do
	local s = SPA.tree(1).skills[k]
	if s and s.plannable and v > 0 then refunded2 = refunded2 + v; M.levels[k] = 0 end
end
M.points = M.points + refunded2
check(refunded2 > 0, "skills to refund with the button")
local calls_reset = #M.add_skill_calls
M.click(find("skill_pts_holder", "button_stats_reset_all"))
M.close_panel()
M.tick(3000)
check(#keys() == 0 and #M.add_skill_calls == calls_reset, "reset button: pre-allocations cleared, nothing spent (" .. #keys() .. ")")
open_panel()

---------------------------------------------------------------- allocate now
-- free points (e.g. a lord recruited at a high rank) and a preset loaded in the panel: nothing is
-- spent while the panel is open; "Allocate N points now" spends what the free points cover
M.points = 0
SPA.refresh_points(1)
plan_greedy(5)
check(#keys() == 5, "five points planned for the allocate-now test (" .. #keys() .. ")")
local five = {}
for i, k in ipairs(keys()) do five[i] = k end
check(SPA.save_preset_as(1, "Five"), "preset Five saved")
menu("spa_act_clear")
check(#keys() == 0, "plan cleared")
M.points = 3                                     -- three free points
SPA.refresh_points(1)
local calls_now = #M.add_skill_calls
local five_i
for i, p in ipairs(SPA.preset_list("wh_main_emp_lord")) do if p.name == "Five" then five_i = i end end
check(five_i and menu("spa_opt_" .. five_i), "preset Five in the menu")
check(#keys() == 5 and #M.add_skill_calls == calls_now and M.points == 3,
	"preset loaded, nothing spent while the panel is open (" .. #keys() .. " planned, points " .. M.points .. ")")
local function badge_shows(key, text, colour) return string.find(badge(key) or "", "[[col:" .. colour .. "]]" .. text .. "[[/col]]", 1, true) ~= nil end
check(badge_shows(five[1], "1", "green") and badge_shows(five[2], "2", "green") and badge_shows(five[3], "3", "green"),
	"the points the free points cover are numbered in order, 1 2 3: " .. tostring(badge(five[1])) .. " / " .. tostring(badge(five[3])))
check(string.find(badge(five[1]), "col:green", 1, true) and not string.find(badge(five[1]), "col:yellow", 1, true),
	"points the free points cover are green: " .. tostring(badge(five[1])))
check(badge_shows(five[4], tostring(M.rank + 1), "yellow") and badge_shows(five[5], tostring(M.rank + 2), "yellow"),
	"later points show their rank in yellow: " .. tostring(badge(five[4])) .. " / " .. tostring(badge(five[5])))
check(enabled("spend") and icon("spend").tooltip == "Allocate 3 points now", "Allocate now works: " .. tostring(icon("spend").tooltip))
M.click(icon("spend"))
check(find("spa_confirm", "DY_text").text == "Allocate 3 points now?", "it asks first")
M.click(find("spa_confirm", "both_group", "button_cancel"))
check(M.points == 3 and #keys() == 5 and #M.add_skill_calls == calls_now, "cancel: nothing spent")
local refreshes, spent_calls = 0, 0
local real_refresh, real_spent = SPA.ui.refresh, SPA.ui.on_points_spent
SPA.ui.refresh = function(...) refreshes = refreshes + 1 return real_refresh(...) end
SPA.ui.on_points_spent = function(cqi) spent_calls = spent_calls + 1 end
check(menu("spa_act_spend"), "Allocate now clicked")
SPA.ui.refresh, SPA.ui.on_points_spent = real_refresh, real_spent
check(spent_calls == 1, "the panel is told once, when the pass is over (" .. spent_calls .. ")")
-- the game's skills panel doesn't show points spent while it is open (switching tabs doesn't help):
-- the game is asked to show the character again; if the counter still shows the old number, the panel
-- is closed and opened again
local function show_calls()
	local n = 0
	for _, c in ipairs(M.commands) do if c == 'SelectAndShowDetailsForCharacter(this, "skills")' then n = n + 1 end end
	return n
end
-- redrawn in place
M.counter.text = "3"                           -- what the panel showed before the points were spent
M.simulated, M.commands, M.redraw_in_place = {}, {}, true
SPA.ui.on_points_spent(1)
M.tick(1000)
M.redraw_in_place = false
check(show_calls() == 1 and #M.simulated == 0 and SPA.ui.panel_open and M.counter.text == "0",
	"redrawn in place: no close (" .. show_calls() .. " calls, " .. table.concat(M.simulated, ",") .. ")")
check(row_visible(true) and badge(five[4]) ~= nil, "buttons and badges still there")
-- not redrawn in place: closed and opened again
M.counter.text = "3"
M.simulated, M.commands = {}, {}
SPA.ui.on_points_spent(1)
M.advance(100)
check(#M.simulated == 0 and SPA.ui.panel_open, "first only asked to show it again")
M.advance(100)
check(M.simulated[1] == "button_ok" and #M.simulated == 1 and not SPA.ui.panel_open, "counter still old: closed")
M.advance(200)
check(show_calls() == 2 and SPA.ui.panel_open and M.counter.text == "0", "and opened again on the Skills tab")
M.tick(3000)
check(row_visible(true) and badge(five[4]) ~= nil, "buttons and badges back")
check(#M.add_skill_calls == calls_now + 3, "redrawing spent nothing more")
-- showing it again closes the panel: it is opened again
M.counter.text = "3"
M.simulated, M.commands, M.show_toggles = {}, {}, true
SPA.ui.on_points_spent(1)
M.tick(2000)
M.show_toggles = false
check(SPA.ui.panel_open and #M.simulated == 0 and show_calls() == 2, "closed by showing it: opened again (" .. show_calls() .. ")")
-- not reopened by a later close if the panel didn't close
M.counter.text = "3"
M.simulated, M.commands = {}, {}
M.ok_button_stuck = true
SPA.ui.on_points_spent(1)
M.tick(1500)
M.ok_button_stuck = false
check(SPA.ui.panel_open and SPA.ui.reopen_cqi == nil and M.simulated[1] == "button_ok", "a panel that didn't close is left alone")
close_panel()
M.tick(1000)
check(not SPA.ui.panel_open, "the player's own close is not undone")
-- with the panel closed (points spent at a rank-up) nothing happens
M.simulated, M.commands = {}, {}
SPA.ui.on_points_spent(1)
M.tick(1000)
check(#M.simulated == 0 and show_calls() == 0 and not SPA.ui.panel_open, "nothing done with the panel closed")
open_panel()
-- a panel that doesn't open again is tried twice, then reported
M.counter.text = "3"
M.no_reopen = true
M.commands = {}
local real_error, reported = SPA.error, nil
SPA.error = function(msg) reported = msg end
SPA.ui.on_points_spent(1)
M.tick(3000)
SPA.error = real_error
M.no_reopen = false
check(show_calls() == 3 and not SPA.ui.panel_open, "shown once in place, then two tries to open it again (" .. show_calls() .. ")")
check(reported ~= nil and string.match(reported, "did not open again") ~= nil, "then reported: " .. tostring(reported))
open_panel()
check(not enabled("spend"), "no free points left: Allocate now doesn't work")

-- free points not allocated in the panel wait: closing it, the turn start and opening it again
-- spend nothing; the next rank-up spends them with the new one
M.points = 1
SPA.refresh_points(1)
local calls_wait = #M.add_skill_calls
close_panel()
M.fire("FactionTurnStart", { faction = function() return M.faction end })
M.drain()
open_panel()
check(M.points == 1 and #keys() == 2 and #M.add_skill_calls == calls_wait, "nothing spent by closing the panel or the turn start")
level_up(1)
check(M.points == 0 and #keys() == 0, "the next rank-up spends them all (" .. #keys() .. " left, points " .. M.points .. ")")

-- a pre-allocation that needs a higher rank, with free points granted without rank-ups: only the points
-- before it are allocated now (numbered 1, 2, ... in green), it waits for its rank (on a fresh character:
-- rank 1, nothing learned)
for k, v in pairs(initial_levels) do M.levels[k] = v end
M.rank, M.points = 1, 0
SPA.tree(1, true)
local t7 = SPA.tree(1)
local locked7
for _, k in ipairs(t7.order) do
	local s = t7.skills[k]
	local need7 = R.required_rank(s.ranks[1])
	if s.plannable and (M.levels[k] or 0) == 0 and #s.req == 0 and #s.sub == 0 and need7 > M.rank + 1 and need7 <= M.rank + 6 then
		locked7 = k
		break
	end
end
if locked7 then
	for _ = 1, 10 do
		local t = SPA.tree(1)
		if fits_now(t, keys(), locked7) then break end
		for _, k in ipairs(t.order) do
			if k ~= locked7 and fits_now(t, keys(), k) then M.click(M.cards[k]) break end
		end
	end
	M.click(M.cards[locked7])
	local n7 = #keys()
	check(keys()[n7] == locked7 and n7 >= 2, "rank-locked skill planned after " .. (n7 - 1) .. " others")
	M.points = n7                                -- enough free points for all of them
	SPA.refresh_points(1)
	SPA.ui.refresh()
	local text7 = icon("spend").tooltip
	check(text7 == "Allocate " .. (n7 - 1) .. (n7 - 1 == 1 and " point" or " points") .. " now", "only the points before it are offered: " .. tostring(text7))
	local numbered = true
	for i = 1, n7 - 1 do
		if not string.find(badge(keys()[i]) or "", "[[col:green]]" .. i .. "[[/col]]", 1, true) then numbered = false end
	end
	check(numbered and string.find(badge(locked7), "[[col:yellow]]" .. R.required_rank(t7.skills[locked7].ranks[1]) .. "[[/col]]", 1, true),
		"the points learned now are numbered 1 to " .. (n7 - 1) .. " in green; it shows its rank in yellow")
	menu("spa_act_spend")
	check(#keys() == 1 and keys()[1] == locked7 and M.points == 1, "it waits for its rank (" .. #keys() .. " left, points " .. M.points .. ")")
	SPA.clear_plan(1)
	M.points = 0
	SPA.refresh_points(1)
	M.drain()
else
	print("note: no rank-locked skill left for the allocate-now test")
end

---------------------------------------------------------------- multiplayer
-- plans are personal (nothing sent); spends go through UI triggers and are made from the trigger
M.points = 0
SPA.refresh_points(1)
plan_greedy(2)
M.multiplayer = true
M.sent = {}
local next_key = keys()[1]
local n_mp = #keys()
close_panel()
M.level_up(1)
M.drain()
open_panel()
local spend_msg
for _, s in ipairs(M.sent) do if string.match(s, "^spa2|spend|1||") then spend_msg = s end end
check(spend_msg == "spa2|spend|1||" .. next_key, "MP: spend sent as a UI trigger, with the skill's key: " .. tostring(spend_msg))
check(M.add_skill_calls[#M.add_skill_calls] == next_key and #keys() == n_mp - 1, "MP: the trigger made the spend (" .. #keys() .. " left)")
local n_sent = #M.sent
menu("spa_act_clear")
plan_greedy(2)
check(#M.sent == n_sent, "MP: plan changes stay on this machine (" .. (#M.sent - n_sent) .. " messages sent)")
SPA.save_preset_as(1, "MP personal")
SPA.rename_preset(1, "MP personal", "MP personal 2")
SPA.delete_preset(1, "MP personal 2")
check(#M.sent == n_sent, "MP: preset changes stay on this machine")
menu("spa_act_clear")
-- a spend message from another player's faction spends nothing here
local calls_other = #M.add_skill_calls
M.fire("UITrigger", { trigger = function() return "spa2|spend|1||" .. next_key end, faction_cqi = function() return 78 end })
check(#M.add_skill_calls == calls_other, "MP: a spend for a character of another faction is ignored")
-- Allocate now in multiplayer: one UI trigger per point
plan_greedy(3)
M.points = 2
SPA.refresh_points(1)
M.sent = {}
menu("spa_act_spend")
local n_spend, longest, only_spend = 0, 0, true
for _, s in ipairs(M.sent) do
	if string.match(s, "^spa2|spend|1||") then n_spend = n_spend + 1 else only_spend = false end
	if #s > longest then longest = #s end
end
check(n_spend == 2 and M.points == 0 and #keys() == 1, "MP: Allocate now spends through one trigger per point (" .. n_spend .. ", " .. #keys() .. " left)")
check(only_spend and longest <= 255, "MP: only short spend messages are sent (longest " .. longest .. ")")
check(SPA.spending[1] == nil, "MP: nothing left in flight")
menu("spa_act_clear")
M.multiplayer = false

---------------------------------------------------------------- characters the game no longer has
-- at the turn start, everything kept for a character the game can't find any more is dropped
local some_skill = SPA.tree(1).order[1]
SPA.history[901] = { some_skill }
SPA.plans[902] = { keys = { some_skill } }
SPA.live_cache[903], SPA.tree_cache[903] = { skills = {} }, {}
SPA.pending_choices[904] = { [some_skill] = 1 }
SPA.unshown[905] = 1
local history_1 = SPA.history[1]
M.fire("FactionTurnStart", { faction = function() return M.faction end })
M.drain()
check(SPA.history[901] == nil and SPA.plans[902] == nil and SPA.live_cache[903] == nil and SPA.tree_cache[903] == nil
	and SPA.pending_choices[904] == nil and SPA.unshown[905] == nil, "turn start: what was kept for characters the game no longer has is dropped")
check(SPA.live_cache[1] ~= nil and SPA.tree_cache[1] ~= nil and SPA.history[1] == history_1, "turn start: the living character's data is kept")
check(string.match(SPA.serialize_state(), "H:901:") == nil, "the save no longer holds a dead character's history")

---------------------------------------------------------------- greyed out and back
-- The game's disabled flag isn't documented (M.disable_mode): whichever way it behaves, a button that
-- was greyed out must work again once it should. A case seen in game: the dropdown greyed out on a
-- character type without presets stayed locked on one with presets. Here: the type's presets
-- deleted, then one saved, twice, with fresh buttons for each way the flag may behave.
local mode_before = M.disable_mode
local subtype = "wh_main_emp_lord"
for _, mode in ipairs({ "flag", "state", "both" }) do
	M.disable_mode = mode
	for _, name in ipairs({ "spa_presets", "spa_btn_plan", "spa_btn_new", "spa_btn_overwrite", "spa_btn_rename", "spa_btn_delete",
		"spa_btn_clear", "spa_btn_spend" }) do
		local c = find(name)
		if c then c:Destroy() end                       -- a new panel: the game made new buttons
	end
	SPA.clear_plan(1)
	local list = SPA.preset_list(subtype)
	while #list > 0 do SPA.delete_preset(1, list[1].name) end
	M.drain()
	SPA.ui.refresh()
	btn = find("spa_presets")
	check(#SPA.preset_list(subtype) == 0 and greyed(btn) and plain(btn:Find("button_txt").text) == "No presets",
		mode .. ": no presets, dropdown greyed out")
	M.click(btn)
	check(find("spa_menu") == nil, mode .. ": greyed-out dropdown doesn't open")
	check(greyed(icon("clear")), mode .. ": nothing planned, Clear greyed out")
	for cycle = 1, 2 do
		plan_greedy(1)
		SPA.ui.refresh()
		check(works(icon("clear")), mode .. " #" .. cycle .. ": something planned, Clear works again")
		check(SPA.save_preset_as(1, "Cycle " .. mode .. " " .. cycle), mode .. " #" .. cycle .. ": preset saved")
		SPA.clear_plan(1)
		M.drain()
		SPA.ui.refresh()
		check(works(btn) and plain(btn:Find("button_txt").text) == "Select preset", mode .. " #" .. cycle .. ": a preset exists, the dropdown works again")
		check(greyed(icon("clear")) and works(icon("new")), mode .. " #" .. cycle .. ": plan cleared, Clear greyed out again (New still works: skills learned)")
		M.click(btn)
		local row = find("spa_menu", "spa_opt_1")
		check(row ~= nil, mode .. " #" .. cycle .. ": clicking the dropdown opens the list")
		if row then M.click(row) end
		check(find("spa_menu") == nil and #keys() > 0 and SPA.plan(1).preset == "Cycle " .. mode .. " " .. cycle,
			mode .. " #" .. cycle .. ": picking the preset loads it")
		SPA.ui.refresh()
		check(works(icon("delete")) and works(icon("clear")), mode .. " #" .. cycle .. ": Delete and Clear work")
		SPA.delete_preset(1, "Cycle " .. mode .. " " .. cycle)
		SPA.clear_plan(1)
		M.drain()
		SPA.ui.refresh()
		check(greyed(btn) and greyed(icon("delete")), mode .. " #" .. cycle .. ": preset deleted, dropdown greyed out again")
	end
end
M.disable_mode = mode_before
check(SPA.save_preset_as(1, "Kept"), "a preset for the presets file")

---------------------------------------------------------------- plan mode
-- A neutral planning view: the character type's tree as at rank 1 with nothing learned. Every click plans
-- (it lands on a shield over the card, so the game makes no choice), the cards show the build, and
-- leaving plan mode makes a build planned there the pre-allocations (an empty one changes nothing).
local function copy(t) local c = {} for k, v in pairs(t) do c[k] = v end return c end
local function draft() return SPA.drafts[1] and SPA.drafts[1].keys or {} end
local function same_list(a, b)
	if #a ~= #b then return false end
	for i = 1, #a do if a[i] ~= b[i] then return false end end
	return true
end
local function undo_clicks()
	local n = 0
	for _, id in ipairs(M.simulated) do if id == "button_stats_reset" then n = n + 1 end end
	return n
end
-- click `n` skills that can join the build (the first or the last candidate each time)
local function plan_mode_click(n, last)
	for _ = 1, n do
		local t = SPA.rules_tree(1)
		local cands = {}
		for _, k in ipairs(t.order) do if fits_now(t, draft(), k) then cands[#cands + 1] = k end end
		if #cands == 0 then break end
		M.click(M.cards[last and cands[#cands] or cands[1]])
	end
end
local function confirm_tick() M.click(find("spa_confirm", "both_group", "button_tick")) end
-- a card's look: its state, its name's and its pips', and whether its tick and sparkles show
local function look(key)
	local card = M.cards[key]
	local lp = card:Find("level_parent")
	return table.concat({ card.state, card:Find("dy_skill").state, lp:Find("level1").state, lp:Find("level2").state,
		lp:Find("level3").state, tostring(card:Find("icon_check").visible), tostring(card:Find("particle_emitter").visible) }, " ")
end
local function looks() local out = {} for key in pairs(M.cards) do out[key] = look(key) end return out end
local function looks_match(want, skip)
	for key, v in pairs(want) do
		if key ~= skip and look(key) ~= v then return false, key .. ": " .. look(key) .. " instead of " .. v end
	end
	return true
end
-- how many cards show their shield
local function shields()
	local n = 0
	for _, card in pairs(M.cards) do
		local sh = card:Find("spa_shield")
		if sh and sh.visible then n = n + 1 end
	end
	return n
end
-- the rank 1 look of a skill (planned or not): the card's state
local function rank1_look(key)
	local s = R.from_scratch(SPA.tree(1)).skills[key]
	local lv = s.level or 0
	if lv <= 0 then return s.auto and "locked_auto_unlock" or "locked" end
	return lv >= (s.total or 1) and "maxed" or "complete"
end
-- every card in its rank 1 look: card, name and pips (greyed out unless learned at creation), no tick,
-- no sparkles
local function rank1_everywhere()
	local scratch = R.from_scratch(SPA.tree(1))
	for key in pairs(M.cards) do
		local want = rank1_look(key)
		local l = look(key)
		if not string.match(l, "^" .. want .. " ") or not string.match(l, " false false$") then return false, key .. ": " .. l .. " (" .. want .. ")" end
		local lv = scratch.skills[key].level or 0
		local lp = M.cards[key]:Find("level_parent")
		for i = 1, math.min(scratch.skills[key].total or 1, 3) do
			local pip = lp:Find("level" .. i).state
			local want_pip = (lv <= 0 and "locked") or (i <= lv and "active") or "inactive"
			if pip ~= want_pip then return false, key .. " pip " .. i .. ": " .. pip .. " (" .. want_pip .. ")" end
		end
	end
	return true
end
local saved_levels, saved_rank, saved_points = copy(M.levels), M.rank, M.points
SPA.clear_plan(1)

-- the card's shield in the mod's own layout (ui/skill_preallocation/spa_shield): hidden, above the card's parts, with
-- a neutral tooltip (the card's skill turned into the skill at level 1: its name, description and the
-- first level's effects from its database record) and no stats preview; it takes the mouse, has no image
-- and none of the card's own code
local layout = read_layout()
local sa = string.find(layout, "\t\t<spa_shield\r\n", 1, true)
local se = sa and string.find(layout, "</spa_shield>", sa, true)
local shield_xml = (sa and se) and string.sub(layout, sa, se) or ""
check(string.find(shield_xml, 'callback_id="ContextLayoutTooltip"\r\n\t\t\t\t\tcontext_object_id="CcoCampaignCharacterSkill"', 1, true)
	and LAYOUT_TIP_FUNCTION == SPA.ui.TOOLTIP_FUNCTION
	and string.find(LAYOUT_TIP_FUNCTION, 'DatabaseRecordContext("CcoCharacterSkillRecord", Key)', 1, true)
	and string.find(LAYOUT_TIP_FUNCTION, "EffectList:r.EffectListForLevel(1)", 1, true)
	and string.find(LAYOUT_TIP_FUNCTION, "=> GetIfElse(IsContextValid(n), n, this)", 1, true)
	and not string.find(shield_xml, 'context_object_id="CcoCharacterSkillRecord"', 1, true)
	and string.find(shield_xml, 'value="ui/common ui/character_background_skill_tooltip"', 1, true)
	and not string.find(shield_xml, "stats_effects_holder", 1, true) and not string.find(shield_xml, "ContextPropagator", 1, true)
	and string.find(shield_xml, 'value="clear_preview"', 1, true) and not string.find(shield_xml, "ContextCommandLeftClick", 1, true)
	and string.find(shield_xml, 'interactive="true"', 1, true) and string.find(shield_xml, 'visible="false"', 1, true)
	and string.find(shield_xml, 'priority="21"', 1, true) and not string.find(shield_xml, "CharacterDetailsCardCallback", 1, true)
	and not string.find(shield_xml, "imagepath", 1, true), "the card's shield in the layout carries the neutral tooltip, no stats preview")
do
	-- the layout: root > spa_shield > its 3 pips' shields (a layout made with CreateComponent yields its
	-- root's child); each pip's shield hidden, a pip's size, at its pip's place on the game's card, with the
	-- tooltip of its level and clear_preview
	local nested = string.match(layout, '<hierarchy>%s*<root this="[^"]+">%s*<spa_shield this="[^"]+">%s*<spa_pip_shield1 this="[^"]+"/>%s*'
		.. '<spa_pip_shield2 this="[^"]+"/>%s*<spa_pip_shield3 this="[^"]+"/>%s*</spa_shield>%s*</root>%s*</hierarchy>') ~= nil
	local function component(id) return string.match(layout, "\r\n\t\t<" .. id .. "\r\n.-</" .. id .. ">") or "" end
	local function attr(xml, name) return string.match(xml, "\t\t\t" .. name .. '="([^"]*)"') end
	local pips_ok = true
	for i = 1, 3 do
		local ps = component("spa_pip_shield" .. i)
		if not (string.find(ps, 'visible="false"', 1, true) and string.find(ps, 'interactive="true"', 1, true)
			and string.find(ps, 'width="16"', 1, true) and string.find(ps, 'height="20"', 1, true) and attr(ps, "priority") == "22"
			and attr(ps, "dock_offset") == string.format("169.00,%d.00", 4 + (i - 1) * 16) and attr(ps, "docking") == "Top Left"
			and LAYOUT_PIP_FUNCTIONS[i] == SPA.ui.tooltip_function(i, true) and not string.find(ps, "ContextCommandLeftClick", 1, true)
			and string.find(ps, 'value="clear_preview"', 1, true) and string.find(ps, 'value="ui/common ui/character_background_skill_tooltip"', 1, true)
			and not string.find(ps, "imagepath", 1, true)) then pips_ok = false end
	end
	local sh = component("spa_shield")
	check(nested and pips_ok and attr(sh, "docking") == "Top Left" and attr(sh, "dock_offset") == "0.00,0.00"
		and string.find(sh, 'width="185"', 1, true) and string.find(sh, 'height="67"', 1, true)
		and not string.find(layout, "spa_mod_click", 1, true)
		and string.find(LAYOUT_PIP_FUNCTIONS[2], 'Name:this.Name + " (2)"', 1, true)
		and string.find(LAYOUT_PIP_FUNCTIONS[2], "EffectList:r.EffectListForLevel(2)", 1, true) and LAYOUT_TIP_FUNCTION == SPA.ui.tooltip_function(1),
		"the shield layout: the card's size at its top left; the pips' shields in it, at the pips' places, each with its level's tooltip")
end
local game_copy = io.open("../../src/ui/campaign ui/character_details_panel_skills.twui.xml")
if game_copy then game_copy:close() end
check(game_copy == nil, "the mod ships no copy of the game's skills panel layout")

-- a hero recruited at rank 15: nothing learned, 14 free points
close_panel()
for k, v in pairs(initial_levels) do M.levels[k] = v end
M.rank, M.points = 15, 14
SPA.plans[1], SPA.history[1] = nil, nil
SPA.forget(1)
open_panel()
check(not SPA.in_plan_mode(1) and works(icon("plan")) and icon("plan").state == "active" and icon("plan").tooltip == SPA.text.get("tip_plan"),
	"plan mode is off, its button works")
local first
do
	local t = SPA.tree(1)
	for _, k in ipairs(t.order) do if fits_now(R.from_scratch(t), {}, k) then first = k break end end
end
M.click(M.cards[first])
check(#M.pending == 1 and SPA.has_unconfirmed(1), "outside plan mode, a click with free points is the game's own choice")
local real = looks()
M.simulated = {}
M.click(icon("plan"))
check(SPA.in_plan_mode(1) and SPA.ui.plan_cqi == 1 and #draft() == 0, "plan mode on: an empty build (" .. #draft() .. ")")
check(#M.pending == 1 and undo_clicks() == 0 and M.points == 14, "the choice made before stays chosen (the game learns it when the panel closes)")
check(icon("plan").state == "selected" and icon("plan").tooltip == SPA.text.get("tip_plan_on"), "the plan mode button is on")
check(greyed(icon("spend")) and icon("spend").tooltip == SPA.text.get("tip_spend_plan"), "Allocate now is off in plan mode")
check(greyed(icon("clear")) and icon("clear").tooltip == SPA.text.get("tip_clear_plan"), "Clear: the build (empty so far)")
-- a shield on every card, made from the mod's layout: over the card, just above it, with the card's skill
-- (its tooltip uses it; a component a script makes has no context of its own)
local shields_ok = true
for _, card in pairs(M.cards) do
	local sh = card:Find("spa_shield")
	if not (sh and sh.visible and sh.priority == 21 and sh.ctx.CcoCampaignCharacterSkill == card.ctx.CcoCampaignCharacterSkill
		and sh.ctx.CcoCharacterSkillRecord == nil and M.covers(sh, card)) then shields_ok = false end
end
check(shields_ok and shields() == #live.skills, "every card shows its shield, over it, just above it, with the card's skill")
local made = 0
for _, c in ipairs(M.created) do if c == "ui/skill_preallocation/spa_shield" then made = made + 1 end end
check(made == #live.skills, "one shield made from the mod's layout per card (" .. made .. ")")
check(M.other_calls == nil and SPA.ui.check_tooltip == nil, "plan mode evaluates nothing of the game's but the cards' Key")
do
	-- the pips' shields: shown over the pips the card shows (its skill's levels), with the card's skill, a
	-- priority above the shield: the mouse over a pip finds its shield
	local ok, why, shown, hidden = true, nil, 0, 0
	for key, card in pairs(M.cards) do
		local lp = card:Find("level_parent")
		local sh = card:Find("spa_shield")
		for i = 1, 3 do
			local pip, ps = lp:Find("level" .. i), sh:Find("spa_pip_shield" .. i)
			local want = pip.visible == true
			if want then shown = shown + 1 else hidden = hidden + 1 end
			if ps.visible ~= want or (want and (ps.ctx.CcoCampaignCharacterSkill ~= card.ctx.CcoCampaignCharacterSkill
				or ps.priority ~= 22 or not M.covers(ps, pip) or M.hit_pip(card, i) ~= ps)) then
				ok, why = false, key .. " pip " .. i
			end
		end
	end
	check(ok and shown > 0 and hidden > 0, "the pips' shields cover the pips the cards show (" .. shown .. "; " .. hidden
		.. " hidden), with the card's skill " .. tostring(why))
	-- a pip the game hides meanwhile: its shield follows at the next refresh
	local key, card
	for k, c in pairs(M.cards) do if c:Find("level_parent"):Find("level2").visible then key, card = k, c break end end
	card:Find("level_parent"):Find("level2").visible = false
	SPA.ui.refresh()
	local ps2 = card:Find("spa_shield"):Find("spa_pip_shield2")
	check(not ps2.visible, "a pip hidden by the game: its shield is hidden too")
	card:Find("level_parent"):Find("level2").visible = true
	SPA.ui.refresh()
	check(ps2.visible and ps2.ctx.CcoCampaignCharacterSkill == card.ctx.CcoCampaignCharacterSkill, "shown again with the pip")
	card:Find("level_parent").visible = false
	SPA.ui.refresh()
	local any = false
	for i = 1, 3 do if card:Find("spa_shield"):Find("spa_pip_shield" .. i).visible then any = true end end
	check(not any, "no pips shown on a card (their column hidden): none of its pips' shields either")
	card:Find("level_parent").visible = true
	SPA.ui.refresh()
	check(ps2.visible, "back with the pips")
end
do
	-- every shield carries the rank its level asks for (its tooltip shows the game's "Available at rank N."
	-- under the description, or "Automatically granted at rank N." for a level the game grants): the card's
	-- shield level 1's, each pip's shield its own level's; "0" for none beyond rank 1, or a level learned
	-- from the start
	local t = SPA.rules_tree(1)
	local function want(s, level)
		if (s.level or 0) >= level then return "0", "0" end
		if s.auto then
			for _, a in ipairs(s.auto) do
				if a.level == level and a.rank + 1 > 1 then return tostring(a.rank + 1), "1" end
			end
			return "0", "0"
		end
		local stored = s.ranks and s.ranks[level]
		if stored and stored + 1 > 1 then return tostring(stored + 1), "0" end
		return "0", "0"
	end
	local ok, why, ranked, granted, own = true, nil, 0, 0, 0
	for key, card in pairs(M.cards) do
		local s = t.skills[key]
		local sh = card:Find("spa_shield")
		local parts = { [0] = sh }
		for i = 1, 3 do parts[i] = sh:Find("spa_pip_shield" .. i) end
		for i = 0, 3 do
			local level = math.max(i, 1)
			local r, a = want(s, level)
			local u = parts[i]
			local got_r, got_a = u:GetProperty("spa_rank"), u:GetProperty("spa_auto")
			if got_r ~= r or got_a ~= a then ok, why = false, key .. " level " .. level .. ": " .. got_r .. "/" .. got_a .. ", expected " .. r .. "/" .. a end
			if i == 0 and r ~= "0" then if a == "1" then granted = granted + 1 else ranked = ranked + 1 end end
			if i >= 2 and r ~= "0" and r ~= (want(s, 1)) then own = own + 1 end
		end
	end
	check(ok and ranked > 0 and granted > 0 and own > 0, "each shield carries its level's rank: " .. ranked .. " cards ask for a rank, "
		.. granted .. " are granted at one, " .. own .. " pips' levels ask for their own " .. tostring(why))
	-- and the tooltip functions in the layout read them, and show the game's own line under the description
	check(string.find(LAYOUT_TIP_FUNCTION, 'k = RoundFloat(ToNumber(self.GetProperty("spa_rank")))', 1, true)
		and string.find(LAYOUT_TIP_FUNCTION, 'Loc(GetIfElse(self.GetProperty("spa_auto") == "1", "skill_locked_auto_unlock", "skill_locked_rank"))', 1, true)
		and string.find(LAYOUT_TIP_FUNCTION, "Description:this.Description + t,", 1, true)
		and string.find(LAYOUT_PIP_FUNCTIONS[3], "Description:this.Description + t,", 1, true),
		"the tooltips add the rank line to the description")
end
check(btn.priority > 21 and icon("plan").priority > 21, "the presets row stays above the shields")
local made_again = 0
for _, c in ipairs(M.created) do if c == "ui/skill_preallocation/spa_shield" then made_again = made_again + 1 end end
check(made_again == made, "the shields are made once while the panel is open (" .. made_again .. ")")
local r1, why1 = rank1_everywhere()
check(r1, "every card looks as at rank 1: locked (points from creation and mounts aside), no tick, no sparkles " .. tostring(why1))
-- the panel's own undo button still drops a choice made before
M.click(find("skill_pts_holder", "button_stats_reset"))
M.tick(300)
check(#M.pending == 0 and not SPA.has_unconfirmed(1) and SPA.tree(1).points == 14, "the panel's undo button drops the earlier choice; the mod follows")
-- clicks plan, even with free points: they land on the shields, the game makes no choice
local levels_before = copy(M.levels)
M.simulated = {}
plan_mode_click(20)
local learned_any = false
for k, v in pairs(M.levels) do if v ~= levels_before[k] then learned_any = true end end
check(#draft() == 20 and #M.pending == 0 and M.points == 14 and not learned_any and undo_clicks() == 0,
	"20 points planned with 14 free points: no choice made, nothing undone, nothing learned (" .. #draft() .. ", " .. #M.pending .. " held)")
check(#keys() == 0, "the pre-allocations aren't touched while planning")
local counts = {}
for _, k in ipairs(draft()) do counts[k] = (counts[k] or 0) + 1 end
local rb, whyb = rank1_everywhere()
check(rb, "planned skills stay greyed out like the rest (their badges show the plan) " .. tostring(whyb))
-- badges: the rank each point comes at from rank 1, never green (no "now" in a build from rank 1)
SPA.ui.refresh()
local function badge_has(key, rank, colour)
	local b = badge(key)
	return b ~= nil and string.find(b, "[[col:" .. colour .. "]]" .. rank .. "[[/col]]", 1, true) ~= nil
end
check(badge_has(draft()[1], 2, "yellow") and badge_has(draft()[20], 21, "yellow"), "badges: the rank from rank 1")
local any_green = false
for _, card in pairs(M.cards) do
	local b = card:Find("spa_badge")
	if b and b.visible and string.find(b.text, "green", 1, true) then any_green = true end
end
check(not any_green, "no green badge in plan mode")
-- a click on a badge removes a point of the build: the badge lies above the shield, so neither the shield
-- nor the card sees the click
local victim = draft()[20]
do
	local vb = M.cards[victim]:Find("spa_badge")
	local card = M.cards[victim]
	check(vb and vb.visible and vb.interactive == true and (vb.priority or 0) > card:Find("spa_shield").priority
		and M.index_of(card, vb) > M.index_of(card, card:Find("spa_shield")), "in plan mode the badges lie above the shields")
	-- a badge is adopted again only when something came after it among the card's parts
	local before = M.adopted or 0
	SPA.ui.refresh()
	SPA.ui.refresh()
	check((M.adopted or 0) == before and before > 0, "refreshes don't adopt the badges again (" .. (M.adopted or 0) - before .. " of " .. before .. ")")
end
click_badge(victim)
check(#draft() == 19 and #M.pending == 0 and undo_clicks() == 0, "a click on the badge removes a point from the build (" .. #draft() .. ")")
counts[victim] = counts[victim] - 1
if counts[victim] == 0 then counts[victim] = nil end
check(rank1_everywhere(), "the cards keep the rank 1 look")
do
	-- a click on a pip's shield plans like one on the card's shield (no choice made); a click on the badge
	-- removes the point again
	local t, key = SPA.rules_tree(1), nil
	for _, k in ipairs(t.order) do
		if M.cards[k] and M.cards[k]:Find("level_parent"):Find("level2").visible and fits_now(t, draft(), k) then key = k break end
	end
	local before, points = #draft(), M.points
	local ps = M.hit_pip(M.cards[key], 2)
	M.click(ps)
	check(ps.id == "spa_pip_shield2" and #draft() == before + 1 and draft()[#draft()] == key and #M.pending == 0 and M.points == points
		and undo_clicks() == 0, "a click on a pip's shield plans a point, no choice made (" .. #draft() .. ")")
	click_badge(key)
	check(#draft() == before and #M.pending == 0 and undo_clicks() == 0, "a click on the badge removes the point again (" .. #draft() .. ")")
end
do
	-- a card that gets its first badge in plan mode (made after its shield): a click on the badge removes
	-- the point, and the numbers keep their size as more are added
	local function in_draft(k) local n = 0 for _, d in ipairs(draft()) do if d == k then n = n + 1 end end return n end
	local t, key = SPA.rules_tree(1), nil
	for _, k in ipairs(t.order) do
		local s = t.skills[k]
		if M.cards[k] and not M.cards[k]:Find("spa_badge") and (s.total or 1) >= 2 and fits_now(t, draft(), k) then key = k break end
	end
	check(key ~= nil, "found a card without a badge yet")
	if key then
		local before = #draft()
		M.click(M.cards[key])
		local fb = M.cards[key]:Find("spa_badge")
		check(#draft() == before + 1 and fb and fb.visible, "planned in plan mode, the card gets its badge")
		if fits_now(SPA.rules_tree(1), draft(), key) then
			M.click(M.cards[key])
			check(in_draft(key) == 2 and not fb.shrunk, "a second level: the numbers keep their size")
			click_badge(key)
		end
		click_badge(key)
		check(#draft() == before and #M.pending == 0 and undo_clicks() == 0,
			"a click on a badge made in plan mode removes the point (" .. #draft() .. ", expected " .. before .. ")")
	end
end
-- strict order while planning too: a skill whose rank isn't reached where its point would come is refused
local late_key
do
	local t = SPA.rules_tree(1)
	for _, k in ipairs(t.order) do
		local sk = t.skills[k]
		if sk.plannable and #sk.req == 0 and #sk.sub == 0 and R.required_rank(sk.ranks[1]) > #draft() + 2 and R.required_rank(sk.ranks[1]) < 40
			and (counts[k] or 0) == 0 then late_key = k break end
	end
end
check(late_key ~= nil, "found a skill whose rank comes later than the next point")
if late_key then
	M.click(M.cards[late_key])
	check(#draft() == 19 and badge(late_key) == nil, "plan mode: it is refused where its point would come before its rank")
end
-- the game draws over a card meanwhile: the plan look comes back (after the mouse moved, or at the next
-- refresh), and the game's newest look is what is put back later
local other_key
for key in pairs(M.cards) do if not counts[key] and rank1_look(key) == "locked" then other_key = key break end end
M.cards[other_key].state = "hover"
M.mouse_on(M.cards[other_key]:Find("spa_shield"))
M.tick(150)
check(M.cards[other_key].state == "locked", "the mouse moved: a card the game drew over gets the rank 1 look back")
SPA.ui.refresh()
M.cards[other_key].state = "available"
SPA.ui.refresh()
check(M.cards[other_key].state == "locked" and not SPA.ui.paint_off, "and at the next refresh")
-- a preset from the build; the pre-allocations follow when plan mode ends
check(SPA.save_preset_as(1, "Plan mode build"), "a preset saved in plan mode")
local pm = SPA.find_preset("wh_main_emp_lord", "Plan mode build")
check(pm and same_list(pm.seq, draft()) and SPA.drafts[1].preset == "Plan mode build" and SPA.plan(1).preset == nil,
	"the preset is the build; the character's own link waits for plan mode to end")
SPA.ui.refresh()
check(plain(btn:Find("button_txt").text) == "Plan mode build", "the dropdown shows the build's preset")
local built = copy(draft())
M.click(icon("plan"))
check(not SPA.in_plan_mode(1) and SPA.ui.plan_cqi == nil and same_list(keys(), built) and SPA.plan(1).preset == "Plan mode build",
	"plan mode off: the build is the pre-allocations, linked to its preset (" .. #keys() .. ")")
check(icon("plan").state == "active" and shields() == 0, "the plan mode button is off again, the shields are hidden")
do
	local pip_free = true
	for _, card in pairs(M.cards) do
		if M.hit_pip(card, 1) ~= card:Find("level_parent"):Find("level1") then pip_free = false end
	end
	check(pip_free, "the mouse over a pip finds the game's pip again")
end
local back, whyr = looks_match(real, other_key)
check(back and string.match(look(other_key), "^available ") ~= nil, "the cards wear their own looks again (the redrawn one its newest) " .. tostring(whyr))
check(SPA.spendable_now(1) == 14 and works(icon("spend")), "the 14 free points can be allocated now (" .. SPA.spendable_now(1) .. ")")
menu("spa_act_spend")
check(M.points == 0 and #keys() == 5, "Allocate now learns the first 14 (" .. #keys() .. " left)")

-- halfway through: plan mode starts empty all the same, every card as at rank 1 (the learned ones too)
local _, learned_now = R.spent_levels(SPA.tree(1))
M.click(icon("plan"))
check(learned_now == 14 and #draft() == 0, "plan mode on a character halfway: an empty build (" .. #draft() .. ")")
check(rank1_everywhere(), "the skills it learned show the rank 1 look too")
-- leaving with nothing planned changes nothing; nor does a build planned and then cleared
M.click(icon("plan"))
check(not SPA.in_plan_mode(1) and #keys() == 5 and SPA.plan(1).preset == "Plan mode build", "plan mode off with nothing planned: the pre-allocations as they were")
M.click(icon("plan"))
plan_mode_click(3)
M.click(icon("clear"))
check(find("spa_confirm", "DY_text").text == SPA.text.get("ask_clear_plan"), "Clear asks first (plan mode's question)")
confirm_tick()
check(#draft() == 0 and SPA.drafts[1].preset == nil, "the build cleared")
M.click(icon("plan"))
check(#keys() == 5 and SPA.plan(1).preset == "Plan mode build", "a build cleared before leaving changes nothing either")
-- a different build: closing the panel leaves plan mode, and the build becomes the pre-allocations
-- where the learned points don't already cover it
M.click(icon("plan"))
plan_mode_click(10, true)
local other = copy(draft())
check(#other == 10 and not same_list(other, { unpack(built, 1, 10) }), "a different build planned (" .. #other .. ")")
close_panel()
check(not SPA.in_plan_mode(1) and SPA.ui.plan_cqi == nil, "closing the panel leaves plan mode")
local expect = R.replay(SPA.tree(1), other, { full_build = true })
check(same_list(keys(), expect.plan) and R.plan_fits(SPA.tree(1), keys()), "the different build became the pre-allocations (" .. #keys() .. ")")
open_panel()
-- a preset picked in plan mode is loaded as the build, as saved
M.click(icon("plan"))
SPA.apply_preset(1, "Plan mode build")
check(same_list(draft(), built) and SPA.drafts[1].preset == "Plan mode build", "a preset picked in plan mode becomes the build")
-- showing another character leaves plan mode (the game draws that character's cards)
local ctxp2 = find("character_context_parent")
ctxp2.ctx.CcoCampaignCharacter = "2"
SPA.ui.refresh()
check(not SPA.in_plan_mode(1) and SPA.ui.plan_cqi == nil and shields() == 0, "showing another character leaves plan mode, the shields are hidden")
ctxp2.ctx.CcoCampaignCharacter = "1"
M.draw_cards()
SPA.ui.refresh()

-- a complete tree: nothing left to plan outside plan mode, a new build in plan mode
close_panel()
local fresh = R.build_tree(live)
local full = {}
for _ = 1, R.capacity(fresh) do
	local pick
	for _, k in ipairs(fresh.order) do if fits_now(fresh, full, k) then pick = k break end end
	if not pick then break end
	full[#full + 1] = pick
end
for k, v in pairs(initial_levels) do M.levels[k] = v end
for _, k in ipairs(full) do M.levels[k] = M.levels[k] + 1 end
M.rank, M.points = 50, 0
SPA.plans[1], SPA.history[1] = nil, nil
SPA.forget(1)
open_panel()
check(R.capacity(SPA.tree(1)) == 0 and not SPA.preallocate(1, full[1]), "a complete tree: nothing can be pre-allocated")
check(works(icon("new")), "its build can be saved as a preset")
M.click(icon("plan"))
check(#draft() == 0 and rank1_everywhere(), "plan mode on a complete tree: an empty build, every card as at rank 1")
plan_mode_click(8, true)
check(#draft() == 8 and SPA.save_preset_as(1, "Respec idea"), "a different build planned on a complete tree and saved")
M.click(icon("plan"))
check(#keys() == 0 and SPA.plan(1).preset == "Respec idea", "plan mode off: nothing to pre-allocate on a complete tree, the preset linked")

-- the game's reset of all skills while in plan mode: leaving plans the whole build on the reset tree
M.click(icon("plan"))
SPA.apply_preset(1, "Respec idea")
local respec = copy(draft())
for k, v in pairs(initial_levels) do M.levels[k] = v end
M.points = #full
M.click(find("button_stats_reset_all"))
close_panel()
check(same_list(keys(), respec) and SPA.spendable_now(1) == #respec, "after a reset of all skills, the build is pre-allocated (" .. #keys() .. ")")
open_panel()

-- a card whose shield can't be made (the mod's layout not found): written to the log once; a click that
-- reaches the card plans, and the game's choice from it is undone
M.click(icon("plan"))
M.simulated = {}
local real_warn, warned = SPA.warn, nil
SPA.warn = function(...) warned = table.concat({ ... }, " ") end
M.fail_create = "ui/skill_preallocation/spa_shield"
M.cards[first]:Find("spa_shield"):Destroy()
SPA.ui.refresh()
check(warned ~= nil and string.match(warned, "no shield could be made") ~= nil, "a card without its shield is reported: " .. tostring(warned))
M.click(M.cards[first])
check(#M.pending == 0 and undo_clicks() == 1 and same_list(draft(), { first }), "a click on a card without its shield plans; the game's choice is undone")
-- the game's choice can't be undone: written to the log once; it is learned when the panel closes
M.undo_stuck = true
warned = nil
local second
do
	local t = SPA.rules_tree(1)
	for _, k in ipairs(t.order) do if k ~= first and fits_now(t, draft(), k) then second = k break end end
end
M.cards[second]:Find("spa_shield"):Destroy()
M.click(M.cards[second])
M.tick(300)
SPA.warn = real_warn
M.undo_stuck = false
check(#M.pending == 1 and warned ~= nil and string.match(warned, "could not be undone") ~= nil, "an undo that doesn't work is reported: " .. tostring(warned))
close_panel()
check(M.levels[second] == 1 and count(second) == 0 and R.plan_fits(SPA.tree(1), keys()),
	"the game teaches that choice when the panel closes; the pre-allocations go on from it (" .. #keys() .. ")")
M.fail_create = nil                            -- (the shields can be made again)
open_panel()
-- a click on a bare card that makes no choice (no free point left) leaves a choice made before alone
M.points = 1
SPA.refresh_points(1)
local chosen_before
do
	local t = SPA.tree(1)
	for _, k in ipairs(t.order) do
		if t.skills[k].plannable and R.check(t, R.new_state(t), k, M.rank) then chosen_before = k break end
	end
end
M.click(M.cards[chosen_before])
M.tick(300)
check(#M.pending == 1 and SPA.has_unconfirmed(1), "a choice made with the last free point")
M.click(icon("plan"))
M.simulated = {}
local bare
do
	local t = SPA.rules_tree(1)
	for _, k in ipairs(t.order) do if fits_now(t, draft(), k) then bare = k break end end
end
M.cards[bare]:Find("spa_shield"):Destroy()
M.click(M.cards[bare])
check(#M.pending == 1 and undo_clicks() == 0 and same_list(draft(), { bare }), "a click on a bare card that makes no choice plans and leaves the earlier choice alone")
M.click(icon("plan"))
-- without GetContextObject the shield is given the card's skill with the game's cco; a shield left
-- without it is written to the log once
do
	local function forget_shield_skills() for _, card in pairs(M.cards) do card:Find("spa_shield").ctx = {} end end
	local function catch_warnings()
		local caught, real = {}, SPA.warn
		SPA.warn = function(...) caught[#caught + 1] = table.concat({ ... }, " ") end
		return caught, function() SPA.warn = real end
	end
	local function warned_of(caught, pattern)
		for _, w in ipairs(caught) do if string.match(w, pattern) then return w end end
		return nil
	end
	local game_cco = cco
	forget_shield_skills()
	M.no_context_objects = true
	M.click(icon("plan"))
	local given = M.cards[first]:Find("spa_shield")
	check(given and given.visible and given.ctx.CcoCampaignCharacterSkill == M.cards[first].ctx.CcoCampaignCharacterSkill,
		"with cco the shield is given the card's skill")
	M.click(icon("plan"))
	M.no_context_objects = nil
	-- the script evaluates nothing of the game's but a context's Key (in game, a script's :Call of
	-- Format(Loc(..)) broke the interface, see mock_game.lua)
	check(M.other_calls == nil, "the script evaluates nothing but Key: " .. table.concat(M.other_calls or {}, " / "))
	local caught, restore
	-- neither GetContextObject nor cco: the shield has no skill, reported
	forget_shield_skills()
	M.no_context_objects = true
	cco = nil
	caught, restore = catch_warnings()
	M.click(icon("plan"))
	restore()
	check(warned_of(caught, "has no skill %(") ~= nil, "a shield left without the skill is reported: " .. table.concat(caught, " / "))
	M.click(icon("plan"))
	M.no_context_objects = nil
	cco = game_cco
end

-- the game keeps drawing over the plan look: given up for the session (written to the log); the cards
-- show the game's looks, the shields stay and planning goes on
M.click(icon("plan"))
real_warn, warned = SPA.warn, nil
SPA.warn = function(...) warned = table.concat({ ... }, " ") end
local drawn
for _ = 1, 3 do
	M.draw_cards()                               -- the game redraws every card
	drawn = looks()
	SPA.ui.refresh()
end
SPA.warn = real_warn
check(SPA.ui.paint_off and warned ~= nil and string.match(warned, "keeps redrawing") ~= nil, "the game keeps redrawing the cards: the rank 1 look is given up, and reported")
check(looks_match(drawn) and shields() == #live.skills, "the cards show the game's looks, the shields stay")
local held = #M.pending
plan_mode_click(1)
local left_alone, why_alone = looks_match(drawn)
check(#draft() == 1 and #M.pending == held and left_alone, "planning goes on (no choice made), the looks are left alone " .. tostring(why_alone))
M.click(icon("plan"))
SPA.ui.paint_off = false

-- a skill tree the mod doesn't know: no plan mode
local tr = SPA.tree(1)
tr.known = false
check(SPA.ui.toolbar_state(1).enabled.plan == false, "plan mode needs a skill tree in the mod's data")
tr.known = true

-- a choice made with free points before plan mode stays chosen: plan mode doesn't show it, leaving
-- without a build changes nothing, and the game learns it when the panel closes
close_panel()
for k, v in pairs(initial_levels) do M.levels[k] = v end
M.rank, M.points = 15, 14
SPA.plans[1], SPA.history[1] = nil, nil
SPA.forget(1)
open_panel()
local t8 = SPA.tree(1)
local banked
for _, k in ipairs(t8.order) do
	local s = t8.skills[k]
	local need8 = R.required_rank(s.ranks[1])
	if s.plannable and #s.req == 0 and #s.sub == 0 and need8 >= 6 and need8 <= 15 and R.can_append(t8, {}, k) then banked = k break end
end
check(banked ~= nil, "found a skill that needs rank 6 to 15")
if banked then
	M.click(M.cards[banked])                    -- the game's own choice (free points)
	check(#M.pending == 1, "chosen with a free point")
	M.click(icon("plan"))
	check(#draft() == 0 and #M.pending == 1 and string.match(look(banked), "^locked ") ~= nil, "plan mode: the choice isn't shown, and stays")
	M.click(icon("plan"))
	check(#keys() == 0 and #M.pending == 1, "leaving with nothing planned changes nothing")
	close_panel()
	check(M.levels[banked] == 1, "the game learns the choice when the panel closes")
	open_panel()
end

-- back to the character as it was for the rest of the tests
close_panel()
for k, v in pairs(saved_levels) do M.levels[k] = v end
M.rank, M.points = saved_rank, saved_points
SPA.plans[1], SPA.history[1] = nil, nil
SPA.forget(1)
open_panel()

---------------------------------------------------------------- presets file, log
SPA.preset_list("wh_main_emp_nobody")            -- looked at, nothing saved for it
SPA.save_presets()
local pf = io.open("skill_preallocation_presets.lua")
local preset_text = pf and pf:read("*a") or ""
if pf then pf:close() end
check(string.match(preset_text, "wh_main_emp_lord") ~= nil, "presets file written")
check(string.match(preset_text, "wh_main_emp_nobody") == nil, "no empty preset lists in the presets file")

local LOG = "skill_preallocation_log.txt"
-- the log as it is on disk (`flush`: after writing the debug lines still waiting for their batch)
local function log_text(flush)
	if flush then SPA.flush_log() end
	local lf = io.open(LOG)
	local t = lf and lf:read("*a") or ""
	if lf then lf:close() end
	return t
end
local text = log_text(true)
check(string.match(text, "^==== Skill Pre%-Allocation " .. (string.gsub(SPA.VERSION, "%.", "%%.")) .. " | data [^|]+ | native loaded 1%.1%.0 | ") ~= nil,
	"the log starts with the session's header (with the data and the native module)")
check(string.match(text, "live skill data live test") ~= nil and string.match(text, "ready; skill data live: live test") ~= nil
	and M.live_loads == 1, "the live data is read once, when the mod gets ready, and used")
check(string.match(text, "click card < ") ~= nil, "debug on: clicks are logged with their path")
check(string.match(text, "on the badge=1") ~= nil, "debug on: clicks on a badge are logged")
check(string.match(text, "ERROR") == nil and string.match(text, "WARNING") == nil, "no script errors or warnings in the log")
check(SPA.ui.panel_checked and string.match(text, "skills panel check: ok") ~= nil, "the skills panel was checked once: ok")
-- debug off (as shipped): playing writes nothing
SPA.debug = false
M.points = 0
SPA.refresh_points(1)
plan_greedy(2)
click_badge(keys()[1])
M.level_up(2)
M.drain()
M.close_panel()
M.tick(3000)
open_panel()
check(log_text() == text, "debug off: nothing written to the log")

-- an error: written at once, with the events before it (until then kept in memory only)
SPA.log("marker event before the error")
check(log_text() == text, "debug off: events are kept in memory only")
SPA.error("test error one")
local after = log_text()
local added = string.sub(after, #text + 1)
check(string.match(added, "^%[[^%]]+%] Skill Pre%-Allocation " .. (string.gsub(SPA.VERSION, "%.", "%%.")) .. " ERROR: test error one\n") ~= nil, "the error is written straight away")
check(string.match(added, "what happened before it %(oldest first%):") ~= nil and string.match(added, "    %[[^%]]+%] marker event before the error") ~= nil
	and string.match(added, "    %[[^%]]+%] click on ") ~= nil, "with the events before it")
-- the same error again: not written again, a note at the 10th time
for _ = 2, 9 do SPA.error("test error one") end
check(log_text() == after, "the same error isn't written again")
SPA.error("test error one")
check(string.match(log_text(), "%(the same error 10 times so far%)") ~= nil, "a note the 10th time")
-- a second error only brings the events since the first one
SPA.log("marker event between errors")
SPA.error("test error two")
local added2 = string.sub(log_text(), #after + 1)
check(string.match(added2, "marker event between errors") ~= nil and string.match(added2, "marker event before the error") == nil,
	"a later error brings only the events since the last one written")
-- a failing call: written, with a stack trace when the Lua has one; results and nils pass through safe
SPA.safe("test boom", function() error("boom") end)
local t_boom = log_text()
check(string.match(t_boom, "ERROR: in test boom: [^\n]*boom") ~= nil, "a failing call is written")
if debug and debug.traceback then check(string.match(t_boom, "stack traceback:") ~= nil, "with a stack trace") end
local r1, r2, r3 = SPA.safe("pass through", function(x, y, z) return x, y, z end, 1, nil, 3)
check(r1 == 1 and r2 == nil and r3 == 3, "safe passes arguments and results through, nils included")

-- warnings: a panel that isn't as expected, a skill tree not in the data (once each)
local ctxp = find("character_context_parent")
local ctx_saved = ctxp.ctx.CcoCampaignCharacter
ctxp.ctx.CcoCampaignCharacter = nil
SPA.ui.panel_checked = false
SPA.ui.check_panel()
ctxp.ctx.CcoCampaignCharacter = ctx_saved
check(string.match(log_text(), "WARNING: the skills panel isn't as the mod expects [^\n]*character_context_parent") ~= nil,
	"a panel the mod can't read is written as a warning")
SPA.tree_cache[906] = { known = false, subtype = "some_modded_lord", agent = "general", order = { "a", "b" } }
SPA.ui.check_tree(906)
SPA.ui.check_tree(906)
local _, n_tree = string.gsub(log_text(), "WARNING: skill tree not in the mod's data[^\n]*some_modded_lord", "")
check(n_tree == 1, "a skill tree not in the data is written once (" .. n_tree .. ")")
SPA.tree_cache[906] = nil
-- at most 10 warnings a session (2 written above)
for i = 1, 9 do SPA.warn("test warning " .. i) end
local t_warn = log_text()
check(string.match(t_warn, "test warning 8") ~= nil and string.match(t_warn, "test warning 9") == nil
	and string.match(t_warn, "no more warnings are written this session") ~= nil, "at most 10 warnings a session")

-- debug mode: lines are written in batches, a moment after the first one
SPA.debug = true
local t_before = log_text()
SPA.log("batched line 1")
SPA.log("batched line 2")
check(log_text() == t_before, "debug on: lines wait for their batch")
M.tick(1100)
local t_batch = log_text()
check(string.match(t_batch, "batched line 1\n[^\n]*batched line 2\n$") ~= nil, "debug on: written together a moment later")
SPA.log("batched line 3")
SPA.error("test error three")
check(string.match(log_text(), "batched line 3\n[^\n]*ERROR: test error three\n$") ~= nil, "debug on: an error writes the lines waiting first, in order")
SPA.debug = false
-- debug mode from a file in the game folder
os.remove("skill_preallocation_debug.txt")
check(SPA.read_debug_flag() == false, "no debug file: debug off")
local df = io.open("skill_preallocation_debug.txt", "w")
df:close()
check(SPA.read_debug_flag() == true, "a skill_preallocation_debug.txt in the game folder turns debug on")
os.remove("skill_preallocation_debug.txt")
-- a new session with a log over 1 MB starts it over
local big = io.open(LOG, "a")
big:write(string.rep("x", 1000001))
big:close()
SPA.log_session_open = false
SPA.error("test error in a new session")
local t_new = log_text()
check(#t_new < 100000 and string.match(t_new, "^==== Skill Pre%-Allocation") ~= nil and string.match(t_new, "test error in a new session") ~= nil,
	"a new session with a big log starts it over (" .. #t_new .. " bytes)")

print(string.format("%d passed, %d failed", passed, failed))
if failed > 0 then os.exit(1) end
