/*
** Copyright (C) 2009 ARATA Mizuki
** See file COPYRIGHT for more information
*/

// wraps a lua object

#ifndef LUAWRAPPER_H
#define LUAWRAPPER_H

#include <lua.h>
#include <stdbool.h>
#include <Foundation/Foundation.h>

@interface LuaWrapper : NSObject {
  lua_State *L_state;
  int ref;
  NSMutableDictionary *methods;
}

// initialize with the value at the top of the stack
- (id)initWithLuaState:(lua_State *)L;

// pushes onto the stack
- (bool)lobjc_pushLuaValue:(lua_State *)L;

- (void)lobjc_addMethod:(SEL)sel type:(const char *)type;

@end

#endif
