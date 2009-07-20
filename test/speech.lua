require "cocoa"
require "cocoa:AppKit"
local s = cocoa.NSSpeechSynthesizer:alloc():initWithVoice_(nil)
s:startSpeakingString_("Hello world!")
cocoa.NSThread:sleepForTimeInterval_(2.0)
s:stopSpeaking()
