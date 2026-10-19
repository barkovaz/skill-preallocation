"""Read and write Total War: WARHAMMER III .pack files (PFH5).

Layout (all little-endian):
  header : b"PFH5", u32 type|flags, u32 dep_count, u32 dep_index_size,
           u32 file_count, u32 file_index_size, u32 timestamp          (28 bytes)
  deps   : dep_count null-terminated names
  index  : per file -> u32 size, u8 is_compressed, null-terminated path ("\\" separators)
  data   : file blobs, in index order

Compressed blobs (vanilla packs) are: u32 uncompressed_size + a zstd frame.
"""
import struct
import time

PACK_TYPE_RELEASE = 1
PACK_TYPE_MOD = 3


class Entry:
    __slots__ = ("path", "size", "compressed", "offset")

    def __init__(self, path, size, compressed, offset):
        self.path, self.size, self.compressed, self.offset = path, size, compressed, offset


def read_index(path):
    with open(path, "rb") as f:
        head = f.read(28)
        if head[:4] != b"PFH5":
            raise ValueError(f"{path}: not a PFH5 pack ({head[:4]!r})")
        ptype, dep_count, dep_size, file_count, index_size, ts = struct.unpack("<6I", head[4:28])
        if ptype & ~0xF:
            raise ValueError(f"{path}: unsupported pack flags {ptype & ~0xF:#x}")
        f.seek(28)
        deps_raw = f.read(dep_size)
        idx = f.read(index_size)
    deps = [d.decode("latin-1") for d in deps_raw.split(b"\0") if d]
    entries, pos = [], 0
    offset = 28 + dep_size + index_size
    for _ in range(file_count):
        size, comp = struct.unpack_from("<IB", idx, pos)
        pos += 5
        end = idx.index(b"\0", pos)
        name = idx[pos:end].decode("latin-1")
        pos = end + 1
        entries.append(Entry(name, size, comp, offset))
        offset += size
    if pos != len(idx):
        raise ValueError(f"{path}: file index has {len(idx) - pos} unparsed bytes")
    return {"type": ptype & 0xF, "timestamp": ts, "dependencies": deps, "entries": entries}


def read_file(pack_path, entry):
    with open(pack_path, "rb") as f:
        f.seek(entry.offset)
        raw = f.read(entry.size)
    return decompress(raw) if entry.compressed else raw


def decompress(raw):
    import zstandard  # only needed for vanilla packs
    size = struct.unpack("<I", raw[:4])[0]
    out = zstandard.ZstdDecompressor().decompress(raw[4:], max_output_size=size)
    if len(out) != size:
        raise ValueError("decompressed size mismatch")
    return out


def iter_files(pack_path, predicate=lambda path: True):
    """Yield (path, bytes) for every file whose path satisfies predicate."""
    ix = read_index(pack_path)
    with open(pack_path, "rb") as f:
        for e in ix["entries"]:
            if not predicate(e.path):
                continue
            f.seek(e.offset)
            raw = f.read(e.size)
            yield e.path, (decompress(raw) if e.compressed else raw)


def write_mod_pack(out_path, files, timestamp=None):
    """files: {"db/some_table/file_name": bytes}. Written uncompressed, sorted like RPFM does."""
    items = sorted(((p.replace("/", "\\"), d) for p, d in files.items()), key=lambda x: x[0].lower())
    index = bytearray()
    for p, d in items:
        index += struct.pack("<IB", len(d), 0) + p.encode("latin-1") + b"\0"
    ts = int(time.time()) if timestamp is None else timestamp
    header = b"PFH5" + struct.pack("<6I", PACK_TYPE_MOD, 0, 0, len(items), len(index), ts & 0xFFFFFFFF)
    with open(out_path, "wb") as f:
        f.write(header)
        f.write(index)
        for _, d in items:
            f.write(d)
