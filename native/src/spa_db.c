/* Skill Pre-Allocation native module: reading a table's files and merging them as the game does.
 *
 * A table file: [FD FE FC FF, u16 n, n UTF-16 units: a GUID] [FC FD FE FF, i32 version] u8 1, u32 rows,
 * then the rows, each field as its version's layout says (spa_schema.h). A table's files are read in name
 * order (spa_game_name_cmp: by their bytes, capitals before small letters); a row whose key a file read
 * before already had is left out, so a mod's file named to sort first ("!!my_mod", "SFO_vanilla")
 * overrides the game's rows (data__). Tables without a key keep every row.
 */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "spa_native.h"
#include "spa_schema.h"

#define MAX_ROWS 4000000u
#define MAX_DEPTH 4

const spa_table_def *spa_find_def(const char *table, int version)
{
	int i;

	for (i = 0; i < SPA_TABLE_DEF_COUNT; i++) {
		if (SPA_TABLE_DEFS[i].version == version && strcmp(SPA_TABLE_DEFS[i].table, table) == 0)
			return &SPA_TABLE_DEFS[i];
	}
	return NULL;
}

static int table_known(const char *table)
{
	int i;

	for (i = 0; i < SPA_TABLE_DEF_COUNT; i++) {
		if (strcmp(SPA_TABLE_DEFS[i].table, table) == 0)
			return 1;
	}
	return 0;
}

/* ---------------------------------------------------------------- reading bytes */
typedef struct {
	const unsigned char *p;
	size_t n, i;
	int bad;
} rd;

static int need(rd *r, size_t k)
{
	if (r->bad || r->n - r->i < k) {
		r->bad = 1;
		return 0;
	}
	return 1;
}

static unsigned rd_u8(rd *r)
{
	return need(r, 1) ? r->p[r->i++] : 0;
}

static unsigned rd_u16(rd *r)
{
	unsigned v;

	if (!need(r, 2))
		return 0;
	v = (unsigned)r->p[r->i] | ((unsigned)r->p[r->i + 1] << 8);
	r->i += 2;
	return v;
}

static uint32_t rd_u32(rd *r)
{
	uint32_t v;

	if (!need(r, 4))
		return 0;
	v = (uint32_t)r->p[r->i] | ((uint32_t)r->p[r->i + 1] << 8) | ((uint32_t)r->p[r->i + 2] << 16)
		| ((uint32_t)r->p[r->i + 3] << 24);
	r->i += 4;
	return v;
}

static uint64_t rd_u64(rd *r)
{
	uint64_t lo = rd_u32(r), hi = rd_u32(r);

	return lo | (hi << 32);
}

static float rd_f32(rd *r)
{
	uint32_t u = rd_u32(r);
	float f;

	memcpy(&f, &u, sizeof f);
	return f;
}

static double rd_f64(rd *r)
{
	uint64_t u = rd_u64(r);
	double d;

	memcpy(&d, &u, sizeof d);
	return d;
}

/* ---------------------------------------------------------------- one field */
typedef struct {
	unsigned char tag;
	double num;
	const unsigned char *s;             /* V_STR: the bytes in the file */
	size_t slen;                        /* bytes (UTF-8) or units (UTF-16) */
	int utf16;
} fval;

static void read_value(rd *r, const spa_field *f, fval *v, int depth)
{
	unsigned len, has;

	v->tag = V_NIL;
	v->utf16 = 0;
	switch (f->type) {
	case FT_BOOL:
		has = rd_u8(r);
		if (has > 1)
			r->bad = 1;
		v->tag = V_BOOL;
		v->num = has;
		break;
	case FT_F32:
		v->tag = V_NUM;
		v->num = rd_f32(r);
		break;
	case FT_F64:
		v->tag = V_NUM;
		v->num = rd_f64(r);
		break;
	case FT_I16:
		v->tag = V_NUM;
		v->num = (int16_t)rd_u16(r);
		break;
	case FT_I32:
		v->tag = V_NUM;
		v->num = (int32_t)rd_u32(r);
		break;
	case FT_I64:
		v->tag = V_NUM;
		v->num = (double)(int64_t)rd_u64(r);
		break;
	case FT_COLOUR:
		v->tag = V_NUM;
		v->num = rd_u32(r);
		break;
	case FT_OI16:
	case FT_OI32:
	case FT_OI64:
		has = rd_u8(r);
		if (has > 1) {
			r->bad = 1;
		} else if (has) {
			v->tag = V_NUM;
			v->num = f->type == FT_OI16 ? (double)(int16_t)rd_u16(r)
				: f->type == FT_OI32 ? (double)(int32_t)rd_u32(r) : (double)(int64_t)rd_u64(r);
		}
		break;
	case FT_OS8:
	case FT_OS16:
		has = rd_u8(r);
		if (has > 1) {
			r->bad = 1;
			break;
		}
		if (!has)
			break;
		/* fall through: the text follows */
	case FT_S8:
	case FT_S16:
		len = rd_u16(r);
		if (f->type == FT_S16 || f->type == FT_OS16) {
			if (need(r, 2 * (size_t)len)) {
				v->tag = V_STR;
				v->s = r->p + r->i;
				v->slen = len;
				v->utf16 = 1;
				r->i += 2 * (size_t)len;
			}
		} else if (need(r, len)) {
			v->tag = V_STR;
			v->s = r->p + r->i;
			v->slen = len;
			r->i += len;
		}
		break;
	case FT_SEQ16:
	case FT_SEQ32: {
		uint32_t n = f->type == FT_SEQ16 ? rd_u16(r) : rd_u32(r), k;
		int j;
		fval skip;
		if (depth >= MAX_DEPTH || n > MAX_ROWS) {
			r->bad = 1;
			break;
		}
		for (k = 0; k < n && !r->bad; k++) {
			for (j = 0; j < f->nsub && !r->bad; j++)
				read_value(r, &f->sub[j], &skip, depth + 1);
		}
		break;
	}
	default:
		r->bad = 1;
	}
}

/* ---------------------------------------------------------------- the keys seen (first wins) */
static int key_grow(spa_table *t)
{
	size_t slots = t->key_slots ? t->key_slots * 2 : 1024, i;
	uint64_t *h = (uint64_t *)calloc(slots, sizeof *h);
	uint32_t *o = (uint32_t *)malloc(slots * sizeof *o), *l = (uint32_t *)malloc(slots * sizeof *l);

	if (!h || !o || !l) {
		free(h);
		free(o);
		free(l);
		return 0;
	}
	for (i = 0; i < t->key_slots; i++) {
		size_t j;
		if (!t->key_hash[i])
			continue;
		j = (size_t)(t->key_hash[i] & (slots - 1));
		while (h[j])
			j = (j + 1) & (slots - 1);
		h[j] = t->key_hash[i];
		o[j] = t->key_off[i];
		l[j] = t->key_len[i];
	}
	free(t->key_hash);
	free(t->key_off);
	free(t->key_len);
	t->key_hash = h;
	t->key_off = o;
	t->key_len = l;
	t->key_slots = slots;
	return 1;
}

/* 1: the key was seen before; 0: it is new (now remembered); -1: out of memory */
static int key_seen(spa_table *t, const char *key, size_t len)
{
	uint64_t h = spa_fnv(SPA_FNV_INIT, key, len) | 1;
	size_t j;

	if ((t->key_count + 1) * 2 > t->key_slots && !key_grow(t))
		return -1;
	j = (size_t)(h & (t->key_slots - 1));
	while (t->key_hash[j]) {
		if (t->key_hash[j] == h && t->key_len[j] == len && memcmp(t->keys.p + t->key_off[j], key, len) == 0)
			return 1;
		j = (j + 1) & (t->key_slots - 1);
	}
	if (t->keys.n + len > 0xFFFFFFF0u)
		return -1;
	{
		uint32_t off = (uint32_t)t->keys.n;
		if (!sb_add(&t->keys, key, len))
			return -1;
		t->key_hash[j] = h;              /* (only once its text is stored) */
		t->key_off[j] = off;
		t->key_len[j] = (uint32_t)len;
	}
	t->key_count++;
	return 0;
}

static void key_part(sbuf *k, const fval *v)
{
	switch (v->tag) {
	case V_NIL:
		sb_addc(k, '\1');
		break;
	case V_BOOL:
		sb_addc(k, v->num != 0 ? '1' : '0');
		break;
	case V_NUM:
		sb_addf(k, "%.17g", v->num);
		break;
	case V_STR:
		if (v->utf16)
			spa_utf16_to_utf8(k, v->s, v->slen);
		else
			sb_add(k, v->s, v->slen);
		break;
	}
	sb_addc(k, '\x1f');
}

/* ---------------------------------------------------------------- keeping a row */
static int push_val(spa_table *t, const fval *v)
{
	spa_val *out;

	if (t->nvals == t->capvals) {
		size_t cap = t->capvals ? t->capvals * 2 : 4096;
		spa_val *nv = (spa_val *)realloc(t->vals, cap * sizeof *nv);
		if (!nv)
			return 0;
		t->vals = nv;
		t->capvals = cap;
	}
	out = &t->vals[t->nvals++];
	out->tag = v ? v->tag : V_NIL;
	out->num = v ? v->num : 0;
	out->off = out->len = 0;
	if (v && v->tag == V_STR) {
		size_t before = t->strings.n;
		if (before > 0xFFFFFFF0u)
			return 0;
		if (v->utf16 ? !spa_utf16_to_utf8(&t->strings, v->s, v->slen) : !sb_add(&t->strings, v->s, v->slen))
			return 0;
		out->off = (uint32_t)before;
		out->len = (uint32_t)(t->strings.n - before);
	}
	return 1;
}

static int add_frag_info(spa_table *t, const char *name, const char *pack)
{
	spa_frag_info *fi;

	if (t->nfrags == t->capfrags) {
		int cap = t->capfrags ? t->capfrags * 2 : 8;
		spa_frag_info *v = (spa_frag_info *)realloc(t->frags, (size_t)cap * sizeof *v);
		if (!v)
			return 0;
		t->frags = v;
		t->capfrags = cap;
	}
	fi = &t->frags[t->nfrags];
	memset(fi, 0, sizeof *fi);
	fi->name = spa_strdup(name);
	fi->pack = spa_strdup(pack);
	fi->version = -1;
	t->nfrags++;
	return fi->name && fi->pack;
}

/* ---------------------------------------------------------------- one table file */
typedef struct {
	int version;
	uint32_t rows;
	size_t data;                        /* where the rows start */
} frag_head;

static int read_head(const unsigned char *p, size_t n, frag_head *h)
{
	rd r = { p, n, 0, 0 };

	h->version = 0;
	if (n >= 4 && p[0] == 0xFD && p[1] == 0xFE && p[2] == 0xFC && p[3] == 0xFF) {
		unsigned units;
		r.i = 4;
		units = rd_u16(&r);
		if (!need(&r, 2 * (size_t)units))
			return 0;
		r.i += 2 * (size_t)units;
	}
	if (r.n - r.i >= 4 && p[r.i] == 0xFC && p[r.i + 1] == 0xFD && p[r.i + 2] == 0xFE && p[r.i + 3] == 0xFF) {
		r.i += 4;
		h->version = (int)(int32_t)rd_u32(&r);
	}
	rd_u8(&r);
	h->rows = rd_u32(&r);
	h->data = r.i;
	return !r.bad;
}

/* Read the rows of one file into the table. Returns NULL, or why the file was left out (nothing of it
 * is used then). */
static const char *merge_frag(spa_table *t, const unsigned char *p, size_t n, spa_frag_info *fi, char *why, size_t whylen)
{
	frag_head h;
	const spa_table_def *def;
	int map[64], ncols = t->ncols, j, has_key = 0;
	fval *vals;
	rd r;
	uint32_t row;
	sbuf key;
	const char *problem = NULL;

	if (!read_head(p, n, &h))
		return "it is too short to be a table";
	fi->version = h.version;
	fi->rows = (int)h.rows;
	def = spa_find_def(t->table, h.version);
	if (!def) {
		snprintf(why, whylen, "its version %d is not one this module knows", h.version);
		return why;
	}
	if (def->nfields > 256 || ncols > 64)
		return "the table has more fields than this module reads";
	vals = (fval *)malloc((size_t)(def->nfields ? def->nfields : 1) * sizeof *vals);
	if (!vals)
		return "out of memory";
	if (h.rows > MAX_ROWS)
		return "it has too many rows";
	for (j = 0; j < def->nfields; j++)
		has_key |= def->fields[j].key;
	for (j = 0; j < ncols; j++) {
		int k;
		map[j] = -1;
		for (k = 0; k < def->nfields; k++) {
			if (strcmp(def->fields[k].name, t->cols[j]) == 0) {
				map[j] = k;
				t->col_found[j] = 1;
				break;
			}
		}
	}
	/* first the whole file is read, so a file that doesn't fit its layout adds nothing */
	r.p = p;
	r.n = n;
	r.i = h.data;
	r.bad = 0;
	for (row = 0; row < h.rows && !r.bad; row++) {
		for (j = 0; j < def->nfields && !r.bad; j++)
			read_value(&r, &def->fields[j], &vals[j], 0);
	}
	if (r.bad) {
		snprintf(why, whylen, "row %u doesn't fit the layout of version %d", (unsigned)row, h.version);
		free(vals);
		return why;
	}
	if (r.i != n) {
		snprintf(why, whylen, "%u bytes are left after the rows: not the layout of version %d", (unsigned)(n - r.i), h.version);
		free(vals);
		return why;
	}
	/* then the rows are kept, the ones with a key seen before left out */
	r.i = h.data;
	sb_init(&key);
	for (row = 0; row < h.rows; row++) {
		int seen = 0;
		for (j = 0; j < def->nfields; j++)
			read_value(&r, &def->fields[j], &vals[j], 0);
		if (has_key) {
			key.n = 0;
			for (j = 0; j < def->nfields; j++) {
				if (def->fields[j].key)
					key_part(&key, &vals[j]);
			}
			if (key.failed || (seen = key_seen(t, key.p ? key.p : "", key.n)) < 0) {
				problem = "out of memory";
				break;
			}
		}
		if (seen)
			continue;
		for (j = 0; j < ncols; j++) {
			if (!push_val(t, map[j] >= 0 ? &vals[map[j]] : NULL)) {
				problem = "out of memory";
				break;
			}
		}
		if (problem)
			break;
		t->rows++;
		fi->kept++;
	}
	sb_free(&key);
	free(vals);
	return problem;
}

/* ---------------------------------------------------------------- the whole load */
static spa_frags *sort_frags_of;

static int cmp_frag(const void *a, const void *b)
{
	const spa_frag *fa = &sort_frags_of->v[*(const int *)a], *fb = &sort_frags_of->v[*(const int *)b];
	int c = spa_game_name_cmp(fa->name, fb->name);

	return c ? c : fa->pack - fb->pack;
}

static void load_table(spa_result *res, spa_table *t, int ti, spa_frags *frags)
{
	int *order = (int *)malloc((size_t)(frags->n ? frags->n : 1) * sizeof *order);
	int n = 0, i;
	char err[256], why[256];

	if (!order) {
		sl_addf(&res->warnings, "%s: out of memory", t->table);
		return;
	}
	for (i = 0; i < frags->n; i++) {
		if (frags->v[i].table == ti)
			order[n++] = i;
	}
	sort_frags_of = frags;
	qsort(order, (size_t)n, sizeof *order, cmp_frag);
	for (i = 0; i < n; i++) {
		const spa_frag *f = &frags->v[order[i]];
		const char *pack = res->packs.v[f->pack].name;
		size_t len = 0;
		unsigned char *bytes;
		spa_frag_info *fi;
		const char *problem;

		if (!add_frag_info(t, f->name, pack))
			break;
		fi = &t->frags[t->nfrags - 1];
		err[0] = '\0';
		bytes = spa_read_frag(&res->packs, f, &len, err, sizeof err);
		if (!bytes) {
			fi->problem = spa_strdup(err);
			sl_addf(&res->warnings, "%s/%s in %s: %s", t->table, f->name, pack, err);
			continue;
		}
		problem = merge_frag(t, bytes, len, fi, why, sizeof why);
		if (problem) {
			fi->problem = spa_strdup(problem);
			sl_addf(&res->warnings, "%s/%s in %s was left out: %s", t->table, f->name, pack, problem);
		} else {
			res->digest = spa_fnv(res->digest, t->table, strlen(t->table) + 1);
			res->digest = spa_fnv(res->digest, f->name, strlen(f->name) + 1);
			res->digest = spa_fnv(res->digest, bytes, len);
		}
		free(bytes);
	}
	free(order);
}

static char *table_folder(const char *name)
{
	sbuf b;
	const char *c;

	sb_init(&b);
	for (c = name; *c; c++)
		sb_addc(&b, (*c >= 'A' && *c <= 'Z') ? (char)(*c - 'A' + 'a') : *c);
	if (!spa_ends_with_i(name, "_tables"))
		sb_adds(&b, "_tables");
	return sb_take(&b);
}

int spa_load(const spa_pack_options *opt, const char *const *tables, const char *const *const *cols,
	const int *ncols, int ntables, spa_result *out)
{
	spa_frags frags;
	const char **folders;
	int i, j;

	memset(out, 0, sizeof *out);
	out->digest = SPA_FNV_INIT;
	if (ntables <= 0)
		return 0;
	out->tables = (spa_table *)calloc((size_t)ntables, sizeof *out->tables);
	folders = (const char **)calloc((size_t)ntables, sizeof *folders);
	if (!out->tables || !folders) {
		free(folders);
		return 0;
	}
	out->ntables = ntables;
	for (i = 0; i < ntables; i++) {
		spa_table *t = &out->tables[i];
		t->table = table_folder(tables[i]);
		t->ncols = ncols[i];
		t->cols = (char **)calloc((size_t)(ncols[i] ? ncols[i] : 1), sizeof *t->cols);
		t->col_found = (int *)calloc((size_t)(ncols[i] ? ncols[i] : 1), sizeof *t->col_found);
		sb_init(&t->strings);
		sb_init(&t->keys);
		if (!t->table || !t->cols || !t->col_found) {
			free(folders);
			return 0;
		}
		for (j = 0; j < ncols[i]; j++)
			t->cols[j] = spa_strdup(cols[i][j]);
		folders[i] = t->table;
		if (!table_known(t->table))
			sl_addf(&out->warnings, "%s: this module has no layout for that table", t->table);
	}
	if (!spa_find_packs(opt, &out->packs)) {
		free(folders);
		return 0;
	}
	spa_scan_packs(&out->packs, folders, ntables, &frags);
	for (i = 0; i < ntables; i++)
		load_table(out, &out->tables[i], i, &frags);
	for (i = 0; i < out->packs.n; i++) {
		pf_close(out->packs.v[i].file);
		out->packs.v[i].file = NULL;
	}
	spa_frags_free(&frags);
	free(folders);
	return 1;
}

void spa_result_free(spa_result *r)
{
	int i, j;

	for (i = 0; i < r->ntables; i++) {
		spa_table *t = &r->tables[i];
		free(t->table);
		for (j = 0; j < t->ncols; j++)
			free(t->cols[j]);
		free(t->cols);
		free(t->col_found);
		free(t->vals);
		sb_free(&t->strings);
		sb_free(&t->keys);
		for (j = 0; j < t->nfrags; j++) {
			free(t->frags[j].name);
			free(t->frags[j].pack);
			free(t->frags[j].problem);
		}
		free(t->frags);
		free(t->key_hash);
		free(t->key_off);
		free(t->key_len);
	}
	free(r->tables);
	spa_packs_free(&r->packs);
	sl_free(&r->warnings);
	memset(r, 0, sizeof *r);
}
