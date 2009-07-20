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

struct OutParam {
  const char *type;
  void *p;
};

static void *fillargs (lua_State *L, int narg, const char *e,
                       unsigned argc, void **args, unsigned char *buffer,
                       struct OutParam *outparam) {
  for (unsigned i = 0; i < argc; ++i) {
    *args++ = buffer;
    const char *f = e; // 位置を保存
    unsigned char q = get_qualifier(e);
    e = skip_qualifier(e);
    if (q & (QUALIFIER_OUT|QUALIFIER_INOUT) && *e == '^') {
      void *p = lua_newuserdata(L, lobjc_conv_sizeof(L, e+1));
      *outparam++ = (struct OutParam){.type = e+1, .p = p};
      *(void **)buffer = p;
      if (q & QUALIFIER_INOUT) {
        lobjc_conv_luatoobjc1(L, narg++, e+1, p);
      }
    } else {
      lobjc_conv_luatoobjc1(L, narg++, f, buffer);
    }
    e = skip_type(L, e);
    buffer += lobjc_conv_sizeof(L, f);
    while (isdigit(*e)) ++e; // skip digits
  }
  return buffer;
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
    struct OutParam outparams[nout];

    // スタックにuserdataがたまっている可能性あり
    const char *b = skip_type(L, e); /* skip return type */
    while (isdigit(*b)) ++b; // skip digits
    void *ret_buffer = fillargs(L, firstarg, b,
      argc, args, buffer, outparams);

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

    int retc = nout; // Luaに返される戻り値の個数
    if (types[0] != &ffi_type_void) {
      ++retc;
      if (already_retained) {
        lobjc_conv_objctolua1_noretain(L, e, ret_buffer);
      } else {
        lobjc_conv_objctolua1(L, e, ret_buffer);
      }
    }
    for (size_t i = 0; i < nout; ++i) {
      lobjc_conv_objctolua1(L, outparams[i].type, outparams[i].p);
    }
    return retc;
  }
  return luaL_error(L, "ffi_prep_cif failed");
}

/*
TODO:
support array, union, bit-field
support pointers
*/



