/*
** Copyright (C) 2009 ARATA Mizuki
** See file COPYRIGHT for more information
*/

#import "lobjc_exception.h"
#import "lobjc.h"
#import <lua.h>
#import <Foundation/Foundation.h>

@implementation lobjc_LuaError
- (id)initWithLuaState:(lua_State *)L errorMessage:(const char *)msg {
  _lua = L;
  if (strstr(msg, "Objective-C exception: ") != NULL) {
    lua_getfield(L, LUA_REGISTRYINDEX, "lobjc-currentexception");
    if (lua_isuserdata(L, -1)) {
      id realException = [lobjc_toid(L, -1) retain];
      lua_pop(L, 1);
      lua_pushnil(L);
      lua_setfield(L, LUA_REGISTRYINDEX, "lobjc-currentexception");
      [self release];
      return realException;
    }
    lua_pop(L, 1);
  }
  self = [super initWithName:@"LuaError"
                      reason:[NSString stringWithUTF8String:msg]
                    userInfo:[NSDictionary dictionary]];
  return self;
}
- (id)initWithLuaState:(lua_State *)L errorMessageAt:(int)idx {
  return [self initWithLuaState:L errorMessage:lua_tostring(L, idx)];
}
- (void)dealloc {
  [super dealloc];
}
@end

int lobjc_exception_rethrow_as_lua (lua_State *L, id ex) {
  if ([ex isKindOfClass:[lobjc_LuaError class]]) {
    lua_pushstring(L, [[ex reason] UTF8String]);
  } else {
    lobjc_pushid(L, ex);
    lua_setfield(L, LUA_REGISTRYINDEX, "lobjc-currentexception");
    if ([ex isKindOfClass:[NSException class]]) {
      lua_pushfstring(L, "Objective-C exception: %s: %s", [[ex name] UTF8String], [[ex reason] UTF8String]);
    } else {
      NSString *msg = [ex description];
      lua_pushfstring(L, "Objective-C exception: <%p> %s", ex, msg ? [msg UTF8String] : "unknown");
    }
  }
  return lua_error(L);
}

