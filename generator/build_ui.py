"""Make the mod's own layout for plan mode's shield: ui/skill_preallocation/spa_shield.twui.xml.

The mod no longer replaces the game's skills panel layout (so UI mods that change the skills panel keep
working). Instead the script makes a shield from this layout on each skill card while plan mode is on
(card:CreateComponent("spa_shield", this layout): a layout made that way yields its root's child) and
gives it the card's skill with SetContextObject.

The shield ("spa_shield", the card's size, docked at its top left, one priority above it):
  * takes the mouse, so the game's card never reacts in plan mode (no choice, no animation); it is an
    interactive state without images, the way the game's own layouts make click areas and tooltip holders
    (hit-testing by the component's box);
  * a neutral skill tooltip: the skill's name, description and first level's effects, and the rank that
    level asks for (see tooltip_function; the script puts it on each shield). The card's own
    tooltip (ui/campaign ui/edict_tooltip, filled by game code) describes the skill on this character. The
    shield's works on the card's skill (CcoCampaignCharacterSkill) and turns it, in its context function,
    into a skill built from the skill's database record (DatabaseRecordContext("CcoCharacterSkillRecord",
    Key)), shown with ui/common ui/character_background_skill_tooltip, as the game's character selection
    panel shows background skills. If the record or the built skill isn't valid, it shows the card's
    skill itself (as on this character) rather than nothing;
  * the card's "clear_preview" broadcaster (no stats preview: the game computes it for the character's
    real next level).
Its children "spa_pip_shield1".."3" (a level pip's size, two priorities above the card) sit over the
card's level pips, each with the tooltip of its level ("<skill> (N)", the record's level N effects, the
rank level N asks for): the script places them over the pips the card shows (docked at the shield's top
left, at the pips' offsets).
A child is drawn above its parent, so they stay above the card's own parts. The card's badge (the ranks
of its planned points, a copy of the card's name text the script makes) sits above the shields and takes
its own clicks: a click on it removes a point.

The callbacks are copied from the game's skill card (ui/campaign ui/character_details_panel_skills), so a
patch that changes them shows up here: re-run after patches that change the skills panel.

Usage (from the project folder):
  python generator/build_ui.py --game-data "<game>/data" --out src
"""
import argparse
import os
import sys
import uuid
import xml.etree.ElementTree as ET
from xml.sax.saxutils import escape

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import tw_pack  # noqa: E402

GAME_LAYOUT = "ui\\campaign ui\\character_details_panel_skills.twui.xml"
OUT = "ui/skill_preallocation/spa_shield.twui.xml"
SHIELD_ID = "spa_shield"                 # (the script looks for these names)
PIP_SHIELD_ID = "spa_pip_shield%d"       # 1, 2, 3
PIPS = ("level1", "level2", "level3")    # the card's level pips, in level_parent
SHIELD_COPY = ("ContextEventBroadcaster", "ContextLayoutTooltip")
SHIELD_DROP = ("additional_hoverables_root", "layout_path")
TOOLTIP_CONTEXT = "CcoCampaignCharacterSkill"
TOOLTIP_LAYOUT = "ui/common ui/character_background_skill_tooltip"


def tooltip_function(level, numbered=False):
    """The neutral tooltip: the card's skill turned into the skill as at `level` (its title numbered for a
    pip's tooltip). Under its description, the rank that level asks for, in the game's own words and colour
    ("Available at rank N.", or "Automatically granted at rank N." for a skill the game grants by itself),
    as the card's own tooltip shows it while the character's rank is lower (plan mode's view is a rank 1
    character): the script puts that rank on each shield as the properties spa_rank (0: none) and
    spa_auto ("1": granted), read with self.GetProperty as the game's layouts read theirs. The script has
    the same text (UI.tooltip_function in skill_preallocation_ui.lua) and checks the shield's once a
    session."""
    name = ('this.Name + " (%d)"' % level) if numbered else "this.Name"
    return ('(r = DatabaseRecordContext("CcoCharacterSkillRecord", Key), '
            'k = RoundFloat(ToNumber(self.GetProperty("spa_rank"))), '
            't = GetIfElse(k > 1, Format(Loc(GetIfElse(self.GetProperty("spa_auto") == "1", "skill_locked_auto_unlock", '
            '"skill_locked_rank")), k), ""), '
            'n = GetIf(IsContextValid(r), CcoCampaignCharacterSkill(Name:%s, Description:this.Description + t, '
            'EffectList:r.EffectListForLevel(%d)))) => GetIfElse(IsContextValid(n), n, this)' % (name, level))


TOOLTIP_FUNCTION = tooltip_function(1)


def guid(name):
    """A GUID in the layouts' form (8-4-4-16 hex), the same on every run."""
    h = uuid.uuid5(uuid.NAMESPACE_URL, "skill_preallocation/" + name).hex.upper()
    return "%s-%s-%s-%s" % (h[0:8], h[8:12], h[12:16], h[16:32])


def attr(value):
    return escape(str(value), {'"': "&quot;"})


def find_layout(game_data):
    """The newest copy of the game's skills panel layout among its ui packs: (pack name, text)."""
    found = None
    for name in sorted(os.listdir(game_data)):
        if not (name.startswith("ui") and name.endswith(".pack")):
            continue
        path = os.path.join(game_data, name)
        try:
            ix = tw_pack.read_index(path)
        except ValueError:
            continue
        for e in ix["entries"]:
            if e.path.lower() == GAME_LAYOUT.lower():
                found = (name, tw_pack.read_file(path, e).decode("utf-8"))
    if not found:
        sys.exit("could not find " + GAME_LAYOUT + " in the game's ui packs")
    return found


def size_of(el, what):
    states = el.find("states")
    first = states[0] if states is not None and len(states) else None
    if first is None or not first.get("width") or not first.get("height"):
        sys.exit(what + " has no size")
    return int(float(first.get("width"))), int(float(first.get("height")))


def offset_of(el):
    x, y = (el.get("offset") or "0,0").split(",")
    return float(x), float(y)


def game_card(root):
    cards = [c for c in root.find("components") if c.get("id") == "card"]
    if len(cards) != 1:
        sys.exit("expected one card component in the game's layout, found %d" % len(cards))
    return cards[0]


def pip_parts(root, card):
    """The card's level_parent and its pips (level1-3), found through the card's place in the hierarchy."""
    comps = {c.get("this"): c for c in root.find("components")}
    nodes = [n for n in root.find("hierarchy").iter("card") if n.get("this") == card.get("this")]
    lp_nodes = [n for n in (nodes[0] if nodes else []) if n.tag == "level_parent"]
    if len(nodes) != 1 or len(lp_nodes) != 1:
        sys.exit("the card's level_parent is not in the hierarchy as expected")
    pip_nodes = {n.tag: n for n in lp_nodes[0]}
    if any(p not in pip_nodes for p in PIPS):
        sys.exit("the card's level pips are not " + ", ".join(PIPS))
    return comps[lp_nodes[0].get("this")], [comps[pip_nodes[p].get("this")] for p in PIPS]


def callback_xml(cb_id, ctx, fn, props, indent="\t\t\t\t"):
    out = indent + "<callback_with_context\r\n" + indent + "\tcallback_id=\"%s\"" % attr(cb_id)
    if ctx:
        out += "\r\n" + indent + "\tcontext_object_id=\"%s\"" % attr(ctx)
    if fn:
        out += "\r\n" + indent + "\tcontext_function_id=\"%s\"" % attr(fn)
    if not props:
        return out + "/>\r\n"
    out += ">\r\n" + indent + "\t<child_m_user_properties>\r\n"
    for name, value in props:
        out += (indent + "\t\t<property\r\n" + indent + "\t\t\tname=\"%s\"\r\n" + indent + "\t\t\tvalue=\"%s\"/>\r\n") % (
            attr(name), attr(value))
    return out + indent + "\t</child_m_user_properties>\r\n" + indent + "</callback_with_context>\r\n"


def shield_callbacks(card, tooltip):
    """The card's clear_preview broadcaster and the neutral tooltip (placed like the card's)."""
    cbs = card.find("callbackwithcontextlist")
    out, copied = "", []
    for cb in (cbs if cbs is not None else []):
        cb_id = cb.get("callback_id")
        if cb_id not in SHIELD_COPY or cb_id in copied:
            continue
        props = [(p.get("name"), p.get("value") or "") for p in cb.iter("property") if p.get("name") not in SHIELD_DROP]
        if cb_id == "ContextLayoutTooltip":
            props.append(("layout_path", TOOLTIP_LAYOUT))
            props.sort()
            out += callback_xml(cb_id, TOOLTIP_CONTEXT, tooltip, props)
        else:
            out += callback_xml(cb_id, cb.get("context_object_id"), cb.get("context_function_id"), props)
        copied.append(cb_id)
    missing = [c for c in SHIELD_COPY if c not in copied]
    if missing:
        sys.exit("the game's card no longer has these actions for the shield: " + ", ".join(missing))
    return out


def component(cid, name, x, y, w, h, priority, callbacks, visible=False, interactive=True):
    g, gs = guid(name), guid(name + "/state")
    out = ("\t\t<%s\r\n\t\t\tthis=\"%s\"\r\n\t\t\tid=\"%s\"\r\n\t\t\toffset=\"%.2f,%.2f\"\r\n"
           "\t\t\tdocking=\"Top Left\"\r\n\t\t\tdock_offset=\"%.2f,%.2f\"\r\n") % (cid, g, cid, x, y, x, y)
    if not visible:
        out += "\t\t\tvisible=\"false\"\r\n"
    out += ("\t\t\tpriority=\"%d\"\r\n\t\t\ttooltipslocalised=\"true\"\r\n\t\t\tuniqueguid=\"%s\"\r\n"
            "\t\t\tcurrentstate=\"%s\"\r\n\t\t\tdefaultstate=\"%s\">\r\n") % (priority, g, gs, gs)
    if callbacks:
        out += "\t\t\t<callbackwithcontextlist>\r\n" + callbacks + "\t\t\t</callbackwithcontextlist>\r\n"
    out += ("\t\t\t<states>\r\n\t\t\t\t<default\r\n\t\t\t\t\tthis=\"%s\"\r\n\t\t\t\t\tname=\"default\"\r\n"
            "\t\t\t\t\twidth=\"%d\"\r\n\t\t\t\t\theight=\"%d\"\r\n") % (gs, w, h)
    if interactive:
        out += "\t\t\t\t\tinteractive=\"true\"\r\n"
    out += "\t\t\t\t\tuniqueguid=\"%s\"/>\r\n\t\t\t</states>\r\n\t\t</%s>\r\n" % (gs, cid)
    return out


def build(game_text):
    root = ET.fromstring(game_text.encode("utf-8"))
    card = game_card(root)
    cw, ch = size_of(card, "the card")
    prio = int(card.get("priority") or 20)
    level_parent, pips = pip_parts(root, card)
    lx, ly = offset_of(level_parent)
    parts = [component("root", "shield_layout_root", 0, 0, cw, ch, 0, "", visible=True, interactive=False),
             component(SHIELD_ID, "card_shield", 0, 0, cw, ch, prio + 1, shield_callbacks(card, TOOLTIP_FUNCTION))]
    for i, pip in enumerate(pips, 1):
        px, py = offset_of(pip)
        pw, ph = size_of(pip, pip.get("id"))
        parts.append(component(PIP_SHIELD_ID % i, "pip_shield/%d" % i, lx + px, ly + py, pw, ph, prio + 2,
                               shield_callbacks(card, tooltip_function(i, True))))
    hierarchy = ("\t<hierarchy>\r\n\t\t<root this=\"%s\">\r\n\t\t\t<%s this=\"%s\">\r\n" % (
        guid("shield_layout_root"), SHIELD_ID, guid("card_shield"))
        + "".join("\t\t\t\t<%s this=\"%s\"/>\r\n" % (PIP_SHIELD_ID % i, guid("pip_shield/%d" % i)) for i in range(1, 4))
        + "\t\t\t</%s>\r\n\t\t</root>\r\n\t</hierarchy>\r\n" % SHIELD_ID)
    return ('<?xml version="1.0"?>\r\n<layout\r\n\tversion="142"\r\n\tcomment="Skill Pre-Allocation: plan mode\'s shield over a '
            'skill card (made by generator/build_ui.py)"\r\n\tprecache_condition="">\r\n'
            + hierarchy + "\t<components>\r\n" + "".join(parts) + "\t</components>\r\n</layout>\r\n")


def check(text):
    """The layout: valid XML; root > spa_shield > 3 pip shields; hidden, interactive, the right callbacks."""
    root = ET.fromstring(text.encode("utf-8"))
    h = root.find("hierarchy")
    r = h[0]
    if r.tag != "root" or len(r) != 1 or r[0].tag != SHIELD_ID or [n.tag for n in r[0]] != [PIP_SHIELD_ID % i for i in (1, 2, 3)]:
        sys.exit("unexpected hierarchy")
    comps = {c.get("this"): c for c in root.find("components")}
    for node in [r[0]] + list(r[0]):
        c = comps.get(node.get("this"))
        if c is None or c.get("id") != node.tag or c.get("visible") != "false":
            sys.exit(node.tag + ": missing or not hidden")
        ids = [cb.get("callback_id") for cb in c.iter("callback_with_context")]
        if sorted(ids) != sorted(SHIELD_COPY):
            sys.exit(node.tag + ": unexpected actions " + ", ".join(ids))
        st = c.find("states")
        if st is None or len(st) != 1 or st[0].get("interactive") != "true" or c.find("componentimages") is not None:
            sys.exit(node.tag + ": must be one interactive state without images")
        tip = [cb for cb in c.iter("callback_with_context") if cb.get("callback_id") == "ContextLayoutTooltip"][0]
        level = int(node.tag[-1]) if node.tag != SHIELD_ID else 1
        want = tooltip_function(level, node.tag != SHIELD_ID)
        tprops = {p.get("name"): p.get("value") for p in tip.iter("property")}
        if (tip.get("context_function_id") != want or tip.get("context_object_id") != TOOLTIP_CONTEXT
                or tprops.get("layout_path") != TOOLTIP_LAYOUT or "additional_hoverables_root" in tprops):
            sys.exit(node.tag + ": the tooltip isn't the neutral one")
    return True


def main():
    here = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    ap = argparse.ArgumentParser()
    ap.add_argument("--game-data", help="the game's data folder (reads the skills panel from its ui packs)")
    ap.add_argument("--game-layout", help="or: a copy of ui/campaign ui/character_details_panel_skills.twui.xml")
    ap.add_argument("--out", default=os.path.join(here, "src"))
    a = ap.parse_args()
    if a.game_layout:
        source, text = a.game_layout, open(a.game_layout, encoding="utf-8").read()
    elif a.game_data:
        source, text = find_layout(a.game_data)
    else:
        sys.exit("give --game-data or --game-layout")
    out_text = build(text)
    check(out_text)
    out = os.path.join(a.out, *OUT.split("/"))
    os.makedirs(os.path.dirname(out), exist_ok=True)
    with open(out, "wb") as f:
        f.write(out_text.encode("utf-8"))
    print("from %s: wrote %s (%d bytes)" % (source, out, len(out_text)))


if __name__ == "__main__":
    main()
