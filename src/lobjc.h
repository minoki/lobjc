/*
** Copyright (C) 2009 ARATA Mizuki
** See file COPYRIGHT for more information
*/

#ifndef LOBJC_H
#define LOBJC_H

#include <lua.h>
#include <lauxlib.h>
#include <objc/objc.h>

LUALIB_API void lobjc_pushid (lua_State *L, id obj);
LUALIB_API void lobjc_pushid_noretain (lua_State *L, id obj);
LUALIB_API void lobjc_rawpushid (lua_State *L, id obj);
LUALIB_API id lobjc_toid (lua_State *L, int idx);
LUALIB_API id lobjc_rawtoid (lua_State *L, int idx);
LUALIB_API void lobjc_pushselector (lua_State *L, SEL sel);
LUALIB_API SEL lobjc_checkselector (lua_State *L, int n);
LUALIB_API void lobjc_pushclass (lua_State *L, Class cls);
LUALIB_API Class lobjc_toclass (lua_State *L, int idx);

LUALIB_API int luaopen_objc_runtime (lua_State *L);
LUALIB_API int luaopen_objc_runtime_struct (lua_State *L);
LUALIB_API int luaopen_objc_runtime_ffi (lua_State *L);
LUALIB_API int luaopen_objc_runtime_pointer (lua_State *L);
LUALIB_API int luaopen_objc_runtime_bridgesupport (lua_State *L);
LUALIB_API int luaopen_objc_runtime_cfunction (lua_State *L);

#endif
