-- Copyright (C) 2010 ARATA Mizuki
-- See file COPYRIGHT for more information

local _G = _G
local assert,type = assert,type
local select = select
local runtime = require "objc.runtime"
local pairs,ipairs = pairs,ipairs
local setmetatable = setmetatable
local string = require "string"
local rawget,rawset = rawget,rawset
module "objc"
local objc = _M

local definition_meta = {}
function definition_meta:__index(name)
  if name == "sig" then
    return function(sig)
      assert(not rawget(self,"__current_signature__"))
      rawset(self,"__current_signature__",sig)
    end
  elseif name == "class" then
    return self.__metaclass_definition__
  end
end
function definition_meta:__newindex(name,func)
  if type(func) == "function" then
    local sel = string.gsub(name,"_",":")
    local sig
      _G.print("sig",rawget(self,"__current_signature__"),name,func)
    if self.__signatures__[sel] then
      sig = self.__signatures__[sel]
      if rawget(self,"__current_signature__") then
        assert(sig == rawget(self,"__current_signature__"),"different signature than one specified in protocol")
        rawset(self,"__current_signature__",nil)
      end
    else
      local super_method = runtime.class_getInstanceMethod(self.__super__,sel)
      if super_method then
        -- TODO: fetch overridden signature
        sig = runtime.method_getTypeEncoding(super_method)
        if rawget(self,"__current_signature__") then
          assert(sig == rawget(self,"__current_signature__"),"different signature than one in super class")
          rawset(self,"__current_signature__",nil)
        end
      else
        sig = assert(rawget(self,"__current_signature__"),"signature missing")
        rawset(self,"__current_signature__",nil)
      end
    end
    runtime.class_addMethod(self.__class__,sel,function(self,_cmd,...)
      return func(self,...)
    end,sig)
  end
end

function defineClass(...)
  local n = select("#",...)
  local def
  if n == 1 and type((...)) == "table" then
    def = ...
  else
    def = {}
    def.name,def.super,def.fields,def.protocols = ...
  end
  assert(type(def.name) == "string","bad class name")
  assert(def.super,"bad super class")
  local createdClass = runtime.createClass(def.name,def.super,def.fields)
  local signatures = {}
  local signaturesforclassmethods = {}
  if def.protocols then
    for _,v in ipairs(def.protocols) do
      if type(v) == "string" and objc.informal_protocols[v] then
        local protocol = objc.informal_protocols[v]
        for selector,info in pairs(protocol.methods) do
          signatures[selector] = info.type
        end
        for selector,info in pairs(protocol.classmethods) do
          signaturesforclassmethods[selector] = info.type
        end
      else
        local protocol
        if type(v) == "string" then
          protocol = runtime.objc_getProtocol(v)
        else
          protocol = v
        end
        local mlist = runtime.protocol_copyMethodDescriptionList(protocol,true,true) -- instance,required
        for _,m in ipairs(mlist) do
          signatures[m.name] = m.types
        end
        mlist = runtime.protocol_copyMethodDescriptionList(protocol,false,true) -- instance,optional
        for _,m in ipairs(mlist) do
          signatures[m.name] = m.types
        end
        mlist = runtime.protocol_copyMethodDescriptionList(protocol,true,false) -- class,required
        for _,m in ipairs(mlist) do
          signaturesforclassmethods[m.name] = m.types
        end
        mlist = runtime.protocol_copyMethodDescriptionList(protocol,true,false) -- class,optional
        for _,m in ipairs(mlist) do
          signaturesforclassmethods[m.name] = m.types
        end
      end
    end
  end
  local metaclass_definition = setmetatable({
    __signatures__ = signaturesforclassmethods,
    __class__ = runtime.object_getClass(createdClass),
    __super__ = runtime.object_getClass(def.super),
    __current_signature__ = nil,
  },definition_meta)
  local definition = setmetatable({
    __signatures__ = signatures,
    __class__ = createdClass,
    __super__ = def.super,
    __current_signature__ = nil,
    __metaclass_definition__ = metaclass_definition,
  },definition_meta)
  return definition,createdClass
end

function extendClass(class)
  local super = runtime.class_getSuperclass(class)
  local metaclass_definition = setmetatable({
    __signatures__ = {},
    __class__ = runtime.object_getClass(class),
    __super__ = runtime.object_getClass(super),
    __current_signature__ = nil,
  },definition_meta)
  local definition = setmetatable({
    __signatures__ = {},
    __class__ = class,
    __super__ = super,
    __current_signature__ = nil,
    __metaclass_definition__ = metaclass_definition,
  },definition_meta)
  return definition
end

