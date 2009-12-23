/*
** Copyright (C) 2009 ARATA Mizuki
** See file COPYRIGHT for more information
*/

#import "lobjc_invoke.h"
#import "lobjc.h"
#import "typeencoding.h"
#import "lobjc_convert.h"
#import "lobjc_exception.h"

#import "objc-runtime.h"
#import <lua.h>
#import <lauxlib.h>
#import <ffi.h>
#import <Foundation/Foundation.h>
#import <stdbool.h>
#import <assert.h>
#import <ctype.h>


// だれか適当に#ifdefしといて
#define ffi_type_slonglong ffi_type_sint64
#define ffi_type_ulonglong ffi_type_uint64
#define ffi_type_bool ffi_type_uint8

// 必要なバッファの大きさをバイト数で返す(lobjc_conv_sizeofを足したものと同じ)
// ついでにout/inout引数の数も返す
static size_t scansig (lua_State *L, unsigned c,
                          const char *e, size_t *nout) {
  size_t size = 0;
  *nout = 0;
  for (unsigned i = 0; i < c; ++i) {
    unsigned char q = get_qualifier(e);
    size += lobjc_conv_sizeof(L, e);
    if (q & (QUALIFIER_OUT|QUALIFIER_INOUT) && nout) {
      ++*nout;
    }
    e = skip_type(L, e);
    while (isdigit(*e)) ++e; // skip digits
  }
  return size;
}

static void to_ffitype (lua_State *L, unsigned c,
                          const char *e, ffi_type *types[]) {
  ffi_type **t = types;
  for (unsigned i = 0; i < c; ++i) {
    e = skip_qualifier(e);
    char c = *e++;
    switch (c) {
#define T(c,ffi_type,type) \
    case c: *t++ = &ffi_type; break;
    T('c', ffi_type_schar, char)
    T('i', ffi_type_sint, int)
    T('s', ffi_type_sshort, short)
    T('l', ffi_type_slong, long)
    T('q', ffi_type_slonglong, long long)
    T('C', ffi_type_uchar, unsigned char)
    T('I', ffi_type_uint, unsigned int)
    T('S', ffi_type_ushort, unsigned short)
    T('L', ffi_type_ulong, unsigned long)
    T('Q', ffi_type_ulonglong, unsigned long long)
    T('f', ffi_type_float, float)
    T('d', ffi_type_double, double)
    T('B', ffi_type_bool, _Bool)
    T('*', ffi_type_pointer, char *)
    T('@', ffi_type_pointer, id)
    T('#', ffi_type_pointer, Class)
    T(':', ffi_type_pointer, SEL)
    T('v', ffi_type_void, void)
#undef T
    case '[': luaL_error(L, "invoke: array not supported"); break;
    case '{': {
        e = skip_tagname(e, NULL);
        unsigned n = 0;
        const char *type_begin = e;
        while (*e != '}') {
          e = skip_type(L, e);
          ++n;
        }
        assert(*e == '}');
        ++e;
        ffi_type *type = lua_newuserdata(L, sizeof(ffi_type)+sizeof(ffi_type *)*(n+1));
        ffi_type **elements = (ffi_type **)(type+1);
        *type = (ffi_type){
          .size = 0,
          .alignment = 0,
          .type = FFI_TYPE_STRUCT,
          .elements = elements
        };
        *t++ = type;
        elements[n] = NULL; // sentinel
        to_ffitype(L, n, type_begin, elements);
        // TODO: consider alignment and padding
        break;
      }
    case '(': luaL_error(L, "invoke: union not supported"); break;
    case 'b': luaL_error(L, "invoke: bitfield not supported"); break;
    case '^':
      *t++ = &ffi_type_pointer;
      e = skip_type(L, e);
      break;
    default: luaL_error(L, "invoke: unknown type encoding: '%c'", c); break;
    }
    while (isdigit(*e)) ++e; // skip digits
  }
}

struct ReturnValue {
  const char *type;
  void *p;
  bool already_retained;
};

static void getarg (lua_State *L, struct ReturnValue *retvals, size_t *pnout, const char *type, int *pnarg, void *buffer) {
  unsigned char q = get_qualifier(type);
  const char *realtype = skip_qualifier(type); // type encoding without qualifier

  if (q & (QUALIFIER_OUT|QUALIFIER_INOUT) && *realtype == '^') {
    const char *referredtype = realtype+1;
    size_t buffer_len = lobjc_conv_sizeof(L, referredtype);
    void *p = lua_newuserdata(L, buffer_len);
    memset(p, 0, buffer_len);
    retvals[(*pnout)++] = (struct ReturnValue){.type = referredtype, .p = p, .already_retained = false};
    *(void **)buffer = p;
    if (q & QUALIFIER_INOUT) {
      lobjc_conv_luatoobjc1(L, (*pnarg)++, referredtype, p);
    }
  } else {
    lobjc_conv_luatoobjc1(L, (*pnarg)++, type, buffer);
  }  
}

static int pushresults (lua_State *L, struct ReturnValue *retvals, int count) {
  for (int i = 0; i < count; ++i) {
    if (retvals[i].already_retained) {
      lobjc_conv_objctolua1_noretain(L, retvals[i].type, retvals[i].p);
    } else {
      lobjc_conv_objctolua1(L, retvals[i].type, retvals[i].p);
    }
  }
  return count;
}

int lobjc_invoke_func_cif (lua_State *L, ffi_cif *cif, void (*fn)(),
                       const char *e, unsigned int argc, int firstarg,
                       bool already_retained) {
  size_t nout;
  size_t buffer_len = scansig(L, argc, e, &nout);
  void *args[argc];
  unsigned char buffer[buffer_len];
  struct ReturnValue retvals[nout+1];
  size_t nret = 0; // number of results
  void *ret_buffer = NULL;

  {
    void *buffer_ptr = buffer;

    if (*skip_qualifier(e) != 'v') {
      retvals[nret++] = (struct ReturnValue){
        .type = e,
        .p = buffer_ptr,
        .already_retained = already_retained
      };
      ret_buffer = buffer_ptr;
      *(unsigned char **)&buffer_ptr += lobjc_conv_sizeof(L, e); // size of return type
    }

    const char *type = skip_type(L, e); /* skip return type */
    while (isdigit(*type)) ++type; // skip digits

    int narg = firstarg; // index of arguments passed from lua

    for (unsigned i = 0; i < argc; ++i) {
      args[i] = buffer_ptr;
      getarg(L, retvals, &nret, type, &narg, buffer_ptr);
      *(unsigned char **)&buffer_ptr += lobjc_conv_sizeof(L, type); // size of return type
      type = skip_type(L, type);
      while (isdigit(*type)) ++type; // skip digits
    }
  }

  {
    id savedException = nil;
    @try {
      ffi_call(cif, (void *)fn, ret_buffer, args);
    }
    @catch (id e) {
      savedException = e;
    }
    if (savedException) {
      return lobjc_exception_rethrow_as_lua(L, savedException);
    }
  }

  return pushresults(L, retvals, nret);
}

int lobjc_invoke_func (lua_State *L, void (*fn)(), const char *e,
                       unsigned int argc, int firstarg,
                       bool already_retained) {
  ffi_cif cif;
  ffi_type* types[argc+1]; // include return type
  lua_settop(L, firstarg+argc-1); // 引数が足りなかった場合のエラーメッセージがちょっと変わるけど気にしない

  to_ffitype(L, argc+1, e, types);
  // スタックにuserdataがたまっている可能性あり

  ffi_status status;
  status = ffi_prep_cif(&cif, FFI_DEFAULT_ABI,
    argc, types[0], &types[1]);
  if (status != FFI_OK) {
    return luaL_error(L, "ffi_prep_cif failed");
  }
  return lobjc_invoke_func_cif(L, &cif, fn, e, argc, firstarg, already_retained);
}

int lobjc_invoke_with_signature (lua_State *L, id obj, SEL sel,
                                 NSMethodSignature *sig, int firstarg,
                                 bool already_retained) {
  size_t argc = [sig numberOfArguments];
  lua_settop(L, firstarg+argc-1); // 引数が足りなかった場合のエラーメッセージがちょっと変わるけど気にしない

  NSInvocation *inv = [NSInvocation invocationWithMethodSignature: sig];
  [inv setSelector: sel]; // _cmd
  [inv setTarget: obj]; // self

  struct ReturnValue retvals[argc+1]; // inefficient
  size_t nret = 0;
  void *ret_buffer = NULL;
  {
    const char *rettype = [sig methodReturnType];
    if (*skip_qualifier(rettype) != 'v') {
      ret_buffer = lua_newuserdata(L, [sig methodReturnLength]);
      retvals[nret++] = (struct ReturnValue){
        .type = rettype,
        .p = ret_buffer,
        .already_retained = already_retained
      };
    }
  }
  {
    int narg = firstarg+2; // firstarg is self and firstarg+1 is _cmd
    for (unsigned i = 2; i < argc; ++i) {
      const char *type = [sig getArgumentTypeAtIndex: i];
      unsigned char buffer[lobjc_conv_sizeof(L, type)];
      getarg(L, retvals, &nret, type, &narg, buffer);
      [inv setArgument: buffer atIndex: i];
    }
  }

  {
    id savedException = nil;
    @try {
      [obj forwardInvocation: inv];
    }
    @catch (id e) {
      savedException = e;
    }
    if (savedException) {
      return lobjc_exception_rethrow_as_lua(L, savedException);
    }
  }

  if (ret_buffer != NULL) {
    [inv getReturnValue: ret_buffer];
  }
  return pushresults(L, retvals, nret);
}

/*
TODO:
support array, union, bit-field
*/



struct InvokeLuaParams {
  NSInvocation *inv;
  int ref;
};

static int invoke_lua_with_NSInvocation_aux (lua_State *L) {
  struct InvokeLuaParams *p = (struct InvokeLuaParams *)lua_touserdata(L, 1);
  NSInvocation *inv = p->inv;
  NSMethodSignature *sig = [inv methodSignature];

  int realargc = 0; // number of arguments passed to lua
  int nret = 0; // number of results expected to be returned from lua
  size_t argc = [sig numberOfArguments];
  struct ReturnValue retvals[argc];
  const char *rettype = [sig methodReturnType];
  void *ret_buffer = NULL;

  if (*skip_qualifier(rettype) != 'v') {
    ret_buffer = lua_newuserdata(L, [sig methodReturnLength]);
    retvals[nret++] = (struct ReturnValue){
      .type = rettype,
      .p = ret_buffer
    };
  }

  lua_rawgeti(L, LUA_REGISTRYINDEX, p->ref);
  luaL_gsub(L, sel_getName([inv selector]), ":", "_");
  lua_gettable(L, -2); // the function

  lua_pushvalue(L, -2); // self

  {
    for (size_t i = 2; i < argc; ++i) {
      const char *type = [sig getArgumentTypeAtIndex:i];
      unsigned char q = get_qualifier(type);
      const char *realtype = skip_qualifier(type);

      if (q & (QUALIFIER_OUT|QUALIFIER_INOUT) && *realtype == '^') {
        const char *referredtype = realtype+1;
        void *ptr = NULL;
        [inv getArgument:&ptr atIndex:i];
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
        unsigned char buffer[lobjc_conv_sizeof(L, type)];
        [inv getArgument:buffer atIndex:i];
        lobjc_conv_objctolua1(L, type, buffer);
        ++realargc;
      }
    }
  }

  lua_call(L, 1+realargc, nret);

  for (int i = 0; i < nret; ++i) {
    if (retvals[i].p) {
      lobjc_conv_luatoobjc1(L, i-nret, retvals[i].type, retvals[i].p);
    }
  }
  if (ret_buffer != NULL) {
    [inv setReturnValue: ret_buffer];
  }
  return 0;
}

void lobjc_invoke_lua_with_NSInvocation (lua_State *L, int ref, NSInvocation *inv) {
  struct InvokeLuaParams p = {.inv = inv, .ref = ref};
  if (lua_cpcall(L, invoke_lua_with_NSInvocation_aux, &p)) {
    id err = [[lobjc_LuaError alloc] initWithLuaState: L errorMessageAt: -1];
    lua_pop(L, 1);
    @throw err;
  }
}



struct ClosureInfo {
  lua_State *L;
  int ref;
  const char *sig;
  bool hasresult;
  size_t argc;
  size_t nout;
  size_t resultlength;
  ffi_cif cif;
  ffi_closure *cl;
};

struct CallInfo {
  struct ClosureInfo *cli;
  void *ret;
  void **args;
};

static int imp_protected (lua_State *L) {
  struct CallInfo *ci = lua_touserdata(L, 1);
  struct ClosureInfo *cli = ci->cli;

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

static int closureinfo_gc (lua_State *L) {
  struct ClosureInfo *cli = lua_touserdata(L, 1);
  if (cli->cl) {
    ffi_closure_free(cli->cl);
  }
  return 0;
}

IMP lobjc_buildIMP (lua_State *L, const char *sig) {
  int ref = luaL_ref(L, LUA_REGISTRYINDEX);
  struct ClosureInfo *cli = lua_newuserdata(L, sizeof(struct ClosureInfo));
  *cli = (struct ClosureInfo) {
    .L = L, .ref = ref,
    .sig = sig, .hasresult = false,
    .argc = 0, .nout = 0,
    .cl = NULL
  };
  if (luaL_newmetatable(L, "lobjc:ClosureInfo")) {
    lua_pushcfunction(L, closureinfo_gc);
    lua_setfield(L, -2, "__gc");
  }
  lua_setmetatable(L, -2);

  // environment table of cli
  lua_newtable(L);
  
  lua_pushvalue(L, -1);
  lua_setfenv(L, -3);
  
  lua_pushstring(L, sig);
  cli->sig = lua_tostring(L, -1);
  luaL_ref(L, -2);

  // stack: <cli> <env>

  {
    const char *e = skip_qualifier(sig);
    cli->hasresult = *e != 'v';
    e = skip_type(L, e);
    while (isdigit(*e)) ++e;
    while (*e) {
      ++cli->argc;
      e = skip_type(L, e);
      while (isdigit(*e)) ++e;
    }
  }

  {
    int n = lua_gettop(L);
    ffi_type **types = lua_newuserdata(L, sizeof(ffi_type *)*(cli->argc+1));
    scansig(L, cli->argc+1, sig, &cli->nout);
    to_ffitype(L, cli->argc+1, sig, types);
    while (lua_gettop(L) > n) luaL_ref(L, n);

    ffi_status status = ffi_prep_cif(&cli->cif, FFI_DEFAULT_ABI, cli->argc,
      types[0], &types[1]);
    if (status != FFI_OK) {
      return luaL_error(L, "ffi_prep_cif failed"), NULL;
    }

    void *codeloc;
    cli->cl = ffi_closure_alloc(sizeof(ffi_closure), &codeloc);
    if (!cli->cl) {
      return luaL_error(L, "ffi_closure_alloc failed"), NULL;
    }

    status = ffi_prep_closure_loc(cli->cl, &cli->cif, imp_proxy, cli, codeloc);
    if (status != FFI_OK) {
      return luaL_error(L, "ffi_prep_closure_loc failed"), NULL;
    }

    lua_pop(L, 1); // pop environment table of cli

    // should luaL_ref(L, LUA_REGISTRYINDEX) here?

    return (IMP)codeloc;
  }
}


