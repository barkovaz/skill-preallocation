"""Bake the vanilla skill-tree rules of Total War: WARHAMMER III into a Lua data file for the
Skill Pre-Allocation mod.

Campaign scripts can read each character's live skill tree through the game's context system
(skills, levels, rank requirements, statuses), but not the rules behind it. This generator reads
those rules from the game's own database and writes them into script/campaign/mod/skill_preallocation_data.lua:

  * which node set (skill tree) each lord/hero type uses, including faction/subculture-specific sets
  * per node: skill, tier/indent (grid position), faction/subculture/campaign filters,
    REQUIRED parents, SUBSET_REQUIRED parents + required_num_parents, points_on_creation,
    visibility and the variant locks (character_skill_nodes_skill_locks)
  * variant groups (mutually exclusive skills or whole lines), so a preset that picked one variant
    can be mapped onto the variant a character already owns
  * skills that unlock automatically at a rank (mounts) and skills that cost Influence
  * skill points per rank and the rank cap per agent type and campaign

Usage:
  python build_data.py --game-data ".../Total War WARHAMMER III/data" --schema schema_wh3.ron --out <mod src folder>
"""
import argparse
import collections
import datetime
import hashlib
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import tw_db  # noqa: E402
import tw_pack  # noqa: E402

TABLES = {
    "character_skill_nodes_tables", "character_skill_node_links_tables", "character_skill_nodes_skill_locks_tables",
    "character_skill_node_sets_tables", "character_skill_node_set_items_tables", "character_skills_tables",
    "character_skills_to_level_reached_criterias_tables", "character_experience_skill_tiers_tables",
    "character_skill_level_details_tables", "character_skill_level_to_effects_junctions_tables",
}
OUT_FILE = "script/campaign/mod/skill_preallocation_data.lua"


def load(game_data, schema_path):
    schema = tw_db.Schema(schema_path)
    rows = collections.defaultdict(list)
    digest = hashlib.sha1()
    db_pack = os.path.join(game_data, "db.pack")
    for path, data in tw_pack.iter_files(db_pack, lambda p: p.startswith("db\\") and p.split("\\")[1] in TABLES):
        t = tw_db.decode_table(schema, path.split("\\")[1], data)
        rows[t["table"]].extend(t["rows"])
        digest.update(path.encode() + data)
    missing = TABLES - set(rows)
    if missing:
        sys.exit(f"db.pack is missing tables: {sorted(missing)}")
    stamp = datetime.datetime.fromtimestamp(os.path.getmtime(db_pack)).strftime("%Y-%m-%d")
    return {k[:-len("_tables")]: v for k, v in rows.items()}, digest.hexdigest()[:12], stamp


def lua_str(s):
    return '"' + s.replace("\\", "\\\\").replace('"', '\\"') + '"'


def build(db):
    nodes = {n["key"]: n for n in db["character_skill_nodes"]}
    skills = {s["key"]: s for s in db["character_skills"]}

    # max level per skill (effects junctions / level details)
    maxlvl = collections.defaultdict(lambda: 1)
    for e in db["character_skill_level_to_effects_junctions"]:
        maxlvl[e["character_skill_key"]] = max(maxlvl[e["character_skill_key"]], e["level"])
    for r in db["character_skill_level_details"]:
        maxlvl[r["skill_key"]] = max(maxlvl[r["skill_key"]], r["level"])

    parents = collections.defaultdict(list)          # child node -> [(parent node, link type)]
    for link in db["character_skill_node_links"]:
        parents[link["child_key"]].append((link["parent_key"], link["link_type"]))

    locks = collections.defaultdict(list)            # node -> [(skill, level)]
    for lk in db["character_skill_nodes_skill_locks"]:
        locks[lk["character_skill_node"]].append((lk["character_skill"], lk["level"]))

    set_items = collections.defaultdict(list)
    for it in db["character_skill_node_set_items"]:
        if not it["mod_disabled"] and it["item"] in nodes:
            set_items[it["set"]].append(it["item"])

    skill_index = {}
    skill_list = []

    def sidx(key):
        if key not in skill_index:
            skill_index[key] = len(skill_list) + 1
            skill_list.append(key)
        return skill_index[key]

    sets_out = {}
    stats = collections.Counter()
    for s in sorted(db["character_skill_node_sets"], key=lambda r: r["key"]):
        members = sorted(set(set_items.get(s["key"], [])), key=lambda k: (nodes[k]["tier"], nodes[k]["indent"], k))
        if not members:
            continue
        pos = {k: i + 1 for i, k in enumerate(members)}
        member_skills = collections.defaultdict(list)
        for k in members:
            member_skills[nodes[k]["character_skill_key"]].append(k)

        # variant groups: connected components of the lock graph inside this set
        locked_by = {k: {o for sk, _ in locks.get(k, []) for o in member_skills.get(sk, [])} for k in members}
        adj = collections.defaultdict(set)
        for k, others in locked_by.items():
            for o in others:
                adj[k].add(o)
                adj[o].add(k)
        variant = {}
        seen = set()
        group_no = 0
        for k in members:
            if k not in adj or k in seen:
                continue
            comp, stack = set(), [k]
            while stack:
                v = stack.pop()
                if v in comp:
                    continue
                comp.add(v)
                stack.extend(adj[v])
            seen |= comp
            group_no += 1
            in_set_parents = {m: [p for p, _ in parents.get(m, []) if p in pos] for m in members}
            # heads: group members without a parent inside the group; each head starts a branch
            heads = sorted([v for v in comp if not any(p in comp for p in in_set_parents[v])],
                           key=lambda v: (nodes[v]["tier"], nodes[v]["indent"], v))
            branch_of = {}
            for b, h in enumerate(heads, 1):
                frontier = [h]
                while frontier:
                    v = frontier.pop()
                    if v in branch_of:
                        continue
                    branch_of[v] = b
                    frontier.extend(c for c in comp if v in in_set_parents[c])
            # a variant line continues through children that only hang below that one branch
            # (e.g. Tomb Prince "Cultist Prince" -> "Heir of the Chariot King" -> "Royal Lieutenant")
            changed = True
            while changed:
                changed = False
                for m in members:
                    if m in branch_of or not in_set_parents[m]:
                        continue
                    bs = {branch_of.get(p) for p in in_set_parents[m]}
                    if len(bs) == 1 and None not in bs:
                        branch_of[m] = bs.pop()
                        changed = True
            depth = {}
            for v in branch_of:
                d, cur, guard = 0, v, 0
                while guard < 60:
                    guard += 1
                    ps = sorted(p for p in in_set_parents[cur] if branch_of.get(p) == branch_of[v])
                    if not ps:
                        break
                    cur = ps[0]
                    d += 1
                depth[v] = d
            for b in set(branch_of.values()):
                ordered = sorted([v for v in branch_of if branch_of[v] == b],
                                 key=lambda v: (depth[v], nodes[v]["tier"], nodes[v]["indent"], v))
                for p_i, v in enumerate(ordered, 1):
                    variant[v] = f"{group_no}.{b}.{p_i}"
            stats["variant groups"] += 1

        rows = []
        for k in members:
            n = nodes[k]
            req = [pos[p] for p, t in parents.get(k, []) if t == "REQUIRED" and p in pos]
            sub = [pos[p] for p, t in parents.get(k, []) if t == "SUBSET_REQUIRED" and p in pos]
            lk = [f"{sidx(sk)}:{lv}" for sk, lv in sorted(locks.get(k, []))]
            rows.append("|".join([
                str(sidx(n["character_skill_key"])), str(n["tier"]), str(n["indent"]),
                str(n["required_num_parents"]), str(n["points_on_creation"]), "1" if n["visible_in_ui"] else "0",
                n["faction_key"] or "", n["subculture"] or "", n["campaign_key"] or "",
                "+".join(map(str, sorted(req))), "+".join(map(str, sorted(sub))), "+".join(lk),
                variant.get(k, ""),
            ]))
            stats["nodes"] += 1
        sets_out[s["key"]] = {
            "subtype": s["agent_subtype_key"] or "", "agent": s["agent_key"] or "",
            "faction": s["faction_key"] or "", "subculture": s["subculture"] or "", "campaign": s["campaign_key"] or "",
            "nodes": ";".join(rows),
        }

    maxlv = {sidx(k): maxlvl[k] for k in list(skill_list)}

    # rank required per skill level, as the game shows it (verified against live data):
    # level L needs character_skill_level_details(L) if present, else the skill's unlocked_at_rank for
    # level 1, else what the level below needed. Rows with a faction/subculture/campaign filter override.
    generic_rows = collections.defaultdict(dict)
    filtered_rows = collections.defaultdict(list)
    for r in db["character_skill_level_details"]:
        if r["faction_key"] or r["subculture_key"] or r["campaign_key"]:
            filtered_rows[r["skill_key"]].append(r)
        else:
            generic_rows[r["skill_key"]][r["level"]] = r["unlocked_at_rank"]
    ranks = {}
    rank_filters = {}
    for key in list(skill_list):
        sk = skills.get(key)
        n = max(1, min(maxlvl[key], 60))
        out, prev = [], 0
        for lv in range(1, n + 1):
            r = generic_rows[key].get(lv)
            if r is None:
                r = (sk["unlocked_at_rank"] if (sk and lv == 1) else prev)
            prev = r
            out.append(r)
        if any(out):
            ranks[sidx(key)] = ",".join(map(str, out))
        if filtered_rows.get(key):
            rank_filters[sidx(key)] = ";".join(
                f'{r["level"]}:{r["unlocked_at_rank"]}:{r["faction_key"] or ""}:{r["subculture_key"] or ""}:{r["campaign_key"] or ""}'
                for r in sorted(filtered_rows[key], key=lambda r: (r["level"], r["faction_key"] or "", r["subculture_key"] or "")))

    auto = collections.defaultdict(list)
    for c in db["character_skills_to_level_reached_criterias"]:
        auto[sidx(c["character_skill"])].append(f'{c["character_level"]}:{c["upgrade_to_skill_level"]}')
    influence = sorted(sidx(k) for k, s in skills.items() if s.get("influence_cost") and not s["is_background_skill"])
    background = sorted(skill_index[k] for k, s in skills.items() if s["is_background_skill"] and k in skill_index)

    tiers = collections.defaultdict(dict)
    for t in db["character_experience_skill_tiers"]:
        camp = t["optional_campaign_key"] or "*"
        tiers[t["agent_key"]].setdefault(camp, {})[t["skill_rank"]] = t["skill_points"]
    return {
        "skills": skill_list, "maxlv": maxlv, "ranks": ranks, "rank_filters": rank_filters,
        "sets": sets_out, "auto": auto, "influence": influence,
        "background": background, "tiers": tiers, "stats": stats,
    }


def write_lua(data, digest, stamp, out_path):
    L = []
    L.append("-- GENERATED by generator/build_data.py from the game's db.pack - do not edit by hand.")
    L.append(f"-- Source: db.pack dated {stamp}, tables digest {digest}.")
    L.append("SKILL_PREALLOCATION_DATA = {")
    L.append(f"version = {lua_str(digest)}, built_from = {lua_str('db.pack ' + stamp)},")
    L.append("skills = {")
    for i in range(0, len(data["skills"]), 8):
        L.append(",".join(lua_str(k) for k in data["skills"][i:i + 8]) + ",")
    L.append("},")
    mx = [f"[{i}]={v}" for i, v in sorted(data["maxlv"].items()) if v != 1]
    L.append("maxlv = {")
    for i in range(0, len(mx), 40):
        L.append(",".join(mx[i:i + 40]) + ",")
    L.append("},")
    L.append("ranks = {")
    items = sorted(data["ranks"].items())
    for i in range(0, len(items), 20):
        L.append(",".join(f"[{k}]={lua_str(v)}" for k, v in items[i:i + 20]) + ",")
    L.append("},")
    L.append("rank_filters = {" + ",".join(f"[{k}]={lua_str(v)}" for k, v in sorted(data["rank_filters"].items())) + "},")
    au = [f"[{i}]={lua_str('+'.join(v))}" for i, v in sorted(data["auto"].items())]
    L.append("auto = {")
    for i in range(0, len(au), 20):
        L.append(",".join(au[i:i + 20]) + ",")
    L.append("},")
    L.append("influence = {" + ",".join(f"[{i}]=true" for i in data["influence"]) + "},")
    bg = [f"[{i}]=true" for i in data["background"]]
    L.append("background = {")
    for i in range(0, len(bg), 40):
        L.append(",".join(bg[i:i + 40]) + ",")
    L.append("},")
    L.append("tiers = {")
    for agent, camps in sorted(data["tiers"].items()):
        parts = []
        for camp, ranks in sorted(camps.items()):
            lo = min(ranks)
            parts.append(f"[{lua_str(camp)}]={{first={lo},points={lua_str(','.join(str(ranks[r]) for r in sorted(ranks)))}}}")
        L.append(f"[{lua_str(agent)}]={{" + ",".join(parts) + "},")
    L.append("},")
    L.append("sets = {")
    for key, s in sorted(data["sets"].items()):
        L.append(f"[{lua_str(key)}]={{subtype={lua_str(s['subtype'])},agent={lua_str(s['agent'])},faction={lua_str(s['faction'])},"
                 f"subculture={lua_str(s['subculture'])},campaign={lua_str(s['campaign'])},nodes={lua_str(s['nodes'])}}},")
    L.append("},")
    L.append("}")
    os.makedirs(os.path.dirname(out_path), exist_ok=True)
    with open(out_path, "w", encoding="utf-8", newline="\n") as f:
        f.write("\n".join(L) + "\n")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--game-data", required=True)
    ap.add_argument("--schema", default=os.path.join(os.path.dirname(__file__), "schema_wh3.ron"))
    ap.add_argument("--out", required=True, help="mod source root (the folder that contains script/)")
    a = ap.parse_args()
    db, digest, stamp = load(a.game_data, a.schema)
    data = build(db)
    out = os.path.join(a.out, OUT_FILE)
    write_lua(data, digest, stamp, out)
    print(f"wrote {out}: {len(data['sets'])} skill trees, {data['stats']['nodes']} nodes, "
          f"{data['stats']['variant groups']} variant groups, {len(data['skills'])} skills, "
          f"{os.path.getsize(out) // 1024} KB")


if __name__ == "__main__":
    main()
