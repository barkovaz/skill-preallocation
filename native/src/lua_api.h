/* The Lua C API of the game.
 *
 * Warhammer3.exe has Lua 5.1 built in, with 32-bit float numbers (vendor/lua-5.1/luaconf.h), and exports
 * its API functions by name. The module looks them up in the running exe when it loads instead of
 * linking to them, so a missing one gives a clear message rather than a DLL that can't load.
 * The offline tests (SPA_LUA_DIRECT) link to the test interpreter's own functions instead.
 */
#ifndef SPA_LUA_API_H
#define SPA_LUA_API_H

#include "lua.h"

#define SPA_LUA_FUNCTIONS(X) \
	X(int, lua_gettop, (lua_State *L)) \
	X(void, lua_settop, (lua_State *L, int idx)) \
	X(int, lua_type, (lua_State *L, int idx)) \
	X(const char *, lua_tolstring, (lua_State *L, int idx, size_t *len)) \
	X(lua_Number, lua_tonumber, (lua_State *L, int idx)) \
	X(int, lua_toboolean, (lua_State *L, int idx)) \
	X(size_t, lua_objlen, (lua_State *L, int idx)) \
	X(int, lua_next, (lua_State *L, int idx)) \
	X(void, lua_pushnil, (lua_State *L)) \
	X(void, lua_pushnumber, (lua_State *L, lua_Number n)) \
	X(void, lua_pushboolean, (lua_State *L, int b)) \
	X(void, lua_pushlstring, (lua_State *L, const char *s, size_t len)) \
	X(void, lua_pushstring, (lua_State *L, const char *s)) \
	X(void, lua_pushvalue, (lua_State *L, int idx)) \
	X(void, lua_createtable, (lua_State *L, int narr, int nrec)) \
	X(void, lua_rawseti, (lua_State *L, int idx, int n)) \
	X(void, lua_rawgeti, (lua_State *L, int idx, int n)) \
	X(void, lua_setfield, (lua_State *L, int idx, const char *k)) \
	X(void, lua_getfield, (lua_State *L, int idx, const char *k)) \
	X(void, lua_pushcclosure, (lua_State *L, lua_CFunction fn, int n)) \
	X(int, lua_error, (lua_State *L)) \
	X(int, lua_checkstack, (lua_State *L, int sz))

#ifndef SPA_LUA_DIRECT
#define SPA_DECLARE(ret, name, args) extern ret (*spa_##name) args;
SPA_LUA_FUNCTIONS(SPA_DECLARE)
#undef SPA_DECLARE

#define lua_gettop spa_lua_gettop
#define lua_settop spa_lua_settop
#define lua_type spa_lua_type
#define lua_tolstring spa_lua_tolstring
#define lua_tonumber spa_lua_tonumber
#define lua_toboolean spa_lua_toboolean
#define lua_objlen spa_lua_objlen
#define lua_next spa_lua_next
#define lua_pushnil spa_lua_pushnil
#define lua_pushnumber spa_lua_pushnumber
#define lua_pushboolean spa_lua_pushboolean
#define lua_pushlstring spa_lua_pushlstring
#define lua_pushstring spa_lua_pushstring
#define lua_pushvalue spa_lua_pushvalue
#define lua_createtable spa_lua_createtable
#define lua_rawseti spa_lua_rawseti
#define lua_rawgeti spa_lua_rawgeti
#define lua_setfield spa_lua_setfield
#define lua_getfield spa_lua_getfield
#define lua_pushcclosure spa_lua_pushcclosure
#define lua_error spa_lua_error
#define lua_checkstack spa_lua_checkstack
#endif

/* 1 when every function was found (always, in the tests) */
int spa_lua_resolve(void);

#endif
