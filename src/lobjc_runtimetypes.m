/*
** Copyright (C) 2010 ARATA Mizuki
** See file COPYRIGHT for more information
*/

#import "lobjc_runtimetypes.h"
#import "lobjc.h"
#import "lobjc_luawrapper.h"

#import "objc-runtime.h"
#import <lua.h>
#import <lauxlib.h>

const char * const tname_id = "objc:id";
static const char tname_Method[] = "objc:Method";
static const char tname_Ivar[] = "objc:Ivar";
#if !defined(DISABLE_OBJC2_PROPERTIES)
static const char tname_property[] = "objc:objc_property_t";
#endif

LUALIB_API void lobjc_pushselector (lua_State *L, SEL sel) {
  lua_pushstring(L, sel_getName(sel));
}

LUALIB_API SEL lobjc_checkselector (lua_State *L, int n) {
  return sel_registerName(luaL_checkstring(L, n));
}

LUALIB_API void lobjc_pushclass (lua_State *L, Class cls) {
  lobjc_pushid(L, cls);
}

LUALIB_API Class lobjc_toclass (lua_State *L, int idx) {
  id o = lobjc_toid(L, idx);
  return class_isMetaClass(object_getClass(o)) ? (Class)o : Nil;
}

static void pushid_impl (lua_State *L, id obj, bool retain, bool try_method) {
#if defined(GNU_RUNTIME)
  // With GNU runtime, you die if you send a message to a metaclass
  bool is_meta_class = class_isMetaClass(obj);
  try_method = try_method && !is_meta_class;
  retain = retain && !is_meta_class;
#endif
  if (obj == nil) {
    lua_pushnil(L); // TODO: reconsider this behavior
  } else if (try_method && [obj respondsToSelector: @selector(lobjc_pushLuaValue:)]
          && [obj lobjc_pushLuaValue: L]) {
  } else {
    lua_getfield(L, LUA_REGISTRYINDEX, "lobjc:id_cache");
    lua_pushlightuserdata(L, (void *)obj);
    lua_rawget(L, -2);
    if (lua_isnil(L, -1)) {
      lua_pop(L, 1);

      id *ptr = (id*)lua_newuserdata(L, sizeof(id));
      *ptr = nil;

      luaL_getmetatable(L, tname_id);
      lua_setmetatable(L, -2);

      // we retain obj AFTER we have set its metatable
      // (to make sure __gc is called)
      if (retain) {
        [obj retain];
      }
      *ptr = obj;

      lua_pushlightuserdata(L, (void *)obj);
      lua_pushvalue(L, -2);
      lua_settable(L, -4);
    }
    lua_remove(L, -2); // remove cache table
  }
}
LUALIB_API void lobjc_pushid (lua_State *L, id obj) {
  pushid_impl(L, obj, true, true);
}

LUALIB_API void lobjc_pushid_noretain (lua_State *L, id obj) {
  pushid_impl(L, obj, false, true);
}

LUALIB_API void lobjc_rawpushid (lua_State *L, id obj) {
  pushid_impl(L, obj, true, false);
}


LUALIB_API id lobjc_toid (lua_State *L, int idx) {
  int type = lua_type(L, idx);
  if (type == LUA_TUSERDATA) { // TODO: try metamethod
    lua_getmetatable(L, idx);
    luaL_getmetatable(L, tname_id);
    if (lua_rawequal(L, -1, -2)) {
      lua_pop(L, 2);
      return *(id*)lua_touserdata(L, idx);
    }
    lua_pop(L, 2);
  } else if (type == LUA_TNUMBER) {
    return [[[lobjc_LuaNumberProxy alloc] initWithLuaNumber: lua_tonumber(L, idx)] autorelease];
  } else if (type == LUA_TSTRING) {
    size_t len = 0;
    const char *str = lua_tolstring(L, idx, &len);
    return [[[lobjc_LuaStringProxy alloc] initWithLuaString: str length: len] autorelease];
  } else if (type == LUA_TBOOLEAN) {
    return [[[lobjc_LuaBooleanProxy alloc] initWithBool: lua_toboolean(L, idx)] autorelease];
  } else if (type == LUA_TNIL || type == LUA_TNONE) {
    return nil;
  }
  lua_pushvalue(L, idx);
  return [[[lobjc_LuaValueWrapper alloc] initWithLuaState: L] autorelease];
}

LUALIB_API id lobjc_rawtoid (lua_State *L, int idx) {
  if (lua_isuserdata(L, idx)) {
    lua_getmetatable(L, idx);
    luaL_getmetatable(L, tname_id);
    if (lua_rawequal(L, -1, -2)) {
      lua_pop(L, 2);
      return *(id*)lua_touserdata(L, idx);
    }
    lua_pop(L, 2);
  }
  return nil;
}


static bool lobjc_pushptr (lua_State *L, void *obj, const char *tname, const char *cache) {
  if (obj == nil) {
    lua_pushnil(L);
  } else {
    lua_getfield(L, LUA_REGISTRYINDEX, cache);
    lua_pushlightuserdata(L, obj);
    lua_rawget(L, -2);
    if (lua_isnil(L, -1)) {
      lua_pop(L, 1);

      *(void**)lua_newuserdata(L, sizeof(void *)) = obj;

      luaL_getmetatable(L, tname);
      lua_setmetatable(L, -2);

      lua_pushlightuserdata(L, obj);
      lua_pushvalue(L, -2);
      lua_settable(L, -4);
      lua_remove(L, -2); // remove cache table
      return true;
    }
    lua_remove(L, -2); // remove cache table
  }
  return false;
}


void lobjc_pushIvar (lua_State *L, Ivar p) {
  lobjc_pushptr(L, p, tname_Ivar, "lobjc:Ivar_cache");
}

Ivar lobjc_checkIvar (lua_State *L, int narg) {
  return *(Ivar *)luaL_checkudata(L, narg, tname_Ivar);
}

void lobjc_pushMethod (lua_State *L, Method p) {
  lobjc_pushptr(L, p, tname_Method, "lobjc:Method_cache");
}

Method lobjc_checkMethod (lua_State *L, int narg) {
  return *(Method *)luaL_checkudata(L, narg, tname_Method);
}

#if !defined(DISABLE_OBJC2_PROPERTIES)
void lobjc_pushproperty (lua_State *L, objc_property_t p) {
  lobjc_pushptr(L, p, tname_property, "lobjc:property_cache");
}

objc_property_t lobjc_checkproperty (lua_State *L, int narg) {
  return *(objc_property_t *)luaL_checkudata(L, narg, tname_property);
}
#endif

void lobjc_pushProtocol (lua_State *L, Protocol *p) {
  lobjc_pushid(L, p);
}

Protocol *lobjc_checkProtocol (lua_State *L, int narg) {
  // TODO: check if the value really is a Protocol
  id protocol = lobjc_rawtoid(L, idx);
  if (protocol == nil) {
    luaL_typerror(L, narg, "Protocol");
  }
  return protocol;
}



static void initcache (lua_State *L, const char *name) {
  lua_createtable(L, 0, 1);
  lua_pushliteral(L, "v");
  lua_setfield(L, -2, "__mode");
  lua_pushvalue(L, -1);
  lua_setmetatable(L, -2);
  lua_setfield(L, LUA_REGISTRYINDEX, name);
}

int luaopen_objc_runtime_types (lua_State *L) {
  initcache(L, "lobjc:id_cache");
  initcache(L, "lobjc:Method_cache");
  initcache(L, "lobjc:Ivar_cache");
#if !defined(DISABLE_OBJC2_PROPERTIES)
  initcache(L, "lobjc:property_cache");
#endif

  luaL_register(L, "objc.runtime", (const luaL_Reg[]){{NULL, NULL}});
  luaL_newmetatable(L, tname_id);
  lua_setfield(L, -2, "__id_metatable");
  luaL_newmetatable(L, tname_Method);
  lua_setfield(L, -2, "__Method_metatable");
  luaL_newmetatable(L, tname_Ivar);
  lua_setfield(L, -2, "__Ivar_metatable");
#if !defined(DISABLE_OBJC2_PROPERTIES)
  luaL_newmetatable(L, tname_property);
  lua_setfield(L, -2, "__property_metatable");
#endif
  return 1;
}
