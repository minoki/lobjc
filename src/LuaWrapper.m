/*
** Copyright (C) 2009 ARATA Mizuki
** See file COPYRIGHT for more information
*/

#import "LuaWrapper.h"
#import "lobjc.h"
#import <lua.h>
#import <lauxlib.h>
#import <stdbool.h>
#import <Foundation/Foundation.h>

@implementation LuaWrapper

- (id)initWithLuaState:(lua_State *)L {
  self = [super init];
  if (self) {
    if (!L) {
      [self release];
      return nil;
    }
    lua_getfield(L, LUA_REGISTRYINDEX, "lobjc:wrapper_cache");
    if (lua_istable(L, -1)) {
      lua_pushvalue(L, -2);
      lua_gettable(L, -2);
      id a = lobjc_rawtoid(L, -1);
      if (a) {
        [a retain];
        [self release];
        return a;
      }
      lua_pop(L, 1);
    }
    lua_pop(L, 1);
    L_state = L;
    ref = luaL_ref(L, LUA_REGISTRYINDEX);
  }
  return self;
}

// what if L_state is closed?
- (void)dealloc {
  if (L_state && ref != LUA_REFNIL) {
    luaL_unref(L_state, LUA_REGISTRYINDEX, ref);
  }
  [super dealloc];
}

- (bool)lobjc_pushLuaValue:(lua_State *)L {
  if (ref == LUA_REFNIL) {
    lua_pushnil(L);
    return true;
  }
  if (L != L_state) {
    return false; // or try lua_xmove?
  }
  lua_rawgeti(L, LUA_REGISTRYINDEX, ref);
  return true;
}

@end


