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

CFLAGS+= -std=c99 -DLUA_LIB -Wall $(MYCFLAGS)
OBJCFLAGS+= -fobjc-exceptions $(MYOBJCFLAGS)
# -fobjc-gc -D"id=__strong id"
BUILD_DIR= build-$(shell uname -m)-$(shell uname -s)
SOURCES= \
  lobjcrt.m \
  lobjc_invoke.m \
  lobjc_convert.m \
  lobjc_exception.m \
  lobjc_bridgesupport.m \
  lobjc_luawrapper.m \
  simplecheck.m \
  lobjc-compat.m \
  lobjc_struct.c \
  lobjc_pointer.c \
  lobjc_ffi.c \
  lobjc_cfunction.c \
  typeencoding.c
OBJS= $(patsubst %.m,$(BUILD_DIR)/%.o,$(filter %.m,$(SOURCES)))
COBJS= $(patsubst %.c,$(BUILD_DIR)/%.o,$(filter %.c,$(SOURCES)))
SO= objc.so

all: $(SO)

echo:
	@echo "sources: $(SOURCES)"
	@echo "objs: $(OBJS)"
	@echo "cobjs: $(COBJS)"

$(BUILD_DIR):
	mkdir $@

$(SO): $(OBJS)
	$(LINK) -o $@ $^ $(LIBS)

$(OBJS): $(BUILD_DIR)/%.o: %.m $(BUILD_DIR)
	$(CC) -o $@ -c $(CFLAGS) $(OBJCFLAGS) $<

$(COBJS): $(BUILD_DIR)/%.o: %.c $(BUILD_DIR)
	$(CC) -o $@ -c $(CFLAGS) $<

clean:
	rm -f $(OBJS)
	rm -f $(SO)

test: tests/test.m $(OBJS)
	$(CC) -o $@ $(CFLAGS) -I. $^ -llua -lobjc $(LIBS)

depend:
	$(CC) -MM $(CFLAGS) *.m *.c > depend.mak

.SUFFIXES: .m .o
.PHONY: all clean depend echo

-include depend.mak
