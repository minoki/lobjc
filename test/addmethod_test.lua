require "objc"
require "cocoa"

local MyClass = objc.runtime.createClass("MyClass",cocoa.NSObject,{"a","b","c","d"})
objc.runtime.class_addMethod(MyClass,"test1",function(self,_cmd)
  print("test1:",self,_cmd)
end,"v0@0:0")
objc.runtime.class_addMethod(MyClass,"test2:",function(self,_cmd,a)
  print("test2:",self,_cmd,a)
end,"v0@0:0i0")
objc.runtime.class_addMethod(MyClass,"test3::",function(self,_cmd,a,b)
  print("test3:",self,_cmd,a,b)
  return a+b
end,"f0@0:0f0f0")
objc.runtime.class_addMethod(MyClass,"test4::::::",function(self,_cmd,a,b,...)
  print("test4:",self,_cmd,a,b,...)
  return a+b,a-b,a*b,a/b
end,"v0@0:0f0f0o^f0o^f0o^f0o^f0")

local o = MyClass:alloc():init()
print("o:",o)
o:test1()
o:test2_(123)
assert(o:test3__(1,2) == 3)
local r = {o:test4______(3,4)}
assert(r[1] == 7)
assert(r[2] == -1)
assert(r[3] == 12)
assert(r[4] == 3/4)
