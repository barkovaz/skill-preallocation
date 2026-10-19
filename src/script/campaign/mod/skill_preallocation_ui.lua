-- Skill Pre-Allocation: skills panel integration.
--  * left-click a skill while the character has no free points -> pre-allocate its next point
--    (with free points the click is the game's own, normal allocation)
--  * pre-allocated skills show the rank(s) at which they will be learned (points are learned in plan
--    order, each as soon as it comes); points the character's free points already cover show their place
--    in that order in green instead, 1, 2, 3... (they are learned by "Allocate N points now")
--  * left-click those numbers (the skill's badge) -> remove its last pre-allocated point, with or without
--    free points, in and out of plan mode (learned points are never touched; right-click stays the
--    game's own, e.g. it opens the spell book)
--  * plan mode (a toggle): a neutral planning view. The tree looks like the character type's tree at rank
--    1 with nothing learned (planned skills stay greyed out too: the badges show the plan), every left
--    click plans (even with free points: a transparent shield over each card takes the clicks, so the
--    game's card doesn't react; its tooltip is neutral, the skill's first level effects from its database
--    record and the rank it asks for, and there is no stats preview), and the whole build is
--    planned from rank 1 (see "plan mode" in skill_preallocation.lua); its badges show the rank each
--    point comes at from rank 1, and sit above the shields. Leaving plan mode (the toggle, closing the
--    panel, another character) turns a build planned there into the pre-allocations.
--  * one row at the top right of the skill tree: the presets dropdown (shows the selected preset; its
--    list loads one of this character type's presets) and seven round icon buttons: plan mode, save as
--    new preset, overwrite / rename / delete the selected preset, clear the pre-allocations, allocate
--    now (spends free points on the pre-allocations; otherwise they are spent at the next rank-up). A
--    button only works when it makes sense; overwrite, delete, clear and allocate now ask first.
--  * every text comes from skill_preallocation_text.lua, in the game's language
--  * no game file is replaced: what the mod adds to the panel (badges, shields, the presets row) is made
--    by this script on the panel the game (or a UI mod) builds, found by the game's own component names

SKILL_PREALLOCATION = SKILL_PREALLOCATION or {}
local SPA = SKILL_PREALLOCATION
local UI = {}
SPA.ui = UI

local T_CHAR = "CcoCampaignCharacter"
local PANEL = "character_details_panel"
local BADGE = "spa_badge"
local BUTTON = "spa_presets"           -- the presets dropdown
local MENU = "spa_menu"                -- its list
local ICON_PREFIX = "spa_btn_"
local POPUP = "spa_popup"
local CONFIRM = "spa_confirm"
local CARD_PRIORITY = 20               -- the skill cards' priority in the game's layout
-- What the mod puts on a skill card sits just above it: plan mode's shield (the card's priority + 1),
-- the shield's pips' shields (+ 2) and the badge (+ 3: it takes its clicks in plan mode too).
local BADGE_LIFT = 3
-- Sizes the game scales with its UI scale. 34 is the height of the button art: a taller button repeats
-- the top of its art underneath (a stray strip below the button). 38 is the round buttons' size.
local DD_W, DD_H = 320, 34             -- the dropdown
local ITEM_W, ITEM_H = 320, 34         -- its list rows
local ICON, ICON_GAP = 38, 4           -- the round icon buttons
local DD_GAP = 10                      -- between the dropdown and the icons
local PAD = 24                         -- between the row and the right edge of the skill tree
local ICON_IDS = { "plan", "new", "overwrite", "rename", "delete", "clear", "spend" }
local ICON_ART = {
	plan = "ui/skins/default/icon_edit.png",
	new = "ui/skins/default/icon_add.png",
	overwrite = "ui/skins/default/icon_save_char.png",
	rename = "ui/skins/default/icon_rename.png",
	delete = "ui/skins/default/icon_delete.png",
	clear = "ui/skins/default/icon_cross.png",
	spend = "ui/skins/default/icon_check.png",
}
-- the plan mode button is an on/off button (the game's toggle template: "selected" states when on)
local ICON_TEMPLATE = { plan = "ui/templates/round_small_button_toggle.twui.xml" }
local ROUND_BUTTON = "ui/templates/round_small_button.twui.xml"
local UNDO_BUTTON = "button_stats_reset"   -- the panel's own "Undo assigned skill points"
local ROW_W = DD_W + DD_GAP + #ICON_IDS * ICON + (#ICON_IDS - 1) * ICON_GAP
-- every component of the row, by name
local TOOLBAR = { BUTTON }
for _, id in ipairs(ICON_IDS) do TOOLBAR[#TOOLBAR + 1] = ICON_PREFIX .. id end
-- The dropdown's images for the text button's slots (pressed, active, hover, inactive, underlay): the
-- game's dropdown art with its arrow box moved 2 units right (made by generator/build_dropdown_art.py),
-- so the box lies entirely in the 26-unit right margin the template doesn't tile (the game's own art
-- showed a thin line in the middle of the wide dropdown).
local DROPDOWN_ART = {
	"ui/skins/default/spa_dropdown_pressed.png",
	"ui/skins/default/spa_dropdown_active.png",
	"ui/skins/default/spa_dropdown_hover.png",
	"ui/skins/default/spa_dropdown_inactive.png",
	"ui/skins/default/spa_dropdown_underlay.png",
}
local POPUP_PRIORITY = 1000

local function R() return SKILL_PREALLOCATION_RULES end
local function log(...) SPA.log(...) end
local function safe(label, fn, ...) return SPA.safe(label, fn, ...) end
local function T(...) return SPA.text.get(...) end

-- A name cut to n characters for a label (the game's string.len / string.sub count UTF-8 characters).
local function short(name, n)
	name = tostring(name or "")
	if string.len(name) <= n then return name end
	return string.sub(name, 1, n - 1) .. "..."
end

UI.panel_open = false
UI.popup_open = false
UI.confirm_open = false
UI.shown_cqi = nil             -- character shown in the panel, if it is the player's
UI.shown_panel_cqi = nil       -- character shown in the panel, whoever owns it
UI.priority = nil              -- priority given to the mod's button and menu
UI.reset_clicked = {}          -- the player's characters whose skill reset button was clicked
UI.plan_cqi = nil              -- the character in plan mode, if any (only while the panel is open)
UI.view_on = false             -- plan mode's view is on the cards (shields made, looks painted)

---------------------------------------------------------------- component helpers
local function root() return core:get_ui_root() end

local function find(...)
	local ok, c = pcall(find_uicomponent, root(), ...)
	if ok then return c end
	return nil
end

local function child(uic, id)
	if not uic then return nil end
	local ok, addr = pcall(function() return uic:Find(id) end)
	if ok and addr then return UIComponent(addr) end
	return nil
end

local function parent(uic)
	local ok, p = pcall(function() return uic:Parent() end)
	if ok and p then return UIComponent(p) end
	return nil
end

local function id_of(uic)
	local ok, id = pcall(function() return uic:Id() end)
	return ok and id or nil
end

local function priority_of(uic)
	if not uic then return nil end
	local ok, p = pcall(function() return uic:Priority() end)
	if ok and type(p) == "number" then return p end
	return nil
end

local function visible(uic)
	if not uic then return false end
	local ok, v = pcall(function() return uic:Visible(true) end)
	return ok and v
end

local function walk(uic, fn, depth)
	if not uic or depth <= 0 then return end
	local n = uic:ChildCount()
	for i = 0, n - 1 do
		local c = UIComponent(uic:Find(i))
		if fn(c) ~= false then walk(c, fn, depth - 1) end
	end
end

-- "id < parent < grandparent ..." for the log
local function path_of(uic, depth)
	local parts = {}
	local cur = uic
	for _ = 1, depth or 6 do
		if not cur then break end
		local id = id_of(cur)
		if not id then break end
		parts[#parts + 1] = id
		if id == PANEL or id == "root" then break end
		cur = parent(cur)
	end
	return table.concat(parts, " < ")
end

local function descends_from(uic, ancestor_id)
	local cur = uic
	for _ = 1, 12 do
		if not cur then return false end
		if id_of(cur) == ancestor_id then return true end
		cur = parent(cur)
	end
	return false
end

-- The clicked component or one of its first parents whose id matches `pattern` (a click can land
-- on a button's text instead of the button itself).
local function own_ancestor(uic, pattern, depth)
	local cur = uic
	for _ = 1, depth or 3 do
		if not cur then return nil end
		local id = id_of(cur)
		if id and string.match(id, pattern) then return id end    -- (the game's string.find is plain text only)
		cur = parent(cur)
	end
	return nil
end

local function card_ancestor(uic)
	local cur = uic
	for _ = 1, 5 do
		if not cur then return nil end
		local id = id_of(cur)
		if id == "card" then return cur end
		if id == PANEL or id == "listview" then return nil end
		cur = parent(cur)
	end
	return nil
end

local function set_text(uic, text)
	if not uic then return end
	pcall(function() uic:SetText(text, "") end)
end

-- text buttons show their text in their "button_txt" child
local function set_button_text(btn, text)
	set_text(child(btn, "button_txt"), text)
end

local function set_tooltip(uic, text)
	if not uic then return end
	pcall(function() uic:SetTooltipText(text, "", true) end)
end

local function destroy(uic)
	if uic then pcall(function() uic:Destroy() end) end
end

---------------------------------------------------------------- panel state
function UI.panel() return find(PANEL) end

function UI.panel_cqi()
	local ctx_parent = find(PANEL, "character_context_parent")
	if not ctx_parent then return nil end
	local ok, id = pcall(function() return ctx_parent:GetContextObjectId(T_CHAR) end)
	return ok and id and tonumber(id) or nil
end

function UI.skills_subpanel() return find(PANEL, "skills_subpanel") end

function UI.skills_visible() return visible(UI.skills_subpanel()) end

-- every skill card shown in the tree: { card = uic, key = skill key }. The cards are the components named
-- "card" under the skills panel's list (all of the panel without one); a card's skill is its parent's
-- name (the game names a card's slot after its skill), or else the skill of its context object (a UI
-- mod that names things differently). Skills the shown character doesn't have are left out.
local function card_skill(c, known)
	local p = parent(c)
	local key = p and id_of(p)
	if key and (not known or known[key]) then return key end
	local ok, k = pcall(function()
		local o = c:GetContextObject("CcoCampaignCharacterSkill")
		return o and o:Call("Key")
	end)
	if ok and type(k) == "string" and k ~= "" and (not known or known[k]) then return k end
	return (not known) and key or nil
end

function UI.cards()
	local out = {}
	local sub = UI.skills_subpanel()
	if not sub then return out end
	local ok, lv = pcall(find_uicomponent, sub, "listview")
	local tree = UI.shown_cqi and SPA.tree_cache[UI.shown_cqi]
	local known = tree and tree.skills
	walk((ok and lv) or sub, function(c)
		if id_of(c) == "card" then
			local key = card_skill(c, known)
			if key then out[#out + 1] = { card = c, key = key } end
			return false
		end
	end, 14)
	return out
end

-- messages only go to the log (the game's own tooltips show rank and prerequisite requirements)
function UI.say(text)
	if text and text ~= "" then log("message:", text) end
end

---------------------------------------------------------------- badges on skill cards
-- A badge is a copy of the card's name text (its font and outline), docked at the card's bottom centre.
-- A left click on it removes the skill's last pre-allocated point (UI.remove_point), so it takes clicks,
-- above the card and above plan mode's shields (BADGE_LIFT). Its box is as wide as its numbers, so a
-- click elsewhere along the card's bottom edge stays a click on the card. The game's layout centres the
-- text in the box and shrinks it (rather than wrapping it) when it doesn't fit the box it is set in, and
-- keeps that size: so the box is sized first, then the text set. The width is reckoned generously:
-- BADGE_CHAR a character (the font is 12 high, its digits and spaces narrower than that), BADGE_PAD each
-- side, at most the BADGE_W it was made with. The sizes are the layout's units, which the text scales with
-- too (the game's UI scale).
local BADGE_W, BADGE_H, BADGE_CHAR, BADGE_PAD = 120, 16, 8, 4

local function badge_width(text)
	local shown = string.gsub(text or "", "%[%[.-%]%]", "")
	return math.min(BADGE_W, string.len(shown) * BADGE_CHAR + 2 * BADGE_PAD)
end

local function make_badge(card)
	local dy = child(card, "dy_skill")
	if not dy then return nil end
	local ok, addr = pcall(function() return dy:CopyComponent(BADGE) end)
	if not ok or not addr then log("badge copy failed", addr) return nil end
	local b = UIComponent(addr)
	pcall(function()
		b:SetCanResizeWidth(true)
		b:SetCanResizeHeight(true)
	end)
	return b
end

-- Keep the badge taking clicks above the card's other parts and above plan mode's shield: its priority,
-- then, unless it is the card's last part already, the card adopts it again, which places it among the
-- card's parts by that priority (a new priority alone doesn't move a component among its siblings; the
-- game's own scripts adopt a component again after PropagatePriority the same way). Docked again after
-- (bottom centre of the card), so it stays centred.
local function last_part(card)
	local okn, n = pcall(function() return card:ChildCount() end)
	if not okn or type(n) ~= "number" or n < 1 then return nil end
	local ok, addr = pcall(function() return card:Find(n - 1) end)
	if ok and addr then return UIComponent(addr) end
	return nil
end

local function lift_badge(b, card)
	pcall(function() b:PropagatePriority((priority_of(card) or CARD_PRIORITY) + BADGE_LIFT) end)
	if id_of(last_part(card)) ~= BADGE then pcall(function() card:Adopt(b:Address()) end) end
	pcall(function()
		b:SetDockingPoint(8)
		b:SetDockOffset(0, -1)
	end)
	pcall(function() b:SetInteractive(true) end)
end

-- Size the badge to `text`, then set the text (so it fits the box it is set in), and lift it.
local function fit_badge(b, card, text)
	pcall(function() b:Resize(badge_width(text), BADGE_H) end)
	set_text(b, text)
	lift_badge(b, card)
end

-- "7 12 15": the rank each planned point of the skill is learned at, in yellow. A point the free points
-- cover now shows its place in the plan instead, in green ("1", "2", ...: the order "Allocate now" learns
-- them in). In plan mode there is no "now" (a build from rank 1): every rank is yellow. Nor is there for
-- a point that waits behind one kept without the live data (see R.kept): it can't be learned yet.
-- `points` = { { rank = r or "?", place = i, waits = true or false }, ... }
local function badge_text(points, now)
	local parts = {}
	for _, p in ipairs(points) do
		local reached = not p.waits and type(p.rank) == "number" and now ~= nil and p.rank <= now
		parts[#parts + 1] = reached and ("[[col:green]]" .. p.place .. "[[/col]]") or ("[[col:yellow]]" .. tostring(p.rank) .. "[[/col]]")
	end
	return table.concat(parts, " ")
end

function UI.update_badges(cqi)
	local cards = UI.cards()
	local by_key = {}
	local real = cqi and SPA.tree(cqi)
	local now = real and not SPA.in_plan_mode(cqi) and real.rank or nil
	local tree = real and SPA.rules_tree(cqi)       -- (from scratch in plan mode)
	if tree then
		local plan = SPA.working(cqi)
		local ranks = R().plan_ranks(tree, plan.keys)
		local waits = false
		for i, k in ipairs(plan.keys) do
			if R().kept(tree, k) then waits = true end
			by_key[k] = by_key[k] or {}
			table.insert(by_key[k], { rank = ranks[i] or "?", place = i, waits = waits })
		end
	end
	local made = 0
	for _, e in ipairs(cards) do
		local b = child(e.card, BADGE)
		local rs = by_key[e.key]
		if rs then
			if not b then
				b = make_badge(e.card)
				if b then made = made + 1 end
			end
			if b then
				local parts = {}
				for _, p in ipairs(rs) do parts[#parts + 1] = tostring(p.rank) end
				set_tooltip(b, T("badge_tip", table.concat(parts, ", ")) .. "\n" .. T("badge_tip_click"))
				fit_badge(b, e.card, badge_text(rs, now))
				pcall(function() b:SetVisible(true) end)
			end
		elseif b then
			pcall(function() b:SetVisible(false) end)
		end
	end
	if made > 0 then log("badges: made", made, "cards", #cards) end
	return #cards
end

---------------------------------------------------------------- the presets dropdown and the icon buttons
-- Components made by a script start with a low priority and then get no clicks in this panel, so
-- they are lifted just above the panel's own components (the mod's own ones don't count).
local function panel_priority()
	local best = priority_of(UI.panel()) or 0
	local skip = { listview = true, stats_effects_holder = true, char_select_list = true }
	local function visit(uic, depth)
		if not uic or depth <= 0 then return end
		local okn, n = pcall(function() return uic:ChildCount() end)
		if not okn or type(n) ~= "number" then return end
		for i = 0, n - 1 do
			local okc, c = pcall(function() return UIComponent(uic:Find(i)) end)
			if okc and c then
				local id = id_of(c)
				if id and not skip[id] and string.sub(id, 1, 4) ~= "spa_" then
					local p = priority_of(c)
					if p and p > best and p < 900 then best = p end
					visit(c, depth - 1)
				end
			end
		end
	end
	visit(UI.panel(), 5)
	return best
end

-- (and above what the mod puts on the skill cards, which sits just above the cards: the presets list
-- opens over the tree)
local function lift(uic)
	UI.priority = UI.priority or (math.max(panel_priority(), CARD_PRIORITY + BADGE_LIFT) + 1)
	pcall(function() uic:PropagatePriority(UI.priority) end)
end

-- A text button; `text_w` = the width its text may take (default: almost all of it).
local function make_button(parent_uic, name, label, w, h, text_w)
	local existing = child(parent_uic, name)
	if existing then return existing end
	local ok, addr = pcall(function() return parent_uic:CreateComponent(name, "ui/templates/square_medium_text_button.twui.xml") end)
	if not ok or not addr then SPA.error("could not create button " .. name .. ": " .. tostring(addr)) return nil end
	local b = UIComponent(addr)
	pcall(function()
		b:SetCanResizeWidth(true)
		b:SetCanResizeHeight(true)
		b:Resize(w, h)
		local t = child(b, "button_txt")
		if t then
			t:SetCanResizeWidth(true)
			t:SetCanResizeHeight(true)
			t:Resize(text_w or (w - 12), h - 4)
		end
	end)
	set_button_text(b, label)
	return b
end

-- A round button (the size and look of the skill points counter's reset buttons) showing `icon`.
local function make_icon(parent_uic, name, icon, template)
	local existing = child(parent_uic, name)
	if existing then return existing end
	local ok, addr = pcall(function() return parent_uic:CreateComponent(name, template or ROUND_BUTTON) end)
	if not ok or not addr then SPA.error("could not create button " .. name .. ": " .. tostring(addr)) return nil end
	local b = UIComponent(addr)
	pcall(function() b:SetImagePath(icon, 0) end)
	return b
end

local function move(uic, x, y)
	if not uic then return end
	local cx, cy = uic:Position()
	if cx ~= x or cy ~= y then pcall(function() uic:MoveTo(x, y) end) end
end

-- "id: state, disabled, priority, visible, x,y wxh" for the log
local function describe(uic)
	if not uic then return "missing" end
	local function get(f) local ok, v = pcall(f) return ok and tostring(v) or "?" end
	return string.format("%s: state=%s disabled=%s priority=%s visible=%s at %s,%s %sx%s", tostring(id_of(uic)),
		get(function() return uic:CurrentState() end), get(function() return uic:IsDisabled() end),
		get(function() return uic:Priority() end), get(function() return uic:Visible(true) end),
		get(function() return (uic:Position()) end), get(function() return select(2, uic:Position()) end),
		get(function() return (uic:Dimensions()) end), get(function() return select(2, uic:Dimensions()) end))
end

-- A button that works or is greyed out: the game's disabled flag (no clicks) plus the template's
-- "inactive" look, or both undone. `selected`: an on/off button that is on (the toggle template's
-- "selected" states). What the mod last set is remembered per button and only a change is applied
-- (setting the state again would cancel the hover look). The game's IsDisabled is not asked: it may
-- not report the flag (asking it left a button that had been greyed out once locked).
UI.enabled_state = {}
local function set_enabled(uic, on, selected)
	local id = uic and id_of(uic)
	local want = (selected and "selected " or "") .. (on and "on" or "off")
	if not id or UI.enabled_state[id] == want then return end
	local state = on and (selected and "selected" or "active") or (selected and "selected_inactive" or "inactive")
	pcall(function() uic:SetDisabled(not on) end)
	pcall(function() uic:SetState(state) end)
	UI.enabled_state[id] = want
	if SPA.debug then log("button", want, describe(uic)) end
end

-- The right edge of the skill points counter (top right of the panel, in line with the right edge of
-- the skill tree below it).
local function counter_right(pts)
	local px = pts:Position()
	local pw = pts:Dimensions()
	local right = px + pw
	walk(pts, function(c)
		if visible(c) then
			local cx = c:Position()
			local cw = c:Dimensions()
			if cx + cw > right then right = cx + cw end
		end
	end, 4)
	return right
end

-- The row goes at the top right of the skill tree, just under the panel's top bar and the skill points
-- counter, with a margin from the right edge: the dropdown, then the icons. Without the counter it
-- starts at the top-left corner of the skills panel.
local function place_toolbar(t)
	local dd = t.dd
	local sub = UI.skills_subpanel()
	if not dd or not sub then return end
	local dw = dd:Dimensions()
	local s = (type(dw) == "number" and dw > 0) and dw / DD_W or 1     -- the game's UI scale
	UI.scale = s
	local sx, sy = sub:Position()
	local y = sy + math.floor(6 * s)
	local pts = find(PANEL, "skill_pts_holder")
	local right = pts and (counter_right(pts) - math.floor(PAD * s)) or (sx + math.floor((70 + ROW_W) * s))
	local icons_left = right - math.floor((#ICON_IDS * ICON + (#ICON_IDS - 1) * ICON_GAP) * s)
	move(dd, icons_left - math.floor(DD_GAP * s) - dw, y)
	local icon_y = y + math.floor((DD_H - ICON) * s / 2)
	for i, id in ipairs(ICON_IDS) do
		move(t.icons[id], icons_left + math.floor((i - 1) * (ICON + ICON_GAP) * s), icon_y)
	end
end

-- The dropdown and the seven icon buttons, made where missing. They are direct children of the panel part
-- that holds the skill points counter (no container of their own). Returns { dd = dropdown,
-- icons = { id = button } }, or nil while the panel isn't laid out.
function UI.ensure_toolbar()
	local pts = find(PANEL, "skill_pts_holder")
	if pts and not visible(pts) then return nil end      -- not laid out yet: the next refresh places it
	local par = pts and parent(pts) or UI.skills_subpanel()
	if not par then return nil end
	local t = { icons = {} }
	t.dd = child(par, BUTTON)
	if not t.dd then
		t.dd = make_button(par, BUTTON, T("select"), DD_W, DD_H, DD_W - 52)
		if not t.dd then return nil end
		pcall(function() for i, path in ipairs(DROPDOWN_ART) do t.dd:SetImagePath(path, i - 1) end end)
		lift(t.dd)
		UI.enabled_state[BUTTON] = nil
		log("presets dropdown created:", describe(t.dd))
	end
	for _, id in ipairs(ICON_IDS) do
		local name = ICON_PREFIX .. id
		local b = child(par, name)
		if not b then
			b = make_icon(par, name, ICON_ART[id], ICON_TEMPLATE[id])
			if b then lift(b) end
			UI.enabled_state[name] = nil
		end
		t.icons[id] = b
	end
	place_toolbar(t)
	return t
end

-- What the row offers for the character: the presets of its type, the selected one (if it still
-- exists), how many points "Allocate now" would spend, and which buttons work. In plan mode the row
-- works on the draft (the whole build) and nothing can be allocated.
local function toolbar_state(cqi)
	local char = SPA.character(cqi)
	if not char then return nil end
	local planning = SPA.in_plan_mode(cqi)
	local plan = SPA.working(cqi)
	local subtype = char:character_subtype_key()
	local list = SPA.preset_list(subtype)
	local preset = plan.preset and SPA.find_preset(subtype, plan.preset) and plan.preset or nil
	local planned = #plan.keys > 0
	local tree = SPA.tree(cqi)
	local known = tree ~= nil and tree.known == true
	-- a preset is the whole build: outside plan mode, what the character learned is part of it
	local build = planned
	if not planning and known then
		local _, spent = R().spent_levels(tree)
		build = build or spent > 0
	end
	local n = planning and 0 or SPA.spendable_now(cqi)
	return {
		subtype = subtype, list = list, preset = preset, spendable = n, planning = planning,
		enabled = { plan = known, new = build, overwrite = build and preset ~= nil, rename = preset ~= nil,
			delete = preset ~= nil, clear = planned, spend = n > 0 },
	}
end
UI.toolbar_state = toolbar_state

local function icon_tip(id, st)
	if id == "plan" then return T(st.planning and "tip_plan_on" or "tip_plan") end
	if id == "spend" then
		if st.planning then return T("tip_spend_plan") end
		return st.spendable > 0 and T("spend", st.spendable) or T("tip_spend")
	end
	if id == "clear" and st.planning then return T("tip_clear_plan") end
	return T("tip_" .. id)
end

function UI.update_toolbar(cqi)
	local t = UI.ensure_toolbar()
	local st = t and toolbar_state(cqi)
	if not st then return end
	set_button_text(t.dd, (#st.list == 0 and T("no_presets")) or (st.preset and short(st.preset, 30)) or T("select"))
	set_tooltip(t.dd, T("button_tip"))
	set_enabled(t.dd, #st.list > 0)
	pcall(function() t.dd:SetVisible(true) end)
	for _, id in ipairs(ICON_IDS) do
		local b = t.icons[id]
		if b then
			set_tooltip(b, icon_tip(id, st))
			set_enabled(b, st.enabled[id], id == "plan" and st.planning)
			pcall(function() b:SetVisible(true) end)
		end
	end
end

function UI.hide_toolbar()
	for _, name in ipairs(TOOLBAR) do
		local c = find(PANEL, name)
		if c then pcall(function() c:SetVisible(false) end) end
	end
	UI.close_menu()
end

function UI.close_menu()
	destroy(find(PANEL, MENU))
end

-- The dropdown's list: this character type's presets, the selected one marked.
function UI.open_menu(cqi)
	UI.close_menu()
	local t = UI.ensure_toolbar()
	local dd = t and t.dd
	local st = dd and toolbar_state(cqi)
	if not st or #st.list == 0 then log("presets list not opened:", st and "no presets" or "no dropdown") return end
	local ok, addr = pcall(function() return parent(dd):CreateComponent(MENU, "UI/Campaign UI/script_dummy.twui.xml") end)
	if not ok or not addr then SPA.error("could not create the presets list: " .. tostring(addr)) return end
	local menu = UIComponent(addr)
	pcall(function()
		menu:SetCanResizeWidth(true)
		menu:SetCanResizeHeight(true)
		menu:Resize(ITEM_W, #st.list * (ITEM_H + 2))
	end)
	for i, p in ipairs(st.list) do
		local ib = make_button(menu, "spa_opt_" .. i, (p.name == st.preset and "> " or "") .. short(p.name, 30), ITEM_W, ITEM_H)
		if ib then pcall(function() ib:SetDockingPoint(1); ib:SetDockOffset(0, (i - 1) * (ITEM_H + 2)) end) end
	end
	-- right under the dropdown, left-aligned with it
	local x, y = dd:Position()
	local _, h = dd:Dimensions()
	pcall(function() menu:MoveTo(x, y + h + 4) end)
	lift(menu)
	log("presets list opened with", #st.list, "presets:", describe(menu))
end

---------------------------------------------------------------- confirmation (the game's yes/no dialog)
function UI.close_confirm()
	destroy(find(CONFIRM))
	UI.confirm_open = false
	UI.confirm_action = nil
end

-- Ask `text`; on_yes runs when the tick is clicked. Returns false if the dialog could not be made.
function UI.confirm(text, on_yes)
	UI.close_confirm()
	local ok, addr = pcall(function() return root():CreateComponent(CONFIRM, "UI/Common UI/dialogue_box") end)
	if not ok or not addr then SPA.error("could not create the confirmation: " .. tostring(addr)) return false end
	pcall(function() UIComponent(addr):PropagatePriority(POPUP_PRIORITY) end)
	local t = find(CONFIRM, "DY_text")
	if t then pcall(function() t:SetStateText(text, "") end) end
	UI.confirm_open = true
	UI.confirm_action = on_yes
	return true
end

function UI.confirmed()
	local action = UI.confirm_action
	UI.close_confirm()
	if action then safe("confirmed", action) end
end

---------------------------------------------------------------- text popup (preset names)
-- Not priority-locked, and the typed text is read from a fresh lookup (never from a component that
-- may be gone).
local function popup_text_now()
	local input = find(POPUP, "text_input")
	if not input then return nil end
	local ok, t = pcall(function() return input:GetStateText() end)
	if ok and type(t) == "string" then return t end
	return nil
end

local function poll_popup()
	if not UI.popup_open or not find(POPUP) then
		UI.popup_open = false
		UI.popup_action = nil
		cm:remove_real_callback("spa_popup_poll")
		return
	end
	local t = popup_text_now()
	if t then UI.popup_text = t end
end

function UI.close_popup()
	cm:remove_real_callback("spa_popup_poll")
	destroy(find(POPUP))
	UI.popup_open = false
	UI.popup_action = nil
end

-- Ask for a name; returns false if the popup could not be made.
function UI.ask_text(heading, initial, on_ok)
	UI.close_popup()
	local ok, addr = pcall(function() return root():CreateComponent(POPUP, "UI/Common UI/popup_text_input.twui.xml") end)
	if not ok or not addr then SPA.error("could not create the text popup: " .. tostring(addr)) return false end
	pcall(function() UIComponent(addr):PropagatePriority(POPUP_PRIORITY) end)
	set_text(find(POPUP, "heading_txt"), heading)
	local input = find(POPUP, "text_input")
	if input then
		pcall(function() input:SetStateText(initial or "", "") end)
		pcall(function() input:SimulateLClick() end)
	end
	UI.popup_open = true
	UI.popup_text = initial or ""
	UI.popup_action = on_ok
	cm:repeat_real_callback(function() safe("poll_popup", poll_popup) end, 200, "spa_popup_poll")
	return true
end

function UI.popup_confirmed()
	local action = UI.popup_action
	local text = popup_text_now() or UI.popup_text
	UI.close_popup()
	if action then safe("popup ok", action, text) end
end

---------------------------------------------------------------- actions
local function current_cqi()
	local cqi = UI.panel_cqi()
	local char = cqi and SPA.character(cqi)
	if not char or not SPA.is_local_character(char) then return nil end
	return cqi, char
end

local function planned_count(cqi, key)
	local n = 0
	for _, k in ipairs(SPA.working(cqi).keys) do if k == key then n = n + 1 end end
	return n
end

---------------------------------------------------------------- plan mode's view of the tree
-- In plan mode the tree shows the character type's tree as a rank 1 character with nothing learned would
-- see it; the character itself is left out:
--  * each card gets a transparent shield ("spa_shield", made from the mod's own layout
--    ui/skill_preallocation/spa_shield, see generator/build_ui.py, the card's size): it takes the mouse, so the game's card never
--    reacts (no choice, no animation, no sound). It carries a neutral tooltip (the skill's name,
--    description and first level's effects, the effects from the skill's database record: nothing the
--    character learned; and the rank the level asks for, as the game says it to a rank 1 character; see
--    UI.tooltip_function). Over the card's level pips
--    it has small shields of its own ("spa_pip_shield1".."3", placed over the pips the card shows): each
--    shows the tooltip of its level. There is no stats preview: the game computes it for the character's
--    real next level.
--  * every card wears the game's locked look, planned skills too (their badges show the plan); only points
--    from creation show learned, and an automatic skill (a mount) shows "unlocks at rank"; the learned
--    tick and the sparkles are hidden. The look doesn't change while planning.
-- What the cards wore is kept and put back when plan mode ends. A look the game draws over the plan
-- view meanwhile is the newer one, and is what is put back. Should the game keep drawing over it
-- (REDRAW_LIMIT checks in a row find its looks), the plan look is given up for the session: the cards
-- show the game's looks again and the shields stay.
local SHIELD = "spa_shield"
local SHIELD_LAYOUT = "ui/skill_preallocation/spa_shield"
local PIP_SHIELD = "spa_pip_shield"     -- spa_pip_shield1..3, the shield's children
local T_SKILL = "CcoCampaignCharacterSkill"
-- The shields' tooltips (in the mod's shield layout: generator/build_ui.py tooltip_function, the same text) are
-- evaluated on the card's skill: the skill's database record is looked up by key (r), and a skill is
-- built with the card's name (numbered on a pip's shield) and description and the record's effects for
-- `level` (n), shown with the game's background skill tooltip. Under the description, the rank that level
-- asks for (t), in the game's own words: "Available at rank N." in red, or "Automatically granted at rank
-- N." for a skill the game grants by itself, as the card's own tooltip shows it while the character's
-- rank is lower (plan mode's view is a rank 1 character). The shield carries that rank (k) as the
-- properties spa_rank and spa_auto (see give_rank), which the function reads with self.GetProperty, as
-- the game's layouts read theirs. If the record or the built skill can't be made, the tooltip shows the
-- card's skill itself (as on this character) rather than nothing. Here they are only used by the tests
-- (the layout must carry the same text).
-- The script never evaluates these functions or their parts itself (obj:Call): in game, a 0.19 build that
-- checked them that way once a session (Format(Loc("skill_locked_rank"), 10) on a card's skill) left the
-- game's interface unable to make components or read the panel's character, and closing or switching the
-- skills panel then crashed the game. The only expression the script evaluates is a context's Key.
local TIP_RECORD = 'DatabaseRecordContext("CcoCharacterSkillRecord", Key)'
function UI.tooltip_function(level, numbered)
	local name = numbered and ('this.Name + " (' .. level .. ')"') or "this.Name"
	return '(r = ' .. TIP_RECORD .. ', k = RoundFloat(ToNumber(self.GetProperty("spa_rank"))), '
		.. 't = GetIfElse(k > 1, Format(Loc(GetIfElse(self.GetProperty("spa_auto") == "1", "skill_locked_auto_unlock", '
		.. '"skill_locked_rank")), k), ""), n = GetIf(IsContextValid(r), CcoCampaignCharacterSkill(Name:' .. name
		.. ', Description:this.Description + t, EffectList:r.EffectListForLevel(' .. level .. ')))) => GetIfElse(IsContextValid(n), n, this)'
end
UI.TOOLTIP_FUNCTION = UI.tooltip_function(1)

-- The rank a level of the skill asks for, on a shield (its tooltip shows it, see above): spa_rank, the
-- rank ("0": none beyond rank 1, or a level learned from the start), and spa_auto, "1" when the game
-- grants the level by itself at that rank (a mount), else "0". `s`: the skill in plan mode's tree.
local function give_rank(uic, s, level)
	local rank, auto = 0, "0"
	if s and (s.level or 0) < level then
		if s.auto then
			for _, a in ipairs(s.auto) do
				if a.level == level then rank, auto = R().required_rank(a.rank), "1" break end
			end
		elseif s.ranks and s.ranks[level] then
			rank = R().required_rank(s.ranks[level])
		end
	end
	if rank <= 1 then rank, auto = 0, "0" end
	pcall(function()
		uic:SetProperty("spa_rank", tostring(rank))
		uic:SetProperty("spa_auto", auto)
	end)
end

local PIPS = { "level1", "level2", "level3" }
local REDRAW_LIMIT = 3
UI.painted = {}                -- skill -> what its card wore before the plan look (see paint)
UI.paint_off = false           -- the plan look given up for the session
UI.redraw_checks = 0           -- checks in a row that found the game's looks over the plan look

local function context_id(uic, t)
	local ok, id = pcall(function() return uic:GetContextObjectId(t) end)
	if ok and id ~= nil and id ~= "" then return id end
	return nil
end

local function state_of(uic)
	local ok, st = pcall(function() return uic:CurrentState() end)
	if ok and type(st) == "string" then return st end
	return nil
end

local function own_visible(uic)
	local ok, v = pcall(function() return uic:Visible() end)
	return ok and v == true
end

local function dims(uic)
	local ok, w, h = pcall(function() return uic:Dimensions() end)
	if ok and type(w) == "number" and type(h) == "number" then return w, h end
	return nil
end

local function pos(uic)
	local ok, x, y = pcall(function() return uic:Position() end)
	if ok and type(x) == "number" and type(y) == "number" then return x, y end
	return nil
end

-- Put `uic` at its parent's top left + (x, y), `w` x `h` big, all in screen pixels (what Position and
-- Dimensions give). Docking offsets and Resize take the layout's units: screen pixels / the game's UI
-- scale (UI.scale, from the presets dropdown, see place_toolbar).
local function place(uic, x, y, w, h)
	local s = (type(UI.scale) == "number" and UI.scale > 0) and UI.scale or 1
	pcall(function()
		uic:SetDockingPoint(1)
		uic:SetDockOffset(math.floor(x / s + 0.5), math.floor(y / s + 0.5))
	end)
	if w and h then
		local cw, ch = dims(uic)
		if cw and (math.abs(cw - w) > 1 or math.abs(ch - h) > 1) then
			pcall(function()
				uic:SetCanResizeWidth(true)
				uic:SetCanResizeHeight(true)
				uic:Resize(math.floor(w / s + 0.5), math.floor(h / s + 0.5))
			end)
		end
	end
end

-- The card's shield, made from the mod's layout the first time plan mode shows it on this card (the game
-- builds its cards afresh each time the panel opens). nil when it can't be made (written to the log once:
-- plan mode then undoes the game's choices instead).
local function card_shield(card, make)
	local s = child(card, SHIELD)
	if s or not make then return s end
	local ok, addr = pcall(function() return card:CreateComponent(SHIELD, SHIELD_LAYOUT) end)
	if ok and addr then s = UIComponent(addr) end
	if not s then
		if not UI.shield_failed then
			UI.shield_failed = true
			SPA.warn("plan mode: no shield could be made on the skill cards (" .. tostring(addr) .. "); the cards take the"
				.. " clicks, and the game's choices are undone instead")
		end
		return nil
	end
	pcall(function() s:SetVisible(false) end)
	local w, h = dims(card)
	place(s, 0, 0, w, h)
	UI.shields_made = (UI.shields_made or 0) + 1
	return s
end

-- A context object made by the game's cco (nil when there is no cco, or it makes none).
local function make_context(t, id)
	if type(cco) ~= "function" or id == nil then return nil end
	local ok, obj = pcall(cco, t, id)
	if ok then return obj end
	return nil
end

-- The shield needs the card's skill: its tooltip is made from it.
-- Built with the card it should have it already; it is given the card's own context object all the same
-- (CA's scripts give a component theirs with SetContextObject), else one made with cco from the card's
-- id. Returns whether the shield's skill reads back as `key`, how it was given, and what was read back.
local function give_skill(shield, card, key)
	local how = "none"
	local okc, obj = pcall(function() return card:GetContextObject(T_SKILL) end)
	if okc and obj and pcall(function() shield:SetContextObject(obj) end) then
		how = "card"
	else
		local made = make_context(T_SKILL, context_id(card, T_SKILL))
		if made ~= nil and pcall(function() shield:SetContextObject(made) end) then how = "cco" end
	end
	local okk, got = pcall(function()
		local o = shield:GetContextObject(T_SKILL)
		return o and o:Call("Key")
	end)
	if okk then return got == key, how, got end
	local sid = context_id(shield, T_SKILL)               -- (no GetContextObject: the ids are compared)
	return sid ~= nil and sid == context_id(card, T_SKILL), how, sid
end

-- The pips' shields in a card's shield (one over each level pip, with that level's tooltip): shown, over
-- their pip, for the pips the card shows, hidden for the others (a skill with fewer levels, or no pips
-- shown). Newly shown ones are given the card's skill; `give`: all those shown (the shield is being shown).
local function sync_pip_shields(shield, card, key, give)
	local lp = child(card, "level_parent")
	local pips_shown = lp ~= nil and own_visible(lp)
	local cx, cy = pos(card)
	for i, id in ipairs(PIPS) do
		local ps = child(shield, PIP_SHIELD .. i)
		if ps then
			local pip = pips_shown and child(lp, id)
			local want = pip ~= nil and pip ~= false and own_visible(pip)
			local shown = own_visible(ps)
			if want then
				local px, py = pos(pip)
				local pw, ph = dims(pip)
				if cx and px then place(ps, px - cx, py - cy, pw, ph) end
				if give or not shown then give_skill(ps, card, key) end
			end
			if want ~= shown then pcall(function() ps:SetVisible(want) end) end
		end
	end
end

-- Show a card's shield, above the card's own parts, with the card's skill (its tooltip uses it) and the
-- rank each level asks for (`s`: the skill in plan mode's tree, see give_rank), and its pips' shields above
-- it (the card's badge stays above both, see BADGE_LIFT). A shield without the skill is written to the log
-- once a session.
local function show_shield(shield, card, key, s)
	local p = priority_of(card) or CARD_PRIORITY
	pcall(function() shield:PropagatePriority(p + 1) end)
	for i = 1, #PIPS do
		local ps = child(shield, PIP_SHIELD .. i)
		if ps then pcall(function() ps:PropagatePriority(p + 2) end) end
	end
	local w, h = dims(card)
	place(shield, 0, 0, w, h)                -- (the card's size, should a UI mod make cards of another size)
	sync_pip_shields(shield, card, key, true)
	local ok, how, got = give_skill(shield, card, key)
	give_rank(shield, s, 1)                  -- (once they have the skill their tooltips read)
	for i = 1, #PIPS do
		local ps = child(shield, PIP_SHIELD .. i)
		if ps then give_rank(ps, s, i) end
	end
	pcall(function() shield:SetVisible(true) end)
	if not UI.shield_described then        -- once per session, for reports
		UI.shield_described = true
		local function at(uic)
			if not uic then return "none" end
			local x, y = pos(uic)
			local cw, ch = dims(uic)
			return tostring(x) .. "," .. tostring(y) .. " " .. tostring(cw) .. "x" .. tostring(ch)
		end
		local lp = child(card, "level_parent")
		log("plan mode shield: skill given from " .. how .. ", reads back " .. tostring(got) .. " for " .. tostring(key)
			.. "; priority " .. tostring(priority_of(shield)) .. " over " .. tostring(priority_of(card)) .. "; card " .. at(card)
			.. ", shield " .. at(shield) .. ", pip 1 " .. at(lp and child(lp, PIPS[1])) .. ", its shield " .. at(child(shield, PIP_SHIELD .. 1))
			.. "; UI scale " .. tostring(UI.scale))
	end
	if not ok and not UI.shield_unskilled then
		UI.shield_unskilled = true
		SPA.warn("plan mode: a card's shield has no skill (its tooltip can't work there): given from "
			.. how .. ", reads back " .. tostring(got) .. " for " .. tostring(key))
	end
end

-- The look of a card in plan mode (the skill at rank 1, before any point is spent): the card's state, its
-- name's state, its level pips' states.
local function plan_look(tree, key)
	local s = tree and tree.skills[key]
	local total = (s and s.total) or 1
	local level = (s and s.level) or 0
	local card, name
	if level <= 0 then
		card = (s and s.auto) and "locked_auto_unlock" or "locked"
		name = card
	elseif level >= total then
		card, name = "maxed", "active"
	else
		card, name = "complete", "active"
	end
	local pips = {}
	for i = 1, math.min(total, #PIPS) do
		pips[i] = (level <= 0 and "locked") or (i <= level and "active") or "inactive"
	end
	return card, name, pips
end

-- Put `uic` in state `want`. rec.saved keeps the state it wore before (the game's), rec.set the one set
-- here. Returns true when the game had drawn over the state set here (its look is then the one kept).
local function paint(uic, rec, want)
	local cur = uic and state_of(uic)
	if not cur then return false end
	local redrawn = rec.set ~= nil and cur ~= rec.set
	if rec.set == nil or redrawn then rec.saved = cur end
	if cur ~= want then pcall(function() uic:SetState(want) end) end
	rec.set = want
	return redrawn
end

local function unpaint(uic, rec)
	if not uic or not rec or rec.saved == nil or rec.saved == rec.set then return end
	if state_of(uic) == rec.set then pcall(function() uic:SetState(rec.saved) end) end
end

local function hide(uic, rec, field)
	if not uic then return end
	local shown = own_visible(uic)
	if rec[field] == nil then rec[field] = shown end
	if shown then pcall(function() uic:SetVisible(false) end) end
end

local function unhide(uic, shown)
	if uic and shown then pcall(function() uic:SetVisible(true) end) end
end

local function restore_cards(cards)
	for _, e in ipairs(cards) do
		local rec = UI.painted[e.key]
		if rec then
			unpaint(e.card, rec.card)
			unpaint(child(e.card, "dy_skill"), rec.name)
			local lp = child(e.card, "level_parent")
			for i, r in pairs(rec.pips) do unpaint(child(lp, PIPS[i]), r) end
			unhide(child(e.card, "icon_check"), rec.tick)
			unhide(child(e.card, "particle_emitter"), rec.sparks)
		end
	end
	UI.painted = {}
end

-- Plan mode's view on the cards shown (made or brought up to date); outside plan mode, taken off.
function UI.update_plan_view(cqi)
	if not (cqi and UI.plan_cqi == cqi and SPA.in_plan_mode(cqi)) then
		-- (with another character shown, its cards are the game's own: nothing is put back on them)
		if UI.view_on then UI.clear_plan_view(cqi ~= nil and cqi == UI.plan_cqi) end
		return
	end
	local cards = UI.cards()
	if #cards == 0 then return end
	UI.view_on = true
	local tree = SPA.rules_tree(cqi)               -- (from scratch)
	local redrawn = 0
	local made = UI.shields_made or 0
	for _, e in ipairs(cards) do
		local shield = card_shield(e.card, true)
		if shield then
			if not own_visible(shield) then
				show_shield(shield, e.card, e.key, tree and tree.skills[e.key])
				local b = child(e.card, BADGE)          -- (above the shield, should it have come after it;
				if b and own_visible(b) then lift_badge(b, e.card) end    -- a hidden one is lifted when shown)
			else sync_pip_shields(shield, e.card, e.key, false) end
		end
		if not UI.paint_off then
			local rec = UI.painted[e.key]
			if not rec then
				rec = { card = {}, name = {}, pips = {} }
				UI.painted[e.key] = rec
			end
			local cs, ns, ps = plan_look(tree, e.key)
			if paint(e.card, rec.card, cs) then redrawn = redrawn + 1 end
			paint(child(e.card, "dy_skill"), rec.name, ns)
			local lp = child(e.card, "level_parent")
			for i, want in ipairs(ps) do
				rec.pips[i] = rec.pips[i] or {}
				paint(child(lp, PIPS[i]), rec.pips[i], want)
			end
			hide(child(e.card, "icon_check"), rec, "tick")
			hide(child(e.card, "particle_emitter"), rec, "sparks")
		end
	end
	if (UI.shields_made or 0) > made then log("plan mode: shields made on", (UI.shields_made or 0) - made, "of", #cards, "cards") end
	if UI.paint_off then return end
	UI.redraw_checks = redrawn > 0 and UI.redraw_checks + 1 or 0
	if redrawn > 0 then log("plan mode: the game drew over the plan look of", redrawn, "cards (" .. UI.redraw_checks .. " checks in a row)") end
	if UI.redraw_checks >= REDRAW_LIMIT then
		UI.paint_off = true
		restore_cards(cards)
		SPA.warn("plan mode: the game keeps redrawing the skill cards, so their rank 1 look is turned off for this session"
			.. " (planning works the same)")
	end
end

-- Take plan mode's view off the cards: the shields are hidden, the cards wear their own looks again
-- (`restore` false: the panel shows another character now, whose cards the game has drawn afresh).
function UI.clear_plan_view(restore)
	local cards = UI.cards()
	for _, e in ipairs(cards) do
		local shield = child(e.card, SHIELD)
		if shield then pcall(function() shield:SetVisible(false) end) end
	end
	if restore then restore_cards(cards) end
	UI.painted = {}
	UI.view_on = false
	UI.redraw_checks = 0
end

-- The mouse moving over the tree may make the game redraw a card (a hover look): the plan look is
-- checked again a moment later.
function UI.schedule_paint()
	if UI.paint_due then return end
	UI.paint_due = true
	cm:real_callback(function()
		UI.paint_due = false
		safe("plan view", function()
			local cqi = current_cqi()      -- (another character shown: the refresh after the click leaves plan mode)
			if cqi and cqi == UI.plan_cqi and UI.panel_open and UI.skills_visible() then UI.update_plan_view(cqi) end
		end)
	end, 100, "spa_paint")
end

---------------------------------------------------------------- plan mode
-- In plan mode the clicks land on the shields, so the game makes no choice from them. Should a click reach
-- a card all the same (a card without its shield), whatever the game holds from it (with free points it
-- holds the skill as chosen until the panel closes) is undone with the panel's own "Undo assigned skill
-- points" button, which undoes every choice not confirmed yet. Checked again a moment later; a choice
-- that can't be undone is written to the log (the game would teach it when the panel closes).
local function game_holds_choices(cqi)
	return SPA.ccv(T_CHAR, tostring(cqi), "HasUncommitedSkills") == true
end

function UI.undo_game_choices(cqi)
	SPA.pending_choices[cqi] = nil
	if not game_holds_choices(cqi) then return end
	local b = find(PANEL, UNDO_BUTTON)
	if not b then
		SPA.warn("plan mode: the panel's " .. UNDO_BUTTON .. " button is missing, a skill chosen with free points stays chosen")
		return
	end
	UI.undoing = true
	pcall(function() b:SimulateLClick() end)
	UI.undoing = false
	SPA.refresh_points(cqi)
	log("plan mode: the game's skill choices undone", cqi)
	cm:real_callback(function()
		safe("undo check", function()
			if game_holds_choices(cqi) then
				SPA.warn("plan mode: the game's skill choice could not be undone (it is learned when the panel closes)")
			end
			SPA.refresh_points(cqi)
			UI.refresh()
		end)
	end, 200)
end

-- A click in plan mode that reached a card itself (no shield on it): if the game made a choice from it
-- (fewer free points than before the click), the choices are undone. (The panel's button undoes every
-- choice not confirmed yet, the ones made before plan mode too: only done when this click made one.)
local function undo_if_chosen(cqi)
	local live = SPA.live_cache[cqi]
	if not live or SPA.points(cqi) < (live.points or 0) then UI.undo_game_choices(cqi) end
end

-- Leave plan mode (the toggle, the panel closing, another character shown): the cards get their own
-- looks back, and a build planned there becomes the pre-allocations. After the game's reset of all
-- skills the character is read again first, so the build is planned on the reset tree.
function UI.leave_plan_mode()
	local cqi = UI.plan_cqi
	UI.plan_cqi = nil
	if not cqi then return end
	if UI.view_on then safe("clear plan view", UI.clear_plan_view, UI.panel_cqi() == cqi) end
	if UI.reset_clicked[cqi] then safe("reread", SPA.reread, cqi) end
	safe("leave plan mode", SPA.leave_plan_mode, cqi)
end

-- Choices made with free points before plan mode stay as they are (the game learns them when the panel
-- closes); plan mode just doesn't show them.
function UI.set_plan_mode(cqi, on)
	UI.enabled_state[ICON_PREFIX .. "plan"] = nil     -- (the game's toggle may have switched its look)
	if on then
		if UI.plan_cqi and UI.plan_cqi ~= cqi then UI.leave_plan_mode() end
		if SPA.enter_plan_mode(cqi) then UI.plan_cqi = cqi end
	else
		UI.leave_plan_mode()
	end
	UI.refresh()
end

-- After a click the game handled itself (a normal allocation with free points), see what changed:
-- the free points tell how many points were chosen there (applied by the game when the panel closes).
local function recheck(cqi, key)
	local live = SPA.live_cache[cqi]
	if not live then return end
	local old_points = live.points or 0
	local points = SPA.points(cqi)
	log("click check", key, "points", old_points, "->", points)
	local delta = old_points - points
	if delta > 0 then
		SPA.note_choice(cqi, key, delta)
	elseif points ~= old_points then
		SPA.refresh_points(cqi)
	end
	UI.refresh()
end

function UI.schedule_recheck(cqi, key)
	cm:real_callback(function() safe("recheck", recheck, cqi, key) end, 200)
end

-- Left click: pre-allocate the next point of the skill (with free points it is the game's own
-- allocation instead). `n` > 1 when the card was clicked several times in a row; `shielded`: the clicks
-- landed on plan mode's shield (the game's card didn't see them).
function UI.add_point(key, n, shielded)
	local cqi = current_cqi()
	if not cqi then return end
	local tree = SPA.tree(cqi)
	if not tree then return end
	if SPA.in_plan_mode(cqi) then
		-- plan mode: every click plans; a choice the game made from a click on the card itself is undone
		for _ = 1, n or 1 do
			local ok, code, detail = SPA.preallocate(cqi, key)
			if not ok then
				UI.say("can't plan " .. key .. ": " .. tostring(code) .. " " .. tostring(detail or ""))
				break
			end
		end
		if not shielded then undo_if_chosen(cqi) end
		UI.refresh()
		return
	end
	-- The game has handled the click already (and may have used a free point), so the decision uses
	-- the points known before the click; a fresh read only catches points that arrived since.
	local live = SPA.live_cache[cqi]
	local known = live and live.points or 0
	local fresh = SPA.points(cqi)
	if live and fresh > known then live.points = fresh; known = fresh end
	if known > 0 then
		UI.schedule_recheck(cqi, key)
		return
	end
	for _ = 1, n or 1 do
		local ok, code, detail = SPA.preallocate(cqi, key)
		if not ok then
			UI.say("can't pre-allocate " .. key .. ": " .. tostring(code) .. " " .. tostring(detail or ""))
			break
		end
	end
	UI.refresh()
end

-- Left click on a skill's badge: remove the last pre-allocated point of the skill (in plan mode: of the
-- build), `n` times when the badge was clicked several times in a row. The badge takes the click, so the
-- game's card doesn't see it.
function UI.remove_point(key, n)
	local cqi = current_cqi()
	if not cqi then return end
	for _ = 1, n or 1 do
		if planned_count(cqi, key) == 0 then break end
		SPA.unallocate(cqi, key)
	end
	UI.refresh()
end

-- A click on a skill card, on its shield in plan mode, or on its badge reaches the script as
-- ComponentLClickUp. The clicks on one skill are gathered for a moment, then acted on once: clicks on the
-- card plan points, clicks on the badge remove them.
-- `kind`: "lclick" (on the card), "shield" (on its shield) or "badge" (on its badge).
UI.clicks = {}

function UI.gather_click(key, kind)
	if not key then return end
	local c = UI.clicks[key]
	if not c then
		c = { lclick = 0, badge = 0, shield = false }
		UI.clicks[key] = c
		cm:real_callback(function()
			if UI.clicks[key] == c then UI.clicks[key] = nil end
			safe("click", UI.resolve_click, key, c)
		end, 150)
	end
	if kind == "badge" then
		c.badge = c.badge + 1
	else
		c.lclick = c.lclick + 1
		if kind == "shield" then c.shield = true end
	end
end

function UI.resolve_click(key, c)
	log("click on", key, "clicks=" .. c.lclick, "on the badge=" .. c.badge, c.shield and "(on the shield)" or "")
	if c.badge > 0 then UI.remove_point(key, c.badge) end
	if c.lclick > 0 then UI.add_point(key, c.lclick, c.shield) end
end

local function next_free_name(subtype, base)
	for i = 1, 99 do
		local name = SPA.clean_name(base .. " " .. i)
		if not SPA.find_preset(subtype, name) then return name end
	end
	return base
end

local function type_name()
	local t = find(PANEL, "panel_subtitle", "dy_subtype")
	local ok, text = pcall(function() return t and t:GetStateText() end)
	if ok and type(text) == "string" and text ~= "" then
		text = string.gsub(text, "%[%[.-%]%]", "")    -- drop colour tags
		text = SPA.clean_name(string.sub(text, 1, 30))
		if text ~= "" then return text end
	end
	return T("default_name")
end

-- A preset picked in the dropdown's list: the pre-allocations are replaced by it (what the character
-- already learned is recognised) and it becomes the selected preset.
function UI.on_option(id)
	local cqi, char = current_cqi()
	UI.close_menu()
	if not cqi then return end
	local i = tonumber(string.match(id, "^spa_opt_(%d+)$") or "")
	local p = i and SPA.preset_list(char:character_subtype_key())[i]
	if p then SPA.apply_preset(cqi, p.name) end
	UI.refresh()
end

-- An icon button. A button that doesn't work right now does nothing (the game also greys it out);
-- overwrite, delete, clear and allocate now ask first.
function UI.on_icon(name)
	local cqi = current_cqi()
	UI.close_menu()
	if not cqi then return end
	local st = toolbar_state(cqi)
	if not st or not st.enabled[name] then return end
	local preset = st.preset
	-- what the dialog or the question then does, if the panel still shows the same character
	local function later(fn)
		return function(...)
			if current_cqi() == cqi then fn(...) end
			UI.refresh()
		end
	end
	if name == "plan" then
		UI.set_plan_mode(cqi, not st.planning)
	elseif name == "new" then
		local subtype = st.subtype
		local default = next_free_name(subtype, type_name())
		local save = later(function(text)
			local ok, why = SPA.save_preset_as(cqi, text)
			if not ok and why == "exists" then SPA.save_preset_as(cqi, next_free_name(subtype, SPA.clean_name(text))) end
		end)
		if not UI.ask_text(T("heading_save"), default, save) then save(default) end
	elseif name == "rename" then
		UI.ask_text(T("heading_rename"), preset, later(function(text) SPA.rename_preset(cqi, preset, text) end))
	elseif name == "overwrite" then
		UI.confirm(T("ask_overwrite", short(preset, 30)), later(function() SPA.overwrite_preset(cqi, preset) end))
	elseif name == "delete" then
		UI.confirm(T("ask_delete", short(preset, 30)), later(function() SPA.delete_preset(cqi, preset) end))
	elseif name == "clear" then
		UI.confirm(T(st.planning and "ask_clear_plan" or "ask_clear"), later(function() SPA.clear_plan(cqi) end))
	elseif name == "spend" then
		UI.confirm(T("ask_spend", st.spendable), later(function() SPA.allocate_now(cqi) end))
	end
	UI.refresh()
end

---------------------------------------------------------------- after the mod spent points
-- Opens the character panel on the Skills tab for the character: the game's own context function
-- behind its character buttons.
local function show_details(cqi)
	local ok, err = pcall(common.call_context_command, "CcoCampaignCharacter", tostring(cqi),
		'SelectAndShowDetailsForCharacter(this, "skills")')
	if not ok then SPA.error("could not open the character panel: " .. tostring(err)) end
end

-- After the panel closed for UI.on_points_spent: open it again, and once more if it didn't open.
local function reopen(cqi, tries)
	show_details(cqi)
	cm:real_callback(function()
		if UI.panel_open then return end
		if tries > 1 then safe("reopen panel", reopen, cqi, tries - 1)
		else SPA.error("the character panel did not open again after Allocate now") end
	end, 800, "spa_reopen_check")
end

-- The number the panel's skill points counter shows, or nil if it can't be read.
local function counter_shows()
	local c = find(PANEL, "skill_pts_holder", "dy_pts")
	if not c then return nil end
	local ok, text = pcall(function() return c:GetStateText() end)
	if not ok or type(text) ~= "string" then return nil end
	return tonumber(string.match(text, "%d+"))
end

local function close_and_reopen(cqi)
	local ok_button = find(PANEL, "button_ok")
	if not ok_button then return end
	log("the panel still shows the old points: closing and opening it again", cqi)
	UI.reopen_cqi = cqi
	pcall(function() ok_button:SimulateLClick() end)
	-- if the panel didn't close, a later close by the player must not reopen it
	cm:real_callback(function() if UI.panel_open and UI.reopen_cqi == cqi then UI.reopen_cqi = nil end end,
		1000, "spa_reopen_expire")
end

-- The game's skills panel doesn't show points the mod spent while it is open (Allocate now): the cards
-- and the points counter keep their old look until the panel is opened again (switching tabs doesn't
-- redraw them). First the game is asked to show the character's details again while the panel is open,
-- which may redraw it in place; if the counter still shows the old number a moment later, the panel is
-- closed and opened again.
function UI.on_points_spent(cqi)
	if not UI.panel_open or UI.shown_cqi ~= cqi then return end
	UI.reopen_cqi = cqi                 -- should showing it again close the panel, it is opened again
	show_details(cqi)
	UI.refresh_soon()
	cm:real_callback(function()
		safe("redraw check", function()
			if not UI.panel_open then return end      -- it closed: the close listener opens it again
			if UI.reopen_cqi == cqi then UI.reopen_cqi = nil end
			local shows = counter_shows()
			if shows ~= nil and shows == SPA.points(cqi) then
				log("panel redrawn in place", cqi)
				return
			end
			close_and_reopen(cqi)
		end)
	end, 200, "spa_redraw_check")
end

---------------------------------------------------------------- refresh
function UI.refresh()
	if not UI.panel_open then return end
	local panel_cqi = UI.panel_cqi()
	local cqi = current_cqi()
	if cqi then SPA.text.detect(cqi) end       -- the game's language, read once
	if panel_cqi ~= UI.shown_panel_cqi then
		-- another character: its tree is read from the game again (this also notices a skill reset); the
		-- one in plan mode leaves it
		if UI.plan_cqi and UI.plan_cqi ~= cqi then UI.leave_plan_mode() end
		UI.shown_panel_cqi = panel_cqi
		UI.shown_cqi = cqi
		UI.close_menu()
		UI.close_confirm()
		if cqi then
			if not SPA.has_unconfirmed(cqi) then SPA.reread(cqi) end
			safe("check_tree", UI.check_tree, cqi)
			if SPA.debug then safe("diagnose", UI.diagnose, cqi) end
		end
	end
	if not cqi or not UI.skills_visible() then
		UI.hide_toolbar()
		if not cqi then UI.update_badges(nil) end
		return
	end
	safe("update_toolbar", UI.update_toolbar, cqi)
	if SPA.debug and UI.described_cqi ~= cqi and find(PANEL, BUTTON) then     -- once per character shown
		UI.described_cqi = cqi
		safe("describe_toolbar", UI.describe_toolbar, cqi)
	end
	safe("update_badges", UI.update_badges, cqi)
	safe("plan_view", UI.update_plan_view, cqi)
end

-- One refresh at a time: a request made while one is on its way is served by that one (several
-- points spent in a row ask for a refresh each).
function UI.schedule_refresh(ms)
	if UI.refresh_due then return end
	UI.refresh_due = true
	cm:real_callback(function()
		UI.refresh_due = false
		safe("refresh", UI.refresh)
	end, ms or 300, "spa_refresh")
end

-- The game tells scripts nothing when the panel switches tab or character, and builds the tree's
-- cards over a moment (also while the panel slides in): after such a click, look a few times in quick
-- succession, so the button and the badges follow the panel without a visible delay.
local SOON = { 50, 150, 400, 1000 }
local PANEL_CHECK_MS = 1500            -- after the last of SOON: the panel is built by then
function UI.refresh_soon()
	for _, ms in ipairs(SOON) do
		cm:real_callback(function() safe("refresh", UI.refresh) end, ms, "spa_refresh_soon")
	end
	if not UI.panel_checked then
		cm:remove_real_callback("spa_panel_check")
		cm:real_callback(function() safe("check_panel", UI.check_panel) end, PANEL_CHECK_MS, "spa_panel_check")
	end
end

-- called by the core when a plan changes
function UI.on_plan_changed(cqi)
	if UI.panel_open and UI.shown_cqi == cqi then UI.schedule_refresh(100) end
end

function UI.on_character_changed(cqi)
	if UI.panel_open and UI.shown_cqi == cqi then UI.schedule_refresh(300) end
end

---------------------------------------------------------------- checks written to the log (once)
-- Once per session, while one of the player's characters shows its skills: are the panel's parts the
-- mod relies on where it expects them? A missing one (a UI mod, or a game update that renamed it) is
-- written to the log once, so a report says why the presets row or the badges are missing.
UI.panel_checked = false
function UI.check_panel()
	if UI.panel_checked or not UI.panel_open then return end
	local missing = {}
	if not UI.panel_cqi() then
		missing[#missing + 1] = "character_context_parent (which character the panel shows)"
	else
		if not current_cqi() then return end              -- another faction's character: checked later
		local sub = UI.skills_subpanel()
		if not sub then
			missing[#missing + 1] = "skills_subpanel"
		else
			if not visible(sub) then return end              -- another tab: checked later
			local ok, lv = pcall(find_uicomponent, sub, "listview")
			if not ok or not lv then
				missing[#missing + 1] = "listview (holds the skill cards)"
			else
				local cards = UI.cards()
				if #cards == 0 then
					missing[#missing + 1] = "card (the skill cards)"
				elseif not child(cards[1].card, "dy_skill") then
					missing[#missing + 1] = "dy_skill (a card's text, copied for the badges)"
				end
			end
			if not find(PANEL, "skill_pts_holder") then
				missing[#missing + 1] = "skill_pts_holder (the presets row is placed by it)"
			else
				if not find(PANEL, "skill_pts_holder", "dy_pts") then
					missing[#missing + 1] = "dy_pts (the points counter, read after Allocate now)"
				end
				if not find(PANEL, "skill_pts_holder", UNDO_BUTTON) then
					missing[#missing + 1] = UNDO_BUTTON .. " (plan mode undoes the game's choices with it)"
				end
			end
		end
	end
	UI.panel_checked = true
	if #missing > 0 then
		SPA.warn("the skills panel isn't as the mod expects (another UI mod or a game update?): missing "
			.. table.concat(missing, "; "))
	else
		log("skills panel check: ok")
	end
end

-- A character whose skill tree isn't in the mod's data (a lord from another mod, or a DLC newer than the
-- data) can't be pre-allocated: written to the log once per character type.
function UI.check_tree(cqi)
	local tree = SPA.tree_cache[cqi]
	if not tree or tree.known then return end
	SPA.warn("skill tree not in the mod's data, nothing can be pre-allocated: " .. tostring(tree.subtype)
		.. " (" .. tostring(tree.agent) .. ", set " .. tostring(tree.set_key or "none") .. ", " .. #tree.order .. " skills)")
end

---------------------------------------------------------------- diagnostics (debug builds)
function UI.diagnose(cqi)
	local tree = SPA.tree(cqi)
	if not tree then return end
	log("DIAG character", cqi, "subtype", tree.subtype, "set", tostring(tree.set_key), "known", tostring(tree.known),
		"rank", tree.rank, "points", tree.points, "skills", #tree.order, "capacity", R().capacity(tree))
	local function pos(name)
		local c = find(PANEL, name)
		if not c then return name .. "=missing" end
		local x, y = c:Position()
		local w, h = c:Dimensions()
		return string.format("%s=%d,%d %dx%d", name, x, y, w, h)
	end
	log("DIAG layout", pos("skills_subpanel"), pos("skill_pts_holder"), pos("button_stats_reset"), pos("button_stats_reset_all"))
end

-- the row's buttons as the game reports them (debug builds)
function UI.describe_toolbar(cqi)
	local st = cqi and toolbar_state(cqi)
	local parts = {}
	for _, name in ipairs(TOOLBAR) do
		local c = find(PANEL, name)
		parts[#parts + 1] = c and describe(c) or (name .. ": missing")
	end
	log("DIAG toolbar", st and (#st.list .. " presets for " .. st.subtype) or "no character", "|", table.concat(parts, " | "))
end

---------------------------------------------------------------- listeners
function UI.init()
	core:add_listener("spa_panel_opened", "PanelOpenedCampaign",
		function(context) return context.string == PANEL end,
		function()
			if UI.panel_open then return end
			UI.panel_open = true
			UI.shown_cqi = nil
			UI.shown_panel_cqi = nil
			UI.described_cqi = nil
			UI.refresh_soon()
		end, true)

	core:add_listener("spa_panel_closed", "PanelClosedCampaign",
		function(context) return context.string == PANEL end,
		function()
			if not UI.panel_open then return end
			UI.leave_plan_mode()                   -- (the draft becomes the pre-allocations)
			UI.panel_open = false
			UI.shown_cqi = nil
			UI.shown_panel_cqi = nil
			UI.close_popup()
			UI.close_confirm()
			local reset = UI.reset_clicked
			UI.reset_clicked = {}
			local again = UI.reopen_cqi
			UI.reopen_cqi = nil
			if again then
				cm:real_callback(function() safe("reopen panel", reopen, again, 2) end, 100, "spa_reopen")
			end
			-- choices made by hand are applied by the game when the panel closes; then the pre-allocated
			-- points are spent
			cm:real_callback(function()
				if UI.panel_open then                 -- opened again meanwhile: its own close does this
					for cqi in pairs(reset) do UI.reset_clicked[cqi] = true end
					return
				end
				safe("after_panel_closed", SPA.after_panel_closed, reset)
			end, 1500)
		end, true)

	core:add_listener("spa_lclick", "ComponentLClickUp",
		function() return UI.panel_open or UI.popup_open or UI.confirm_open end,
		function(context)
			if UI.undoing then return end           -- (the mod's own click on the panel's undo button)
			local uic = UIComponent(context.component)
			if SPA.debug then log("click", path_of(uic, 7), "|", describe(uic)) end
			-- the name popup
			if UI.popup_open and descends_from(uic, POPUP) then
				if own_ancestor(uic, "^button_ok$") then
					UI.popup_confirmed()
				elseif own_ancestor(uic, "^button_cancel$") then
					UI.close_popup()
				end
				return
			end
			-- the confirmation
			if UI.confirm_open and descends_from(uic, CONFIRM) then
				if own_ancestor(uic, "^button_tick$") then
					UI.confirmed()
				elseif own_ancestor(uic, "^button_cancel$") then
					UI.close_confirm()
				end
				return
			end
			-- the presets dropdown, its list and the icon buttons
			if own_ancestor(uic, "^" .. BUTTON .. "$") then
				if find(PANEL, MENU) then UI.close_menu() else
					local cqi = current_cqi()
					if cqi then safe("open_menu", UI.open_menu, cqi) end
				end
				return
			end
			local opt = own_ancestor(uic, "^spa_opt_%d+$")
			if opt then safe("preset picked", UI.on_option, opt) return end
			local icon = own_ancestor(uic, "^spa_btn_%a+$")
			if icon then safe("icon", UI.on_icon, string.sub(icon, string.len(ICON_PREFIX) + 1)) return end
			UI.close_menu()
			-- skill cards (in plan mode: their shields), and the badges on them
			local card = card_ancestor(uic)
			if card then
				local sid = id_of(uic) or ""
				local on_shield = sid == SHIELD or string.match(sid, "^" .. PIP_SHIELD .. "%d$") ~= nil
				local tree = UI.shown_cqi and SPA.tree_cache[UI.shown_cqi]
				local key = card_skill(card, tree and tree.skills)   -- (the same skill UI.cards gives this card)
				if current_cqi() and key then
					UI.gather_click(key, (sid == BADGE and "badge") or (on_shield and "shield") or "lclick")
				end
				return
			end
			-- the skill reset buttons: that character's tree is read again when the panel closes. The panel's
			-- "Undo assigned skill points" drops the choices not confirmed yet: the plan follows a moment later
			-- (one built on top of such a choice is re-checked)
			if own_ancestor(uic, "^button_stats_reset") then
				local cqi = current_cqi()
				if cqi then
					UI.reset_clicked[cqi] = true
					if own_ancestor(uic, "^" .. UNDO_BUTTON .. "$") and SPA.has_unconfirmed(cqi) then
						SPA.pending_choices[cqi] = nil
						cm:real_callback(function()
							safe("choices undone", function()
								SPA.refresh_points(cqi)
								SPA.revalidate(cqi)
								UI.refresh()
							end)
						end, 200)
					end
				end
			end
			-- tab switches, character switches etc. rebuild the panel
			UI.refresh_soon()
		end, true)

	-- plan mode: the mouse over the tree (see UI.schedule_paint)
	core:add_listener("spa_mouse_on", "ComponentMouseOn",
		function() return UI.view_on and UI.panel_open and not UI.paint_off end,
		function() UI.schedule_paint() end, true)
end
