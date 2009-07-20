/*
** Copyright (C) 2009 ARATA Mizuki
** See file COPYRIGHT for more information
*/

#ifndef TYPEENCODING_H
#define TYPEENCODING_H

#include <stddef.h>
#include <lua.h>

#define NUMERICTYPES(m) \
  m('c', signed char) \
  m('i', int) \
  m('s', short) \
  m('l', long) \
  m('q', long long) \
  m('C', unsigned char) \
  m('I', unsigned int) \
  m('S', unsigned short) \
  m('L', unsigned long) \
  m('Q', unsigned long long) \
  m('f', float) \
  m('d', double)

#define QUALIFIER_CONST  0x01
#define QUALIFIER_IN     0x02
#define QUALIFIER_INOUT  0x04
#define QUALIFIER_OUT    0x08
#define QUALIFIER_BYCOPY 0x10
#define QUALIFIER_BYREF  0x20
#define QUALIFIER_ONEWAY 0x40

const char *skip_qualifier (const char *e);
unsigned char get_qualifier (const char *e);
const char *skip_type (lua_State *L, const char *e);

const char *skip_tagname (const char *e, size_t *len);

#endif
