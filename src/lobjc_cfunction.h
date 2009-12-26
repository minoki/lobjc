/*
** Copyright (C) 2009 ARATA Mizuki
** See file COPYRIGHT for more information
*/

#ifndef LOBJC_CFUNCTION_H
#define LOBJC_CFUNCTION_H

#include <stdbool.h>
#include <stddef.h>
#include <lua.h>
#include <ffi.h>

struct lobjc_CFunction {
  void (*fn)();
  unsigned int argc;
  ffi_cif cif;
  bool already_retained : 1;
  bool implemented_in_lua : 1;
  struct lobjc_CFunction_ClosureInfo *closureinfo;
  char sig[];
};

struct lobjc_CFunction_ClosureInfo {
  lua_State *L;
  int ref;
  struct lobjc_CFunction *func;
  bool hasresult;
  size_t nout;
  ffi_closure *cl;
};

struct lobjc_CFunction *lobjc_newcfunction (lua_State *L, void (*fn)(), const char *sig,
                                            bool already_retained);
struct lobjc_CFunction *lobjc_newclosure (lua_State *L, const char *sig);


#endif
