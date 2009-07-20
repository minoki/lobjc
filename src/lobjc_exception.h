/*
** Copyright (C) 2009 ARATA Mizuki
** See file COPYRIGHT for more information
*/

#ifndef LOBJC_EXCEPTION_H
#define LOBJC_EXCEPTION_H

#import <lua.h>

int lobjc_exception_rethrow_as_lua (lua_State *L, id ex);

#endif
