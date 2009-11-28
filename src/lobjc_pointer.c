/*
** Copyright (C) 2009 ARATA Mizuki
** See file COPYRIGHT for more information
*/

#include "lobjc.h"
#include "lobjc_convert.h"
#include <lua.h>
#include <lauxlib.h>
#include <stdint.h>
#include <string.h>
#include <stdbool.h>

static const char tname[] = "lobjc:pointer";

struct Pointer {
  void *ptr;
  bool readonly;
  char type[];
};

void lobjc_pushpointer (lua_State *L, const char *t, void *ptr) {
  if (ptr == NULL) {
    lua_pushnil(L);
  } else {
    struct Pointer *p = lua_newuserdata(L, sizeof(struct Pointer)+strlen(t)+1);
    luaL_getmetatable(L, tname);
    lua_setmetatable(L, -2);
    p->ptr = ptr;
    p->readonly = false;
    strcpy(p->type, t);
  }
}

void lobjc_pushconstpointer (lua_State *L, const char *t, const void *ptr) {
  if (ptr == NULL) {
    lua_pushnil(L);
  } else {
    struct Pointer *p = lua_newuserdata(L, sizeof(struct Pointer)+strlen(t)+1);
    luaL_getmetatable(L, tname);
    lua_setmetatable(L, -2);
    p->ptr = (void *)ptr;
    p->readonly = true;
    strcpy(p->type, t);
  }
}

void *lobjc_checkpointer (lua_State *L, int narg, const char *t) {
  struct Pointer *p = luaL_checkudata(L, narg, tname);
  if (t && strcmp(t, p->type) != 0) {
    const char *extramsg = lua_pushfstring(L, "pointer of type '%s' expected, but got '%s'", t, p->type);
    luaL_argerror(L, narg, extramsg);
  }
  if (p->readonly) {
    luaL_argerror(L, narg, "pointer is readonly");
  }
  return p->ptr;
}

const void *lobjc_checkconstpointer (lua_State *L, int narg, const char *t) {
  struct Pointer *p = luaL_checkudata(L, narg, tname);
  if (t && strcmp(t, p->type) != 0) {
    const char *extramsg = lua_pushfstring(L, "pointer of type '%s' expected, but got '%s'", t, p->type);
    luaL_argerror(L, narg, extramsg);
  }
  return p->ptr;
}

static int ptr_get (lua_State *L) {
  struct Pointer *p = luaL_checkudata(L, 1, tname);
  if (lua_isnumber(L, 2)) {
    size_t size = lobjc_conv_sizeof(L, p->type);
    ptrdiff_t offset = size*lua_tointeger(L, 2);
    lobjc_conv_objctolua1(L, p->type, (char *)p->ptr+offset);
  } else {
    lobjc_conv_objctolua1(L, p->type, p->ptr);
  }
  return 1;
}

static int ptr_set (lua_State *L) {
  struct Pointer *p = luaL_checkudata(L, 1, tname);
  if (p->readonly) {
    luaL_argerror(L, 1, "pointer is readonly");
  }
  if (lua_isnumber(L, 2)) {
    size_t size = lobjc_conv_sizeof(L, p->type);
    ptrdiff_t offset = size*lua_tointeger(L, 2);
    lobjc_conv_luatoobjc1(L, 2, p->type, (char *)p->ptr+offset);
  } else {
    lobjc_conv_luatoobjc1(L, 2, p->type, p->ptr);
  }
  return 0;
}

static int ptr_touserdata (lua_State *L) {
  struct Pointer *p = luaL_checkudata(L, 1, tname);
  lua_pushlightuserdata(L, p->ptr);
  return 1;
}

static int ptr_tonumber (lua_State *L) {
  struct Pointer *p = luaL_checkudata(L, 1, tname);
  lua_pushnumber(L, (intptr_t)p->ptr);
  return 1;
}

static int ptr_type (lua_State *L) {
  struct Pointer *p = luaL_checkudata(L, 1, tname);
  lua_pushstring(L, p->type);
  return 1;
}

static int ptr_readonly (lua_State *L) {
  struct Pointer *p = luaL_checkudata(L, 1, tname);
  lua_pushboolean(L, p->readonly);
  return 1;
}

static int ptr_tostring (lua_State *L) {
  struct Pointer *p = luaL_checkudata(L, 1, tname);
  if (p->readonly) {
    lua_pushfstring(L, "readonly pointer %p of type '%s'", p->ptr, p->type);
  } else {
    lua_pushfstring(L, "pointer %p of type '%s'", p->ptr, p->type);
  }
  return 1;
}

static luaL_Reg funcs[] = {
  {"get", ptr_get},
  {"set", ptr_set},
  {"touserdata", ptr_touserdata},
  {"tonumber", ptr_tonumber},
  {"type", ptr_type},
  {"readonly", ptr_readonly},
  {"__tostring", ptr_tostring},
  {NULL, NULL}
};

LUALIB_API int luaopen_objc_runtime_pointer (lua_State *L) {
  luaL_newmetatable(L, tname);
  lua_pushvalue(L, -1);
  lua_setfield(L, -2, "__index");
  luaL_register(L, NULL, funcs);
  return 0;
}
