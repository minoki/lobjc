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

@interface lobjc_LuaValueWrapper : NSObject {
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

@interface lobjc_LuaValueProxy : NSProxy {
  id _realObject;
}
- (bool)lobjc_pushLuaValue:(lua_State *)L;
@end

@interface lobjc_LuaNumberProxy : lobjc_LuaValueProxy {
  lua_Number _value;
}
- (id)initWithLuaNumber:(lua_Number)value;
@end

@interface lobjc_LuaBooleanProxy : lobjc_LuaValueProxy {
  bool _value;
}
- (id)initWithBool:(bool)value;
@end

@interface lobjc_LuaStringProxy : lobjc_LuaValueProxy {
  char *_str;
  size_t _len;
}
- (id)initWithLuaString:(const char *)str length:(size_t)len;
@end

#endif
