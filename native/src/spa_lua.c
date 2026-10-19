/* Skill Pre-Allocation native module: what the mod's Lua code sees.
 *
 *   local N = require("skill_preallocation_native")     (the mod's loader does this; nothing is global)
 *   N.version, N.api            this module's version ("1.1.0") and interface number (1)
 *   N.mod_list([options])       the packs the game loaded: { source, game_dir, packs = { { name, path, kind } },
 *                               working_dirs, warnings }
 *   N.load_db(request)          the merged rows of tables:
 *     request = { tables = { [table] = { column, ... }, ... },
 *                 packs = { path, ... }, game_dir =, command_line =, cwd = }   (the last four: tests only)
 *     result  = { digest = "16 hex digits", source =, packs =, warnings = { text, ... },
 *                 tables = { [table] = { n = rows, columns = { ... }, found = { [column] = bool },
 *                                        data = { row 1 col 1, row 1 col 2, ... },   (nil = no value)
 *                                        files = { { name, pack, version, rows, kept, problem }, ... } } } }
 *   Numbers come as Lua numbers (32-bit floats in the game: the skill tables only hold small ones).
 */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "spa_native.h"
#include "lua_api.h"

#ifdef _WIN32
#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#define SPA_EXPORT __declspec(dllexport)
#else
#define SPA_EXPORT __attribute__((visibility("default")))
#endif

#define MAX_TABLES 64
#define MAX_COLUMNS 64

#ifndef SPA_LUA_DIRECT
#define SPA_DEFINE(ret, name, args) ret (*spa_##name) args;
SPA_LUA_FUNCTIONS(SPA_DEFINE)
#undef SPA_DEFINE

int spa_lua_resolve(void)
{
	HMODULE exe = GetModuleHandleW(NULL);

	if (!exe)
		return 0;
#define SPA_FIND(ret, name, args) \
	spa_##name = (ret (*) args)(void (*)(void))GetProcAddress(exe, #name); \
	if (!spa_##name) \
		return 0;
	SPA_LUA_FUNCTIONS(SPA_FIND)
#undef SPA_FIND
	return 1;
}
#else
int spa_lua_resolve(void)
{
	return 1;
}
#endif

/* ---------------------------------------------------------------- helpers */
static void set_string(lua_State *L, const char *key, const char *value)
{
	if (!value)
		return;
	lua_pushstring(L, value);
	lua_setfield(L, -2, key);
}

static void set_number(lua_State *L, const char *key, double value)
{
	lua_pushnumber(L, (lua_Number)value);
	lua_setfield(L, -2, key);
}

static void push_list(lua_State *L, const slist *l)
{
	int i;

	lua_createtable(L, l->n, 0);
	for (i = 0; i < l->n; i++) {
		lua_pushstring(L, l->v[i]);
		lua_rawseti(L, -2, i + 1);
	}
}

static char *opt_string(lua_State *L, int t, const char *key)
{
	char *s = NULL;

	lua_getfield(L, t, key);
	if (lua_type(L, -1) == LUA_TSTRING) {
		size_t n;
		const char *v = lua_tolstring(L, -1, &n);
		s = spa_strndup(v, n);
	}
	lua_settop(L, -2);
	return s;
}

static const char *kind_name(int kind)
{
	return kind == PACK_VANILLA ? "vanilla" : kind == PACK_MOVIE ? "movie" : "mod";
}

static void push_packs(lua_State *L, const spa_packs *p)
{
	int i;

	set_string(L, "source", p->source);
	set_string(L, "game_dir", p->game_dir);
	lua_createtable(L, p->n, 0);
	for (i = 0; i < p->n; i++) {
		lua_createtable(L, 0, 3);
		set_string(L, "name", p->v[i].name);
		set_string(L, "path", p->v[i].path);
		set_string(L, "kind", kind_name(p->v[i].kind));
		lua_rawseti(L, -2, i + 1);
	}
	lua_setfield(L, -2, "packs");
	push_list(L, &p->working_dirs);
	lua_setfield(L, -2, "working_dirs");
}

/* the options a request may carry (tests); returned strings and pack list are malloc'd */
typedef struct {
	spa_pack_options opt;
	char *game_dir, *command_line, *cwd;
	char *packs[256];
	int npacks;
} request_options;

static void read_options(lua_State *L, int t, request_options *o)
{
	memset(o, 0, sizeof *o);
	if (lua_type(L, t) != LUA_TTABLE)
		return;
	o->game_dir = opt_string(L, t, "game_dir");
	o->command_line = opt_string(L, t, "command_line");
	o->cwd = opt_string(L, t, "cwd");
	lua_getfield(L, t, "packs");
	if (lua_type(L, -1) == LUA_TTABLE) {
		int i, n = (int)lua_objlen(L, -1);
		for (i = 1; i <= n && o->npacks < 256; i++) {
			lua_rawgeti(L, -1, i);
			if (lua_type(L, -1) == LUA_TSTRING) {
				size_t len;
				const char *s = lua_tolstring(L, -1, &len);
				o->packs[o->npacks++] = spa_strndup(s, len);
			}
			lua_settop(L, -2);
		}
	}
	lua_settop(L, -2);
	o->opt.game_dir = o->game_dir;
	o->opt.command_line = o->command_line;
	o->opt.cwd = o->cwd;
	o->opt.packs = (const char **)o->packs;
	o->opt.npacks = o->npacks;
}

static void free_options(request_options *o)
{
	int i;

	free(o->game_dir);
	free(o->command_line);
	free(o->cwd);
	for (i = 0; i < o->npacks; i++)
		free(o->packs[i]);
}

/* ---------------------------------------------------------------- N.mod_list([options]) */
static int l_mod_list(lua_State *L)
{
	request_options o;
	spa_packs p;
	int ok;

	read_options(L, 1, &o);
	ok = spa_find_packs(&o.opt, &p);
	lua_createtable(L, 0, 6);
	push_packs(L, &p);
	push_list(L, &p.warnings);
	lua_setfield(L, -2, "warnings");
	lua_pushboolean(L, ok);
	lua_setfield(L, -2, "ok");
	spa_packs_free(&p);
	free_options(&o);
	return 1;
}

/* ---------------------------------------------------------------- N.load_db(request) */
static void push_table(lua_State *L, const spa_table *t)
{
	size_t i;
	int j;

	lua_createtable(L, 0, 6);
	set_string(L, "table", t->table);
	set_number(L, "n", t->rows);
	lua_createtable(L, t->ncols, 0);
	for (j = 0; j < t->ncols; j++) {
		lua_pushstring(L, t->cols[j]);
		lua_rawseti(L, -2, j + 1);
	}
	lua_setfield(L, -2, "columns");
	lua_createtable(L, 0, t->ncols);
	for (j = 0; j < t->ncols; j++) {
		lua_pushboolean(L, t->col_found[j]);
		lua_setfield(L, -2, t->cols[j]);
	}
	lua_setfield(L, -2, "found");
	lua_createtable(L, (int)t->nvals, 0);
	for (i = 0; i < t->nvals; i++) {
		const spa_val *v = &t->vals[i];
		switch (v->tag) {
		case V_BOOL:
			lua_pushboolean(L, v->num != 0);
			break;
		case V_NUM:
			lua_pushnumber(L, (lua_Number)v->num);
			break;
		case V_STR:
			lua_pushlstring(L, t->strings.p + v->off, v->len);
			break;
		default:
			continue;
		}
		lua_rawseti(L, -2, (int)i + 1);
	}
	lua_setfield(L, -2, "data");
	lua_createtable(L, t->nfrags, 0);
	for (j = 0; j < t->nfrags; j++) {
		const spa_frag_info *f = &t->frags[j];
		lua_createtable(L, 0, 6);
		set_string(L, "name", f->name);
		set_string(L, "pack", f->pack);
		set_number(L, "version", f->version);
		set_number(L, "rows", f->rows);
		set_number(L, "kept", f->kept);
		set_string(L, "problem", f->problem);
		lua_rawseti(L, -2, j + 1);
	}
	lua_setfield(L, -2, "files");
}

static int load_db(lua_State *L, const char **names, const char *(*colv)[MAX_COLUMNS], const char *const **cols,
	int *ncols, request_options *o);

/* (the request's lists on the heap: the game's script thread may have a small stack) */
static int l_load_db(lua_State *L)
{
	const char **names = (const char **)malloc(MAX_TABLES * sizeof *names);
	const char *(*colv)[MAX_COLUMNS] = (const char *(*)[MAX_COLUMNS])malloc(MAX_TABLES * sizeof *colv);
	const char *const **cols = (const char *const **)malloc(MAX_TABLES * sizeof *cols);
	int *ncols = (int *)malloc(MAX_TABLES * sizeof *ncols);
	request_options *o = (request_options *)malloc(sizeof *o);
	int r;

	if (!names || !colv || !cols || !ncols || !o) {
		free(names);
		free(colv);
		free((void *)cols);
		free(ncols);
		free(o);
		lua_pushnil(L);
		lua_pushstring(L, "out of memory");
		return 2;
	}
	memset(o, 0, sizeof *o);
	r = load_db(L, names, colv, cols, ncols, o);
	free(names);
	free(colv);
	free((void *)cols);
	free(ncols);
	free(o);
	return r;
}

static int load_db(lua_State *L, const char **names, const char *(*colv)[MAX_COLUMNS], const char *const **cols,
	int *ncols, request_options *o)
{
	int ntables = 0, i;
	spa_result res;
	char digest[24];

	if (lua_type(L, 1) != LUA_TTABLE) {
		lua_pushnil(L);
		lua_pushstring(L, "load_db needs a request table");
		return 2;
	}
	lua_getfield(L, 1, "tables");
	if (lua_type(L, -1) != LUA_TTABLE) {
		lua_pushnil(L);
		lua_pushstring(L, "the request has no tables");
		return 2;
	}
	/* the names and columns stay on the Lua stack (in the request) while they are used */
	lua_pushnil(L);
	while (lua_next(L, -2)) {
		if (lua_type(L, -2) == LUA_TSTRING && lua_type(L, -1) == LUA_TTABLE && ntables < MAX_TABLES) {
			int n = (int)lua_objlen(L, -1), k, c = 0;
			names[ntables] = lua_tolstring(L, -2, NULL);
			for (k = 1; k <= n && c < MAX_COLUMNS; k++) {
				lua_rawgeti(L, -1, k);
				if (lua_type(L, -1) == LUA_TSTRING)
					colv[ntables][c++] = lua_tolstring(L, -1, NULL);
				lua_settop(L, -2);          /* (the string stays alive in the request's list) */
			}
			cols[ntables] = colv[ntables];
			ncols[ntables] = c;
			ntables++;
		}
		lua_settop(L, -2);
	}
	if (ntables == 0) {
		lua_pushnil(L);
		lua_pushstring(L, "the request names no tables");
		return 2;
	}
	read_options(L, 1, o);
	if (!spa_load(&o->opt, names, cols, ncols, ntables, &res)) {
		spa_result_free(&res);
		free_options(o);
		lua_pushnil(L);
		lua_pushstring(L, "the tables could not be read (out of memory, or the game's folder is unknown)");
		return 2;
	}
	lua_createtable(L, 0, 8);
	snprintf(digest, sizeof digest, "%016llx", (unsigned long long)res.digest);
	set_string(L, "digest", digest);
	push_packs(L, &res.packs);
	{
		slist all;
		memset(&all, 0, sizeof all);
		for (i = 0; i < res.packs.warnings.n; i++)
			sl_add(&all, res.packs.warnings.v[i]);
		for (i = 0; i < res.warnings.n; i++)
			sl_add(&all, res.warnings.v[i]);
		push_list(L, &all);
		sl_free(&all);
	}
	lua_setfield(L, -2, "warnings");
	lua_createtable(L, 0, ntables);
	for (i = 0; i < ntables; i++) {
		push_table(L, &res.tables[i]);
		lua_setfield(L, -2, names[i]);
	}
	lua_setfield(L, -2, "tables");
	spa_result_free(&res);
	free_options(o);
	return 1;
}

/* ---------------------------------------------------------------- the module */
SPA_EXPORT int luaopen_skill_preallocation_native(lua_State *L)
{
	if (!spa_lua_resolve())
		return 0;                       /* (require then gives true: the loader reports it) */
	lua_createtable(L, 0, 8);
	set_string(L, "version", SPA_NATIVE_VERSION);
	set_number(L, "api", SPA_NATIVE_API);
#ifdef _WIN32
	set_string(L, "platform", "windows");
#else
	set_string(L, "platform", "test");
#endif
	lua_pushcclosure(L, l_mod_list, 0);
	lua_setfield(L, -2, "mod_list");
	lua_pushcclosure(L, l_load_db, 0);
	lua_setfield(L, -2, "load_db");
	return 1;
}
