/*
** Copyright (C) 2009 ARATA Mizuki
** See file COPYRIGHT for more information
*/

#import "lobjc_luawrapper.h"
#import "lobjc.h"
#import "lobjc_invoke.h"
#import <lua.h>
#import <lauxlib.h>
#import <stdbool.h>
#import <Foundation/Foundation.h>
#if defined(__NEXT_RUNTIME__)
#include <objc/runtime.h>
#elif defined(GNU_RUNTIME)
#include "lobjc-compat.h"
#else
#error "unknown Objective-C runtime"
#endif

static id sel_to_id (SEL sel) {
  return [NSValue value: &sel withObjCType: @encode(SEL)];
}

@interface lobjc_LuaValueWrapperInfo : NSObject {
@public
  NSMutableDictionary *methods;
}

+ (id)wrapperInfoWithLuaState:(lua_State *)L;

- (void)lobjc_addMethod:(SEL)sel type:(const char *)type;

@end

@implementation lobjc_LuaValueWrapperInfo

+ (id)wrapperInfoWithLuaState:(lua_State *)L {
  lua_getfield(L, LUA_REGISTRYINDEX, "lobjc:wrapperinfo");
  lua_pushvalue(L, -2); // the lua value
  lua_gettable(L, -2);
  id a = lobjc_toid(L, -1);
  if (a) {
    lua_pop(L, 2); // pop fetched value and registry["lobjc:wrapperinfo"]
    return a;
  } else {
    a = [self new];
    lua_pop(L, 1); // pop fetched value
    lua_pushvalue(L, -2); // the lua value
    lobjc_pushid_noretain(L, a);
    lua_settable(L, -3);
    lua_pop(L, 1); // pop registry["lobjc:wrapperinfo"]
    return a;
  }
}

- (id)init {
  self = [super init];
  if (self) {
    methods = [NSMutableDictionary new];
    if (!methods) {
      [self release];
      return nil;
    }
  }
  return self;
}

- (void)dealloc {
  [methods release];
  [super dealloc];
}

- (void)lobjc_addMethod:(SEL)sel type:(const char *)type {
  [methods setObject: [NSMethodSignature signatureWithObjCTypes: type]
              forKey: sel_to_id(sel)];
}

@end


@implementation lobjc_LuaValueWrapper

- (id)initWithLuaState:(lua_State *)L {
  self = [super init];
  if (self) {
    if (!L) {
      [self release];
      return nil;
    }
    L_state = L;
    info = [[lobjc_LuaValueWrapperInfo wrapperInfoWithLuaState: L] retain];
    if (!info) {
      [self release];
      return nil;
    }
    lua_getfield(L, LUA_REGISTRYINDEX, "lobjc:wrapper_cache");
    lua_pushvalue(L, -2); // the lua value
    lua_gettable(L, -2);
    id a = lobjc_toid(L, -1);
    if (a) {
      lua_pop(L, 3); // pop fetched value and registry["lobjc:wrapper_cache"]
      [a retain];
      [self release];
      return a;
    } else {
      lua_pop(L, 1); // pop fetched value
      lua_pushvalue(L, -2); // the lua value
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
  [info release];
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
  [info lobjc_addMethod:sel type:type];
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
  if ([info->methods objectForKey: sel_to_id(sel)]) {
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
  id m = [info->methods objectForKey: sel_to_id(sel)];
  return m ? m : [super methodSignatureForSelector: sel];
}

- (void)forwardInvocation:(NSInvocation *)inv {
  lobjc_invoke_lua_with_NSInvocation(L_state, ref, inv);
  //[super forwardInvocation: inv];
}

@end


@implementation lobjc_LuaValueProxy

- (void)dealloc {
  [_realObject release];
  [super dealloc];
}

- (BOOL)respondsToSelector:(SEL)sel {
  if (sel_isEqual(sel, @selector(lobjc_pushLuaValue:))) {
    return YES;
  }
  return [_realObject respondsToSelector: sel];
}

- (NSMethodSignature *)methodSignatureForSelector:(SEL)sel {
  return [_realObject methodSignatureForSelector: sel];
}

- (void)forwardInvocation:(NSInvocation *)inv {
  [inv invokeWithTarget: _realObject];
}

- (bool)lobjc_pushLuaValue:(lua_State *)L {
  return false;
}

@end

@implementation lobjc_LuaNumberProxy

- (id)initWithLuaNumber:(lua_Number)value {
#if defined(LUA_NUMBER_DOUBLE)
  _realObject = [[NSNumber alloc] initWithDouble: value];
#else
# error "cannot convert lua_Number to NSNumber"
#endif
  _value = value;
  return self;
}

- (bool)lobjc_pushLuaValue:(lua_State *)L {
  lua_pushnumber(L, _value);
  return true;
}

@end

@implementation lobjc_LuaBooleanProxy

- (id)initWithBool:(bool)value {
  _realObject = [[NSNumber alloc] initWithBool: value];
  _value = value;
  return self;
}

- (bool)lobjc_pushLuaValue:(lua_State *)L {
  lua_pushboolean(L, _value);
  return true;
}

@end

@implementation lobjc_LuaStringProxy

- (id)initWithLuaString:(const char *)str length:(size_t)len {
  _realObject = [[NSString alloc] initWithUTF8String: str];
  _str = malloc(len+1);
  memcpy(_str, str, len+1);
  _len = len;
  return self;
}

- (void)dealloc {
  free(_str);
  [super dealloc];
}

- (bool)lobjc_pushLuaValue:(lua_State *)L {
  lua_pushlstring(L, _str, _len);
  return true;
}

@end


