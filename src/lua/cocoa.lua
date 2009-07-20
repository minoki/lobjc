local setmetatable = setmetatable
local objc = require "objc"
module "cocoa"

setmetatable(_M,{__index = function(t,k)
  return objc.classes[k] or objc.constants[k] or objc.functions[k]
end})
