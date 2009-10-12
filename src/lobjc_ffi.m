/*
** Copyright (C) 2009 ARATA Mizuki
** See file COPYRIGHT for more information
*/

#define _GNU_SOURCE

#import "lobjc.h"
#import "lobjc_convert.h"
#import "lobjc_invoke.h"

#import <dlfcn.h>
#import <lua.h>
#import <lauxlib.h>
#import <stdbool.h>

static const char dylib_tname[] = "lobjc:dylib";

static int function_aux (lua_State *L) {
  void (*fn)() = (void (*)())lua_touserdata(L, lua_upvalueindex(1));
  const char *sig = lua_tostring(L, lua_upvalueindex(2));
  unsigned int argc = (unsigned int)lua_tointeger(L, lua_upvalueindex(3));
  bool already_retained = (bool)lua_toboolean(L, lua_upvalueindex(4));
  return lobjc_invoke_func(L, fn, sig, argc, 1, already_retained);
}

static int lobjc_loadfunction (lua_State *L) { /** loadfunction(hnd,name,type,argc,already_retained) */
  void *hnd = *(void **)luaL_checkudata(L, 1, dylib_tname);
  const char *name = luaL_checkstring(L, 2);
  luaL_checkstring(L, 3); // type encoding
  lua_Integer argc = luaL_checkinteger(L, 4);
  luaL_argcheck(L, argc >= 0, 3, "argc must be non-negative");
  luaL_checktype(L, 5, LUA_TBOOLEAN); // already_retained
  void *fn = dlsym(hnd, name);
  if (!fn) {
    lua_pushnil(L);
    lua_pushstring(L, dlerror());
    return 2;
  }
  lua_pushlightuserdata(L, fn); // function pointer
  lua_pushvalue(L, 3); // type encoding
  lua_pushvalue(L, 4); // number of arguments
  lua_pushvalue(L, 5); // already_retained
  lua_pushvalue(L, 1); // make resulting function refer to the dylib
  lua_pushcclosure(L, function_aux, 5);
  return 1;
}

static int lobjc_getglobal (lua_State *L) { /** getglobal(hnd,name,type) */
  void *hnd = *(void **)luaL_checkudata(L, 1, dylib_tname);
  const char *name = luaL_checkstring(L, 2);
  const char *e = luaL_checkstring(L, 3);
  void *p = dlsym(hnd, name);
  if (!p) {
    lua_pushnil(L);
    lua_pushstring(L, dlerror());
    return 2;
  }
  lobjc_conv_objctolua1(L, e, p);
  return 1;
}

static int lobjc_opendylib (lua_State *L) { /** opendylib(name) */
  const char *name = luaL_checkstring(L, 1);
  void **p = lua_newuserdata(L, sizeof(void *));
  *p = NULL;
  luaL_getmetatable(L, dylib_tname);
  lua_setmetatable(L, -2);
  *p = dlopen(name, RTLD_NOW | RTLD_LOCAL);
  if (!*p) {
    lua_pushnil(L);
    lua_pushstring(L, dlerror());
    return 2;
  }
  return 1;
}

static int dylib_gc (lua_State *L) { /** __gc(hnd) */
  void *hnd = *(void **)lua_touserdata(L, 1);
  if (hnd && hnd != RTLD_DEFAULT) {
    dlclose(hnd);
  }
  return 0;
}

static const luaL_Reg dylib_funcs[] = {
  {"__gc", dylib_gc},
  {NULL, NULL}
};

static const luaL_Reg funcs[] = {
  {"loadfunction", lobjc_loadfunction},
  {"getglobal", lobjc_getglobal},
  {"opendylib", lobjc_opendylib},
  {NULL, NULL}
};

LUALIB_API int luaopen_objc_runtime_ffi (lua_State *L) {
  luaL_newmetatable(L, dylib_tname);
  luaL_register(L, NULL, dylib_funcs);
  luaL_register(L, "objc.runtime.ffi", funcs);

  *(void **)lua_newuserdata(L, sizeof(void *)) = RTLD_DEFAULT;
  luaL_getmetatable(L, dylib_tname);
  lua_setmetatable(L, -2);
  lua_setfield(L, -2, "RTLD_DEFAULT");

  return 1;
}
