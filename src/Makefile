# Makefile for lobjc

ifeq ($(shell uname),Darwin)
  ENVIRONMENT= cocoa
  LINK= $(CC) -bundle -undefined dynamic_lookup
else
  ENVIRONMENT= gnustep
  LINK= $(CC) -shared
endif

ifeq ($(ENVIRONMENT),cocoa)
  LIBS+= -framework Foundation
else
  CFLAGS+= $(shell gnustep-config --objc-flags)
  LIBS+= $(shell gnustep-config --base-libs)
endif

CFLAGS+= $(shell pkg-config --cflags libffi)
LIBS+= $(shell pkg-config --libs libffi)

CFLAGS+= -std=c99 -DLUA_LIB -Wall -fobjc-exceptions $(MYCFLAGS)
# -fobjc-gc -D"id=__strong id"
OBJS= \
  lobjcrt.o \
  lobjc_invoke.o \
  lobjc_convert.o \
  lobjc_struct.o \
  lobjc_ffi.o \
  lobjc_exception.o \
  lobjc_pointer.o \
  lobjc_bridgesupport.o \
  typeencoding.o \
  LuaWrapper.o \
  simplecheck.o \
  lobjc-compat.o
SO= objc.so

all: $(SO)

$(SO): $(OBJS)
	$(LINK) -o $@ $^ $(LIBS)

.m.o:
	$(CC) -o $@ -c $(CFLAGS) $<

clean:
	rm -f $(OBJS)
	rm -f $(SO)

test: tests/test.m $(OBJS)
	$(CC) -o $@ $(CFLAGS) -I. $^ -llua -lobjc $(LIBS)

depend:
	$(CC) -MM $(CFLAGS) *.m > depend.mak

.SUFFIXES: .m .o
.PHONY: all clean depend

-include depend.mak
