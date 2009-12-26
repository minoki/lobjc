/*
** Copyright (C) 2009 ARATA Mizuki
** See file COPYRIGHT for more information
*/

#include "lobjc_cfunction.h"

#include "lobjc.h"
#include "lobjc_convert.h"
#include "lobjc_invoke.h"
#include "typeencoding.h"

#include <lua.h>
#include <lauxlib.h>
#include <stdint.h>
#include <string.h>
#include <stdbool.h>
#include <ctype.h>
#include <ffi.h>

// in lobjc_invoke.m
extern size_t scansig (lua_State *L, unsigned c,
                       const char *e, size_t *nout);
extern void to_ffitype (lua_State *L, unsigned c,
                        const char *e, ffi_type *types[]);


static const char tname[] = "lobjc:cfunction";


static struct lobjc_CFunction *newcfunction (lua_State *L, const char *sig) {
  struct lobjc_CFunction *p = lua_newuserdata(L, sizeof(struct lobjc_CFunction)+strlen(sig)+1);
  memset(p, 0, sizeof(struct lobjc_CFunction));
  strcpy(p->sig, sig);
  lua_newtable(L);
  lua_setfenv(L, -2);
  luaL_getmetatable(L, tname);
  lua_setmetatable(L, -2);
  return p;
}

static struct lobjc_CFunction *checkcfunction (lua_State *L) {
  return luaL_checkudata(L, 1, tname);
}

static int cfunction_gc (lua_State *L) {
  struct lobjc_CFunction *p = lua_touserdata(L, 1);
  (void)p;
  return 0;
}

static int cfunction_call (lua_State *L) {
  struct lobjc_CFunction *p = checkcfunction(L);
  return lobjc_invoke_func_cif(L, &p->cif, p->fn, p->sig, p->argc, 2, p->already_retained);
}


struct lobjc_CFunction *lobjc_newcfunction (lua_State *L, void (*fn)(), const char *sig, bool already_retained) {
  struct lobjc_CFunction *p = newcfunction(L, sig);
  unsigned int argc = 0;
  {
    const char *e = skip_type(L, sig);
    while (isdigit(*e)) ++e;
    while (*e) {
      ++argc;
      e = skip_type(L, e);
      while (isdigit(*e)) ++e;
    }
  }
  p->fn = fn;
  p->argc = argc;
  p->already_retained = already_retained;
  p->implemented_in_lua = false;
  p->closureinfo = NULL;

  { // prepare cif
    lua_getfenv(L, -1); // push environment table
    int n = lua_gettop(L);
    ffi_type **types = lua_newuserdata(L, sizeof(ffi_type *)*(argc+1));
    to_ffitype(L, argc+1, sig, types); // in lobjc_invoke.m
    while (lua_gettop(L) > n) luaL_ref(L, n);
    lua_pop(L, 1); // pop environment table

    ffi_status status = ffi_prep_cif(&p->cif, FFI_DEFAULT_ABI,
      argc, types[0], &types[1]);
    if (status != FFI_OK) {
      luaL_error(L, "ffi_prep_cif failed");
    }
  }
  return p;
}

// Closure
/*
static int closureinfo_gc (lua_State *L) {
  struct lobjc_CFunction_ClosureInfo *closureinfo = lua_touserdata(L, 1);
  if (closureinfo->cl) {
    ffi_closure_free(closureinfo->cl);
  }
  return 0;
}

struct CallInfo {
  struct lobjc_CFunction_ClosureInfo *closureinfo;
  void *ret;
  void **args;
};

static int imp_protected (lua_State *L) {
  struct CallInfo *ci = lua_touserdata(L, 1);
  struct lobjc_CFunction_ClosureInfo *closureinfo = ci->closureinfo;

  struct ReturnValue retvals[cli->nout];
  size_t nret = 0;
  const char *rettype = cli->sig;
  const char *type = cli->sig;
  int realargc = 0;

  if (cli->hasresult) {
    retvals[nret++] = (struct ReturnValue){
      .type = rettype,
      .p = ci->ret
    };
  }
  type = skip_type(L, type);
  while (isdigit(*type)) ++type;

  // push the lua function
  lua_rawgeti(L, LUA_REGISTRYINDEX, cli->ref);

  for (size_t i = 0; i < cli->argc; ++i) {
    unsigned char q = get_qualifier(type);
    const char *realtype = skip_qualifier(type);

    if (q & (QUALIFIER_OUT|QUALIFIER_INOUT) && *realtype == '^') {
      const char *referredtype = realtype+1;
      void *ptr = *(void **)ci->args[i];
      retvals[nret++] = (struct ReturnValue){.type = referredtype, .p = ptr};
      if (q & QUALIFIER_INOUT) {
        if (!ptr) {
          lua_pushnil(L);
        } else {
          lobjc_conv_objctolua1(L, referredtype, ptr);
        }
        ++realargc;
      }
    } else {
      lobjc_conv_objctolua1(L, type, ci->args[i]);
      ++realargc;
    }

    type = skip_type(L, type);
    while (isdigit(*type)) ++type;
  }

  lua_call(L, realargc, nret);

  for (int i = 0; i < nret; ++i) {
    if (retvals[i].p) {
      lobjc_conv_luatoobjc1(L, i-nret, retvals[i].type, retvals[i].p);
    }
  }
  return 0;
}

static void imp_proxy (ffi_cif *cif, void *ret, void **args, void *userdata) {
  struct ClosureInfo *cli = userdata;
  lua_State *L = cli->L;
  struct CallInfo ci = {.cli = cli, .ret = ret, .args = args};
  if (lua_cpcall(L, imp_protected, &ci)) {
    id err = [[[lobjc_LuaError alloc] initWithLuaState: L errorMessageAt: -1] autorelease];
    lua_pop(L, 1);
    @throw err;
  }
}




struct lobjc_CFunction *lobjc_newclosure (lua_State *L, const char *sig) {
  int ref = luaL_ref(L, LUA_REGISTRYINDEX);
  struct lobjc_CFunction *p = newcfunction(L, sig);
  struct lobjc_CFunction_ClosureInfo *closureinfo = lua_newuserdata(L, sizeof(struct lobjc_CFunction_ClosureInfo));
  luaL_getmetatable(L, "lobjc:CFunction_ClosureInfo");
  lua_setmetatable(L, -1);
  unsigned int argc = 0;
  {
    const char *e = skip_type(L, sig);
    while (isdigit(*e)) ++e;
    while (*e) {
      ++argc;
      e = skip_type(L, e);
      while (isdigit(*e)) ++e;
    }
  }
  p->fn = NULL;
  p->argc = argc;
  p->already_retained = false;
  p->implemented_in_lua = true;
  p->closureinfo = closureinfo;
  closureinfo->L = L;
  closureinfo->ref = ref;
  closureinfo->func = p;
  closureinfo->hasresult = *skip_qualifier(sig) != 'v';
  closureinfo->nout = 0;
  closureinfo->cl = NULL;

  lua_getfenv(L, -2); // push environment table
  lua_pushvalue(L, -2); // push closureinfo
  luaL_ref(L, -2);
  lua_pop(L, 2); // pop environment table and closureinfo

  { // prepare cif
    lua_getfenv(L, -1); // push environment table
    int n = lua_gettop(L);
    ffi_type **types = lua_newuserdata(L, sizeof(ffi_type *)*(argc+1));
    scansig(L, argc+1, sig, &closureinfo->nout); // in lobjc_invoke.m
    to_ffitype(L, argc+1, sig, types); // in lobjc_invoke.m
    while (lua_gettop(L) > n) luaL_ref(L, n);
    lua_pop(L, 1); // pop environment table

    ffi_status status = ffi_prep_cif(&p->cif, FFI_DEFAULT_ABI,
      argc, types[0], &types[1]);
    if (status != FFI_OK) {
      luaL_error(L, "ffi_prep_cif failed");
    }
  }
  {
    void *codeloc;
    closureinfo->cl = ffi_closure_alloc(sizeof(ffi_closure), &codeloc);
    if (!closureinfo->cl) {
      return luaL_error(L, "ffi_closure_alloc failed"), NULL;
    }

    ffi_status status = ffi_prep_closure_loc(closureinfo->cl, &p->cif, imp_proxy, cli, codeloc);
    if (status != FFI_OK) {
      return luaL_error(L, "ffi_prep_closure_loc failed"), NULL;
    }
    
    p->func = (void (*)())codeloc;
  }
  return p;
}
*/
#if 0
static int newclosure (lua_State *L) { /** newclosure(sig,func) */
  const char *sig = luaL_checkstring(L, 1);
  luaL_checktype(L, 2, LUA_TFUNCTION);
  lua_pushvalue(L, 2);
  int n = lua_gettop(L);
  lobjc_newclosure(L, sig);
  assert(lua_gettop(L) == n+1);
  return 1
}

static const luaL_Reg cfunc_funcs[] = {
  {"newclosure", newclosure},
  {NULL, NULL}
};
#endif

static const luaL_Reg cfunc_funcs[] = {
  {"__gc", cfunction_gc},
  {"__call", cfunction_call},
  {NULL, NULL}
};

LUALIB_API int luaopen_objc_runtime_cfunction (lua_State *L) {
  luaL_newmetatable(L, tname);
  luaL_register(L, NULL, cfunc_funcs);
//  luaL_newmetatable(L, "lobjc:CFunction_ClosureInfo");
//  lua_pushcfunction(L, closureinfo_gc);
//  lua_setfield(L, -2, "__gc");
  return 0;
}



