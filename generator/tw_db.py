"""Decode / encode WARHAMMER III DB tables and .loc files, driven by the RPFM schema (schema_wh3.ron).

DB table binary layout:
  [GUID marker FD FE FC FF + u16-length UTF-16 GUID]
  [version marker FC FD FE FF + i32 version]          (omitted when version == 0)
  u8  "mysterious byte" (always 1 in WH3)
  u32 row count
  rows, fields in schema order
"""
import io
import os
import pickle
import struct
import uuid

import ron

GUID_MARKER = bytes([253, 254, 252, 255])
VERSION_MARKER = bytes([252, 253, 254, 255])


class Schema:
    def __init__(self, ron_path):
        cache = ron_path + ".pkl"
        if os.path.exists(cache) and os.path.getmtime(cache) >= os.path.getmtime(ron_path):
            data = pickle.load(open(cache, "rb"))
        else:
            data = ron.loads(open(ron_path, encoding="utf-8").read())
            pickle.dump(data, open(cache, "wb"))
        self.defs = data["definitions"]

    def definition(self, table, version):
        for d in self.defs.get(table, []):
            if d["version"] == version:
                return d
        raise KeyError(f"{table} version {version} is not in the schema")


def ftype(field):
    t = field["field_type"]
    return t if isinstance(t, str) else t.name


class Reader:
    def __init__(self, b, i=0):
        self.b, self.i = b, i

    def take(self, n):
        v = self.b[self.i:self.i + n]
        if len(v) != n:
            raise EOFError(f"wanted {n} bytes at {self.i}")
        self.i += n
        return v

    def unpack(self, fmt):
        return struct.unpack(fmt, self.take(struct.calcsize(fmt)))[0]

    def boolean(self):
        v = self.take(1)[0]
        if v not in (0, 1):
            raise ValueError(f"invalid bool {v} at {self.i - 1}")
        return v == 1

    def s8(self):
        return self.take(self.unpack("<H")).decode("utf-8")

    def s16(self):
        return self.take(self.unpack("<H") * 2).decode("utf-16-le")


_SIMPLE = {"F32": "<f", "F64": "<d", "I16": "<h", "I32": "<i", "I64": "<q", "ColourRGB": "<I"}


def read_field(r, f):
    t = ftype(f)
    if t == "Boolean":
        return r.boolean()
    if t in _SIMPLE:
        return r.unpack(_SIMPLE[t])
    if t == "StringU8":
        return r.s8()
    if t == "StringU16":
        return r.s16()
    if t in ("OptionalI16", "OptionalI32", "OptionalI64"):
        r.boolean()
        return r.unpack(_SIMPLE[t[8:]])
    if t == "OptionalStringU8":
        return r.s8() if r.boolean() else None
    if t == "OptionalStringU16":
        return r.s16() if r.boolean() else None
    if t in ("SequenceU16", "SequenceU32"):
        start = r.i
        n = r.unpack("<H" if t == "SequenceU16" else "<I")
        sub = f["field_type"].args[0]
        for _ in range(n):
            for sf in sub["fields"]:
                read_field(r, sf)
        return ("raw", r.b[start:r.i])
    raise NotImplementedError(t)


def decode_table(schema, table, data):
    r = Reader(data)
    guid = None
    if r.b[:4] == GUID_MARKER:
        r.i = 4
        guid = r.s16()
    version = 0
    if r.b[r.i:r.i + 4] == VERSION_MARKER:
        r.i += 4
        version = r.unpack("<i")
    mysterious = r.boolean()
    count = r.unpack("<I")
    d = schema.definition(table, version)
    names = [f["name"] for f in d["fields"]]
    rows = [dict(zip(names, (read_field(r, f) for f in d["fields"]))) for _ in range(count)]
    if r.i != len(data):
        raise ValueError(f"{table}: {len(data) - r.i} trailing bytes - schema/version mismatch")
    return {"table": table, "version": version, "guid": guid, "mysterious": mysterious, "rows": rows}


def write_field(w, f, v):
    t = ftype(f)
    if t == "Boolean":
        w.write(b"\x01" if v else b"\x00")
    elif t in _SIMPLE:
        w.write(struct.pack(_SIMPLE[t], v))
    elif t == "StringU8":
        b = v.encode("utf-8")
        w.write(struct.pack("<H", len(b)) + b)
    elif t == "StringU16":
        b = v.encode("utf-16-le")
        w.write(struct.pack("<H", len(b) // 2) + b)
    elif t == "OptionalStringU8":
        if v is None:
            w.write(b"\x00")
        else:
            w.write(b"\x01")
            write_field(w, {"field_type": "StringU8"}, v)
    else:
        raise NotImplementedError(f"writing {t} is not needed by this mod")


def encode_table(schema, table, version, rows):
    d = schema.definition(table, version)
    w = io.BytesIO()
    g = str(uuid.uuid4()).encode("utf-16-le")
    w.write(GUID_MARKER + struct.pack("<H", len(g) // 2) + g)
    if version > 0:
        w.write(VERSION_MARKER + struct.pack("<i", version))
    w.write(b"\x01")
    w.write(struct.pack("<I", len(rows)))
    for row in rows:
        for f in d["fields"]:
            write_field(w, f, row[f["name"]])
    return w.getvalue()


def decode_loc(data):
    if data[:6] != b"\xff\xfeLOC\x00":
        raise ValueError("not a loc file")
    _version, count = struct.unpack_from("<II", data, 6)
    r = Reader(data, 14)
    out = {}
    for _ in range(count):
        k = r.s16()
        v = r.s16()
        r.boolean()
        out[k] = v
    return out
