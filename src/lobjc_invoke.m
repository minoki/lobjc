/*
** Copyright (C) 2009 ARATA Mizuki
** See file COPYRIGHT for more information
*/

#import "lobjc_invoke.h"
#import "lobjc.h"
#import "typeencoding.h"
#import "lobjc_convert.h"
#import "lobjc_exception.h"

#import <objc/runtime.h>
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
// NOTE: この関数はLuaのスタックにuserdataを置くかもしれない(malloc代わり)
static size_t to_ffitype (lua_State *L, unsigned c,
                          const char *e, ffi_type *types[], size_t *nout) {
  ffi_type **t = types;
  size_t size = 0;
  for (unsigned i = 0; i < c; ++i) {
    unsigned char q = get_qualifier(e);
    e = skip_qualifier(e);
    char c = *e++;
    switch (c) {
#define T(c,ffi_type,type) \
    case c: *t++ = &ffi_type; size += sizeof(type); break;
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
#undef T
    case 'v': *t++ = &ffi_type_void; break;
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
        elements[n] = NULL; // 番兵
        size += to_ffitype(L, n, type_begin, elements, NULL);
        // TODO: consider alignment and padding
        break;
      }
    case '(': luaL_error(L, "invoke: union not supported"); break;
    case 'b': luaL_error(L, "invoke: bitfield not supported"); break;
    case '^':
      *t++ = &ffi_type_pointer;
      size += sizeof(void *);
      e = skip_type(L, e);
      if (q & (QUALIFIER_OUT|QUALIFIER_INOUT) && nout) {
        ++*nout;
      }
      break;
    default: luaL_error(L, "invoke: unknown type encoding: '%c'", c); break;
    }
    while (isdigit(*e)) ++e; // skip digits
  }
  return size;
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
    void *p = lua_newuserdata(L, lobjc_conv_sizeof(L, referredtype));
    retvals[(*pnout)++] = (struct ReturnValue){.type = referredtype, .p = p, .already_retained = false};
    *(void **)buffer = p;
    if (q & QUALIFIER_INOUT) {
      lobjc_conv_luatoobjc1(L, (*pnarg)++, referredtype, p);
    }
  } else {
    lobjc_conv_luatoobjc1(L, (*pnarg)++, type, buffer);
  }  
}

static int pushresults (lua_State *L, struct ReturnValue* retvals, int count) {
  for (int i = 0; i < count; ++i) {
    if (retvals[i].already_retained) {
      lobjc_conv_objctolua1_noretain(L, retvals[i].type, retvals[i].p);
    } else {
      lobjc_conv_objctolua1(L, retvals[i].type, retvals[i].p);
    }
  }
  return count;
}

int lobjc_invoke_func (lua_State *L, void (*fn)(), const char *e,
                       unsigned int argc, int firstarg,
                       bool already_retained) {
  ffi_cif cif;
  ffi_type* types[argc+1]; // include return type
  size_t nout = 0;
  lua_settop(L, firstarg+argc-1); // 引数が足りなかった場合のエラーメッセージがちょっと変わるけど気にしない

  size_t buffer_len = to_ffitype(L, argc+1, e, types, &nout);
  // スタックにuserdataがたまっている可能性あり

  ffi_status status;
  status = ffi_prep_cif(&cif, FFI_DEFAULT_ABI,
    argc, types[0], &types[1]);
  if (status == FFI_OK) {
    void *args[argc];
    unsigned char buffer[buffer_len]; // バッファオーバーフロー注意
    struct ReturnValue retvals[nout+1];
    size_t nret = 0; // number of results
    void *ret_buffer = NULL;

    // スタックにuserdataがたまっている可能性あり
    {
      void *buffer_ptr = buffer;

      if (types[0] != &ffi_type_void) {
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
        ffi_call(&cif, (void *)fn, ret_buffer, args);
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
  return luaL_error(L, "ffi_prep_cif failed");
}

int lobjc_invoke_with_signature (lua_State *L, id obj, SEL sel,
                                 NSMethodSignature *sig, int firstarg,
                                 bool already_retained) {
  size_t argc = [sig numberOfArguments];
  lua_settop(L, firstarg+argc-1); // 引数が足りなかった場合のエラーメッセージがちょっと変わるけど気にしない

  NSInvocation *inv = [NSInvocation invocationWithMethodSignature: sig];
  [inv setSelector: sel]; // _cmd
  [inv setTarget: obj]; // self

  struct ReturnValue retvals[argc+1];
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
    for (unsigned i = 0; i < argc; ++i) {
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
        const char *referredtype = realtype;
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




