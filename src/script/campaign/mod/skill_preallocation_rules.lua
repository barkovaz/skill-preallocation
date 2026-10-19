-- Skill Pre-Allocation: rules engine (pure logic, no game calls).
-- Decides whether a skill point can be taken at a given rank, simulates how a sequence of points (a
-- character's pre-allocations or a preset) is learned as the character ranks up (strictly in order, each
-- point when it comes) and maps presets onto characters that already picked a different variant.
--
-- A "tree" describes one character: its live skills (read from the game) merged with the rules of the
-- game's database: read from the packs the game loaded (skill_preallocation_live.lua, mods included),
-- or else baked from the vanilla database by generator/build_data.py (SKILL_PREALLOCATION_DATA).

SKILL_PREALLOCATION_RULES = SKILL_PREALLOCATION_RULES or {}
local R = SKILL_PREALLOCATION_RULES

-- Split `s` on a one-character separator, keeping empty fields.
-- (The game's Lua does not support string.find's "plain" argument, so this uses gmatch.)
local function split(s, sep)
	local out = {}
	if s == nil or s == "" then return out end
	for field in string.gmatch(s .. sep, "(.-)%" .. sep) do
		out[#out + 1] = field
	end
	return out
end
R.split = split

-- The rules' source: the live data once it is read (R.use_source), else the baked data.
R.source = nil
local function data() return R.source or SKILL_PREALLOCATION_DATA end
R.data = data

---------------------------------------------------------------- data access
local decoded_sets = {}
local skill_index_cache

-- Use `source` (data shaped like SKILL_PREALLOCATION_DATA; nil: the baked data) from now on. Trees
-- built before keep what they were built from: the caller reads them again.
function R.use_source(source)
	R.source = source
	decoded_sets = {}
	skill_index_cache = nil
end

-- Decode one skill tree (node set) from its compact string form (the live data builds it itself).
function R.decode_set(set_key)
	if decoded_sets[set_key] then return decoded_sets[set_key] end
	local d = data()
	if d and d.decode_set then
		local set = d.decode_set(set_key)
		decoded_sets[set_key] = set
		return set
	end
	local raw = d and d.sets[set_key]
	if not raw then return nil end
	local skills = data().skills
	local set = { key = set_key, subtype = raw.subtype, agent = raw.agent, faction = raw.faction,
		subculture = raw.subculture, campaign = raw.campaign, nodes = {} }
	for i, row in ipairs(split(raw.nodes, ";")) do
		local f = split(row, "|")
		local node = {
			index = i,
			skill = skills[tonumber(f[1])],
			tier = tonumber(f[2]), indent = tonumber(f[3]),
			rnp = tonumber(f[4]) or 0, poc = tonumber(f[5]) or 0, visible = f[6] == "1",
			faction = f[7] or "", subculture = f[8] or "", campaign = f[9] or "",
			req = {}, sub = {}, locks = {},
		}
		for _, p in ipairs(split(f[10], "+")) do node.req[#node.req + 1] = tonumber(p) end
		for _, p in ipairs(split(f[11], "+")) do node.sub[#node.sub + 1] = tonumber(p) end
		for _, lk in ipairs(split(f[12], "+")) do
			local s, lv = string.match(lk, "^(%d+):(%d+)$")
			if s then node.locks[#node.locks + 1] = { skill = skills[tonumber(s)], level = tonumber(lv) } end
		end
		if f[13] and f[13] ~= "" then
			local g, b, p = string.match(f[13], "^(%d+)%.(%d+)%.(%d+)$")
			node.variant = { group = tonumber(g), branch = tonumber(b), pos = tonumber(p) }
		end
		set.nodes[i] = node
	end
	decoded_sets[set_key] = set
	return set
end

local function skill_index(key)
	if not skill_index_cache then
		skill_index_cache = {}
		for i, k in ipairs(data().skills) do skill_index_cache[k] = i end
	end
	return skill_index_cache[key]
end
R.skill_index = skill_index

-- Keys in byte order (the game's Lua compares strings with the computer's locale: a tie must break the
-- same way on every machine).
local function key_less(a, b)
	if a == b then return false end
	local n = #a < #b and #a or #b
	for i = 1, n do
		local x, y = string.byte(a, i), string.byte(b, i)
		if x ~= y then return x < y end
	end
	return #a < #b
end
R.key_less = key_less

-- Pick the node set the game uses for a character: the most specific set whose filters match.
function R.pick_set(subtype, agent, faction, subculture, campaign)
	if not data() then return nil end
	local best, best_score
	for key, s in pairs(data().sets) do
		if s.subtype == subtype or (s.subtype == "" and s.agent == agent) then
			local ok = (s.faction == "" or s.faction == faction)
				and (s.subculture == "" or s.subculture == subculture)
				and (s.campaign == "" or s.campaign == campaign)
			if ok then
				local score = (s.faction ~= "" and 4 or 0) + (s.subculture ~= "" and 2 or 0) + (s.campaign ~= "" and 1 or 0)
					+ (s.subtype == subtype and 8 or 0)
				if not best_score or score > best_score or (score == best_score and key_less(key, best)) then
					best, best_score = key, score
				end
			end
		end
	end
	return best
end

local function node_matches(node, live)
	return (node.faction == "" or node.faction == live.faction)
		and (node.subculture == "" or node.subculture == live.subculture)
		and (node.campaign == "" or node.campaign == live.campaign)
end

local function specificity(node)
	return (node.faction ~= "" and 4 or 0) + (node.subculture ~= "" and 2 or 0) + (node.campaign ~= "" and 1 or 0)
end

-- Rank required for each level of a skill (index = level), from the baked data.
function R.skill_ranks(key, faction, subculture, campaign)
	local d = data()
	local idx = skill_index(key)
	local total = (idx and d.maxlv[idx]) or 1
	local out = {}
	local generic = idx and d.ranks[idx]
	if generic then
		for i, r in ipairs(split(generic, ",")) do out[i] = tonumber(r) or 0 end
	end
	for lv = 1, total do out[lv] = out[lv] or out[lv - 1] or 0 end
	local filt = idx and d.rank_filters[idx]
	if filt then
		for _, row in ipairs(split(filt, ";")) do
			local f = split(row, ":")
			local lv, r = tonumber(f[1]), tonumber(f[2])
			if lv and r and (f[3] == "" or f[3] == faction) and (f[4] == "" or f[4] == subculture)
				and (f[5] == "" or f[5] == campaign) then
				out[lv] = r
			end
		end
	end
	return out, total
end

---------------------------------------------------------------- rank / point maths
-- The database stores rank requirements one lower than the rank shown in game ("unlocked_at_rank"
-- 11 = "Available at rank 12"), while the character's rank() is the rank shown. So a requirement
-- of r is met at rank r + 1.
function R.required_rank(stored)
	return (stored or 0) + 1
end

-- Skill-point rows for this character type: rows[i] = points gained when reaching rank i + 1.
function R.point_rows(agent, campaign)
	local t = data() and data().tiers[agent]
	local rows = {}
	if not t then return rows end
	local function add(entry)
		if not entry then return end
		local pts = split(entry.points, ",")
		for i, p in ipairs(pts) do rows[entry.first + i] = tonumber(p) end
	end
	add(t["*"])
	add(t[campaign])
	return rows
end

-- Points still to be earned after `rank`, and the rank cap.
function R.future_points(tree)
	local total, cap = 0, 1
	for i, p in pairs(tree.point_rows) do
		local reach = i + 1          -- rows[i] is earned on reaching rank i + 1
		if reach > cap then cap = reach end
		if reach > tree.rank then total = total + p end
	end
	return total, cap
end

-- Rank at which plan slot k (1-based) is spent. Slots covered by currently free points are spent now.
function R.slot_rank(tree, k)
	if k <= (tree.points or 0) then return tree.rank end
	local need = k - (tree.points or 0)
	local got = 0
	local reach = tree.rank
	while got < need do
		reach = reach + 1
		local p = tree.point_rows[reach - 1]
		if p == nil then return nil end   -- beyond the rank cap
		got = got + p
	end
	return reach
end

function R.capacity(tree)
	return (tree.points or 0) + (R.future_points(tree))
end

-- The rank at which each of the next `n` points arrives (out[k] = R.slot_rank(tree, k), in one pass);
-- nil from the first one beyond the rank cap.
function R.arrival_ranks(tree, n)
	local out = {}
	local free = tree.points or 0
	local reach, got = tree.rank, 0
	for k = 1, n do
		if k <= free then
			out[k] = tree.rank
		else
			while got < k - free do
				reach = reach + 1
				local p = tree.point_rows[reach - 1]
				if p == nil then return out end
				got = got + p
			end
			out[k] = reach
		end
	end
	return out
end

-- The rank at which a point of `key` that comes at `rank` is learned. Every point of a plan fits the rank
-- its place comes at (R.can_append, R.replay), so that is `rank` itself. Only a point that comes earlier
-- than the plan expected (a skill point granted without a rank-up) can find its skill's rank not reached
-- yet: it waits for that rank, and the points after it wait too (the order is always kept). A rank beyond
-- the cap is never reached: the rank is left as it is and R.check refuses the point.
function R.wait_rank(tree, st, key, rank)
	local s = tree.skills[key]
	if not rank or not s or not s.ranks then return rank end
	local cur = st.levels[key] or 0
	local need = R.required_rank(s.ranks[cur + 1] or s.ranks[#s.ranks])
	if need > rank then
		local _, cap = R.future_points(tree)
		if need <= math.max(cap, tree.rank or 1) then return need end
	end
	return rank
end

---------------------------------------------------------------- tree construction
-- live = {
--   cqi, subtype, agent, faction, subculture, campaign, rank, points,
--   skills = { { key, level, total, tier, indent, status, ranks = {rank required per level}, background } ... },
--   hidden = { [skill] = level },   -- background / hidden skills (can matter for locks)
-- }
function R.build_tree(live)
	local tree = {
		cqi = live.cqi, subtype = live.subtype, agent = live.agent, faction = live.faction,
		subculture = live.subculture, campaign = live.campaign, rank = live.rank or 1, points = live.points or 0,
		skills = {}, order = {}, hidden = live.hidden or {}, unknown = 0,
	}
	tree.point_rows = R.point_rows(live.agent, live.campaign)
	tree.set_key = R.pick_set(live.subtype, live.agent, live.faction, live.subculture, live.campaign)
	local set = tree.set_key and R.decode_set(tree.set_key)
	tree.known = set ~= nil

	-- candidate nodes per skill key
	local by_skill = {}
	if set then
		for _, node in ipairs(set.nodes) do
			if node_matches(node, live) then
				by_skill[node.skill] = by_skill[node.skill] or {}
				table.insert(by_skill[node.skill], node)
			end
		end
	end

	local node_skill = {}       -- node index -> skill key present in this tree
	for _, ls in ipairs(live.skills or {}) do
		local s = {
			key = ls.key, list_index = ls.list_index, level = ls.level or 0, total = ls.total, tier = ls.tier, indent = ls.indent,
			status = ls.status, ranks = ls.ranks, background = ls.background,
			req = {}, sub = {}, locks = {}, rnp = 0, poc = 0,
		}
		if not s.ranks or #s.ranks == 0 or not s.total then
			local baked_ranks, baked_total = R.skill_ranks(ls.key, live.faction, live.subculture, live.campaign)
			s.ranks = (s.ranks and #s.ranks > 0) and s.ranks or baked_ranks
			s.total = s.total or baked_total
		end
		local cands = by_skill[ls.key]
		local node
		if cands then
			for _, c in ipairs(cands) do
				if (ls.tier == nil or c.tier == ls.tier) and (ls.indent == nil or c.indent == ls.indent) then
					if not node or specificity(c) > specificity(node) then node = c end
				end
			end
			if not node then
				for _, c in ipairs(cands) do
					if not node or specificity(c) > specificity(node) then node = c end
				end
			end
		end
		s.node = node
		if node then node_skill[node.index] = ls.key end
		tree.skills[ls.key] = s
		tree.order[#tree.order + 1] = ls.key
	end

	-- a tree that does not match the baked data (e.g. a lord added by another mod) is not plannable
	local matched = 0
	for _, key in ipairs(tree.order) do if tree.skills[key].node then matched = matched + 1 end end
	if #tree.order > 0 and matched * 2 < #tree.order then
		tree.known = false
		for _, key in ipairs(tree.order) do tree.skills[key].node = nil end
		for k in pairs(node_skill) do node_skill[k] = nil end
	end

	local d = data()
	for _, key in ipairs(tree.order) do
		local s = tree.skills[key]
		local node = s.node
		local idx = skill_index(key)
		s.auto = idx and d.auto[idx] and {} or nil
		if s.auto then
			for _, crit in ipairs(split(d.auto[idx], "+")) do
				local lv_char, lv_skill = string.match(crit, "^(%d+):(%d+)$")
				s.auto[#s.auto + 1] = { rank = tonumber(lv_char), level = tonumber(lv_skill) }
			end
		end
		s.influence = idx and d.influence[idx] or false
		if node then
			s.rnp, s.poc = node.rnp, node.poc
			for _, p in ipairs(node.req) do if node_skill[p] then s.req[#s.req + 1] = node_skill[p] end end
			for _, p in ipairs(node.sub) do if node_skill[p] then s.sub[#s.sub + 1] = node_skill[p] end end
			s.locks = node.locks
			s.variant = node.variant
		else
			tree.unknown = tree.unknown + 1
		end
		-- a point can only ever be planned on a skill the rules know about
		local why
		if not node then why = "unknown"
		elseif s.background or (idx and d.background[idx]) then why = "background"
		elseif s.auto then why = "auto"
		elseif s.influence then why = "influence"
		elseif not node.visible then why = "hidden"
		end
		s.plannable = why == nil
		s.not_plannable_reason = why
	end
	return tree
end

---------------------------------------------------------------- simulation state
function R.new_state(tree)
	local st = { levels = {}, taken = 0 }
	for key, s in pairs(tree.skills) do st.levels[key] = s.level or 0 end
	return st
end

local function copy_state(st)
	local c = { levels = {}, taken = st.taken }
	for k, v in pairs(st.levels) do c.levels[k] = v end
	return c
end
R.copy_state = copy_state

-- level of a skill in the simulation, including automatic unlocks reached by `rank`
local function level_at(tree, st, key, rank)
	local lv = st.levels[key]
	if lv == nil then lv = tree.hidden[key] or 0 end
	local s = tree.skills[key]
	if s and s.auto and rank then
		for _, a in ipairs(s.auto) do
			if R.required_rank(a.rank) <= rank and a.level > lv then lv = a.level end
		end
	end
	return lv
end
R.level_at = level_at

-- Can the next point of `key` be taken at `rank`, given simulation state `st`?
-- Returns ok, code where code is one of:
--   unknown, background, auto, influence, hidden, maxed, rank, parents, subset, locked
function R.check(tree, st, key, rank)
	local s = tree.skills[key]
	if not s then return false, "unknown" end
	if not s.plannable then return false, s.not_plannable_reason or "unknown" end
	local cur = st.levels[key] or 0
	if cur >= (s.total or 1) then return false, "maxed" end
	local need = R.required_rank(s.ranks[cur + 1] or s.ranks[#s.ranks])
	if rank == nil or need > rank then return false, "rank", need end
	for _, p in ipairs(s.req) do
		if level_at(tree, st, p, rank) < 1 then return false, "parents", p end
	end
	if #s.sub > 0 and (s.rnp or 0) > 0 then
		local sum = 0
		for _, p in ipairs(s.sub) do sum = sum + level_at(tree, st, p, rank) end
		if sum < s.rnp then return false, "subset", s.rnp - sum end
	end
	for _, lk in ipairs(s.locks) do
		if level_at(tree, st, lk.skill, rank) >= lk.level then return false, "locked", lk.skill end
	end
	return true
end

-- A point the rules can't check: on a tree built while the rules are the baked vanilla data (the mod sets
-- tree.keep_unknown when the live data is off), a skill the character's tree shows but the rules don't
-- know (one another mod adds). A plan made with the live data keeps such points: nothing re-checks it
-- (the mod's revalidate), removing a point leaves the rest as it is (R.remove_last), and spending stops
-- at the first one, until the live data is back.
function R.kept(tree, key)
	if not tree.keep_unknown then return false end
	local s = tree.skills[key]
	return s ~= nil and s.not_plannable_reason == "unknown"
end

-- How many points of `plan` are kept that way.
function R.count_kept(tree, plan)
	if not tree.keep_unknown then return 0 end
	local n = 0
	for _, key in ipairs(plan) do
		if R.kept(tree, key) then n = n + 1 end
	end
	return n
end

---------------------------------------------------------------- variants
-- Find the skill that plays the same role as `key` in the variant branch the character owns.
-- Returns the counterpart skill key, or nil.
function R.counterpart(tree, key, owned_levels)
	local s = tree.skills[key]
	if not s or not s.variant then return nil end
	local g, pos = s.variant.group, s.variant.pos
	-- which branch of this group does the character own?
	local owned_branch
	for k, other in pairs(tree.skills) do
		if other.variant and other.variant.group == g and other.variant.branch ~= s.variant.branch
			and (owned_levels[k] or 0) > 0 then
			owned_branch = other.variant.branch
			break
		end
	end
	if not owned_branch then return nil end
	for k, other in pairs(tree.skills) do
		if other.variant and other.variant.group == g and other.variant.branch == owned_branch and other.variant.pos == pos then
			return k
		end
	end
	return nil
end

-- First skill of the variant line `key` belongs to (the skill whose lock blocks the whole line).
function R.branch_head(tree, key)
	local s = tree.skills[key]
	if not s or not s.variant then return nil end
	for k, other in pairs(tree.skills) do
		if other.variant and other.variant.group == s.variant.group and other.variant.branch == s.variant.branch
			and other.variant.pos == 1 then
			return k
		end
	end
	return key
end

-- Is the variant line of `key` closed off by what the character owns?
function R.variant_blocked(tree, levels, key)
	if R.lock_source(tree, levels, key) then return true end
	local head = R.branch_head(tree, key)
	return head ~= nil and head ~= key and R.lock_source(tree, levels, head) ~= nil
end

---------------------------------------------------------------- simulation: points in plan order
-- Points are learned strictly in plan order, each when its skill point comes: the free points at the
-- character's rank, then the points gained per rank. Every entry of a plan fits the rank its point comes
-- at (R.can_append and R.replay make sure of it), so a point is spent as soon as it comes and none is left
-- unspent while pre-allocations remain. (A point that comes earlier than expected, granted without a
-- rank-up, can reach a skill whose rank isn't reached yet: that one and the ones after it wait, see
-- R.wait_rank.)
--
-- Returns ranks (ranks[i] = the rank at which entry i is learned; nil = beyond the rank cap), the state
-- after the plan, the rank of its last entry (or the character's rank) and the arrival ranks of
-- #plan + extra points.
function R.simulate(tree, plan, extra)
	local ranks = {}
	local st = R.new_state(tree)
	local arrivals = R.arrival_ranks(tree, #plan + (extra or 0))
	local prev = tree.rank or 1
	for i = 1, #plan do
		local key = plan[i]
		local r = arrivals[i]
		if r then
			if r < prev then r = prev end
			r = R.wait_rank(tree, st, key, r)
			prev = r
		end
		ranks[i] = r
		st.levels[key] = (st.levels[key] or 0) + 1
	end
	return ranks, st, prev, arrivals
end

-- The rank at which every entry of a plan is learned (see R.simulate).
function R.plan_ranks(tree, plan)
	return (R.simulate(tree, plan))
end

---------------------------------------------------------------- sequences
-- Which skill (if any) locks `key`, looking only at the levels in `levels`.
function R.lock_source(tree, levels, key)
	local s = tree.skills[key]
	if not s then return nil end
	for _, lk in ipairs(s.locks or {}) do
		local lv = levels[lk.skill]
		if lv == nil then lv = tree.hidden[lk.skill] or 0 end
		if lv >= lk.level then return lk.skill end
	end
	return nil
end
-- Simulate a sequence of points against the character and keep what fits, in order.
--   entries : list of skill keys, one entry per point, in the order they should be taken
--   opts.full_build : the sequence describes a whole build from rank 1 (a preset); points the
--                     character already has are recognised and skipped, and a variant the character
--                     cannot take any more is mapped onto the variant it already owns.
-- Each point must fit the rank its place in the plan comes at. One that doesn't (its rank isn't reached
-- by then, or its prerequisite comes later) moves to the first place where it fits; one that never fits
-- is dropped.
-- Returns { plan = {...}, ranks = {...}, dropped = { {key=, code=} }, remapped = { {from=, to=} }, skipped = n }
function R.replay(tree, entries, opts)
	opts = opts or {}
	local st = R.new_state(tree)
	local live, live_spent = {}, R.spent_levels(tree)
	for k, sk in pairs(tree.skills) do live[k] = sk.level or 0 end
	local consumed = {}
	local capacity = R.capacity(tree)
	local res = { plan = {}, ranks = {}, dropped = {}, remapped = {}, skipped = 0 }
	local deferred = {}

	local function try_place(key, original)
		local slot = #res.plan + 1
		if slot > capacity then return false, "no_points" end
		local rank = R.slot_rank(tree, slot)
		local prev = res.ranks[slot - 1]
		if rank and prev and prev > rank then rank = prev end
		local ok, code = R.check(tree, st, key, rank)
		if ok then
			st.levels[key] = (st.levels[key] or 0) + 1
			res.plan[slot] = key
			res.ranks[slot] = rank
			if original and original ~= key then res.remapped[#res.remapped + 1] = { from = original, to = key } end
			return true
		end
		return false, code
	end

	local function retry_deferred()
		local progress = true
		while progress and #deferred > 0 do
			progress = false
			for i = 1, #deferred do
				local d = deferred[i]
				if try_place(d.key, d.original) then
					table.remove(deferred, i)
					progress = true
					break
				end
			end
		end
	end

	for _, entry in ipairs(entries) do
		local key, original = entry, entry
		if opts.full_build then
			-- variant the character can no longer take -> the one it owns (only when the lock comes
			-- from what the character really has, never from earlier entries of the same preset)
			local sk = tree.skills[key]
			if sk and sk.plannable and R.variant_blocked(tree, live, key) then
				local cp = R.counterpart(tree, key, live)
				if cp then key = cp end
			end
			consumed[key] = (consumed[key] or 0) + 1
			if consumed[key] <= (live_spent[key] or 0) then
				res.skipped = res.skipped + 1       -- the character already has this point
				key = nil
			elseif original ~= key and tree.skills[key] and (st.levels[key] or 0) >= (tree.skills[key].total or 1) then
				res.skipped = res.skipped + 1       -- mapped onto a variant that is already complete
				key = nil
			end
		end
		if key then
			local ok, code = try_place(key, original)
			if ok then
				retry_deferred()
			elseif code == "rank" or code == "parents" or code == "subset" then
				deferred[#deferred + 1] = { key = key, original = original, code = code }   -- (a later place may fit)
			else
				res.dropped[#res.dropped + 1] = { key = original, code = code }
			end
		end
	end
	retry_deferred()
	for _, d in ipairs(deferred) do res.dropped[#res.dropped + 1] = { key = d.original, code = d.code } end
	return res
end

-- Can one more point of `key` be pre-allocated after `plan`? Its point comes at the rank of its place in
-- the plan (never before the entry ahead of it), and the skill must be learnable right then: a skill whose
-- rank isn't reached by then is refused ("rank", detail = the rank it needs), so no point ever waits.
-- Returns ok, code, detail (see R.check: the rank it needs, the missing parent, the variant that locks
-- it, ...) and that rank.
function R.can_append(tree, plan, key)
	local slot = #plan + 1
	if slot > R.capacity(tree) then return false, "no_points" end
	local _, st, prev, arrivals = R.simulate(tree, plan, 1)
	local rank = arrivals[slot]
	if rank and prev > rank then rank = prev end
	local ok, code, detail = R.check(tree, st, key, rank)
	return ok, code, detail, rank
end

-- Remove the last pre-allocated point of `key`; anything later that no longer fits moves to the
-- first place where it is legal, or is dropped. Returns the replay result (plan, ranks, dropped). A plan
-- holding points the rules can't check (R.kept) keeps the rest as it is.
function R.remove_last(tree, plan, key)
	local cut
	for i = #plan, 1, -1 do
		if plan[i] == key then cut = i break end
	end
	if not cut then return nil end
	local rest = {}
	for i, k in ipairs(plan) do if i ~= cut then rest[#rest + 1] = k end end
	if R.count_kept(tree, rest) > 0 then
		return { plan = rest, ranks = R.plan_ranks(tree, rest), dropped = {}, remapped = {}, skipped = 0 }
	end
	return R.replay(tree, rest)
end

-- Does a plan still fit the character, apart from rank requirements (a point whose rank isn't reached
-- yet keeps its place)? Returns ok, or false, the first entry that doesn't fit and why.
function R.plan_fits(tree, plan)
	local st = R.new_state(tree)
	for _, key in ipairs(plan) do
		local ok, code = R.check(tree, st, key, 9999)
		if not ok then return false, key, code end
		st.levels[key] = (st.levels[key] or 0) + 1
	end
	return true
end

-- Points the character has really spent, per skill (levels minus the free points from creation).
function R.spent_levels(tree)
	local out, total = {}, 0
	for key, s in pairs(tree.skills) do
		local free = (s.poc or 0)
		if s.auto or s.background then free = s.level end
		local spent = math.max(0, (s.level or 0) - free)
		if spent > 0 then out[key] = spent; total = total + spent end
	end
	return out, total
end

-- The same character at rank 1 with no points spent: what a whole build (a preset, or plan mode's
-- draft) is planned against. Points from creation and background skills stay; automatic skills come
-- back with the ranks that unlock them (see level_at).
function R.from_scratch(tree)
	local spent = R.spent_levels(tree)
	local t = {}
	for k, v in pairs(tree) do t[k] = v end
	t.rank, t.points, t.skills = 1, 0, {}
	for key, s in pairs(tree.skills) do
		local c = {}
		for k, v in pairs(s) do c[k] = v end
		if s.auto then c.level = 0 else c.level = (s.level or 0) - (spent[key] or 0) end
		t.skills[key] = c
	end
	return t
end

-- A full build (preset) from what the character has learned plus its pre-allocations.
-- `history` is the order of points this mod has seen being spent (may be incomplete or empty).
-- Learned points with no known order are put first, in an order that satisfies the rules.
function R.full_sequence(tree, history, plan)
	local spent = R.spent_levels(tree)
	local seq, used = {}, {}
	for _, k in ipairs(history or {}) do
		if (used[k] or 0) < (spent[k] or 0) then
			used[k] = (used[k] or 0) + 1
			seq[#seq + 1] = k
		end
	end
	-- remaining learned points: order by required rank, then grid position, parents first
	local rest = {}
	for k, n in pairs(spent) do
		for lv = (used[k] or 0) + 1, n do
			local s = tree.skills[k]
			rest[#rest + 1] = { key = k, level = lv, rank = (s.ranks[lv] or 0), tier = s.tier or 0, indent = s.indent or 0 }
		end
	end
	table.sort(rest, function(a, b)
		if a.rank ~= b.rank then return a.rank < b.rank end
		if a.level ~= b.level then return a.level < b.level end
		if a.tier ~= b.tier then return a.tier < b.tier end
		if a.indent ~= b.indent then return a.indent < b.indent end
		return a.key < b.key
	end)
	-- emit parents before children
	local placed = {}
	for _, k in ipairs(seq) do placed[k] = (placed[k] or 0) + 1 end
	local guard = 0
	while #rest > 0 and guard < 1000 do
		guard = guard + 1
		local progressed = false
		for i, r in ipairs(rest) do
			local s = tree.skills[r.key]
			local ready = true
			for _, p in ipairs(s.req) do
				if (spent[p] or 0) > 0 and (placed[p] or 0) == 0 then ready = false end
			end
			if ready then
				seq[#seq + 1] = r.key
				placed[r.key] = (placed[r.key] or 0) + 1
				table.remove(rest, i)
				progressed = true
				break
			end
		end
		if not progressed then
			for _, r in ipairs(rest) do seq[#seq + 1] = r.key end
			break
		end
	end
	for _, k in ipairs(plan or {}) do seq[#seq + 1] = k end
	return seq
end

return R
