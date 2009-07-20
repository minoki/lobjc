/*
** Copyright (C) 2009 ARATA Mizuki
** See file COPYRIGHT for more information
*/

#import "lobjc_exception.h"
#import "lobjc.h"
#import <lua.h>
#import <Foundation/Foundation.h>

int lobjc_exception_rethrow_as_lua (lua_State *L, id ex) {
  lobjc_pushid(L, ex);
  lua_setfield(L, LUA_REGISTRYINDEX, "lobjc-currentexception");
  if ([ex isKindOfClass:[NSException class]]) {
    lua_pushfstring(L, "Objective-C exception: %s: %s", [[ex name] UTF8String], [[ex reason] UTF8String]);
  } else {
    NSString *msg = [ex description];
    lua_pushfstring(L, "Objective-C exception: <%p> %s", ex, msg ? [msg UTF8String] : "unknown");
  }
  return lua_error(L);
}

