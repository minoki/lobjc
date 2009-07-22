require "cocoa"
local o = cocoa.NSConnection:rootProxyForConnectionWithRegisteredName_host_("lua-server",nil)
print("server object:",o)
