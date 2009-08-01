/*
** Copyright (C) 2009 ARATA Mizuki
** See file COPYRIGHT for more information
*/

#ifndef LOBJC_H
#define LOBJC_H

#include <lua.h>
#include <lauxlib.h>
#include <objc/objc.h>
#include <objc/runtime.h>

LUALIB_API void lobjc_pushid (lua_State *L, id obj);
LUALIB_API void lobjc_pushid_noretain (lua_State *L, id obj);
LUALIB_API void lobjc_rawpushid (lua_State *L, id obj);
LUALIB_API id lobjc_toid (lua_State *L, int idx);
LUALIB_API id lobjc_rawtoid (lua_State *L, int idx);

LUALIB_API int luaopen_objc_runtime (lua_State *L);
LUALIB_API int luaopen_objc_runtime_struct (lua_State *L);
LUALIB_API int luaopen_objc_runtime_ffi (lua_State *L);
LUALIB_API int luaopen_objc_runtime_pointer (lua_State *L);

static inline void lobjc_pushselector (lua_State *L, SEL sel) {
  lua_pushstring(L, sel_getName(sel));
}
static inline SEL lobjc_checkselector (lua_State *L, int n) {
  return sel_registerName(luaL_checkstring(L, n));
}
static inline void lobjc_pushclass (lua_State *L, Class cls) {
  lobjc_pushid(L, cls);
}
static inline Class lobjc_toclass (lua_State *L, int idx) {
  return (Class)lobjc_toid(L, idx);
}
/*
#define lobjc_pushselector(L, sel) \
    lua_pushstring(L, sel_getName(sel))
#define lobjc_toselector(L, n) \
    sel_registerName(luaL_checkstring(L, n))
#define lobjc_pushclass(L, cls) \
    lobjc_pushid(L, cls)
#define lobjc_toclass(L, idx) \
    (Class)lobjc_toid(L, idx)
*/

#endif
