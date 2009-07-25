/*
** Copyright (C) 2009 ARATA Mizuki
** See file COPYRIGHT for more information
*/

#import "LuaWrapper.h"
#import "lobjc.h"
#import "lobjc_invoke.h"
#import <lua.h>
#import <lauxlib.h>
#import <stdbool.h>
#import <Foundation/Foundation.h>

static id sel_to_id (SEL sel) {
  return [NSValue value: &sel withObjCType: @encode(SEL)];
}

@implementation LuaWrapper

- (id)initWithLuaState:(lua_State *)L {
  self = [super init];
  if (self) {
    if (!L) {
      [self release];
      return nil;
    }
    L_state = L;
    methods = [NSMutableDictionary new];
    if (!methods) {
      [self release];
      return nil;
    }
    lua_getfield(L, LUA_REGISTRYINDEX, "lobjc:wrapper_cache");
    lua_pushvalue(L, -2);
    lua_gettable(L, -2);
    id a = lobjc_rawtoid(L, -1);
    if (a) {
      lua_pop(L, 3); // pop fetched value and registry["lobjc:wrapper_cache"]
      [a retain];
      [self release];
      return a;
    } else {
      lua_pop(L, 1); // pop fetched value
      lua_pushvalue(L, -2);
      lobjc_rawpushid(L, self);
      lua_settable(L, -3);
      lua_pop(L, 1); // pop registry["lobjc:wrapper_cache"]
      ref = luaL_ref(L, LUA_REGISTRYINDEX);
    }
  }
  return self;
}

// what if L_state is closed?
- (void)dealloc {
  if (L_state && ref != LUA_REFNIL) {
    luaL_unref(L_state, LUA_REGISTRYINDEX, ref);
  }
  [methods release];
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

- (void)lobjc_addMethod:(SEL)sel type:(const char *)type {
  [methods setObject: [NSMethodSignature signatureWithObjCTypes: type]
              forKey: sel_to_id(sel)];
}

struct rts_params {
  int ref;
  const char *name;
  BOOL result;
};

static int respondsToSelector_aux (lua_State *L) {
  struct rts_params *p = lua_touserdata(L, 1);
  lua_rawgeti(L, LUA_REGISTRYINDEX, p->ref);
  luaL_gsub(L, p->name, ":", "_");
  lua_gettable(L, -2);
  p->result = !lua_isnil(L, -1);
  return 0;
}

- (BOOL)respondsToSelector:(SEL)sel {
  if ([methods objectForKey: sel_to_id(sel)]) {
    struct rts_params params = {.ref=ref, .name = sel_getName(sel), .result = NO};
    if (lua_cpcall(L_state, respondsToSelector_aux, &params)) {
      lua_pop(L_state, 1);
      return NO;
    }
    return params.result;
  }
  return [super respondsToSelector: sel];
}

- (NSMethodSignature *)methodSignatureForSelector:(SEL)sel {
  id m = [methods objectForKey: sel_to_id(sel)];
  return m ? m : [super methodSignatureForSelector: sel];
}

- (void)forwardInvocation:(NSInvocation *)inv {
  lobjc_invoke_lua_with_NSInvocation(L_state, ref, inv);
  //[super forwardInvocation: inv];
}

@end


