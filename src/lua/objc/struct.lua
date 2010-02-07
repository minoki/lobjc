local getmetatable,setmetatable = getmetatable,setmetatable
local ipairs,pairs = ipairs,pairs
local string = require "string"
local table = require "table"
local tostring = tostring
local runtime = require "objc.runtime"
local rawget,rawset = rawget,rawset
module "objc.struct"

local struct_registry = runtime.__struct_registry
--[[
struct_registry = {
  [tagname] = {
    [":count:"] = number of field,
    [":typeencoding:"] = type encoding,
    [index] = field name,
    [field name] = index,
  }
}
]]
local struct_meta = runtime.__struct_metatable

function struct_meta:__eq(other)
  if rawget(self,":tagname:") ~= rawget(other,":tagname:") then
    return false
  end
  local n = rawget(self,":struct_info:")[":count:"]
  for i = 1,n do
    if self[i] ~= other[i] then
      return false
    end
  end
  return true
end

function struct_meta:__index(fieldname)
  local si = rawget(self,":struct_info:")
  return rawget(self,si[fieldname])
end

function struct_meta:__newindex(fieldname,value)
  local si = rawget(self,":struct_info:")
  rawset(self,si[fieldname],value)
end

function struct_meta:__tostring()
  local tagname = rawget(self,":tagname:")
  local si = rawget(self,":struct_info:")
  local fields = ""
  for i = 1,si[":count:"] do
    fields = string.format("%s%s=%s; ",fields,si[i] or "#"..i,tostring(self[i]))
  end
  return string.format("struct %s { %s}",tagname,fields)
end

function new(tagname,fields,struct_info)
  if tagname then
    struct_info = struct_info or struct_registry[tagname]
    if struct_info == nil then
      struct_info = {}
      struct_registry[tagname] = struct_info
    end
  end
  local t = {
    [":tagname:"]=tagname,
    [":struct_info:"]=struct_info,
  }
  if fields then
    local n = struct_info[":count:"]
    if n == nil then
      for i,v in ipairs(fields) do
        t[i] = v
      end
    else
      local j = 1
      for i = 1,n do
        local fieldname = struct_info[i]
        local v = fields[fieldname]
        if v == nil then
          v,j = fields[j],j+1
        end
        t[i] = v
      end
    end
  end
  return setmetatable(t,struct_meta)
end



