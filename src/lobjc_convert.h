/*
** Copyright (C) 2009 ARATA Mizuki
** See file COPYRIGHT for more information
*/

#ifndef LOBJC_CONVERT_H
#define LOBJC_CONVERT_H

#include <lua.h>
#include <stddef.h>

void lobjc_conv_luatoobjc1 (lua_State *L, int n, const char *e, void *b);
void lobjc_conv_objctolua1 (lua_State *L, const char *e, void *b);
void lobjc_conv_objctolua1_noretain (lua_State *L, const char *e, void *b);
size_t lobjc_conv_sizeof (lua_State *L, const char *e);
size_t lobjc_conv_alignof (lua_State *L, const char *e);

void lobjc_pushpointer (lua_State *L, const char *t, void *ptr);
void lobjc_pushconstpointer (lua_State *L, const char *t, const void *ptr);
void *lobjc_checkpointer (lua_State *L, int narg, const char *t);
const void *lobjc_checkconstpointer (lua_State *L, int narg, const char *t);

#endif
