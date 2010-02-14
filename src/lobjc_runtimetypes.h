/*
** Copyright (C) 2010 ARATA Mizuki
** See file COPYRIGHT for more information
*/

#ifndef LOBJC_RUNTIMETYPES_H
#define LOBJC_RUNTIMETYPES_H

#include "objc-runtime.h"
#include <lua.h>
#include <lauxlib.h>

const char * const tname_id;

void   lobjc_pushIvar (lua_State *L, Ivar p);
Ivar   lobjc_checkIvar (lua_State *L, int narg);
void   lobjc_pushMethod (lua_State *L, Method p);
Method lobjc_checkMethod (lua_State *L, int narg);
#if !defined(DISABLE_OBJC2_PROPERTIES)
void   lobjc_pushproperty (lua_State *L, objc_property_t p);
objc_property_t lobjc_checkproperty (lua_State *L, int narg);
#endif
void   lobjc_pushProtocol (lua_State *L, Protocol *p);
Protocol *lobjc_checkProtocol (lua_State *L, int narg);

int luaopen_objc_runtime_types (lua_State *L);

#endif
