CFLAGS= -std=c99 -DLUA_LIB -I/opt/local/include -Wall -fobjc-exceptions $(MYCFLAGS)
# -fobjc-gc -D"id=__strong id"
LINKFLAGS= -L/opt/local/lib $(MYLINKFLAGS)
LIBS= -lffi -framework Foundation
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
  simplecheck.o
SO= objc.so

all: $(SO)

$(SO): $(OBJS)
	$(CC) -bundle -undefined dynamic_lookup $(LINKFLAGS) -o $@ $^ $(LIBS)

.m.o:
	$(CC) -o $@ -c $(CFLAGS) $<

clean:
	rm -f $(OBJS)
	rm -f $(SO)

test: tests/test.m $(OBJS)
	$(CC) -o $@ $(CFLAGS) $(LINKFLAGS) -I. $^ -llua -lobjc $(LIBS)

depend:
	$(CC) -MM $(CFLAGS) *.m > depend.mak

.SUFFIXES: .m .o
.PHONY: all clean depend

-include depend.mak
