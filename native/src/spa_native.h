/* Skill Pre-Allocation native module: shared declarations.
 *
 * The module reads the skill tables the game loaded: it finds the packs (vanilla db.pack and the mod
 * list the launcher gave the game), takes each table's files from them the way the game does (a file
 * path in a pack higher in the list hides the same path lower down; a table's files are read in name
 * order and the first row with a key wins), and gives the rows to the mod's Lua code. It only reads
 * files: it never reads or changes the game's memory or code.
 */
#ifndef SPA_NATIVE_H
#define SPA_NATIVE_H

#include <stddef.h>
#include <stdint.h>

#define SPA_NATIVE_VERSION "1.1.0"
#define SPA_NATIVE_API 1

/* ---------------------------------------------------------------- DB table layouts (spa_schema.h) */
enum {
	FT_BOOL, FT_F32, FT_F64, FT_I16, FT_I32, FT_I64, FT_COLOUR, FT_S8, FT_S16,
	FT_OI16, FT_OI32, FT_OI64, FT_OS8, FT_OS16, FT_SEQ16, FT_SEQ32
};

typedef struct spa_field {
	const char *name;
	unsigned char type;
	unsigned char key;
	int nsub;                       /* a sequence: the fields of each of its entries */
	const struct spa_field *sub;
} spa_field;

typedef struct {
	const char *table;              /* the folder name, e.g. "character_skill_nodes_tables" */
	int version;
	int nfields;
	const spa_field *fields;
} spa_table_def;

/* ---------------------------------------------------------------- small helpers (spa_util.c) */
typedef struct { char *p; size_t n, cap; int failed; } sbuf;

void sb_init(sbuf *b);
void sb_free(sbuf *b);
int sb_add(sbuf *b, const void *data, size_t n);
int sb_addc(sbuf *b, char c);
int sb_adds(sbuf *b, const char *s);
int sb_addf(sbuf *b, const char *fmt, ...);
char *sb_take(sbuf *b);                 /* the text so far, zero-terminated, owned by the caller */

typedef struct { char **v; int n, cap; } slist;

void sl_free(slist *l);
int sl_add(slist *l, const char *s);    /* adds a copy */
int sl_addf(slist *l, const char *fmt, ...);

char *spa_strdup(const char *s);
char *spa_strndup(const char *s, size_t n);
int spa_stricmp(const char *a, const char *b);
int spa_ends_with_i(const char *s, const char *suffix);
const char *spa_basename(const char *path);
int spa_game_name_cmp(const char *a, const char *b);
uint64_t spa_fnv(uint64_t h, const void *data, size_t n);
#define SPA_FNV_INIT 0xcbf29ce484222325ULL
int spa_utf16_to_utf8(sbuf *b, const unsigned char *src, size_t units);

/* ---------------------------------------------------------------- the computer (spa_platform.c) */
typedef struct pf_file pf_file;

pf_file *pf_open(const char *path);     /* UTF-8 path, read only, shared with the game */
int pf_read_at(pf_file *f, uint64_t offset, void *buf, size_t n);   /* 1 when all n bytes came */
uint64_t pf_size(const pf_file *f);
void pf_close(pf_file *f);
int pf_is_file(const char *path);
char *pf_read_text(const char *path, size_t max, size_t *len);   /* a small text file as UTF-8 */
char *pf_exe_dir(void);
char *pf_cwd(void);
char *pf_command_line(void);
int pf_list_files(const char *dir, const char *suffix, slist *out);
int pf_is_absolute(const char *path);
char *pf_join(const char *dir, const char *name);

/* ---------------------------------------------------------------- packs (spa_packs.c) */
enum { PACK_VANILLA, PACK_MOD, PACK_MOVIE };

typedef struct {
	char *name;                         /* as listed (a file name, or a full path) */
	char *path;                         /* where it was found, NULL when not found */
	int kind;
	pf_file *file;                      /* open while the tables are read */
} spa_pack;

typedef struct {
	spa_pack *v;
	int n, cap;
	char *source;                       /* where the list of mods came from */
	char *game_dir;
	slist working_dirs;
	slist warnings;
} spa_packs;

typedef struct {
	const char *game_dir;               /* overrides, for tests: NULL = the running game */
	const char *command_line;
	const char *cwd;
	const char **packs;                 /* tests: exactly these packs, in this order (highest first) */
	int npacks;
} spa_pack_options;

int spa_find_packs(const spa_pack_options *opt, spa_packs *out);
void spa_packs_free(spa_packs *p);

typedef struct {
	int table;                          /* index into the tables asked for */
	char *name;                         /* the file's name in the table's folder */
	int pack;                           /* index into spa_packs */
	uint64_t offset;
	uint32_t size;
	int compressed;
} spa_frag;

typedef struct { spa_frag *v; int n, cap; } spa_frags;

int spa_scan_packs(spa_packs *packs, const char *const *tables, int ntables, spa_frags *out);
void spa_frags_free(spa_frags *f);
unsigned char *spa_read_frag(spa_packs *packs, const spa_frag *f, size_t *len, char *err, size_t errlen);

/* ---------------------------------------------------------------- tables (spa_db.c) */
enum { V_NIL, V_BOOL, V_NUM, V_STR };

typedef struct {
	unsigned char tag;
	double num;                         /* V_BOOL (0/1) and V_NUM */
	uint32_t off, len;                  /* V_STR: in the table's string arena */
} spa_val;

typedef struct {
	char *name;
	char *pack;
	int version;
	int rows;                           /* rows in the file */
	int kept;                           /* rows used (the others had a key seen before) */
	char *problem;                      /* why the file was skipped, or NULL */
} spa_frag_info;

typedef struct {
	char *table;                        /* folder name, "<table>_tables" */
	int ncols;
	char **cols;
	int *col_found;                     /* the column exists in the files read */
	spa_val *vals;                      /* rows * ncols */
	size_t nvals, capvals;
	int rows;
	sbuf strings;
	spa_frag_info *frags;
	int nfrags, capfrags;
	/* keys seen (first wins) */
	uint64_t *key_hash;
	uint32_t *key_off, *key_len;
	size_t key_slots, key_count;
	sbuf keys;
} spa_table;

typedef struct {
	spa_table *tables;
	int ntables;
	spa_packs packs;
	uint64_t digest;
	slist warnings;
} spa_result;

int spa_load(const spa_pack_options *opt, const char *const *tables, const char *const *const *cols,
	const int *ncols, int ntables, spa_result *out);
void spa_result_free(spa_result *r);
const spa_table_def *spa_find_def(const char *table, int version);

#endif
