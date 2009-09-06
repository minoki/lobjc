require "objc"
require "cocoa"

local MyClass = objc.runtime.createClass("MyClass",cocoa.NSObject,{"a","b","c","d"})
local o = MyClass:alloc():init()
o.__fields.a = 123
o.__fields.b = o
o.__fields.c = "hoge"
o.__fields.d = true
assert(o.__fields.a == 123)
assert(o.__fields.b == o)
assert(o.__fields.c == "hoge")
assert(o.__fields.d == true)
