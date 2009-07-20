/*
** Copyright (C) 2009 ARATA Mizuki
** See file COPYRIGHT for more information
*/

// wraps a lua object

#ifndef LUAWRAPPER_H
#define LUAWRAPPER_H

#include <lua.h>
#include <stdbool.h>
#include <Foundation/NSObject.h>
#include <Foundation/NSValue.h>

@interface LuaWrapper : NSObject {
  lua_State *L_state;
  int ref;
}

// initialize with the value at the top of the stack
- (id)initWithLuaState:(lua_State *)L;

// pushes onto the stack
- (bool)lobjc_pushLuaValue:(lua_State *)L;

@end

#endif
