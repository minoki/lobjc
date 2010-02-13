-- Copyright (C) 2010 ARATA Mizuki
-- See file COPYRIGHT for more information

local error = error
local string = require "string"
local table = require "table"
local setmetatable = setmetatable
local tonumber = tonumber
local assert = assert
local ipairs = ipairs
local tostring = tostring
local type = type
local runtime = require "objc.runtime"
module "objc.types"

local meta = {}
meta.__index = meta
function meta.__eq(a,b)
  if a.kind ~= b.kind then
    return false
  end
  local kind = a.kind
  if kind == "primitive" then
    return a.name == b.name
  elseif kind == "pointer" then
    return a.referred == b.referred
  elseif kind == "array" then
    return a.length == b.length and a.element == b.element
  elseif kind == "struct" or kind == "union" then
    if a.tag ~= b.tag or #a.elements ~= #b.elements then
      return false
    end
    for i,t in ipairs(a.elements) do
      if t ~= b.elements[i] then
        return false
      end
    end
    return true
  else
    error "invalid type kind"
  end
end
function meta.__tostring(type)
  if type.kind == "primitive" then
    return type.name
  elseif type.kind == "pointer" then
    return tostring(type.referred).."*"
  elseif type.kind == "array" then
    return tostring(type.element).."["..type.length.."]"
  elseif type.kind == "struct" or type.kind == "union" then
    local elements = ""
    for _,t in ipairs(type.elements) do
      elements = elements..tostring(t).."; "
    end
    return string.format("%s %s{ %s}",type.kind,type.tag and type.tag.." " or "",elements)
  else
    error "invalid type kind"
  end
end

local function encode(type)
  if type.kind == "primitive" then
    return type.code
  elseif type.kind == "pointer" then
    return "^"..encode(type.referred)
  elseif type.kind == "array" then
    return "["..type.length..encode(type.element).."]"
  elseif type.kind == "struct" then
    local code = "{"..(type.tag or "?").."="
    for _,t in ipairs(type.elements) do
      code = code..encode(t)
    end
    return code.."}"
  elseif type.kind == "union" then
    local code = "("..(type.tag or "?").."="
    for _,t in ipairs(type.elements) do
      code = code..encode(t)
    end
    return code..")"
  else
    error "invalid type kind"
  end
end
_M.encode = encode

local types = {}
local unencode_t = {}
local function primitive(name,code)
  types[name] = setmetatable({kind="primitive",name=name,code=code},meta)
  unencode_t[code] = types[name]
end
local function pointer(type)
  return setmetatable({kind="pointer",referred=type},meta)
end
local function array(type,length)
  return setmetatable({kind="array",element=type,length=length},meta)
end
primitive("char","c")
primitive("int","i")
primitive("short","s")
primitive("long","l")
primitive("longlong","q")
primitive("uchar","C")
primitive("uint","I")
primitive("ushort","S")
primitive("ulong","L")
primitive("ulonglong","Q")
primitive("float","f")
primitive("double","d")
primitive("bool","B")
primitive("void","v")
primitive("string","*")
primitive("id","@")
primitive("Class","#")
primitive("SEL",":")

local function rawparse(str,i)
  i = string.match(str,"^%s*()",i or 1)
  local t
  if string.match(str,"^struct%f[^%w_]",i) or string.match(str,"^union%f[^%w_]",i) then
    local kind,tag,j = string.match(str,"^(%w+)%f[^%w_]%s*([%w_]*)%s*()",i)
    t = setmetatable({kind=kind,elements={},fieldnames={}},meta)
    if tag ~= "" then
      t.tag = tag
    end
    local c = 1
    if string.match(str,"^{",j) then
      i = string.match(str,"^{%s*()",j)
      while true do
        if string.match(str,"^}",i) then
          i = string.match(str,"^}%s*()",i)
          break
        elseif string.match(str,"^$",i) then
          error("unexpected end of "..kind.." definition")
        end
        local u,j = rawparse(str,i)
        local fieldname
        fieldname,i = string.match(str,"^([%w_]*)%s*;%s*()",j)
        t.elements[c] = u
        if fieldname ~= "" then
          t.fieldnames[c] = fieldname
        end
        c = c + 1
      end
    end
  elseif string.match(str,"^%w+%f[^%w_]",i) then
    local n
    n,i = string.match(str,"^(%w+)%s*()",i)
    t = assert(types[n],"unknown type '"..n.."'")
  else
    error "invalid type"
  end
  assert(type(t) == "table")
  repeat
    if string.match(str,"^%*",i) then
      i = string.match(str,"^%*%s*()",i)
      t = pointer(t)
    elseif string.match(str,"^%[%s*%d+%s*%]",i) then
      local len
      len,i = string.match(str,"^%[%s*(%d+)%s*%]%s*()",i)
      t = array(t,tonumber(len))
    else
      break
    end
  until false
  return t,i
end
function parse(str,i)
  local t,i = rawparse(str,i)
  assert(type(t) == "table")
  assert(i > #str,"invalid type")
  return t
end

local function decode(str,i)
  -- TODO: qualifier
  if string.match(str,"^[cislqCISLQfdBv*@#:]",i) then
    local c,i = string.match(str,"^[cislqCISLQfdBv*@#:]",i)
    return unencode_t[c],i
  elseif string.match(str,"^%[",i) then -- array
    local len,i = string.match(str,"^%[(%d+)()",i)
    assert(len)
    local t,i = decode(str,i)
    i = assert(string.match(str,"^%]()",i))
    return array(t,tonumber(len)),i
  elseif string.match(str,"^{",i) then -- structure
    local tag,i = string.match(str,"^{([?%w_]+)=()",i)
    assert(tag)
    local t = setmetatable({kind="struct",elements={},fieldnames={}},meta)
    if tag ~= "?" then
      t.tag = tag
    end
    local c = 1
    while true do
      if string.match(str,"^}",i) then
        i = i + 1
        break
      else
        local fieldname,u
        if string.match(str,'^".+"',i) then
          fieldname,i = string.match(str,'^"(.+)"()',i)
        end
        u,i = decode(str,i)
        t.elements[c] = u
        if fieldname then
          t.fieldnames[c] = fieldname
        end
        c = c+1
      end
    end
    return t,i
  elseif string.match(str,"^%(",i) then -- union
    local tag,i = string.match(str,"^%(([?%w_]+)=()",i)
    assert(tag)
    local t = setmetatable({kind="union",elements={},fieldnames={}},meta)
    if tag ~= "?" then
      t.tag = tag
    end
    local c = 1
    while true do
      if string.match(str,"^%)",i) then
        i = i + 1
        break
      else
        local fieldname,u
        if string.match(str,'^".+"',i) then
          fieldname,i = string.match(str,'^"(.+)"()',i)
        end
        u,i = decode(str,i)
        t.elements[c] = u
        if fieldname then
          t.fieldnames[c] = fieldname
        end
        c = c+1
      end
    end
    return t,i
  elseif string.match(str,"^b%d+",i) then -- bitfield
    error("bitfield not supported")
  elseif string.match(str,"^%^",i) then -- pointer
    t,i = decode(str,i+1)
    return pointer(t),i
  elseif i > #str then
    error("unexpected end of type encoding")
  else
    error("invalid type encoding: '"..string.sub(str,i).."'")
  end
end

function typedef(t,alias)
  if type(t) == "string" then
    t = parse(t)
  end
  assert(not types[alias] or types[alias] == t,"the type with name '"..alias.."' already defined")
  if not types[alias] then
    types[alias] = t
  end
end

do
  assert(parse"int * " == pointer(types.int))
  assert(parse"int * [123]" == array(pointer(types.int),123))
  assert(parse"struct hage {}*" == parse"struct    hage {  } *")
  assert(parse"struct hage {  int; }*" == parse"struct    hage {  int neko; } *")
end


---[==[ Should be in BridgeSupport
if runtime._PTRSIZE == 8 then
  -- 64bit
  typedef("double","CGFloat")
  typedef("long","NSInteger")
  typedef("ulong","NSUInteger")
else
  -- 32bit
  typedef("float","CGFloat")
  typedef("int","NSInteger")
  typedef("uint","NSUInteger")
end
typedef([[struct CGPoint { CGFloat x; CGFloat y; }]],"CGPoint")
typedef([[struct CGSize { CGFloat width; CGFloat height; }]],"CGSize")
typedef([[struct CGRect { CGPoint origin; CGSize size; }]],"CGRect")
if runtime._PTRSIZE == 8 then
  -- 64bit
  typedef("CGPoint","NSPoint")
  typedef("CGSize","NSSize")
  typedef("CGRect","NSRect")
else
  -- 32bit
  typedef([[struct _NSPoint { CGFloat x; CGFloat y; }]],"NSPoint")
  typedef([[struct _NSSize { CGFloat width; CGFloat height; }]],"NSSize")
  typedef([[struct _NSRect { NSPoint origin; NSSize size; }]],"NSRect")
end
typedef([[struct _NSRange { uint location; uint length; }]],"NSRange")
---]==]
