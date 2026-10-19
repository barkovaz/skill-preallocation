-- Offline tests for the rules engine, using the real baked data.
-- Run from the project root:  lua5.1 tests/test_rules.lua
dofile("src/script/campaign/mod/skill_preallocation_data.lua")
dofile("src/script/campaign/mod/skill_preallocation_rules.lua")
local R = SKILL_PREALLOCATION_RULES
local FIX = dofile("tests/skill_fixture.lua")
local D = SKILL_PREALLOCATION_DATA

-- SPA_RULES_SOURCE=live (with SPA_GAME_DATA = the game's data folder, after generator/build_native.py
-- --test): the same tests on the live data, read from db.pack through the native module
if os.getenv("SPA_RULES_SOURCE") == "live" then
	package.cpath = "build/test/?.so;" .. package.cpath
	dofile("src/script/campaign/mod/skill_preallocation_live.lua")
	local N = require("skill_preallocation_native")
	local res = assert(N.load_db({ packs = { assert(os.getenv("SPA_GAME_DATA"), "SPA_GAME_DATA") .. "/db.pack" },
		tables = SKILL_PREALLOCATION_LIVE.TABLES }))
	R.use_source(assert(SKILL_PREALLOCATION_LIVE.build(res)))
	D = R.data()
	print("rules tests on the live data " .. D.version)
end

local passed, failed = 0, 0
local function check(cond, msg)
	if cond then passed = passed + 1 else failed = failed + 1; print("FAIL: " .. msg) end
end

-- Build a "live" character from the baked data, the way the game would show it.
local function make_live(subtype, opts)
	opts = opts or {}
	local set_key = R.pick_set(subtype, opts.agent or "general", opts.faction or "", opts.subculture or "", opts.campaign or "wh3_main_combi")
	assert(set_key, "no set for " .. subtype)
	local set = R.decode_set(set_key)
	local live = {
		cqi = 1, subtype = subtype, agent = opts.agent or D.sets[set_key].agent, faction = opts.faction or "",
		subculture = opts.subculture or "", campaign = opts.campaign or "wh3_main_combi",
		rank = opts.rank or 1, points = opts.points or 0, skills = {}, hidden = {},
	}
	if live.agent == "" then live.agent = "general" end
	local seen = {}
	for _, n in ipairs(set.nodes) do
		local match = (n.faction == "" or n.faction == live.faction) and (n.subculture == "" or n.subculture == live.subculture)
			and (n.campaign == "" or n.campaign == live.campaign)
		if match and not seen[n.skill] then
			seen[n.skill] = true
			local f = FIX[n.skill] or { total = 1, ranks = { 0 }, bg = false }
			if n.visible then
				local lv = (opts.levels and opts.levels[n.skill]) or n.poc
				live.skills[#live.skills + 1] = { key = n.skill, level = lv, total = f.total, tier = n.tier, indent = n.indent,
					ranks = f.ranks, background = f.bg }
			else
				live.hidden[n.skill] = n.poc
			end
		end
	end
	return live, set_key
end

---------------------------------------------------------------- 1. ranks and capacity
do
	local live = make_live("wh_main_emp_lord", { faction = "wh_main_emp_empire", subculture = "wh_main_sc_emp_empire" })
	local tree = R.build_tree(live)
	check(tree.known, "empire lord tree known")
	local fut, cap = R.future_points(tree)
	check(fut == 49 and cap == 50, "rank 1 general in IE: 49 future points, cap 50 (got " .. fut .. ", " .. cap .. ")")
	check(R.slot_rank(tree, 1) == 2, "slot 1 at rank 2")
	check(R.slot_rank(tree, 49) == 50, "slot 49 at rank 50")
	check(R.slot_rank(tree, 50) == nil, "slot 50 does not exist")
	tree.points = 2
	check(R.slot_rank(tree, 2) == 1 and R.slot_rank(tree, 3) == 2, "free points are spent at the current rank")
	local live_p = make_live("wh_main_emp_lord", { campaign = "wh3_main_prologue" })
	local fut_p, cap_p = R.future_points(R.build_tree(live_p))
	check(cap_p == 41, "prologue general cap 41 (got " .. cap_p .. ")")
	local live_h = make_live("wh_main_emp_bright_wizard", { agent = "wizard", rank = 10 })
	local th = R.build_tree(live_h)
	local fh, ch = R.future_points(th)
	check(fh == 40 and ch == 50, "rank 10 wizard: 40 future points (got " .. fh .. ")")
end

---------------------------------------------------------------- 2. greedy valid plans for every skill tree
-- A random valid plan: each pick is one of the points R.check allows at the rank the next point comes at
-- (strict order: no point ever waits). R.can_append must accept every pick.
local appended_ok, appended_bad = 0, 0
local function greedy_plan(tree, seed)
	local plan = {}
	-- (a small generator whose numbers stay exact in the game's 32-bit float Lua: lua5.1f)
	local rng = seed % 30268 + 1
	local function rnd(n) rng = (rng * 171) % 30269; return (rng % n) + 1 end
	for _ = 1, R.capacity(tree) do
		local _, st, prev, arrivals = R.simulate(tree, plan, 1)
		local arrive = arrivals[#plan + 1]
		if arrive and prev > arrive then arrive = prev end
		local cands = {}
		for _, key in ipairs(tree.order) do
			if R.check(tree, st, key, arrive) then cands[#cands + 1] = key end
		end
		if #cands == 0 then break end
		local pick = cands[rnd(#cands)]
		if R.can_append(tree, plan, pick) then appended_ok = appended_ok + 1 else appended_bad = appended_bad + 1 end
		plan[#plan + 1] = pick
	end
	return plan
end

local trees_tested, plans_len, unknown_trees, unplannable = 0, 0, 0, 0
local subtypes = {}
for key, s in pairs(D.sets) do
	if s.subtype ~= "" then subtypes[#subtypes + 1] = { s.subtype, key, s.agent, s.faction, s.subculture } end
end
table.sort(subtypes, function(a, b) return a[2] < b[2] end)
for i, st in ipairs(subtypes) do
	local live = make_live(st[1], { agent = st[3], faction = st[4], subculture = st[5] })
	local tree = R.build_tree(live)
	if not tree.known then unknown_trees = unknown_trees + 1 end
	local plan = greedy_plan(tree, i)
	trees_tested = trees_tested + 1
	plans_len = plans_len + #plan
	if #plan == 0 then unplannable = unplannable + 1 end
	-- every point is learned as soon as it comes (strict order, nothing waits)
	local ranks, _, _, arrivals = R.simulate(tree, plan)
	local in_time = true
	for j = 1, #plan do if not ranks[j] or ranks[j] ~= arrivals[j] then in_time = false end end
	check(in_time, "every point of the greedy plan is learned as soon as it comes for " .. st[2])
	-- the plan must replay to itself
	local res = R.replay(tree, plan)
	local same = #res.plan == #plan and #res.dropped == 0
	for j = 1, #plan do if res.plan[j] ~= plan[j] then same = false end end
	check(same, "plan replays unchanged for " .. st[2])
	-- a full build replayed on a fresh character gives the same plan
	local seq = R.full_sequence(tree, {}, plan)
	local res2 = R.replay(tree, seq, { full_build = true })
	check(#res2.plan == #plan and #res2.dropped == 0, "full build round-trip for " .. st[2] .. " (" .. #res2.plan .. " vs " .. #plan .. ", dropped " .. #res2.dropped .. ")")
end
print(string.format("greedy plans: %d trees, avg %.1f points, %d trees unknown, %d with nothing plannable",
	trees_tested, plans_len / trees_tested, unknown_trees, unplannable))
check(appended_bad == 0 and appended_ok > 20000, "R.can_append agrees with every pick (" .. appended_ok .. " ok, " .. appended_bad .. " refused)")

---------------------------------------------------------------- 3. Tomb Prince: line variants
do
	local live = make_live("wh2_dlc09_tmb_tomb_prince", { agent = "general", subculture = "wh2_dlc09_sc_tmb_tomb_kings", rank = 9 })
	local tree = R.build_tree(live)
	local function key_of(suffix)
		for _, k in ipairs(tree.order) do if k:sub(-#suffix) == suffix then return k end end
	end
	local cultist, heir, lieutenant = key_of("tomb_prince_0"), key_of("tomb_prince_1"), key_of("tomb_prince_2")
	local dunes, dynasty, herald = key_of("tomb_prince_3"), key_of("tomb_prince_4"), key_of("tomb_prince_5")
	check(cultist and dunes and dynasty, "tomb prince unique skills found")
	if cultist and dunes then
		-- both line heads can start a plan, but not together
		check(R.can_append(tree, {}, cultist), "cultist prince can be planned")
		check(not R.can_append(tree, { cultist }, dunes), "prince of the dunes is blocked after cultist prince")
		-- a preset that went the Cultist line, applied to a prince who took Prince of the Dunes
		local live2 = make_live("wh2_dlc09_tmb_tomb_prince", { agent = "general", subculture = "wh2_dlc09_sc_tmb_tomb_kings", rank = 10,
			levels = { [dunes] = 1 } })
		local tree2 = R.build_tree(live2)
		local preset = { cultist, heir, lieutenant }
		local res = R.replay(tree2, preset, { full_build = true })
		local got = table.concat(res.plan, ",")
		check(res.plan[1] == dynasty and res.plan[2] == herald, "cultist line mapped onto dunes line: " .. got)
		check(#res.dropped == 0, "nothing dropped in the line remap")
	end
end

---------------------------------------------------------------- 4. clique variants (necrotect)
do
	local opts = { agent = "engineer", subculture = "wh2_dlc09_sc_tmb_tomb_kings", rank = 14 }
	local tree = R.build_tree(make_live("wh2_dlc09_tmb_necrotect", opts))
	local masters, constructor = {}, nil
	for _, k in ipairs(tree.order) do
		if tree.skills[k].variant then masters[#masters + 1] = k end
		if k:find("master_constructor") then constructor = k end
	end
	table.sort(masters)
	check(#masters == 3 and constructor, "necrotect has 3 sphinx/titan variants (" .. #masters .. ")")
	if #masters >= 2 and constructor then
		local a, b = masters[1], masters[2]
		opts.levels = { [constructor] = 1, [b] = 1 }
		local tree2 = R.build_tree(make_live("wh2_dlc09_tmb_necrotect", opts))
		local res = R.replay(tree2, { constructor, a }, { full_build = true })
		check(#res.plan == 0 and res.skipped == 2, "owned parent skipped, completed variant ignored (plan " .. #res.plan .. ", skipped " .. res.skipped .. ")")
		-- before any variant is owned the preset's own choice is kept
		opts.levels = { [constructor] = 1 }
		local tree3 = R.build_tree(make_live("wh2_dlc09_tmb_necrotect", opts))
		local res3 = R.replay(tree3, { constructor, a }, { full_build = true })
		check(res3.plan[1] == a, "free choice keeps the preset's variant")
		-- once one variant is pre-allocated the others cannot be
		check(not R.can_append(tree3, { a }, b), "other variant blocked by a pre-allocated one")
	end
end

---------------------------------------------------------------- 5. strict order: rank requirements, and removal
do
	local live = make_live("wh_main_emp_lord", { faction = "wh_main_emp_empire", subculture = "wh_main_sc_emp_empire" })
	local tree = R.build_tree(live)
	local function copy(t) local c = {} for k, v in pairs(t) do c[k] = v end return c end
	-- points learnable at once, one after the other, and a parentless skill that needs a rank they can bridge
	local lows, st0 = {}, R.new_state(tree)
	for _ = 1, 30 do
		local added = false
		for _, k in ipairs(tree.order) do
			local s = tree.skills[k]
			if s.plannable and R.check(tree, st0, k, 1) then
				lows[#lows + 1] = k
				st0.levels[k] = (st0.levels[k] or 0) + 1
				added = true
				break
			end
		end
		if not added then break end
	end
	local high
	for _, k in ipairs(tree.order) do
		local s = tree.skills[k]
		local need = R.required_rank(s.ranks[1])
		if s.plannable and #s.req == 0 and #s.sub == 0 and #s.locks == 0 and need >= 5 and need - 1 <= #lows then high = k break end
	end
	check(#lows >= 5 and high ~= nil, "found " .. #lows .. " skills learnable at once and a rank-locked one")
	if high then
		local need = R.required_rank(tree.skills[high].ranks[1])
		-- too early: refused (its point would come before its rank, and no point ever waits)
		local ok, code, detail = R.can_append(tree, {}, high)
		check(not ok and code == "rank" and detail == need, "a rank-locked skill can't be the first point (" .. tostring(code) .. ", " .. tostring(detail) .. ")")
		-- where its point comes at its rank it fits: after need - 2 points (ranks 2 .. need - 1)
		local plan = {}
		for i = 1, need - 2 do plan[i] = lows[i] end
		check(not R.can_append(tree, { unpack(plan, 1, need - 3) }, high), "one place too early it is refused")
		local ok2, _, _, at2 = R.can_append(tree, plan, high)
		check(ok2 and at2 == need, "where its point comes at rank " .. need .. " it fits (" .. tostring(at2) .. ")")
		-- the points are learned as they come: the ranks grow along the plan
		plan[#plan + 1] = high
		plan[#plan + 1] = lows[need - 1]
		local ranks = R.plan_ranks(tree, plan)
		local grow = true
		for i = 1, #plan do if ranks[i] ~= i + 1 then grow = false end end
		check(grow, "each point is learned as it comes: ranks 2, 3, 4, ...")
		-- replay moves a point that comes too early to the first place where it fits
		local early = { high }
		for i = 1, need - 1 do early[#early + 1] = lows[i] end
		local res = R.replay(tree, early)
		check(#res.plan == need and res.plan[need - 1] == high and res.ranks[need - 1] == need and #res.dropped == 0,
			"replay puts the rank-locked point where its rank is reached (place " .. tostring((function() for i, k in ipairs(res.plan) do if k == high then return i end end end)()) .. ")")
		local short = R.replay(tree, { high, lows[1] })
		check(#short.plan == 1 and short.dropped[1] and short.dropped[1].key == high and short.dropped[1].code == "rank",
			"with too few points before it, it is dropped")
		-- free points cover the first points, at the character's rank
		local bonus = copy(tree)
		bonus.points = 2
		local rb = R.plan_ranks(bonus, { lows[1], lows[2], lows[3] })
		check(rb[1] == 1 and rb[2] == 1 and rb[3] == 2, "free points are spent at the character's rank")
		-- a point that comes earlier than the plan expected (granted without a rank-up): the order is kept,
		-- the rank-locked point waits for its rank and the next one with it
		local granted = copy(tree)
		granted.points = 1
		local rg = R.plan_ranks(granted, plan)
		check(rg[need - 2] == need - 2 and rg[need - 1] == need and rg[need] == need, "an early point: the rank-locked one waits, the order is kept ("
			.. tostring(rg[need - 2]) .. " " .. tostring(rg[need - 1]) .. " " .. tostring(rg[need]) .. ")")
		check(R.plan_fits(granted, plan), "with an early point the plan still fits (ranks aside)")
		-- a skill above the rank cap can never be learned
		local capped = copy(tree)
		capped.point_rows = {}
		for r, pts in pairs(tree.point_rows) do if r + 1 < need then capped.point_rows[r] = pts end end
		local okc, codec = R.can_append(capped, { unpack(plan, 1, need - 3) }, high)   -- (its point would be the last, at the cap)
		check(not okc and codec == "rank", "a skill above the rank cap is refused (" .. tostring(codec) .. ")")
		-- no point left: refused
		local one = copy(tree)
		one.point_rows = { [1] = 1 }                 -- one more point, at rank 2
		check(R.can_append(one, {}, lows[1]) and select(2, R.can_append(one, { lows[1] }, lows[2])) == "no_points",
			"with no point left a skill is refused (no_points)")
	end
	local plan = greedy_plan(tree, 7)
	local victim = plan[1]
	local res = R.remove_last(tree, plan, victim)
	check(res and #res.plan <= #plan - 1, "removal shortens the plan")
	local still_valid = R.replay(tree, res.plan)
	check(#still_valid.dropped == 0, "plan after removal is valid")
	-- a plan whose prerequisite is missing does not fit
	local child
	for _, k in ipairs(tree.order) do
		local s = tree.skills[k]
		if s.plannable and #s.req == 1 and (tree.skills[s.req[1]].level or 0) == 0 then child = k break end
	end
	check(child ~= nil and not R.plan_fits(tree, { child }), "a child without its parent does not fit")
end

---------------------------------------------------------------- 6. from scratch (plan mode's whole build)
-- A character halfway through a build, seen from scratch, is the fresh character again: the whole build
-- replays unchanged on it, and so does its learned half (in order) followed by the rest.
local scratch_trees, scratch_ok = 0, 0
for i, st in ipairs(subtypes) do
	local opts = { agent = st[3], faction = st[4], subculture = st[5] }
	local fresh = R.build_tree(make_live(st[1], opts))
	local plan = greedy_plan(fresh, i + 1000)
	if fresh.known and #plan >= 2 then
		scratch_trees = scratch_trees + 1
		local half = math.floor(#plan / 2)
		local levels = {}
		for k, s in pairs(fresh.skills) do levels[k] = s.level end
		for j = 1, half do levels[plan[j]] = levels[plan[j]] + 1 end
		-- the character at the rank by which its learned half is learned (later points may have been
		-- learned before some of it: they are left out, their points stay free)
		local pr = R.plan_ranks(fresh, plan)
		local at = 1
		for j = 1, half do if pr[j] > at then at = pr[j] end end
		local earned = 0
		for _, r in ipairs(R.arrival_ranks(fresh, R.capacity(fresh))) do if r <= at then earned = earned + 1 end end
		local o2 = { agent = st[3], faction = st[4], subculture = st[5], rank = at, points = earned - half, levels = levels }
		local mid = R.build_tree(make_live(st[1], o2))
		local scratch = R.from_scratch(mid)
		local same_levels = scratch.rank == 1 and scratch.points == 0
		for k, s in pairs(fresh.skills) do
			if not s.auto and scratch.skills[k].level ~= s.level then same_levels = false end
		end
		local res = R.replay(scratch, plan)
		local same = #res.plan == #plan and #res.dropped == 0
		for j = 1, #plan do if res.plan[j] ~= plan[j] then same = false end end
		local history = {}
		for j = 1, half do history[j] = plan[j] end
		local rest = {}
		for j = half + 1, #plan do rest[#rest + 1] = plan[j] end
		local res2 = R.replay(scratch, R.full_sequence(mid, history, rest))
		local same2 = #res2.plan == #plan
		for j = 1, #plan do if res2.plan[j] ~= plan[j] then same2 = false end end
		local ok = same_levels and same and same2 and R.capacity(scratch) == R.capacity(fresh) and mid.skills ~= scratch.skills
		if ok then scratch_ok = scratch_ok + 1 end
		check(ok, "from scratch for " .. st[2] .. ": levels " .. tostring(same_levels) .. ", build " .. tostring(same)
			.. ", learned half + rest " .. tostring(same2))
	end
end
check(scratch_trees > 500, "from scratch: tested on " .. scratch_trees .. " trees")
-- automatic skills (mounts) come back with their rank, not with the character's
do
	local found
	for i, st in ipairs(subtypes) do
		local tree = R.build_tree(make_live(st[1], { agent = st[3], faction = st[4], subculture = st[5], rank = 40 }))
		for _, k in ipairs(tree.order) do
			local s = tree.skills[k]
			if s.auto and s.auto[1] and R.required_rank(s.auto[1].rank) > 1 then
				s.level = s.auto[1].level            -- the character owns it (it reached the rank)
				found = { tree = tree, key = k, rank = R.required_rank(s.auto[1].rank) }
				break
			end
		end
		if found then break end
	end
	check(found ~= nil, "a tree with an automatic skill")
	if found then
		local scratch = R.from_scratch(found.tree)
		local st = R.new_state(scratch)
		check(R.level_at(scratch, st, found.key, 1) == 0 and R.level_at(scratch, st, found.key, found.rank) >= 1,
			"from scratch: " .. found.key .. " not owned at rank 1, owned again at rank " .. found.rank)
		check(found.tree.skills[found.key].level >= 1, "the tree itself is left as it was")
	end
end

print(string.format("%d passed, %d failed", passed, failed))
if failed > 0 then os.exit(1) end
