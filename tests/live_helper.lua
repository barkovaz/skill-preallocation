-- Builds a "live" character (as the game would show it) from the baked data and the test fixture.
local H = {}
function H.make_live(R, D, FIX, subtype, opts)
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
				live.skills[#live.skills + 1] = { key = n.skill, list_index = #live.skills, level = lv, total = f.total,
					tier = n.tier, indent = n.indent, ranks = f.ranks, background = f.bg }
			else
				live.hidden[n.skill] = n.poc
			end
		end
	end
	return live, set_key
end
return H
