/*
** Copyright (C) 2009 ARATA Mizuki
** See file COPYRIGHT for more information
*/

#ifndef LOBJC_INVOKE_H
#define LOBJC_INVOKE_H

#include <lua.h>
#include <stdbool.h>
#include <objc/objc.h>
#include <ffi.h>

#if defined(__OBJC__)
@class NSMethodSignature;
@class NSInvocation;
#else
typedef struct objc_object NSMethodSignature, NSInvocation;
#endif

int lobjc_invoke_func (lua_State *L, void (*fn)(), const char *e,
                       unsigned int argc, int firstarg,
                       bool already_retained);
int lobjc_invoke_func_cif (lua_State *L, ffi_cif *cif, void (*fn)(),
                       const char *e, unsigned int argc, int firstarg,
                       bool already_retained);
int lobjc_invoke_with_signature (lua_State *L, id obj, SEL sel,
                                 NSMethodSignature *sig, int firstarg,
                                 bool already_retained);

void lobjc_invoke_lua_with_NSInvocation (lua_State *L, int ref, NSInvocation *inv);

IMP lobjc_buildIMP (lua_State *L, const char *sig);

#endif
