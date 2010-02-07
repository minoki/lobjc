-- Copyright (C) 2009-2010 ARATA Mizuki
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
local runtime = require "objc.runtime"
local bridgesupport -- load later
module "objc"

local fields_proxy do
  local cache = setmetatable({},{__mode="kv"})
  local meta = {}
  function meta:__index(k)
    return runtime.getInstanceVariable(self[meta],k)
  end
  function meta:__newindex(k,v)
    runtime.setInstanceVariable(self[meta],k,v)
  end
  function fields_proxy(o)
    local c = cache[o]
    if not c then
      c = setmetatable({[meta]=o},meta)
      cache[o] = c
    end
    return c
  end
end

local objc_super_meta = {}
function objc_super_meta:__index(k)
  assert(type(k) == "string")
  local sel = string.gsub(k,"_",":")
  return function(self,...)
    return runtime.invokewithclass(self.class,self.receiver,sel,...)
  end
end

local id_meta = runtime.__id_metatable
--runtime.__id_metatable = nil
function id_meta:__index(k)
  if k == "__fields" then
    return fields_proxy(self)
  elseif k == "__super" then
    return function(class)
      return setmetatable({receiver=self,class=class},objc_super_meta)
    end
  end
  assert(type(k) == "string")
  local sel = string.gsub(k,"_",":")
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
    local cpath = classes.NSString:stringWithUTF8String_(path)
    cpath = cpath:stringByExpandingTildeInPath()
    if classes.NSFileManager:defaultManager():fileExistsAtPath_(cpath) then
      return path
    end
  end
  return nil
end

table.insert(package.loaders,function(name)
  local m = string.match(name,"^cocoa:(%w+)$")
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


-- for debugging
function runtime.gettypeencoding(obj,sel)
  local cls = runtime.object_getClass(obj)
  local m = runtime.class_getInstanceMethod(cls,sel)
  return runtime.method_getTypeEncoding(m)
end





function implement_informal_protocol(o,name)
  local protocol = _M.informal_protocols[name]
  for sel,m in pairs(protocol.methods) do
    runtime.registermethod(o,sel,m.type)
  end
  return o
end


do
  local Method_meta = runtime.__Method_metatable
  Method_meta.__index = Method_meta
  Method_meta.getName = runtime.method_getName
  Method_meta.getNumberOfArguments = runtime.method_getNumberOfArguments
  Method_meta.getTypeEncoding = runtime.method_getTypeEncoding
  function Method_meta:__tostring()
    return string.format("Method '%s' <%s>", self:getName(), self:getTypeEncoding())
  end
  local Ivar_meta = runtime.__Ivar_metatable
  Ivar_meta.__index = Ivar_meta
  Ivar_meta.getName = runtime.ivar_getName
  Ivar_meta.getTypeEncoding = runtime.ivar_getTypeEncoding
  Ivar_meta.getOffset = runtime.ivar_getOffset
  function Ivar_meta:__tostring()
    return string.format("Ivar '%s' <%s>", self:getName(), self:getTypeEncoding())
  end
end


require "objc.struct"
