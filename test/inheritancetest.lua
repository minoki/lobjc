require "objc"
require "cocoa"

local Hoge = objc.runtime.createClass("Hoge",cocoa.NSObject,{})
objc.runtime.class_addMethod(Hoge,"test1:",function(self,_cmd,a)
  print("Hoge -test1:",a)
end,"v@:i")
objc.runtime.class_addMethod(Hoge,"test2:",function(self,_cmd,a)
  print("Hoge -test2:",a)
end,"v@:i")
objc.runtime.class_addMethod(Hoge,"dealloc",function(self,_cmd)
  print("Hoge -dealloc")
  self.__super(cocoa.NSObject):dealloc()
end,"v@:")

local Piyo = objc.runtime.createClass("Piyo",Hoge,{})
objc.runtime.class_addMethod(Piyo,"test1:",function(self,_cmd,a)
  print("Piyo -test1:",a)
  self.__super(Hoge):test1_(a)
end,"v@:i")
objc.runtime.class_addMethod(Piyo,"dealloc",function(self,_cmd)
  print("Piyo -dealloc")
  self.__super(Hoge):dealloc()
end,"v@:")

local o = Piyo:new()
print(o)
print(o:isKindOfClass_(Hoge))
o:test1_(123)
o:test2_(123)
