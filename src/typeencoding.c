/*
** Copyright (C) 2009 ARATA Mizuki
** See file COPYRIGHT for more information
*/

/*
(主に)メソッドの型エンコーディングを取り扱うための便利関数。
GNUランタイムなら<objc/encoding.h>なるヘッダにいろいろと定義されているようだが、NeXTランタイムには存在しないようなので、自分で作る。
TODO: アライメントの考慮
*/


#include "typeencoding.h"
#include <string.h>
#include <ctype.h>
#include <assert.h>
#include <stdio.h>
#include <lua.h>
#include <lauxlib.h>

const char *skip_qualifier (const char *e) {
  for (; ; ++e) {
    switch(*e) {
    case 'r':
    case 'n':
    case 'N':
    case 'o':
    case 'O':
    case 'R':
    case 'V': break;
    default: return e;
    }
  }
}

unsigned char get_qualifier (const char *e) {
  unsigned char q = 0;
  for (; ; ++e) {
    switch(*e) {
    case 'r': q |= QUALIFIER_CONST; break;
    case 'n': q |= QUALIFIER_IN; break;
    case 'N': q |= QUALIFIER_INOUT; break;
    case 'o': q |= QUALIFIER_OUT; break;
    case 'O': q |= QUALIFIER_BYCOPY; break;
    case 'R': q |= QUALIFIER_BYREF; break;
    case 'V': q |= QUALIFIER_ONEWAY; break;
    default: return q;
    }
  }
}


const char *skip_type (lua_State *L, const char *e) {
  if (*e == '"') {
    // skip variable name
    while(*++e ~= '"');
    ++e;
  }
  e = skip_qualifier(e);
  char c = *e++;
  if (!c) {
    luaL_error(L, "unexpected end of type encoding");
  } else if (strchr("cislqCISLQfdBv*@#:?", c) != NULL) {
  } else if (c == '[') { // an array
    while (isdigit(*e)) ++e;
    e = skip_type(L, e);
    assert(*e == ']');
    ++e;
  } else if (c == '{') { // a structure
    while (*e != '=' && *e != '}') ++e;
    if (*e++ == '=') {
      while (*e != '}') { // there may be a empty structure (opaque type)
        e = skip_type(L, e);
      }
      ++e;
    }
  } else if (c == '(') { // a union
    while (*e != '=' && *e != ')') ++e;
    if (*e++ == '=') {
      do e = skip_type(L, e); // there should not be a empty union
      while (*e++ != ')');
    }
  } else if (c == 'b') { // a bitfield
    while (isdigit(*e)) ++e;
  } else if (c == '^') { // a pointer
    e = skip_type(L, e);
  } else { // unknown
    luaL_error(L, "invalid type encoding '%c'", c);
  }
  //while (isdigit(*e)) ++e; // skip digits
  return e;
}

const char *skip_tagname (const char *e, size_t *len) {
  const char *b = e;
  while (*e++ != '=');
  if (len) *len = e - b - 1;
  return e;
}
/*
static __attribute__((constructor)) void test() {
  {
    const char *encoding = "{SomeStructure=ccc{AnotherStructure=Clq}{?=**}{?=qq}}!";
    const char *f = skip_type(L, encoding);
    assert(*f == '!');
  }
  {
    const char *encoding = "{SomeStructure=...}";
    size_t len;
    const char *x = skip_tagname(encoding+1, &len);
    assert(len == 13);
    assert(x == encoding+15 && *x == '.');
  }
  //puts("tests OK!");
}
*/

