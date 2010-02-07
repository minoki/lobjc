/*
** Copyright (C) 2009-2010 ARATA Mizuki
** See file COPYRIGHT for more information
*/

#import "lobjc_convert.h"
#import "lobjc.h"
#import "typeencoding.h"

#import <objc/objc.h> // for id, Class, SEL
#import <lua.h>
#import <lauxlib.h>
#import <stdbool.h>
#import <string.h>
#import <assert.h>
#import <ctype.h>
#import <stdlib.h>

static inline size_t round_align(size_t n, size_t align) {
  return ((n+align-1)/align)*align;
}

void lobjc_conv_luatoobjc1 (lua_State *L, int n, const char *e, void *buffer) {
  int top = lua_gettop(L);
  if (n < 0) {
    n = top + n + 1;
  }
  unsigned char q = get_qualifier(e);
  e = skip_qualifier(e);
  char c = *e++;
  switch (c) {
#define T(c,type,check) \
  case c: \
    *(type*)buffer = check(L, n); \
    break;
#define N(c,type) T(c, type, (type)luaL_checknumber)
  NUMERICTYPES(N)
#undef N
  T('B', bool, (bool)lua_toboolean)
  T('@', id, lobjc_toid)
  T('#', Class, lobjc_toclass)
  T(':', SEL, lobjc_checkselector)
#undef T
  case '*':
    if (q & QUALIFIER_CONST) {
      *(const char **)buffer = luaL_checkstring(L, n);
    } else {
      luaL_error(L, "lua->objc: non-const char* not supported");
    }
    break;
  case 'v': luaL_error(L, "lua->objc: invalid type specifier: void"); break;
  case '[': {
      int count = 0; // number of elements
      while (isdigit(*e)) {
        count = count*10 + (*e - '0');
        ++e;
      }
      luaL_checktype(L, n, LUA_TTABLE);
      size_t size = lobjc_conv_sizeof(L, e);
      for (int i = 1; i <= count; ++i) {
        lua_rawgeti(L, n, i); // should use lua_gettable
        lobjc_conv_luatoobjc1(L, -1, e, buffer);
        lua_pop(L, 1);
        *(unsigned char **)&buffer += size;
      }
      break;
    }
  case '{': {
      const char *typeenc_start = e-1;
      size_t size = lobjc_conv_sizeof(L, e-1);
      e = skip_type(L, e-1);
      if (luaL_getmetafield(L, n, "__toobjc")) {
        lua_pushvalue(L, n);
        lua_pushlstring(L, typeenc_start, e-typeenc_start);
        lua_call(L, 2, 1);
        if (lua_isstring(L, -1)) {
          size_t retlen;
          const char *s = lua_tolstring(L, -1, &retlen);
          if (size != retlen) {
            luaL_error(L, "lua->objc: #%d '__toobjc' metamethod returned a string of wrong size", n);
          }
          memcpy(buffer, s, size);
        } else if (lua_isuserdata(L, -1)) {
          size_t retlen = lua_objlen(L, -1);
          if (size != retlen) {
            luaL_error(L, "lua->objc: #%d '__toobjc' metamethod returned an userdata of wrong size", n);
          }
          void *p = lua_touserdata(L, -1);
          memcpy(buffer, p, size);
        } else {
          luaL_error(L, "lua->objc: #%d '__toobjc' metamethod returned a non-string", n);
        }
        lua_pop(L, 1);
      } else {
        luaL_error(L, "lua->objc: cannot convert value to an Objective-C struct");
      }
      break;
    }
  case '(': luaL_error(L, "lua->objc: union not supported"); break;
  case 'b': luaL_error(L, "lua->objc: bitfield not supported"); break;
  case '^': {
      const char *f = skip_type(L, e);
      char t[f-e+1];
      strncpy(t, e, sizeof(t)-1);
      t[sizeof(t)-1] = '\0';
      if (q & QUALIFIER_CONST) {
        *(const void **)buffer = lobjc_checkconstpointer(L, n, t);
      } else {
        *(void **)buffer = lobjc_checkpointer(L, n, t);
      }
      break;
    }
  case '?': luaL_error(L, "lua->objc: unknown type"); break;
  case '\0': luaL_error(L, "lua->objc: unexpected end of type encoding"); break;
  default: luaL_error(L, "lua->objc: unknown type encoding: '%c'", c); break;
  }
  assert(lua_gettop(L) == top);
}

static void objctolua1_impl (lua_State *L, const char *e, void *buffer, bool retain) {
  int t0 = lua_gettop(L);
  unsigned char q = get_qualifier(e);
  e = skip_qualifier(e);
  char c = *e++;
  switch (c) {
  //TODO: strict aliasing
#define T(c,type,push) \
  case c: push(L, *(type*)buffer); break;
#define N(c,type) T(c, type, lua_pushnumber)
  NUMERICTYPES(N)
#undef N
  T('B', bool, lua_pushboolean)
  T('*', char *, lua_pushstring)
  T('#', Class, lobjc_pushclass)
  T(':', SEL, lobjc_pushselector)
#undef T
  case '@': {
      if (retain) {
        lobjc_pushid(L, *(id*)buffer);
      } else {
        lobjc_pushid_noretain(L, *(id*)buffer);
      }
      break;
    }
  case 'v': lua_pushnil(L); break;
  case '[': {
      int n = atoi(e);
      while (isdigit(*e)) ++e;
      lua_createtable(L, n, 0);
      size_t size = lobjc_conv_sizeof(L, e);
      for (int i = 1; i <= n; ++i) {
        objctolua1_impl(L, e, buffer, true);
        lua_rawseti(L, -2, i);
        buffer += size;
      }
      break;
    }
  case '{': {
      const char *name = e;
      size_t name_len;
      e = skip_tagname(e, &name_len);

      lua_newtable(L);
      if (*name != '?') {
        lua_pushlstring(L, name, name_len); // push tagname

        lua_getfield(L, LUA_REGISTRYINDEX, "lobjc:struct_registry");
        lua_pushvalue(L, -2); // tagname
        lua_rawget(L, -2);
        if (lua_isnil(L, -1)) {
          lua_pop(L, 1);
          lua_newtable(L);
          unsigned int count = 0;
          const char *p = e;
          while (*p != '}') {
            ++count;
            p = skip_type(L, p);
          }
          lua_pushlstring(L, name-1, p+1-(name-1)); // type encoding
          lua_setfield(L, -2, ":typeencoding:");
          lua_pushinteger(L, count);
          lua_setfield(L, -2, ":count:");
          lua_pushvalue(L, -3); // tagname
          lua_pushvalue(L, -2); // newly created table
          lua_rawset(L, -4);
        }
        lua_remove(L, -2); // remove struct_registry
        lua_setfield(L, -3, ":struct_info:");

        lua_setfield(L, -2, ":tagname:");
      } else {
        lua_newtable(L);
        unsigned int count = 0;
        const char *p = e;
        while (*p != '}') {
          ++count;
          p = skip_type(L, p);
        }
        lua_pushlstring(L, name-1, p+1-(name-1)); // type encoding
        lua_setfield(L, -2, ":typeencoding:");
        lua_pushinteger(L, count);
        lua_setfield(L, -2, ":count:");
        lua_setfield(L, -2, ":struct_info:");
      }

      int n = 1;
      size_t pos = 0;
      while (*e != '}') {
        pos = round_align(pos, lobjc_conv_alignof(L, e));
        objctolua1_impl(L, e, (char *)buffer+pos, true);
        pos += lobjc_conv_sizeof(L, e);
        lua_rawseti(L, -2, n++);
        e = skip_type(L, e);
      }
      luaL_getmetatable(L, "lobjc:struct");
      lua_setmetatable(L, -2);
      break;
    }
  case '(': luaL_error(L, "objc->lua: union not supported"); break;
  case 'b': luaL_error(L, "objc->lua: bitfield not supported"); break;
  case '^': {
      const char *f = skip_type(L, e);
      char t[f-e+1];
      strncpy(t, e, sizeof(t)-1);
      t[sizeof(t)-1] = '\0';
      if (q & QUALIFIER_CONST) {
        lobjc_pushconstpointer(L, t, *(const void **)buffer);
      } else {
        lobjc_pushpointer(L, t, *(void **)buffer);
      }
      break;
    }
  case '?': luaL_error(L, "objc->lua: unknown type"); break;
  case '\0': luaL_error(L, "objc->lua: unexpected end of type encoding"); break;
  default: luaL_error(L, "objc->lua: unknown type encoding: '%c'", c); break;
  }
  assert(lua_gettop(L) == t0+1);
}
void lobjc_conv_objctolua1 (lua_State *L, const char *e, void *buffer) {
  objctolua1_impl(L, e, buffer, true);
}
void lobjc_conv_objctolua1_noretain (lua_State *L, const char *e, void *buffer) {
  objctolua1_impl(L, e, buffer, false);
}

size_t lobjc_conv_sizeof (lua_State *L, const char *e) {
  e = skip_qualifier(e);
  char c = *e++;
  switch (c) {
#define T(c,type) \
  case c: return sizeof(type);
  NUMERICTYPES(T)
  T('B', bool)
  T('*', char *)
  T('@', id)
  T('#', Class)
  T(':', SEL)
#undef T
  case 'v': return 0;
  case '[': {
      unsigned int n = 0;
      while (isdigit(*e)) {
        n = n*10 + (*e - '0');
        ++e;
      }
      return n*lobjc_conv_sizeof(L, e);
    }
  case '{': {
      size_t size = 0;
      size_t maxalign = 0;
      e = skip_tagname(e, NULL);
      while (*e != '}') {
        size_t s1 = lobjc_conv_sizeof(L, e);
        size_t a1 = lobjc_conv_alignof(L, e);
        size = round_align(size+s1, a1);
        if (a1 > maxalign) maxalign = a1;
        e = skip_type(L, e);
      }
      return round_align(size,maxalign);
    }
  case '(': {
      size_t maxsize = 0;
      size_t maxalign = 0;
      e = skip_tagname(e, NULL);
      while (*e != ')') {
        size_t size = lobjc_conv_sizeof(L, e);
        size_t align = lobjc_conv_alignof(L, e);
        if (size > maxsize) maxsize = size;
        if (align > maxalign) maxalign = align;
        e = skip_type(L, e);
      }
      return round_align(maxsize, maxalign);
    }
  case 'b': luaL_error(L, "bitfield not supported"); return 0;
  case '^': return sizeof(void *);
  case '?': luaL_error(L, "unknown type"); return 0;
  case '\0': luaL_error(L, "unexpected end of type encoding"); return 0;
  default: luaL_error(L, "unknown type encoding: '%c' /%s/", c, e-2); return 0;
  }
}


size_t lobjc_conv_alignof (lua_State *L, const char *e) {
  e = skip_qualifier(e);
  char c = *e++;
  switch (c) {
#define T(c,type) \
  case c: return __alignof__(type);
  NUMERICTYPES(T)
  T('B', bool)
  T('*', char *)
  T('@', id)
  T('#', Class)
  T(':', SEL)
#undef T
  case 'v': return 0;
  case '[': {
      while (isdigit(*e)) ++e;
      return lobjc_conv_alignof(L, e);
    }
  case '{': {
      size_t maxalign = 0;
      e = skip_tagname(e, NULL);
      while (*e != '}') {
        size_t align = lobjc_conv_alignof(L, e);
        if (align > maxalign) maxalign = align;
        e = skip_type(L, e);
      }
      return maxalign;
    }
  case '(': {
      size_t maxalign = 0;
      e = skip_tagname(e, NULL);
      while (*e != ')') {
        size_t align = lobjc_conv_alignof(L, e);
        if (align > maxalign) maxalign = align;
        e = skip_type(L, e);
      }
      return maxalign;
    }
  case 'b': luaL_error(L, "bitfield not supported"); return 0;
  case '^': return __alignof__(void *);
  case '?': luaL_error(L, "unknown type"); return 0;
  case '\0': luaL_error(L, "unexpected end of type encoding"); return 0;
  default: luaL_error(L, "unknown type encoding: '%c' /%s/", c, e-2); return 0;
  }
}


