-- Copyright (C) 2009 ARATA Mizuki
-- See file COPYRIGHT for more information

local _G = _G
local rawset = rawset
local type,assert,error = type,assert,error
local require = require
local setmetatable = setmetatable
local pairs,ipairs = pairs,ipairs
local table = require "table"
local string = require "string"
local package = package
local lfs = require "lfs" -- luafilesystem
local runtime = require "objc.runtime"
local bridgesupport -- load later
module "objc"

local id_meta = runtime.__id_metatable
--runtime.__id_metatable = nil
function id_meta:__index(sel)
  assert(type(sel) == "string")
  sel = string.gsub(sel,"_",":")
  return function(self,...)
    return runtime.invoke(self,sel,...)
  end
end
function id_meta:__tostring()
  return self:description():UTF8String()
end
function id_meta:__call(...) -- for NSEnumerator
  local cls = runtime.object_getClass(self)
  local m = runtime.class_getInstanceMethod(cls,"nextObject")
  if m then
    return self:nextObject()
  else
    error("attempt to call a Objective-C object")
  end
end

_M.classes = setmetatable({},{__mode="kv",__index=function(t,n)
  local c = runtime.objc_lookUpClass(n)
  rawset(t,n,c)
  return c
end})

_M.constants = {} -- constant or string_constant or enum

_M.functions = {} -- C functions
-- TODO: 名前空間を統一するべきか

_M.structures = {} -- C structure constructors

_M.informal_protocols = {} -- informal protocols


local function loadBundle(bundle)
  if not bundle then
    return nil,"bundle not found"
  end
  -- NSBundle -isLoadedはBridgeSupportで戻り値がboolになってるのでBridgeSupportを読み込まないとダメ
  return bundle:isLoaded() or bundle:load()
end
function loadFrameworkByPath(path)
  local loaded,e = loadBundle(classes.NSBundle:bundleWithPath_(path))
  if not loaded then return loaded,e end
  return bridgesupport.loadBridgeSupportFile(path)
end
--[[
function loadFrameworkByIdentifier(id)
  return loadBundle(classes.NSBundle:bundleWithIdentifier_(id))
end
]]

bridgesupport = require "objc.bridgesupport"


bridgesupport.loadBridgeSupportFile "/System/Library/Frameworks/Foundation.framework"

local function findFileInDirectories(file,dirs)
  for _,dir in ipairs(dirs) do
    local path = dir.."/"..file
    if lfs.attributes(path,"mode") then
      return path
    end
  end
  return nil
end

table.insert(package.loaders,function(name)
  local m = string.match(name,"^objc.framework:(%w+)$") or string.match(name,"^cocoa:(%w+)$")
  if not m then return end
  local path = findFileInDirectories(m..".framework",{
    "/System/Library/Frameworks",
    "/Library/Frameworks",
    "~/Library/Frameworks",
  })
  if not path then
    return "framework '"..m.."' not found"
  end
  return function(modname)
    return assert(loadFrameworkByPath(path))
  end
end)

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

-- for debugging
function runtime.gettypeencoding(obj,sel)
  local cls = runtime.object_getClass(obj)
  local m = runtime.class_getInstanceMethod(cls,sel)
  return runtime.method_getTypeEncoding(m)
end


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



function implement_informal_protocol(o,name)
  local protocol = _M.informal_protocols[name]
  for sel,m in pairs(protocol.methods) do
    runtime.registermethod(o,sel,m.type)
  end
  return o
end


