"""Small recursive-descent parser for the subset of RON used by RPFM schema files."""
import re

_ws = re.compile(r"(?:\s+|//[^\n]*)*")
_ident = re.compile(r"[A-Za-z_][A-Za-z0-9_]*")
_num = re.compile(r"-?\d+(?:\.\d+)?(?:[eE][+-]?\d+)?")


class Variant:
    """An enum variant with arguments, e.g. SequenceU32(...) or Some("x")."""
    __slots__ = ("name", "args")

    def __init__(self, name, args):
        self.name, self.args = name, args

    def __repr__(self):
        return f"{self.name}{self.args!r}"


class Parser:
    def __init__(self, text):
        self.s, self.i = text, 0

    def ws(self):
        self.i = _ws.match(self.s, self.i).end()

    def peek(self):
        self.ws()
        return self.s[self.i] if self.i < len(self.s) else ""

    def expect(self, ch):
        self.ws()
        assert self.s[self.i] == ch, (ch, self.s[self.i:self.i + 60])
        self.i += 1

    def value(self):
        c = self.peek()
        if c == "(":
            return self.tuple_or_struct()
        if c == "[":
            return self.list_()
        if c == "{":
            return self.map_()
        if c == '"':
            return self.string()
        m = _num.match(self.s, self.i)
        if m and (c.isdigit() or c == "-"):
            self.i = m.end()
            t = m.group()
            return float(t) if any(x in t for x in ".eE") else int(t)
        m = _ident.match(self.s, self.i)
        assert m, self.s[self.i:self.i + 60]
        self.i = m.end()
        name = m.group()
        if name == "true":
            return True
        if name == "false":
            return False
        if name == "None":
            return None
        if self.peek() == "(":
            inner = self.tuple_or_struct()
            if name == "Some":
                return inner[0] if isinstance(inner, list) and len(inner) == 1 else inner
            return Variant(name, inner)
        return name  # unit enum variant

    def string(self):
        self.expect('"')
        out = []
        while True:
            c = self.s[self.i]
            if c == "\\":
                out.append(self.s[self.i + 1]); self.i += 2; continue
            if c == '"':
                self.i += 1; break
            out.append(c); self.i += 1
        return "".join(out)

    def tuple_or_struct(self):
        self.expect("(")
        # struct if `ident :` follows
        self.ws()
        m = _ident.match(self.s, self.i)
        is_struct = False
        if m:
            j = _ws.match(self.s, m.end()).end()
            is_struct = j < len(self.s) and self.s[j] == ":"
        if is_struct:
            d = {}
            while self.peek() != ")":
                self.ws()
                m = _ident.match(self.s, self.i); self.i = m.end()
                self.expect(":")
                d[m.group()] = self.value()
                if self.peek() == ",":
                    self.i += 1
            self.expect(")")
            return d
        items = []
        while self.peek() != ")":
            items.append(self.value())
            if self.peek() == ",":
                self.i += 1
        self.expect(")")
        return items

    def list_(self):
        self.expect("[")
        items = []
        while self.peek() != "]":
            items.append(self.value())
            if self.peek() == ",":
                self.i += 1
        self.expect("]")
        return items

    def map_(self):
        self.expect("{")
        d = {}
        while self.peek() != "}":
            k = self.value()
            self.expect(":")
            d[k] = self.value()
            if self.peek() == ",":
                self.i += 1
        self.expect("}")
        return d


def loads(text):
    return Parser(text).value()
