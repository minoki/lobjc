/*
** Copyright (C) 2009 ARATA Mizuki
** See file COPYRIGHT for more information
*/

#import "lobjc.h"
#import "lobjc_convert.h"
#import "typeencoding.h"
#import <lua.h>
#import <assert.h>

static void type_test (lua_State *L) {
#define T(t) \
  assert(sizeof(t) == lobjc_conv_sizeof(L, @encode(t)) || !"sizeof() mismatch"); \
  assert(__alignof__(t) == lobjc_conv_alignof(L, @encode(t)) || !"alignof() mismatch");
  T(char);
  T(unsigned long);
  T(lua_State *);
  T(char [10]);
  T(short [10]);
  T(struct { int a; });
  T(struct { int a; char b; });
  T(struct { int a; char b; short c[7]; });
//  T(struct { double a; });
//  T(struct { int a; double b; double c; });
  T(struct { int a; char b; char c; });
//  T(struct { int a; char b; double c; });
  T(union { int a; char b; });
  T(union { int a; char b; short c[7]; });
  T(struct { char a; short b; } [7]);
}

int run_simple_test (lua_State *L) {
  assert(sizeof(void *) == sizeof(void (*)()));
  type_test(L);
//  puts("simple tests ok!");
  return 1;
}

