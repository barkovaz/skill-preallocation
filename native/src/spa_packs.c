/* Skill Pre-Allocation native module: which packs the game loaded, and the table files in them.
 *
 * The launcher starts the game with a mod list file on its command line (used_mods.txt from CA's
 * launcher). Its statements, one per line or separated by ';':
 *   add_working_directory "C:/.../workshop/content/1142710/123";   a folder that holds mod packs
 *   mod "my_mod.pack";                                             a mod, highest priority first
 * Mod packs are looked for in the game's data folder first, then in the working directories in order.
 * Of the game's own packs only db.pack (and any other data/db*.pack) holds tables; movie packs in the
 * data folder load without being listed, so they are read too.
 */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "zstd.h"

#include "spa_native.h"

#define MAX_LIST_FILE (4u << 20)
#define MAX_INDEX (512u << 20)
#define MAX_FILE (256u << 20)

/* ---------------------------------------------------------------- the list of packs */
static int add_pack(spa_packs *p, const char *name, const char *path, int kind)
{
	spa_pack *e;

	if (p->n == p->cap) {
		int cap = p->cap ? p->cap * 2 : 16;
		spa_pack *v = (spa_pack *)realloc(p->v, (size_t)cap * sizeof *v);
		if (!v)
			return 0;
		p->v = v;
		p->cap = cap;
	}
	e = &p->v[p->n];
	memset(e, 0, sizeof *e);
	e->name = spa_strdup(name);
	e->path = path ? spa_strdup(path) : NULL;
	e->kind = kind;
	if (!e->name || (path && !e->path)) {
		free(e->name);
		free(e->path);
		return 0;
	}
	p->n++;
	return 1;
}

static int listed(const spa_packs *p, const char *name)
{
	int i;

	for (i = 0; i < p->n; i++) {
		if (spa_stricmp(spa_basename(p->v[i].name), spa_basename(name)) == 0)
			return 1;
	}
	return 0;
}

void spa_packs_free(spa_packs *p)
{
	int i;

	for (i = 0; i < p->n; i++) {
		free(p->v[i].name);
		free(p->v[i].path);
		pf_close(p->v[i].file);
	}
	free(p->v);
	free(p->source);
	free(p->game_dir);
	sl_free(&p->working_dirs);
	sl_free(&p->warnings);
	memset(p, 0, sizeof *p);
}

/* ---------------------------------------------------------------- the mod list */
static char *trim(char *s)
{
	char *end;

	while (*s == ' ' || *s == '\t' || *s == '\r' || *s == '\n')
		s++;
	end = s + strlen(s);
	while (end > s && (end[-1] == ' ' || end[-1] == '\t' || end[-1] == '\r' || end[-1] == '\n'))
		*--end = '\0';
	if (end > s + 1 && *s == '"' && end[-1] == '"') {
		end[-1] = '\0';
		s++;
	}
	return s;
}

typedef struct {
	slist mods;
	slist dirs;
	char *script;                       /* the mod list file named on the command line */
} statements;

static int is_space(char c)
{
	return c == ' ' || c == '\t' || c == '\r' || c == '\n';
}

/* The last word of a statement: words are separated by spaces, and a word in double quotes keeps its
 * spaces (the quotes are not part of it). A copy, or NULL. */
static char *last_word(const char *st)
{
	const char *p = st, *start = NULL;
	size_t len = 0;

	while (*p) {
		while (is_space(*p))
			p++;
		if (!*p)
			break;
		if (*p == '"') {
			const char *q = strchr(p + 1, '"');
			start = p + 1;
			len = q ? (size_t)(q - start) : strlen(start);
			p = q ? q + 1 : start + len;
		} else {
			start = p;
			while (*p && !is_space(*p))
				p++;
			len = (size_t)(p - start);
		}
	}
	return start ? spa_strndup(start, len) : NULL;
}

/* One statement: `mod <pack>`, `add_working_directory <folder>` (the rest of the statement, its quotes
 * dropped), or, on the command line, a word ending in .txt (the mod list file). */
static void read_statement(char *st, int from_file, statements *out)
{
	char *arg;
	size_t klen;

	while (is_space(*st))
		st++;
	if (!*st)
		return;
	for (arg = st; *arg && !is_space(*arg); arg++)
		;
	klen = (size_t)(arg - st);
	if ((klen == 3 && strncmp(st, "mod", 3) == 0) || (klen == 21 && strncmp(st, "add_working_directory", 21) == 0)) {
		int is_mod = klen == 3;
		arg = trim(arg);
		if (*arg)
			sl_add(is_mod ? &out->mods : &out->dirs, arg);
		return;
	}
	if (!from_file && !out->script && !(klen == 14 && strncmp(st, "appdata_folder", 14) == 0)) {
		char *word = last_word(st);
		if (word && spa_ends_with_i(word, ".txt"))
			out->script = word;
		else
			free(word);
	}
}

/* Statements end at ';' or at the end of a line; in the mod list file '#' starts a comment. Neither
 * counts inside double quotes (a folder may be called "Steam #2"). */
static void read_statements(char *text, int from_file, statements *out)
{
	char *st = text, *p;
	int quoted = 0;

	for (p = text;; p++) {
		char c = *p;
		if (c == '"') {
			quoted = !quoted;
			continue;
		}
		if (c == '#' && from_file && !quoted) {
			char *eol = p;
			while (*eol && *eol != '\n')
				eol++;
			memset(p, ' ', (size_t)(eol - p));   /* (the comment, blanked to the end of its line) */
			c = *p;
		}
		if ((c == ';' && !quoted) || c == '\n' || c == '\0') {
			*p = '\0';
			read_statement(st, from_file, out);
			if (c == '\0')
				break;
			st = p + 1;
			if (c == '\n')
				quoted = 0;
		}
	}
}

static const char *skip_program(const char *cmd)
{
	if (*cmd == '"') {
		const char *q = strchr(cmd + 1, '"');
		return q ? q + 1 : "";
	}
	while (*cmd && *cmd != ' ' && *cmd != '\t')
		cmd++;
	return cmd;
}

static char *full_path(const char *base, const char *path)
{
	return pf_is_absolute(path) ? spa_strdup(path) : pf_join(base, path);
}

static char *find_mod(const spa_packs *p, const char *name)
{
	int i;

	if (pf_is_absolute(name))
		return pf_is_file(name) ? spa_strdup(name) : NULL;
	for (i = 0; i < p->working_dirs.n; i++) {
		char *path = pf_join(p->working_dirs.v[i], name);
		if (path && pf_is_file(path))
			return path;
		free(path);
	}
	return NULL;
}

static int read_u32(const unsigned char *p)
{
	return (int)((unsigned)p[0] | ((unsigned)p[1] << 8) | ((unsigned)p[2] << 16) | ((unsigned)p[3] << 24));
}

/* the pack's type (0 boot, 1 release, 2 patch, 3 mod, 4 movie), or -1 */
static int pack_type(const char *path)
{
	unsigned char head[8];
	pf_file *f = pf_open(path);
	int ok;

	if (!f)
		return -1;
	ok = pf_read_at(f, 0, head, sizeof head);
	pf_close(f);
	if (!ok || head[0] != 'P' || head[1] != 'F' || head[2] != 'H')
		return -1;
	return read_u32(head + 4) & 0xF;
}

/* the game's packs that hold its tables: db.pack (and db_*.pack, should CA ever split it) */
static int is_table_pack(const char *name)
{
	return (name[0] == 'd' || name[0] == 'D') && (name[1] == 'b' || name[1] == 'B')
		&& (name[2] == '.' || name[2] == '_') && spa_ends_with_i(name, ".pack");
}

static int cmp_names(const void *a, const void *b)
{
	return spa_stricmp(*(char *const *)a, *(char *const *)b);
}

int spa_find_packs(const spa_pack_options *opt, spa_packs *out)
{
	statements st;
	char *cwd = NULL, *cmd = NULL, *data_dir = NULL, *list_path = NULL, *text;
	slist names;
	int i;

	memset(out, 0, sizeof *out);
	memset(&st, 0, sizeof st);
	memset(&names, 0, sizeof names);

	if (opt && opt->npacks > 0) {           /* tests: exactly these packs */
		for (i = 0; i < opt->npacks; i++) {
			const char *path = opt->packs[i];
			int vanilla = spa_stricmp(spa_basename(path), "db.pack") == 0;
			add_pack(out, spa_basename(path), pf_is_file(path) ? path : NULL, vanilla ? PACK_VANILLA : PACK_MOD);
			if (!pf_is_file(path))
				sl_addf(&out->warnings, "pack not found: %s", path);
		}
		out->source = spa_strdup("the packs given");
		return 1;
	}

	out->game_dir = (opt && opt->game_dir) ? spa_strdup(opt->game_dir) : pf_exe_dir();
	cwd = (opt && opt->cwd) ? spa_strdup(opt->cwd) : pf_cwd();
	cmd = (opt && opt->command_line) ? spa_strdup(opt->command_line) : pf_command_line();
	if (!out->game_dir || !cwd || !cmd) {
		sl_add(&out->warnings, "the game's folder or command line could not be read");
		free(cwd);
		free(cmd);
		return 0;
	}
	data_dir = pf_join(out->game_dir, "data");
	sl_add(&out->working_dirs, data_dir);

	read_statements((char *)skip_program(cmd), 0, &st);
	if (st.script)
		list_path = full_path(cwd, st.script);
	if (!list_path || !pf_is_file(list_path)) {
		/* not named on the command line (or not there): CA's launcher's file in the game's folder */
		char *fallback = pf_join(cwd, "used_mods.txt");
		if (!pf_is_file(fallback)) {
			free(fallback);
			fallback = pf_join(out->game_dir, "used_mods.txt");
		}
		if (list_path)
			sl_addf(&out->warnings, "the mod list %s named on the command line was not found", list_path);
		free(list_path);
		list_path = NULL;
		if (pf_is_file(fallback)) {
			list_path = fallback;
			sl_addf(&out->warnings, "no mod list on the command line: used %s", list_path);
		} else {
			free(fallback);
		}
	}
	if (list_path && (text = pf_read_text(list_path, MAX_LIST_FILE, NULL)) != NULL) {
		read_statements(text, 1, &st);
		free(text);
		out->source = spa_strdup(list_path);
	} else {
		out->source = spa_strdup(list_path ? "unreadable mod list" : "no mod list: the game's own packs only");
		if (list_path)
			sl_addf(&out->warnings, "the mod list %s could not be read", list_path);
	}
	for (i = 0; i < st.dirs.n; i++) {
		char *dir = full_path(cwd, st.dirs.v[i]);
		if (dir)
			sl_add(&out->working_dirs, dir);
		free(dir);
	}

	/* the mods, highest priority first */
	for (i = 0; i < st.mods.n; i++) {
		char *path;
		if (listed(out, st.mods.v[i]))
			continue;
		path = find_mod(out, st.mods.v[i]);
		if (!path)
			sl_addf(&out->warnings, "mod pack not found: %s", st.mods.v[i]);
		add_pack(out, st.mods.v[i], path, PACK_MOD);
		free(path);
	}

	/* the game's own packs: movie packs (they load without being listed), then the table packs */
	if (pf_list_files(data_dir, ".pack", &names) && names.n > 0) {
		qsort(names.v, (size_t)names.n, sizeof *names.v, cmp_names);
		for (i = 0; i < names.n; i++) {
			char *path;
			if (listed(out, names.v[i]) || is_table_pack(names.v[i]))
				continue;
			path = pf_join(data_dir, names.v[i]);
			if (path && pack_type(path) == 4)
				add_pack(out, names.v[i], path, PACK_MOVIE);
			free(path);
		}
		for (i = 0; i < names.n; i++) {
			char *path;
			int type;
			if (listed(out, names.v[i]) || !is_table_pack(names.v[i]))
				continue;
			path = pf_join(data_dir, names.v[i]);
			type = path ? pack_type(path) : -1;
			if (type >= 0 && type <= 2)
				add_pack(out, names.v[i], path, PACK_VANILLA);
			free(path);
		}
	}
	if (!listed(out, "db.pack"))
		sl_add(&out->warnings, "the game's db.pack was not found");

	sl_free(&names);
	sl_free(&st.mods);
	sl_free(&st.dirs);
	free(st.script);
	free(list_path);
	free(data_dir);
	free(cwd);
	free(cmd);
	return 1;
}

/* ---------------------------------------------------------------- the table files in the packs */
#define PFH_INDEX_TIMESTAMPS 0x40
#define PFH_ENCRYPTED_INDEX 0x80
#define PFH_ENCRYPTED_DATA 0x10
#define PFH_EXTENDED_HEADER 0x100

static int add_frag(spa_frags *f, const spa_frag *e)
{
	if (f->n == f->cap) {
		int cap = f->cap ? f->cap * 2 : 64;
		spa_frag *v = (spa_frag *)realloc(f->v, (size_t)cap * sizeof *v);
		if (!v)
			return 0;
		f->v = v;
		f->cap = cap;
	}
	f->v[f->n++] = *e;
	return 1;
}

void spa_frags_free(spa_frags *f)
{
	int i;

	for (i = 0; i < f->n; i++)
		free(f->v[i].name);
	free(f->v);
	memset(f, 0, sizeof *f);
}

static int has_frag(const spa_frags *f, int table, const char *name)
{
	int i;

	for (i = 0; i < f->n; i++) {
		if (f->v[i].table == table && spa_stricmp(f->v[i].name, name) == 0)
			return 1;
	}
	return 0;
}

/* `path` (an index entry, "\" between folders) is db\<table>\<name>: which of the tables, or -1 */
static int table_of(const char *path, const char *const *tables, int ntables, const char **name)
{
	const char *t, *slash;
	size_t n;
	int i;

	if ((path[0] != 'd' && path[0] != 'D') || (path[1] != 'b' && path[1] != 'B') || (path[2] != '\\' && path[2] != '/'))
		return -1;
	t = path + 3;
	slash = t;
	while (*slash && *slash != '\\' && *slash != '/')
		slash++;
	if (!*slash || !slash[1] || strchr(slash + 1, '\\') || strchr(slash + 1, '/'))
		return -1;
	n = (size_t)(slash - t);
	for (i = 0; i < ntables; i++) {
		const char *a = tables[i];
		size_t k;
		if (strlen(a) != n)
			continue;
		for (k = 0; k < n; k++) {
			char x = t[k], y = a[k];
			if (x >= 'A' && x <= 'Z')
				x = (char)(x - 'A' + 'a');
			if (x != y)
				break;
		}
		if (k == n) {
			*name = slash + 1;
			return i;
		}
	}
	return -1;
}

static int scan_pack(spa_packs *packs, int index, const char *const *tables, int ntables, spa_frags *out)
{
	spa_pack *pk = &packs->v[index];
	unsigned char head[28];
	unsigned char *ix;
	int pfh5, type, flags, count, k;
	uint32_t dep_size, index_size;
	uint64_t header, offset, pos;

	if (!pk->path)
		return 0;
	if (!pk->file && !(pk->file = pf_open(pk->path))) {
		sl_addf(&packs->warnings, "%s could not be opened", pk->name);
		return 0;
	}
	if (!pf_read_at(pk->file, 0, head, sizeof head) || head[0] != 'P' || head[1] != 'F' || head[2] != 'H'
		|| (head[3] != '5' && head[3] != '4')) {
		sl_addf(&packs->warnings, "%s is not a pack this module can read", pk->name);
		return 0;
	}
	pfh5 = head[3] == '5';
	type = read_u32(head + 4);
	flags = type & ~0xF;
	if (flags & (PFH_ENCRYPTED_INDEX | PFH_ENCRYPTED_DATA)) {
		if (pk->kind != PACK_MOVIE)
			sl_addf(&packs->warnings, "%s is encrypted: its tables are not read", pk->name);
		return 0;
	}
	dep_size = (uint32_t)read_u32(head + 12);
	count = read_u32(head + 16);
	index_size = (uint32_t)read_u32(head + 20);
	header = 28 + ((flags & PFH_EXTENDED_HEADER) ? 20 : 0);
	if (index_size > MAX_INDEX || count < 0) {
		sl_addf(&packs->warnings, "%s has an index this module can't read", pk->name);
		return 0;
	}
	ix = (unsigned char *)malloc((size_t)index_size + 1);
	if (!ix)
		return 0;
	if (!pf_read_at(pk->file, header + dep_size, ix, index_size)) {
		sl_addf(&packs->warnings, "%s: its index could not be read", pk->name);
		free(ix);
		return 0;
	}
	ix[index_size] = '\0';
	offset = header + dep_size + index_size;
	pos = 0;
	for (k = 0; k < count; k++) {
		uint32_t size;
		int compressed = 0, table;
		const char *path, *name = NULL;
		size_t len;

		if (pos + 4 > index_size)
			break;
		size = (uint32_t)read_u32(ix + pos);
		pos += 4;
		if (flags & PFH_INDEX_TIMESTAMPS)
			pos += 4;
		if (pfh5) {
			if (pos >= index_size)
				break;
			compressed = ix[pos++] != 0;
		}
		if (pos >= index_size)
			break;
		path = (const char *)ix + pos;
		len = strlen(path);
		if (pos + len >= index_size + 1)
			break;
		pos += len + 1;
		table = table_of(path, tables, ntables, &name);
		if (table >= 0 && !has_frag(out, table, name)) {
			spa_frag e;
			e.table = table;
			e.name = spa_strdup(name);
			e.pack = index;
			e.offset = offset;
			e.size = size;
			e.compressed = compressed;
			if (!e.name || !add_frag(out, &e))
				free(e.name);
		}
		offset += size;
	}
	if (k < count)
		sl_addf(&packs->warnings, "%s: its index ends early (%d of %d files)", pk->name, k, count);
	free(ix);
	return 1;
}

int spa_scan_packs(spa_packs *packs, const char *const *tables, int ntables, spa_frags *out)
{
	int i;

	memset(out, 0, sizeof *out);
	for (i = 0; i < packs->n; i++)      /* highest priority first: the first copy of a path wins */
		scan_pack(packs, i, tables, ntables, out);
	return 1;
}

unsigned char *spa_read_frag(spa_packs *packs, const spa_frag *f, size_t *len, char *err, size_t errlen)
{
	spa_pack *pk = &packs->v[f->pack];
	unsigned char *raw, *out;
	uint32_t usize;
	size_t got;

	*len = 0;
	if (!pk->file && !(pk->file = pf_open(pk->path))) {
		snprintf(err, errlen, "%s could not be opened", pk->name);
		return NULL;
	}
	if (f->size > MAX_FILE) {
		snprintf(err, errlen, "the file is larger than %u bytes", MAX_FILE);
		return NULL;
	}
	raw = (unsigned char *)malloc((size_t)f->size + 1);
	if (!raw) {
		snprintf(err, errlen, "out of memory");
		return NULL;
	}
	if (!pf_read_at(pk->file, f->offset, raw, f->size)) {
		snprintf(err, errlen, "it could not be read from %s", pk->name);
		free(raw);
		return NULL;
	}
	if (!f->compressed) {
		*len = f->size;
		return raw;
	}
	/* compressed: the size it unpacks to, then a zstd frame */
	if (f->size < 8) {
		snprintf(err, errlen, "it is compressed but too short");
		free(raw);
		return NULL;
	}
	usize = (uint32_t)read_u32(raw);
	if (usize > MAX_FILE) {
		snprintf(err, errlen, "it unpacks to more than %u bytes", MAX_FILE);
		free(raw);
		return NULL;
	}
	if (!(raw[4] == 0x28 && raw[5] == 0xB5 && raw[6] == 0x2F && raw[7] == 0xFD)) {
		snprintf(err, errlen, "it is compressed in a format this module can't unpack (not zstd)");
		free(raw);
		return NULL;
	}
	out = (unsigned char *)malloc((size_t)usize + 1);
	if (!out) {
		snprintf(err, errlen, "out of memory");
		free(raw);
		return NULL;
	}
	got = ZSTD_decompress(out, usize, raw + 4, f->size - 4);
	free(raw);
	if (ZSTD_isError(got) || got != usize) {
		snprintf(err, errlen, "it could not be unpacked (%s)", ZSTD_isError(got) ? ZSTD_getErrorName(got) : "size differs");
		free(out);
		return NULL;
	}
	*len = usize;
	return out;
}
