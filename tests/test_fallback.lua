-- The mod without its native module (another platform, the DLL blocked): the baked data is used, a
-- click on a skill's badge removes its last point as always, plan mode works as usual. With the game's UI
-- scaled (M.scale = 1.5), the shields still lie exactly over the cards and their pips, and the badges'
-- boxes scale too. A plan made with the live data keeps its points on skills another mod adds (the baked
-- data doesn't know them): nothing re-checks it, spending stops at them, removing a point leaves the rest.
-- Run from tests/run:  lua5.1 ../test_fallback.lua
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
M.scale = 1.5
M.build_ui()
M.install()
dofile(MOD .. "skill_preallocation.lua")
dofile(MOD .. "skill_preallocation_live.lua")
dofile(MOD .. "skill_preallocation_text.lua")
dofile(MOD .. "skill_preallocation_ui.lua")
local SPA = SKILL_PREALLOCATION

local passed, failed = 0, 0
local function check(c, msg)
	if c then passed = passed + 1 else failed = failed + 1 print("FAIL: " .. msg) end
end
local function keys() return SPA.plan(1).keys end
local function count(key) local n = 0 for _, k in ipairs(keys()) do if k == key then n = n + 1 end end return n end
local function find(...) return M.find_uicomponent(M.root, ...) end
local function open_panel() M.fire("PanelOpenedCampaign", { string = "character_details_panel" }); M.drain() end

for _, fn in ipairs(M.first_tick) do fn() end
M.drain()

-- no native module here (the tests don't run on Windows): the baked data, and a warning in the log
check(SKILL_PREALLOCATION_LIVE.native == nil and string.match(SKILL_PREALLOCATION_LIVE.native_problem or "", "^not Windows") ~= nil,
	"no native module: " .. tostring(SKILL_PREALLOCATION_LIVE.native_problem))
check(R.source == nil and string.match(SPA.live_state, "^baked: ") ~= nil, "the baked data is used: " .. SPA.live_state)
local lf = io.open("skill_preallocation_log.txt")
local text = lf and lf:read("*a") or ""
if lf then lf:close() end
check(string.match(text, "WARNING: live skill data off %(not Windows") ~= nil
	and string.find(text, "points already planned on their skills are kept, and wait for the live data", 1, true) ~= nil,
	"the log says why the live data is off, and that planned points on other mods' skills are kept")
check(string.find(text, "native module off: not Windows", 1, true) ~= nil, "and how the native module fared")

-- pre-allocate three points (no free points: the clicks plan)
open_panel()
local t = SPA.tree(1)
local planned = {}
for _, k in ipairs(t.order) do
	if #planned < 3 and R.can_append(t, keys(), k) then
		M.click(M.cards[k])
		if count(k) > 0 and not planned[k] then planned[#planned + 1] = k; planned[k] = true end
	end
end
check(#keys() >= 3, "points pre-allocated by clicks (" .. #keys() .. ")")
local last = keys()[#keys()]
local b = M.cards[last]:Find("spa_badge")
check(b and b.visible and b.interactive == true and string.find(b.tooltip or "", SPA.text.get("badge_tip_click"), 1, true) ~= nil,
	"a planned skill's badge takes clicks, and its tooltip says so")
check(b and b.w == (string.len(string.gsub(b.text, "%[%[.-%]%]", "")) * 8 + 8) * 1.5 and b.h == 16 * 1.5,
	"its box is as wide as its numbers, at UI scale 1.5 too (" .. tostring(b and b.w) .. ")")
-- a click on the badge removes the skill's last point
local before = count(last)
M.click(b)
check(count(last) == before - 1, "a click on the badge removes its last point (" .. before .. " -> " .. count(last) .. ")")

-- plan mode: the shields lie over the cards and their pips (UI scale 1.5); the badges lie above the shields
M.click(find("spa_btn_plan"))
check(SPA.in_plan_mode(1), "plan mode on")
check(math.abs((SPA.ui.scale or 0) - 1.5) < 0.001, "the UI scale is read from the presets dropdown: " .. tostring(SPA.ui.scale))
local covered, pips_covered, pips = true, true, 0
for _, card in pairs(M.cards) do
	local sh = card:Find("spa_shield")
	if not (sh and sh.visible and M.covers(sh, card)) then covered = false end
	local lp = card:Find("level_parent")
	for i = 1, 3 do
		local pip, ps = lp:Find("level" .. i), sh and sh:Find("spa_pip_shield" .. i)
		if pip.visible then
			pips = pips + 1
			if not (ps and ps.visible and M.covers(ps, pip)) then pips_covered = false end
		end
	end
end
check(covered, "every shield lies over its card at UI scale 1.5")
check(pips_covered and pips > 0, "every shown pip has its shield over it at UI scale 1.5 (" .. pips .. ")")
local tt = SPA.rules_tree(1)
local pick
for _, k in ipairs(tt.order) do if R.can_append(tt, SPA.working(1).keys, k) then pick = k break end end
M.click(M.cards[pick])
check(#SPA.working(1).keys == 1 and SPA.working(1).keys[1] == pick, "a click on a shield plans the build (" .. #SPA.working(1).keys .. ", pre-allocations " .. #keys() .. ", " .. count(pick) .. ")")
SPA.ui.refresh()
local pb = M.cards[pick]:Find("spa_badge")
check(pb and pb.interactive == true and pb.priority > M.cards[pick]:Find("spa_shield").priority, "in plan mode the badges lie above the shields")
M.click(pb)
check(#SPA.working(1).keys == 0, "a click on the badge removes the point from the build")
M.click(find("spa_btn_plan"))
check(not SPA.in_plan_mode(1), "plan mode off (an empty build: the pre-allocations stay)")

---------------------------------------------------------------- a plan made with the live data
-- Another mod adds two skills to this lord's tree: the game shows them, the baked data doesn't know them.
local MOD_A, MOD_B, GONE = "spa_test_mod_skill_a", "spa_test_mod_skill_b", "spa_test_gone_skill"
for i, key in ipairs({ MOD_A, MOD_B }) do
	M.live.skills[#M.live.skills + 1] = { key = key, list_index = #M.live.skills, level = 0, total = 1, tier = i, indent = 6,
		ranks = { 0 }, background = false }
	M.levels[key] = 0
end
M.close_panel()
M.tick(3000)
SPA.clear_plan(1)
local tree = SPA.tree(1, true)
check(tree.known and tree.keep_unknown == true and tree.unknown == 2 and R.kept(tree, MOD_A) and not R.kept(tree, GONE)
	and not R.kept(tree, planned[1]), "the other mod's skills: on the tree, unknown to the baked data, kept (" .. tostring(tree.unknown) .. ")")
-- three of the lord's own skills that fit one after another, with the other mod's skill between the first two
local own = {}
for _, k in ipairs(tree.order) do
	local plan = {}
	for i, o in ipairs(own) do plan[i] = o end
	if #plan >= 1 then table.insert(plan, 2, MOD_A) end
	if #own < 3 and tree.skills[k].plannable and R.can_append(tree, plan, k) then own[#own + 1] = k end
end
check(#own == 3, "three of the lord's own skills that fit (" .. #own .. ")")
local function same(a, b2)
	if #a ~= #b2 then return false end
	for i = 1, #a do if a[i] ~= b2[i] then return false end end
	return true
end
-- as loaded from a save made with the live data
SPA.set_plan(1, { own[1], MOD_A, own[2], own[3] })
SPA.reread(1)
check(same(keys(), { own[1], MOD_A, own[2], own[3] }), "re-checked without the live data: the plan stays as it is")
-- removing a point leaves the rest as it is
open_panel()
M.click(M.cards[own[3]]:Find("spa_badge"))
check(same(keys(), { own[1], MOD_A, own[2] }), "a click on a badge removes that point only (" .. table.concat(keys(), ", ") .. ")")
-- with two free points: "Allocate now" counts only the point before the other mod's skill; its badge is
-- green, the point after it waits (yellow)
M.points = 2
SPA.refresh_points(1)
SPA.ui.refresh()
check(SPA.spendable_now(1) == 1, "one point can be spent now, the one before the other mod's skill (" .. SPA.spendable_now(1) .. ")")
local b1, b2 = M.cards[own[1]]:Find("spa_badge"), M.cards[own[2]]:Find("spa_badge")
check(b1 and string.find(b1.text, "[[col:green]]1[[/col]]", 1, true) and b2 and string.find(b2.text, "col:yellow", 1, true),
	"its badge shows 1 in green, the waiting point's rank is yellow (" .. tostring(b1 and b1.text) .. " / " .. tostring(b2 and b2.text) .. ")")
M.close_panel()
M.tick(3000)
SPA.try_spend(1)
M.drain()
check(M.levels[own[1]] == 1 and M.points == 1 and same(keys(), { MOD_A, own[2] }),
	"spending learns the first point and stops at the other mod's skill (points " .. M.points .. ", plan " .. table.concat(keys(), ", ") .. ")")
-- a point spent by hand on a skill planned later: only that point leaves the plan
M.add_skill(M.char, own[2], false, false)
M.drain()
check(M.levels[own[2]] == 1 and same(keys(), { MOD_A }), "a point learned by hand leaves the plan; the other mod's point stays")
-- a skill that is gone from the tree (its mod removed) is still dropped when the plan holds nothing kept
SPA.set_plan(1, { own[3], GONE })
SPA.reread(1)
check(same(keys(), { own[3] }), "a skill no longer on the tree is dropped (" .. table.concat(keys(), ", ") .. ")")

print(passed .. " passed, " .. failed .. " failed")
if failed > 0 then os.exit(1) end
