"""Make tests/fixtures/native: a small fake game folder for tests/test_native.lua.

  game/Warhammer3.exe            (empty: only the folder matters)
  game/used_mods.txt             the mod list the command line names
  game/data/db.pack              the game's tables (zstd-compressed, as the game ships them)
  game/data/mod1.pack            a mod: overrides a node ("!!" file) and another (a file named with a capital,
                                 which sorts before data__), loses one ("zz" file), adds some
  game/data/mod2.pack            a lower mod: the same "!!" file name as mod1 (hidden by mod1's copy) and a
                                 full replacement of character_skills (data__)
  game/data/movie_mod.pack       a movie pack (loads without being listed) with one node
  workshop/123/mod3.pack         a mod in a working directory, index with timestamps (flag 0x40): a file
                                 of the older node layout (version 5), and one of an unknown version
  workshop/123/not_listed.pack   not in the mod list: never read
  workshop/steam #2/mod4.pack    in a library folder with "#" in its name
  game/my lists/mods list.txt    another mod list, in a folder with a space (named on the command line in quotes)

Run from the project folder (needs zstandard):  python tests/make_native_fixtures.py
"""
import os
import struct
import sys

import zstandard

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(os.path.dirname(HERE), "generator"))
import tw_db  # noqa: E402

OUT = os.path.join(HERE, "fixtures", "native")
SCHEMA = tw_db.Schema(os.path.join(os.path.dirname(HERE), "generator", "schema_wh3.ron"))


def node(key, skill, tier, indent=0, faction=None):
    return {"campaign_key": None, "character_skill_key": skill, "character_skill_node_set_key": "set_a",
            "faction_key": faction, "indent": indent, "key": key, "tier": tier, "subculture": None,
            "points_on_creation": 0, "required_num_parents": 0, "visible_in_ui": True}


def skill(key, rank=0):
    return {"image_path": "x.png", "key": key, "localised_description": "", "localised_name": "", "unlocked_at_rank": rank,
            "is_background_skill": False, "is_female_only_background_skill": False, "is_male_only_background_skill": False,
            "background_weighting": 0.0, "influence_cost": 0}


def table(name, version, rows):
    return tw_db.encode_table(SCHEMA, name, version, rows)


def unknown_version(name):
    data = table(name, 6, [node("ghost", "ghost_skill", 1)])
    # the version marker and number follow the GUID: make the version 99
    at = data.index(bytes([252, 253, 254, 255]))
    return data[:at + 4] + struct.pack("<i", 99) + data[at + 8:]


def write_pack(path, files, ptype=3, timestamps=False, compress=()):
    """files: [(path inside the pack, bytes)]; compress: the paths stored zstd-compressed."""
    index = bytearray()
    blobs = []
    for p, d in files:
        p = p.replace("/", "\\")
        if p in compress:
            d = struct.pack("<I", len(d)) + zstandard.ZstdCompressor(level=3).compress(d)
        index += struct.pack("<I", len(d))
        if timestamps:
            index += struct.pack("<I", 1700000000)
        index += bytes([1 if p in compress else 0]) + p.encode("latin-1") + b"\0"
        blobs.append(d)
    flags = 0x40 if timestamps else 0
    header = b"PFH5" + struct.pack("<6I", ptype | flags, 0, 0, len(files), len(index), 1700000000)
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "wb") as f:
        f.write(header + index + b"".join(blobs))


def main():
    game = os.path.join(OUT, "game")
    data = os.path.join(game, "data")
    ws = os.path.join(OUT, "workshop", "123")
    os.makedirs(data, exist_ok=True)
    os.makedirs(ws, exist_ok=True)
    open(os.path.join(game, "Warhammer3.exe"), "wb").close()
    nodes = "db/character_skill_nodes_tables/"
    skills = "db/character_skills_tables/"

    write_pack(os.path.join(data, "db.pack"), [
        (nodes + "data__", table("character_skill_nodes_tables", 6,
            [node("n_a", "s_a", 0), node("n_b", "s_b", 1), node("n_c", "s_c", 2)])),
        (skills + "data__", table("character_skills_tables", 5, [skill("s_a"), skill("s_b"), skill("s_c", 4)])),
        ("text/db/ignored.loc", b"not a table"),
    ], ptype=1, compress={nodes.replace("/", "\\") + "data__", skills.replace("/", "\\") + "data__"})

    write_pack(os.path.join(data, "mod1.pack"), [
        (nodes + "!!mod1", table("character_skill_nodes_tables", 6, [node("n_b", "s_b", 5), node("n_d", "s_d", 3)])),
        (nodes + "zz_mod1", table("character_skill_nodes_tables", 6, [node("n_c", "s_c", 9), node("n_e", "s_e", 4)])),
        (nodes + "Mod1_Upper", table("character_skill_nodes_tables", 6, [node("n_a", "s_a", 11), node("n_h", "s_h", 8)])),
    ])
    write_pack(os.path.join(data, "mod2.pack"), [
        (nodes + "!!mod1", table("character_skill_nodes_tables", 6, [node("n_b", "s_b", 7)])),
        (skills + "data__", table("character_skills_tables", 5, [skill("s_x", 9)])),
    ])
    write_pack(os.path.join(data, "movie_mod.pack"), [
        (nodes + "movie", table("character_skill_nodes_tables", 6, [node("n_m", "s_m", 6)])),
    ], ptype=4)
    write_pack(os.path.join(data, "not_a_mod_in_list.pack"), [
        (nodes + "!!!never", table("character_skill_nodes_tables", 6, [node("n_a", "s_a", 99)])),
    ])
    old = dict(node("n_f", "s_f", 0))
    old["tier"], old["indent"] = 2.0, 1.0
    write_pack(os.path.join(ws, "mod3.pack"), [
        (nodes + "mod3", table("character_skill_nodes_tables", 5, [old])),
        (nodes + "mod3_future", unknown_version("character_skill_nodes_tables")),
    ], timestamps=True)
    write_pack(os.path.join(ws, "not_listed.pack"), [
        (nodes + "!!!never", table("character_skill_nodes_tables", 6, [node("n_a", "s_a", 99)])),
    ])
    # a library folder with "#" in its name, and a mod list in a folder with a space (named on the command
    # line in quotes)
    ws2 = os.path.join(OUT, "workshop", "steam #2")
    os.makedirs(ws2, exist_ok=True)
    write_pack(os.path.join(ws2, "mod4.pack"), [
        (nodes + "!mod4", table("character_skill_nodes_tables", 6, [node("n_g", "s_g", 7)])),
    ])
    lists = os.path.join(game, "my lists")
    os.makedirs(lists, exist_ok=True)
    with open(os.path.join(lists, "mods list.txt"), "w", encoding="utf-8", newline="\r\n") as f:
        f.write('add_working_directory "../workshop/steam #2"; # a library with "#" in its name\n')
        f.write('mod "mod4.pack";\n')
        f.write('mod "mod1.pack"; mod "mod2.pack"\n')
    with open(os.path.join(game, "used_mods.txt"), "w", encoding="utf-8", newline="\r\n") as f:
        f.write('add_working_directory "../workshop/123";\n')    # (relative: to the game's folder)
        f.write('mod "mod1.pack";\n')
        f.write('mod "mod2.pack";\n')
        f.write('mod "mod3.pack"; # in the working directory\n')
        f.write('mod "missing.pack";\n')
    print("wrote", OUT)


if __name__ == "__main__":
    main()
