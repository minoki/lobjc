/*
** Copyright (C) 2009 ARATA Mizuki
** See file COPYRIGHT for more information
*/

#ifndef LOBJC_INVOKE_H
#define LOBJC_INVOKE_H

#include <lua.h>
#include <stdbool.h>

int lobjc_invoke_func (lua_State *L, void (*fn)(), const char *e,
                       unsigned int argc, int firstarg,
                       bool already_retained);

#endif
