INSTALL_TOP= /usr/local
INSTALL_LMOD= $(INSTALL_TOP)/share/lua/5.1
INSTALL_CMOD= $(INSTALL_TOP)/lib/lua/5.1

INSTALL= install -p
INSTALL_EXEC= $(INSTALL) -m 0755
INSTALL_DATA= $(INSTALL) -m 0644

MKDIR= mkdir -p


all clean:
	cd src && $(MAKE) $@

TO_CMOD= objc.so
TO_LMOD= lua/objc.lua lua/objc/typeencoding.lua lua/objc/bridgesupport.lua lua/cocoa.lua

install:
	cd src && $(MKDIR) $(INSTALL_LMOD) $(INSTALL_CMOD) $(INSTALL_LMOD)/objc
	cd src && $(INSTALL_EXEC) $(TO_CMOD) $(INSTALL_CMOD)
	cd src && $(INSTALL_DATA) lua/objc.lua lua/cocoa.lua $(INSTALL_LMOD)
	cd src && $(INSTALL_DATA) lua/objc/bridgesupport.lua lua/objc/typeencoding.lua $(INSTALL_LMOD)/objc

local:
	$(MAKE) install INSTALL_TOP=..

.PHONY: all clean install local
