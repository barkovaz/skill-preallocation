"""Test fixtures from the game's database: rank required per skill level, max levels and a
'live' character builder input. Not shipped with the mod."""
import json, collections, sys
W = sys.argv[1]
L = lambda t: json.load(open(f'{W}/db/{t}_tables.json'))
skills = {s['key']: s for s in L('character_skills')}
lvl = L('character_skill_level_details'); eff = L('character_skill_level_to_effects_junctions')
maxlvl = collections.defaultdict(lambda: 1)
for e in eff: maxlvl[e['character_skill_key']] = max(maxlvl[e['character_skill_key']], e['level'])
for r in lvl: maxlvl[r['skill_key']] = max(maxlvl[r['skill_key']], r['level'])
generic = {(r['skill_key'], r['level']): r['unlocked_at_rank'] for r in lvl if not (r['faction_key'] or r['subculture_key'] or r['campaign_key'])}
out = ['return {']
for k, s in sorted(skills.items()):
    n = min(maxlvl[k], 3)
    ranks = []
    for lv in range(1, n + 1):
        r = generic.get((k, lv))
        if r is None: r = s['unlocked_at_rank'] if lv == 1 else (ranks[-1] if ranks else 0)
        ranks.append(r)
    out.append('[%s]={total=%d,ranks={%s},bg=%s},' % (json.dumps(k), maxlvl[k], ','.join(map(str, ranks)), 'true' if s['is_background_skill'] else 'false'))
out.append('}')
open('tests/skill_fixture.lua', 'w').write('\n'.join(out))
print('fixture skills', len(skills))
