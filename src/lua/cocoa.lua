-- Copyright (C) 2009-2010 ARATA Mizuki
-- See file COPYRIGHT for more information

local setmetatable = setmetatable
local pairs,ipairs = pairs,ipairs
local table = require "table"
local objc = require "objc"
local runtime = require "objc.runtime"
module "cocoa"

local classes = objc.classes

local function enumerator_aux(e)
  return e:nextObject()
end
function enumerator(e)
  return enumerator_aux,e
end
--[[
for elem in objc.enumerator(arr:objectEnumerator()) do
end
function enumerator(e)
  return function()
    return e:nextObject()
  end
end
for elem in (function() return e:nextObject() end) do
end
]]

-- convert to NS*** collections
function table_to_NSArray(t)
  local a = classes.NSMutableArray:arrayWithCapacity_(#t)
  for _,v in ipairs(t) do
    a:addObject_(v)
  end
  return a
end
function table_to_NSDictionary(t)
  local a = classes.NSMutableDictionary:new()
  for k,v in pairs(t) do
    a:setObject_forKey_(v,k)
  end
  return a
end
function table_to_NSSet(t)
  local a = classes.NSMutableSet:new()
  for _,v in ipairs(t) do
    a:addObject_(v)
  end
  return a
end
function table_to_NSCountedSet(t)
  local a = classes.NSCountedSet:new()
  for _,v in ipairs(t) do
    a:addObject_(v)
  end
  return a
end
function string_to_NSString(s)
  return classes.NSString:stringWithUTF8String_(s)
end
string_to_NSData = runtime.string_to_NSData

-- convert back from NS***
function NSArray_to_table(a)
  local t = {}
  for x in enumerator(a:objectEnumerator()) do
    table.insert(t,x)
  end
  return t
end
function NSDictionary_to_table(a)
  local t = {}
  for k in enumerator(a:objectEnumerator()) do
    t[k] = a:objectForKey_(k)
  end
  return t
end
function NSString_to_string(a)
  if a == nil then return nil end
  return a:UTF8String()
end
NSData_to_string = runtime.NSData_to_string


setmetatable(_M,{__index = function(t,k)
  return classes[k] or objc.constants[k] or objc.functions[k] or objc.structures[k]
end})
