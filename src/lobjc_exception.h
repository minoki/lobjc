/*
** Copyright (C) 2009 ARATA Mizuki
** See file COPYRIGHT for more information
*/

#ifndef LOBJC_EXCEPTION_H
#define LOBJC_EXCEPTION_H

#import <lua.h>
#import <Foundation/Foundation.h>

@interface lobjc_LuaError : NSException {
  lua_State *_lua;
}
- (id)initWithLuaState:(lua_State *)L errorMessage:(const char *)msg;
- (id)initWithLuaState:(lua_State *)L errorMessageAt:(int)idx;
@end

int lobjc_exception_rethrow_as_lua (lua_State *L, id ex);

#endif
