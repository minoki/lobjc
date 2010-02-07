/*
** Copyright (C) 2009 ARATA Mizuki
** See file COPYRIGHT for more information
*/

#include "lobjc.h"
#include "lobjc_convert.h"
#include "typeencoding.h"

#include <lua.h>
#include <lauxlib.h>
#include <string.h>

static const char tname_struct[] = "lobjc:struct";
static const char struct_registry_key[] = "lobjc:struct_registry";

static inline size_t round_align(size_t n, size_t align) {
  return ((n+align-1)/align)*align;
}

static int struct_toobjc (lua_State *L) { /** __toobjc(self,type) */
  luaL_checktype(L, 1, LUA_TTABLE);
  size_t typeenc_len;
  const char *e = luaL_checklstring(L, 2, &typeenc_len);
  const char *type = e;
  luaL_argcheck(L, typeenc_len > 3, 2, "bad type encoding (too short)");
  luaL_argcheck(L, e[0] == '{' && e[typeenc_len-1] == '}', 2, "bad type encoding");
  const char *sep = strchr(e, '=');
  luaL_argcheck(L, sep != NULL, 2, "bad type encoding ('=' missing)");

  // check if 'type' has a tag
  if (*++e != '?') {
    lua_getfield(L, 1, ":tagname:");
    size_t name2_len;
    const char *name2 = lua_tolstring(L, -1, &name2_len);
    if(name2 && (name2_len != sep-e || strncmp(e, name2, sep-e) != 0)) {
      lua_pushlstring(L, e, sep-e);
      return luaL_error(L, "structure tagname mismatch ('%s' expected, got '%s')", lua_tostring(L, -1), name2);
    }
    lua_pop(L, 1);
  }
  e = sep+1;

  void *buffer = lua_newuserdata(L, lobjc_conv_sizeof(L, type));
  size_t pos = 0;
  for (int i = 1; *e != '}'; ++i) {
    pos = round_align(pos, lobjc_conv_alignof(L, e));
    lua_rawgeti(L, 1, i);
    lobjc_conv_luatoobjc1(L, -1, e, (char *)buffer+pos);
    lua_pop(L, 1);
    pos += lobjc_conv_sizeof(L, e);
    e = skip_type(L, e);
  }
  return 1;
}


static const luaL_Reg structfuncs[] = {
  {"__toobjc", struct_toobjc},
  {NULL, NULL}
};

static const luaL_Reg funcs[] = {
  {NULL, NULL}
};

LUALIB_API int luaopen_objc_runtime_struct (lua_State *L) {
  luaL_register(L, "objc.runtime", funcs);

  lua_newtable(L);
  lua_pushvalue(L, -1);
  lua_setfield(L, LUA_REGISTRYINDEX, struct_registry_key);
  lua_setfield(L, -2, "__struct_registry");

  luaL_newmetatable(L, tname_struct);
  luaL_register(L, NULL, structfuncs);
  lua_setfield(L, -2, "__struct_metatable");
  return 1;
}


