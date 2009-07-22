require "cocoa"
local o = cocoa.NSString:stringWithUTF8String_(arg[1] or "Hello!")
local c = cocoa.NSConnection:defaultConnection();
c:setRootObject_(o);
if not c:registerName_("lua-server") then
  error("registerName failed")
end

local running = false
repeat
  local next = cocoa.NSDate:dateWithTimeIntervalSinceNow_(1.0)
  running = cocoa.NSRunLoop:currentRunLoop():runMode_beforeDate_(cocoa.NSDefaultRunLoopMode,next)
until not running
