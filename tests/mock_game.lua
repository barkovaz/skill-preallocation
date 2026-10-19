-- A stand-in for the campaign environment, driven by the real baked data:
-- one local character whose skill tree comes from the database, a context system that answers
-- the queries the mod makes, and a UI tree shaped like the real skills panel.

local M = { listeners = {}, callbacks = {}, first_tick = {}, commands = {}, files = {} }

-- ---------------------------------------------------------------- character
function M.setup(live, R)
	M.R = R
	M.live = live
	M.points = live.points or 0
	M.rank = live.rank or 1
	M.levels = {}
	for _, s in ipairs(live.skills) do M.levels[s.key] = s.level or 0 end
	M.pending = {}
end

local function tree_now()
	local live = {}
	for k, v in pairs(M.live) do live[k] = v end
	live.rank, live.points = M.rank, M.points
	live.skills = {}
	for i, s in ipairs(M.live.skills) do
		local c = {}
		for k, v in pairs(s) do c[k] = v end
		c.level = M.levels[s.key]
		live.skills[i] = c
	end
	return M.R.build_tree(live)
end

local function status_of(key)
	local tree = tree_now()
	local s = tree.skills[key]
	local lv = M.levels[key]
	if lv >= s.total then return "maxed" end
	if M.points > 0 then
		local ok = M.R.check(tree, M.R.new_state(tree), key, M.rank)
		if ok then return lv > 0 and "complete" or "available" end
		-- a non-plannable but already owned skill
	end
	if lv > 0 then return "complete" end
	return "locked"
end

local char = {}
function char:command_queue_index() return 1 end
function char:cqi() return 1 end
function char:character_subtype_key() return M.live.subtype end
function char:character_type_key() return M.live.agent end
function char:character_type(t) return M.live.agent == t end
function char:rank() return M.rank end
function char:get_forename() return "names_name_1" end
function char:faction() return M.faction end
function char:is_wounded() return false end
function char:is_null_interface() return false end
function char:has_skill(k) return (M.levels[k] or 0) > 0 end
M.char = char

M.faction = {}
function M.faction:name() return M.live.faction ~= "" and M.live.faction or "wh_main_emp_empire" end
function M.faction:subculture() return M.live.subculture end
function M.faction:command_queue_index() return 77 end
function M.faction:is_null_interface() return false end
function M.faction:faction_leader() return char end
function M.faction:character_list() return { num_items = function() return 1 end, item_at = function() return char end } end

-- ---------------------------------------------------------------- context system
function M.get_context_value(t, id, expr)
	if t ~= "CcoCampaignCharacter" or tostring(id) ~= "1" then return nil end
	if expr == "LocLanguage" then M.lang_reads = (M.lang_reads or 0) + 1 return M.lang or "EN" end
	if expr == "SkillPointsAvailable" then return M.points - #M.pending end
	if expr == "Rank" then return M.rank end
	if expr == "SkillList.Size" then M.tree_reads = (M.tree_reads or 0) + 1 return #M.live.skills end
	if expr == "HiddenSkillList.Size" then return 0 end
	if expr == "HasUncommitedSkills" then return #M.pending > 0 end
	local i, field = string.match(expr, "^SkillList%.At%((%d+)%)%.(.+)$")
	if i then
		local s = M.live.skills[tonumber(i) + 1]
		if not s then return nil end
		if field == "Key" then return s.key end
		if field == "Name" then return "Name of " .. s.key end
		if field == "Level" then return M.levels[s.key] end
		if field == "TotalLevels" then return s.total end
		if field == "Tier" then return s.tier end
		if field == "Indent" then return s.indent end
		if field == "Status" then return status_of(s.key) end
		if field == "IsBackgroundSkill" then return s.background or false end
		if field == "LevelsDetailsList.Size" then return #s.ranks end
		local j = string.match(field, "^LevelsDetailsList%.At%((%d+)%)%.RankRequired$")
		if j then return s.ranks[tonumber(j) + 1] end
	end
	return nil
end

function M.call_context_command(t, id, expr)
	M.commands[#M.commands + 1] = expr
	local i = string.match(expr, "^SkillList%.At%((%d+)%)%.AddPoint$")
	if i then
		local s = M.live.skills[tonumber(i) + 1]
		if s and status_of(s.key) ~= "locked" and status_of(s.key) ~= "maxed" and M.points > #M.pending then
			M.pending[#M.pending + 1] = s.key
		end
	elseif expr == "CommitSkillChoices" then
		local committed = M.pending
		M.pending = {}
		for _, k in ipairs(committed) do
			M.levels[k] = M.levels[k] + 1
			M.points = M.points - 1
			M.queue_event("CharacterSkillPointAllocated", { character = function() return char end, skill_point_spent_on = function() return k end })
		end
	elseif expr == "ClearAllSkillChoices" then
		M.pending = {}
	elseif string.match(expr, "^SelectAndShowDetailsForCharacter%(this, \"skills\"%)$") then
		if M.panel_is_open then
			-- with the panel open: M.redraw_in_place = it is redrawn there; M.show_toggles = it closes
			if M.redraw_in_place then M.draw_counter() end
			if M.show_toggles then M.queue_event("PanelClosedCampaign", { string = "character_details_panel" }) end
		elseif not M.no_reopen then
			M.queue_event("PanelOpenedCampaign", { string = "character_details_panel" })
		end
	end
end

-- The game's add_skill: checks the rules at the current rank, uses one point and fires the
-- allocation event inside the call (as the game does). M.refuse_add_skill = true: every call refused.
M.add_skill_calls = {}
function M.add_skill(char_or_str, key, ignore_requirements, ignore_points)
	M.add_skill_calls[#M.add_skill_calls + 1] = key
	if M.refuse_add_skill then return end
	local tree = tree_now()
	if not ignore_points and M.points <= 0 then return end
	if not ignore_requirements and not M.R.check(tree, M.R.new_state(tree), key, M.rank) then return end
	M.levels[key] = M.levels[key] + 1
	if not ignore_points then M.points = M.points - 1 end
	M.fire("CharacterSkillPointAllocated", { character = function() return char end, skill_point_spent_on = function() return key end })
end

-- What the skills panel itself does on a click with free points: the choice waits (not applied yet),
-- the free points shown go down, the skill's level does not change until the panel closes.
function M.vanilla_click(key)
	local tree = tree_now()
	local st = M.R.new_state(tree)
	for _, k in ipairs(M.pending) do st.levels[k] = (st.levels[k] or 0) + 1 end
	if M.points - #M.pending > 0 and M.R.check(tree, st, key, M.rank) then
		M.pending[#M.pending + 1] = key
	end
end

function M.commit_pending()
	local committed = M.pending
	M.pending = {}
	for _, k in ipairs(committed) do
		M.levels[k] = M.levels[k] + 1
		M.points = M.points - 1
		M.queue_event("CharacterSkillPointAllocated", { character = function() return char end, skill_point_spent_on = function() return k end })
	end
end

function M.level_up(n)
	for _ = 1, n do
		M.rank = M.rank + 1
		M.points = M.points + 1
		M.queue_event("CharacterSkillPointAvailable", { character = function() return char end })
	end
	M.queue_event("CharacterRankUp", { character = function() return char end, ranks_gained = function() return n end })
end

-- ---------------------------------------------------------------- UI
local mt = {}
mt.__index = mt
local function new(id, parent)
	local u = setmetatable({ id = id, parent = parent, children = {}, state = "active", ctx = {}, text = "", visible = true, x = 0, y = 0, w = 100, h = 30 }, mt)
	if parent then parent.children[#parent.children + 1] = u end
	return u
end
M.new_uic = new
-- Where a component a script adds to a parent (CreateComponent, CopyComponent, Adopt) goes among its
-- siblings isn't documented; CA's scripts re-adopt a component after PropagatePriority to move it, so
-- PropagatePriority alone doesn't. M.order_mode picks one of two ways (the mod must work with both):
--  "priority" (default) by its priority at that moment, after those with the same or a lower one
--  "append"   last
-- Siblings are drawn in that order, so the mouse finds the last one that takes it.
M.order_mode = os.getenv("SPA_ORDER_MODE") or "priority"
local function insert_sorted(parent, u)
	u.parent = parent
	local at = #parent.children + 1
	if M.order_mode == "append" then parent.children[at] = u return end
	for i = #parent.children, 1, -1 do
		if parent.children[i]:Priority() <= u:Priority() then break end
		at = i
	end
	table.insert(parent.children, at, u)
end
local function index_of(parent, u)
	for i, c in ipairs(parent.children) do if c == u then return i end end
	return nil
end
M.index_of = index_of
-- A text that doesn't fit its box is shrunk (dy_skill's text_clip_behaviour), to the box it is set in:
-- resizing the box later doesn't change it, nor does setting the same text again (in game, a badge whose
-- text is set before its resize keeps that size through the refreshes after). Its width in the
-- layout's units: 7 a character, 4 a space; colour tags take none.
local function text_width(t)
	local shown = string.gsub(t or "", "%[%[.-%]%]", "")
	local w = 0
	for ch in string.gmatch(shown, ".") do w = w + (ch == " " and 4 or 7) end
	return w
end
function mt:Id() return self.id end
function mt:Parent() return self.parent end
function mt:Address() return self end
function mt:ChildCount() return #self.children end
function mt:Find(x)
	if type(x) == "number" then return self.children[x + 1] end
	for _, c in ipairs(self.children) do if c.id == x then return c end end
end
function mt:CurrentState() return self.state end
function mt:SetState(s) self.state = s end
function mt:Visible() return self.visible end
function mt:SetVisible(v) self.visible = v end
function mt:Position() return self.x, self.y end
function mt:Dimensions() return self.w, self.h end
-- sizes and docking offsets are in the layout's units: screen pixels / the game's UI scale (M.scale)
M.scale = 1
function mt:Resize(w, h) self.w, self.h = w * M.scale, h * M.scale end
function mt:MoveTo(x, y) self.x, self.y = x, y end
function mt:GetContextObjectId(t) return self.ctx[t] end
function mt:SetText(t)
	if t == self.text then return end
	self.text = t
	if self.shrink_text then self.shrunk = text_width(t) > self.w / M.scale + 0.001 end
end
function mt:SetStateText(t) self.text = t end
function mt:GetStateText() return self.text end
function mt:SetTooltipText(t) self.tooltip = t end
function mt:Destroy()
	if self.parent then
		for i, c in ipairs(self.parent.children) do if c == self then table.remove(self.parent.children, i) break end end
		self.parent = nil
	end
	self.destroyed = true
end
function mt:Adopt(addr)
	if addr.parent then
		for i, c in ipairs(addr.parent.children) do if c == addr then table.remove(addr.parent.children, i) break end end
	end
	insert_sorted(self, addr)
	M.adopted = (M.adopted or 0) + 1
end
-- a copy of a component, next to it (with its priority, size, state, text and text behaviour)
function mt:CopyComponent(name)
	local c = new(name)
	c.text, c.state, c.priority, c.w, c.h, c.shrink_text = self.text, self.state, self:Priority(), self.w, self.h, self.shrink_text
	insert_sorted(self.parent, c)
	return c
end
local TEMPLATES = {
	["ui/templates/square_medium_text_button"] = { "button_txt" },
	["ui/templates/round_small_button"] = {},
	["ui/campaign ui/script_dummy"] = {},
	["ui/common ui/popup_text_input"] = { "text_input_list_parent/text_input", "panel_title/heading_txt", "ok_cancel_buttongroup/button_ok", "ok_cancel_buttongroup/button_cancel" },
	["ui/common ui/dialogue_box"] = { "DY_text", "both_group/button_tick", "both_group/button_cancel", "ok_group/button_tick", "purchase_options" },
}
-- The mod's own layout for plan mode's shield (ui/skill_preallocation/spa_shield), read from the mod's
-- file: its components (id, hidden or not, priority, size, docking offset) and their nesting below root.
M.SHIELD_LAYOUT = "ui/skill_preallocation/spa_shield"
M.shield_layout_file = "../../src/ui/skill_preallocation/spa_shield.twui.xml"
local function read_shield_layout()
	local f = io.open(M.shield_layout_file, "rb")
	if not f then error("mock: no shield layout at " .. M.shield_layout_file) end
	local text = f:read("*a")
	f:close()
	local hier = string.match(text, "<hierarchy>(.-)</hierarchy>")
	local comps = {}
	for tag, body in string.gmatch(text, "\r\n\t\t<([%w_]+)\r\n(.-)</%1>") do
		local function attr(n) return string.match(body, "\t\t\t" .. n .. '="([^"]*)"') end
		local dx, dy = string.match(attr("dock_offset") or "0,0", "^([%-%d%.]+),([%-%d%.]+)$")
		comps[tag] = { visible = attr("visible") ~= "false", priority = tonumber(attr("priority")),
			w = tonumber(string.match(body, 'width="([%d%.]+)"')), h = tonumber(string.match(body, 'height="([%d%.]+)"')),
			dx = tonumber(dx) or 0, dy = tonumber(dy) or 0,
			interactive = string.find(body, 'interactive="true"', 1, true) ~= nil }
	end
	-- the nesting: the tags in the hierarchy block, in order, with their depth
	local nodes = {}
	for indent, tag in string.gmatch(hier, "\n(\t*)<([%w_]+) this=") do nodes[#nodes + 1] = { depth = #indent, tag = tag } end
	return comps, nodes
end
-- Made like the game makes a layout with CreateComponent: the layout's root's child, named `name`, with
-- what is below it; docked at its parent's top left by the layout's offset. A component a script makes
-- gets no context object (the script gives it one).
local function make_from_layout(parent, name)
	local comps, nodes = read_shield_layout()
	local made, stack = nil, {}
	for _, n in ipairs(nodes) do
		if n.tag ~= "root" then
			local c = comps[n.tag]
			local depth = n.depth
			while #stack > 0 and stack[#stack].depth >= depth do table.remove(stack) end
			local at = #stack > 0 and stack[#stack].uic or parent
			local u = new(made and n.tag or name, made and at or nil)
			u.visible, u.priority, u.interactive = c.visible, c.priority, c.interactive
			if not made then insert_sorted(at, u) end
			u.w, u.h = (c.w or 100) * M.scale, (c.h or 30) * M.scale
			u.dock, u.dock_x, u.dock_y = 1, c.dx, c.dy
			u.x, u.y = at.x + c.dx * M.scale, at.y + c.dy * M.scale
			made = made or u
			stack[#stack + 1] = { depth = depth, uic = u }
		end
	end
	return made
end

-- A component made inside another one has its context objects (M.no_context_inherit: it hasn't; one made
-- from the mod's shield layout never has); M.fail_create = a layout path that can't be made.
function mt:CreateComponent(name, path)
	local norm = string.gsub(string.lower(path), "%.twui%.xml$", "")
	if M.fail_create == norm then return nil end
	if norm == M.SHIELD_LAYOUT then
		if M.other_calls then return nil end                -- (as in game after such a call, see call)
		M.created = M.created or {}
		M.created[#M.created + 1] = norm
		return make_from_layout(self, name)
	end
	local c = new(name)
	insert_sorted(self, c)
	if not M.no_context_inherit then for k, v in pairs(self.ctx) do c.ctx[k] = v end end
	M.created = M.created or {}
	M.created[#M.created + 1] = norm
	for _, p in ipairs(TEMPLATES[norm] or {}) do
		local cur = c
		for part in string.gmatch(p, "[^/]+") do
			cur = cur:Find(part) or new(part, cur)
		end
	end
	return c
end
function mt:PropagatePriority(p)
	local old = self.priority
	local function set(u) u.priority = p for _, c in ipairs(u.children) do set(c) end end
	set(self)
	return old
end
-- Context objects: { type, id, Call = function(o, expr) }. Call knows "Key" (a skill context's id is
-- "skill:<key>"). Any other expression is recorded in M.other_calls and gives nil: the script must never
-- evaluate one (in game, a script's :Call of Format(Loc(..)) on a skill broke the interface: no component
-- could be made after it, the panel's character couldn't be read, and closing or switching the panel then
-- crashed the game). After one, the mod's shields can't be made here either.
-- M.no_context_objects: GetContextObject isn't there (the script then tries the game's cco, see install).
local context_object
local function call(o, expr)
	if expr == "Key" then return (string.gsub(tostring(o.id), "^%a+:", "")) end
	M.other_calls = M.other_calls or {}
	M.other_calls[#M.other_calls + 1] = expr
	return nil
end
context_object = function(t, id) return { type = t, id = id, Call = call } end
M.context_object = context_object
function mt:GetContextObject(t)
	if M.no_context_objects then error("no GetContextObject") end
	return self.ctx[t] and context_object(t, self.ctx[t]) or nil
end
function mt:SetContextObject(o) self.ctx[o.type] = o.id end
function mt:LockPriority() M.locks = (M.locks or 0) + 1 end
function mt:UnLockPriority() M.locks = (M.locks or 0) - 1 end
-- docking at the parent's top left (point 1) places the component there + the offset; other points only
-- record the offset
function mt:SetDockingPoint(p) self.dock = p end
function mt:SetDockOffset(x, y)
	self.dock_x, self.dock_y = x, y
	if self.dock == 1 and self.parent then self.x, self.y = self.parent.x + x * M.scale, self.parent.y + y * M.scale end
end
function mt:SetInteractive(v) self.interactive = v end
-- a component's own properties (the game's layouts read them with self.GetProperty)
function mt:SetProperty(name, value) self.props = self.props or {} self.props[name] = value end
function mt:GetProperty(name) return self.props and self.props[name] or "" end
-- How the game's disabled flag behaves is not documented, so M.disable_mode picks one of three ways
-- (the mod must work with each; a component takes no clicks while flagged or in its "inactive" state):
--  "flag"  (default, the strictest): SetDisabled sets a flag only, the look stays; IsDisabled reports
--          the look (the inactive state), so it never sees a flag set by script
--  "state" SetDisabled(true) also switches to "inactive"; SetDisabled(false) only clears the flag
--  "both"  SetDisabled switches the flag and the look together; IsDisabled reports the flag
M.disable_mode = os.getenv("SPA_DISABLE_MODE") or "flag"
function mt:SetDisabled(v)
	self.disabled = v and true or nil
	if M.disable_mode == "both" then self.state = v and "inactive" or "active"
	elseif M.disable_mode == "state" and v then self.state = "inactive" end
end
function mt:IsDisabled()
	if M.disable_mode == "flag" then return self.state == "inactive" end
	return self.disabled == true
end
function mt:SetImagePath(path, i) self.images = self.images or {}; self.images[i or 0] = path end
M.simulated = {}                                            -- ids of components clicked by the script
function mt:SimulateLClick()
	M.simulated[#M.simulated + 1] = self.id
	if self.id == "button_ok" and not M.ok_button_stuck then        -- the panel's close button
		M.commit_pending()
		M.queue_event("PanelClosedCampaign", { string = "character_details_panel" })
	elseif self.id == "button_stats_reset" and not M.undo_stuck then -- "Undo assigned skill points"
		M.drop_pending()
	end
end
function mt:Priority() return self.priority or (self.id == "card" and 20) or 50 end
for _, f in ipairs({ "SetCanResizeWidth", "SetCanResizeHeight",
	"SetTextHAlign", "SetTextVAlign", "RegisterTopMost",
	"StealInputFocus" }) do
	mt[f] = function() end
end

function M.build_ui()
	M.root = new("root")
	local panel = new("character_details_panel", M.root)
	new("panel_frame_wh3", panel).priority = 60
	local ctxp = new("character_context_parent", panel)
	ctxp.ctx.CcoCampaignCharacter = "1"
	new("button_ok", new("button_bottom_holder", ctxp))       -- the panel's own close button
	local pts = new("skill_pts_holder", ctxp)                 -- the skill points counter (top right)
	pts.x, pts.y, pts.w, pts.h = 2040, 95, 84, 38
	M.counter = new("dy_pts", new("skill_pts", pts))
	local reset = new("button_stats_reset", pts)
	reset.x, reset.y = 2048, 95
	local reset_all = new("button_stats_reset_all", pts)
	reset_all.x, reset_all.y = 2086, 95
	local subtitle = new("panel_subtitle", new("character_name", ctxp))
	new("dy_subtype", subtitle).text = "Lord"
	local tab_group = new("TabGroup", ctxp)                    -- the panel's tabs
	new("spacer", tab_group).visible = false
	new("details", tab_group)
	new("skills", tab_group)
	local tabs = new("tab_panels", ctxp)
	local sub = new("skills_subpanel", tabs)
	sub.x, sub.y, sub.w, sub.h = 320, 148, 1270, 700         -- the skill tree, under the top bar
	local skills = new("character_details_panel_skills", sub)
	local search = new("skill_search", skills)
	search.x, search.y, search.w, search.h = 100, 900, 250, 30
	local lv = new("listview", skills)
	local lb = new("list_box", new("list_clip", lv))
	M.cards = {}
	local chains = {}
	for _, s in ipairs(M.live.skills) do
		local ci = s.tier or 0
		chains[ci] = chains[ci] or new("chain", new("chain" .. ci, lb))
		local entry = new(s.key, chains[ci])
		local card = new("card", entry)              -- the parts of the game's card (185x67, pips on its right)
		card.ctx.CcoCampaignCharacterSkill = "skill:" .. s.key
		card.x, card.y, card.w, card.h = 340 + (s.indent or 0) * 200, 200 + ci * 80, 185 * M.scale, 67 * M.scale
		new("particle_emitter", card).priority = 20
		new("icon_check", card).priority = 20
		local ti = new("type_icon", card)
		ti.visible, ti.priority = false, 20
		local dy = new("dy_skill", card)
		dy.priority, dy.w, dy.h, dy.shrink_text = 20, 112 * M.scale, 44 * M.scale, true
		local lp = new("level_parent", card)
		lp.priority = 20
		lp.x, lp.y, lp.w, lp.h = card.x + 169 * M.scale, card.y + 4 * M.scale, 16 * M.scale, 52 * M.scale
		for i = 1, 3 do
			local pip = new("level" .. i, lp)
			pip.x, pip.y, pip.w, pip.h = lp.x, lp.y + (i - 1) * 16 * M.scale, 16 * M.scale, 20 * M.scale
		end
		if M.old_layout then M.add_shield(card) end
		M.cards[s.key] = card
	end
	M.panel = panel
	M.draw_cards()
end

-- M.old_layout: the cards already have a shield, as with the original mod's copy of the skills panel layout
-- also enabled (the shield with its pips' shields in a column).
function M.add_shield(card)
	local sh = new("spa_shield", card)
	sh.visible, sh.priority = false, 21
	local col = new("spa_pip_column", sh)
	col.priority = 22
	for i = 1, 3 do
		local ps = new("spa_pip_shield" .. i, col)
		ps.visible, ps.priority = false, 22
	end
	return sh
end

-- Whether `a` lies exactly over `b` (position and size).
function M.covers(a, b)
	return a ~= nil and b ~= nil and a.x == b.x and a.y == b.y and a.w == b.w and a.h == b.h
end

-- What the mouse hits over a card's level pip `i`, as the game draws it (a child above its parent): the
-- pip's shield when it is shown over the pip, else the card's shield, else the pip.
function M.hit_pip(card, i)
	local sh = card:Find("spa_shield")
	local pip = card:Find("level_parent"):Find("level" .. i)
	if sh and sh.visible then
		local ps = sh:Find("spa_pip_shield" .. i)
		if ps and ps.visible and M.covers(ps, pip) then return ps end
		return sh
	end
	return pip
end

-- The game drawing the skill cards from the character (when the panel opens): the card's look, its
-- name's, its level pips' (one per level), the learned tick, the sparkles of a skill that can be taken.
function M.draw_cards()
	if not M.cards then return end
	local tree = tree_now()
	local st = M.R.new_state(tree)
	for key, card in pairs(M.cards) do
		local s = tree.skills[key]
		local lv, total = M.levels[key] or 0, s.total or 1
		local look
		if lv >= total then look = "maxed"
		elseif M.points > 0 and M.R.check(tree, st, key, M.rank) then look = lv > 0 and "complete" or "available"
		elseif lv > 0 then look = "complete"
		elseif s.auto then look = "locked_auto_unlock"
		else look = "locked" end
		card.state = look
		card:Find("dy_skill").state = (look == "locked" or look == "locked_auto_unlock") and look or "active"
		local lp = card:Find("level_parent")
		for i = 1, 3 do
			local pip = lp:Find("level" .. i)
			pip.visible = i <= total
			pip.state = (i <= lv and "active") or (look == "locked" and "locked") or "inactive"
		end
		card:Find("icon_check").visible = lv > 0
		card:Find("particle_emitter").visible = look == "available"
	end
end

local function find_in(u, id)
	if u.id == id then return u end
	for _, c in ipairs(u.children) do
		local r = find_in(c, id)
		if r then return r end
	end
end

function M.find_uicomponent(start, ...)
	local cur = start
	for _, id in ipairs({ ... }) do
		if type(id) ~= "string" then return nil end
		cur = cur and find_in(cur, id)
	end
	return cur
end

-- ---------------------------------------------------------------- events and globals
M.queued = {}
function M.queue_event(name, ctx) M.queued[#M.queued + 1] = { name, ctx } end

-- The panel's skill points counter: drawn when the panel opens, not after a script spends points.
function M.draw_counter() if M.counter then M.counter.text = tostring(M.points - #M.pending) end end

function M.fire(event, context)
	if event == "PanelOpenedCampaign" then M.panel_is_open = true; M.draw_counter(); M.draw_cards()
	elseif event == "PanelClosedCampaign" then M.panel_is_open = false end
	for _, l in ipairs({ unpack(M.listeners) }) do
		if l.event == event then
			local ok = l.cond == true or (type(l.cond) == "function" and l.cond(context))
			if ok then l.fn(context) end
		end
	end
end

-- A virtual clock: callbacks run in the order of their due time; events run as soon as queued.
M.now = 0
M.timers = {}
local timer_seq = 0
function M.add_timer(fn, ms, name, interval)
	timer_seq = timer_seq + 1
	M.timers[#M.timers + 1] = { due = M.now + (ms or 0), seq = timer_seq, fn = fn, name = name, interval = interval }
end

function M.remove_timers(name)
	for i = #M.timers, 1, -1 do
		if M.timers[i].name == name then table.remove(M.timers, i) end
	end
end

local function next_timer(limit, one_shots_only)
	local best, best_i
	for i, tm in ipairs(M.timers) do
		if (not one_shots_only or not tm.interval) and tm.due <= limit then
			if not best or tm.due < best.due or (tm.due == best.due and tm.seq < best.seq) then best, best_i = tm, i end
		end
	end
	return best, best_i
end

local function run_timer(tm, i)
	table.remove(M.timers, i)
	if tm.due > M.now then M.now = tm.due end
	if tm.interval then M.add_timer(tm.fn, tm.interval, tm.name, tm.interval) end
	tm.fn()
end

-- Run events and callbacks until no one-shot callback is left (repeating ones run when due on the way).
function M.drain()
	for _ = 1, 20000 do
		if #M.queued > 0 then
			local e = table.remove(M.queued, 1)
			M.fire(e[1], e[2])
		else
			local last = next_timer(math.huge, true)
			if not last then return end
			local tm, i = next_timer(last.due, false)
			run_timer(tm, i)
		end
	end
	error("mock: drain did not settle")
end

-- Let `ms` of time pass, running only what becomes due.
function M.advance(ms)
	local limit = M.now + ms
	for _ = 1, 20000 do
		if #M.queued > 0 then
			local e = table.remove(M.queued, 1)
			M.fire(e[1], e[2])
		else
			local tm, i = next_timer(limit, false)
			if not tm then break end
			run_timer(tm, i)
		end
	end
	M.now = limit
end

-- Let `ms` of time pass, then run everything still waiting.
function M.tick(ms)
	M.advance(ms)
	M.drain()
end

-- A left click. One on a badge lands on it when it takes clicks and, with the card's shield shown, comes
-- after the shield among the card's parts (drawn above it); otherwise it lands on what is under it: the
-- shield shown over the card (plan mode: the shield takes the mouse), else the card (the badge's parent). On the card itself the game's own click
-- happens first (with free points it holds the choice); then the script's event, ComponentLClickUp. The
-- panel's "Undo assigned skill points" button drops the choices held.
M.native = { version = "1.1.0", api = 1, platform = "mock" }
function M.click(uic)
	if uic.id == "spa_badge" then
		local card = uic.parent
		local shield = card:Find("spa_shield")
		local under = (shield and shield.visible) and shield or card
		if not uic.interactive or (under ~= card and index_of(card, uic) < index_of(card, under)) then uic = under end
	end
	if uic.id == "card" then
		local shield = uic:Find("spa_shield")
		if shield and shield.visible then uic = shield end
	end
	-- like the game: a disabled button (or its text) takes no clicks, nor does one in its inactive state
	local cur = uic
	for _ = 1, 2 do
		if not cur then break end
		if cur.disabled or cur.state == "inactive" then return end
		cur = cur.parent
	end
	local card = (uic.id == "card" and uic) or (uic.id == "spa_shield" and uic.parent) or (uic.id == "spa_badge" and uic.parent)
		or (string.match(uic.id, "^spa_pip_shield%d$") and (uic.parent.id == "spa_shield" and uic.parent.parent or uic.parent.parent.parent))
		or (string.match(uic.id, "^level%d$") and uic.parent.parent) or nil
	-- a click on the card or one of its pips is the game's own (a choice with free points)
	if card and (uic.id == "card" or string.match(uic.id, "^level%d$")) and M.points - #M.pending > 0 then M.vanilla_click(card.parent.id) end
	if uic.id == "button_stats_reset" and not M.undo_stuck then M.drop_pending() end
	M.fire("ComponentLClickUp", { component = uic, string = uic.id })
	M.drain()
end

-- The mouse moving onto a component.
function M.mouse_on(uic)
	M.fire("ComponentMouseOn", { component = uic, string = uic.id })
end

function M.drop_pending() M.pending = {} end

function M.close_panel(drop)
	if drop then M.drop_pending() else M.commit_pending() end
	M.fire("PanelClosedCampaign", { string = "character_details_panel" })
	M.drain(); M.drain()
end

function M.install()
	M.multiplayer = false
	-- like the game: string.find searches plain text only (no patterns)
	local plain_find = string.find
	string.find = function(s, sub, init) return plain_find(s, sub, init, true) end
	common = {
		get_context_value = M.get_context_value,
		call_context_command = M.call_context_command,
		get_localised_string = function(k) return k end,
	}
	core = {
		add_listener = function(_, name, event, cond, fn, persist)
			M.listeners[#M.listeners + 1] = { name = name, event = event, cond = cond, fn = fn }
		end,
		remove_listener = function(_, name)
			for i = #M.listeners, 1, -1 do if M.listeners[i].name == name then table.remove(M.listeners, i) end end
		end,
		get_ui_root = function() return M.root end,
		get_screen_resolution = function() return M.screen_w or 2560, 1440 end,
	}
	cm = {
		add_first_tick_callback = function(_, fn) M.first_tick[#M.first_tick + 1] = fn end,
		callback = function(_, fn, s, name) M.add_timer(fn, (s or 0) * 1000, name) end,
		real_callback = function(_, fn, ms, name) M.add_timer(fn, ms or 0, name) end,
		repeat_real_callback = function(_, fn, ms, name) M.add_timer(fn, ms, name, ms) end,
		remove_real_callback = function(_, name) M.remove_timers(name) end,
		get_local_faction = function() return M.faction end,
		get_local_faction_name = function() return M.faction:name() end,
		model = function() return { turn_number = function() return 1 end, campaign_name_key = function() return M.live.campaign end } end,
		is_multiplayer = function() return M.multiplayer end,
		get_character_by_cqi = function(_, cqi) if cqi == 1 then return char end end,
		char_lookup_str = function() return "character_cqi:1" end,
		add_saving_game_callback = function(_, fn) M.save_cb = fn end,
		add_loading_game_callback = function(_, fn) M.load_cb = fn end,
		save_named_value = function(_, name, value) M.saved = M.saved or {}; M.saved[name] = value end,
		load_named_value = function(_, name, default) return (M.saved and M.saved[name]) or default end,
		game_interface = {
			level_up_agent_rank = function(_, s, n) M.level_up(n) end,
			add_skill = function(_, c, key, a, b) M.add_skill(c, key, a, b) end,
		},
	}
	CampaignUI = { TriggerCampaignScriptEvent = function(cqi, s)
		M.sent = M.sent or {}
		M.sent[#M.sent + 1] = s
		if M.multiplayer then
			M.queue_event("UITrigger", { trigger = function() return s end, faction_cqi = function() return cqi end })
		end
	end }
	find_uicomponent = M.find_uicomponent
	cco = function(t, id) return context_object(t, id) end     -- the game's context object maker
	UIComponent = function(addr) return addr end
	out = function() end
end

return M
