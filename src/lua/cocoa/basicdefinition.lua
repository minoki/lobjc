-- Copyright (C) 2010 ARATA Mizuki
-- See file COPYRIGHT for more information

local ipairs = ipairs
local assert = assert
local string = require "string"
local objc = require "objc"
local runtime = require "objc.runtime"
local types = require "objc.types"
local typeencoding = require "objc.typeencoding"
module "cocoa"
local skipqualifier,skiptype = typeencoding.skipqualifier,typeencoding.skiptype
local typedef = types.typedef
local struct_registry = runtime.__struct_registry

local function readOptionalType(s,i)
  local b,t = string.match(s,"^(%b())()",i)
  if b then
    b = string.match(b,"^%(%s*(.*)%s*%)$")
    local l = 1
    local d = {}
    repeat
      local k,j = string.match(b,"^(%w+)%s*()",l)
      if k == "in" or k == "out" or k == "inout" then
        d[k] = true
        l = j
      else
        break
      end
    until false
    if #b >= l then
      d.type = types.parse(b,l)
    end
    return d,t
  else
    return nil,i
  end
end

local function class_override(classname)
  local class = objc.classes[classname]
  return function(def)
    if not class then return end
    for kind,d in string.gmatch(def,"([%-%+])%s*(.-)%s*;") do
      local overrides,i,j = {n=2}
      overrides[0],i = readOptionalType(d,1)
      local methodname,colon,p
      methodname,colon,i = string.match(d,"^%s*([%w_]+(:?))%s*()",i)
      if colon == ":" then
        while true do
          overrides.n = overrides.n+1
          overrides[overrides.n],i = readOptionalType(d,i)
          p,j = string.match(d,"^%s*([%w_]+:)%s*()",i)
          if not p then
            assert(i > #d)
            break
          else
            i = j
            methodname = methodname..p
          end
        end
      end

      local methad
      if kind == "+" then
        method = runtime.class_getClassMethod(class,methodname)
      else
        method = runtime.class_getInstanceMethod(class,methodname)
      end
      if method then
        local encoding = runtime.method_getTypeEncoding(method)
        if encoding then
          for i = 0,overrides.n do
            local r = overrides[i]
            if r then
              local type,type_modifier
              if r["out"] then
                type_modifier = "o"
              elseif r["inout"] then
                type_modifier = "N"
              end
              if r.type then
                type = types.encode(r.type)
              end
              local s = encoding
              for _=1,i do
                s = skiptype(s)
                s = string.match(s,"^%d*(.*)") -- skip frame offset
              end
              if type and type_modifier then
                encoding = string.sub(encoding,1,-#s-1)..type_modifier..type..skiptype(s)
              elseif type then
                s = skipqualifier(s)
                encoding = string.sub(encoding,1,-#s-1)..type..skiptype(s)
              elseif type_modifier then
                encoding = string.sub(encoding,1,-#s-1)..type_modifier..skipqualifier(s)
              end
            end
          end
          runtime.overridesignature(method,encoding)
        end
      end
    end
  end
end

local function struct(name)
  return function(def)
    local t = types.parse(def)
    types.typedef(t,name)
    local struct_info
    local tagname = t.tag
    if tagname then
      struct_info = struct_registry[tagname]
      if struct_info == nil then
        struct_info = {}
        struct_registry[tagname] = struct_info
      end
    else
      struct_info = {}
    end
    for i,e in ipairs(t.elements) do
      if t.fieldnames[i] then
        struct_info[i] = t.fieldnames[i]
        struct_info[t.fieldnames[i]] = i
      end
    end
    assert(not struct_info[":count:"] or struct_info[":count:"] == #t.elements)
    struct_info[":count:"] = #t.elements
    struct_info[":typeencoding:"] = types.encode(t)
    objc.structures[name] = function(fields)
      return objc.struct.new(tagname,fields,struct_info)
    end
  end
end

typedef("bool","BOOL")
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

-- Foundation
struct "CGPoint" [[
struct CGPoint {
  CGFloat x;
  CGFloat y;
}
]]
struct "CGSize" [[
struct CGSize {
  CGFloat width;
  CGFloat height;
}
]]
struct "CGRect" [[
struct CGRect {
  CGPoint origin;
  CGSize size;
}
]]
if runtime._PTRSIZE == 8 then
  -- 64bit
  struct "NSPoint" [[CGPoint]]
  struct "NSSize" [[CGSize]]
  struct "NSRect" [[CGRect]]
else
  -- 32bit
  struct "NSPoint" [[
  struct _NSPoint {
    CGFloat x;
    CGFloat y;
  }
  ]]
  struct "NSSize" [[
  struct _NSSize {
    CGFloat width;
    CGFloat height;
  }
  ]]
  struct "NSRect" [[
  struct _NSRect {
    NSPoint origin;
    NSSize size;
  }
  ]]
end
struct "NSRange" [[
struct _NSRange {
  uint location;
  uint length;
}
]]

class_override "NSObject" [[
- (bool)respondsToSelector:;
+ (bool)instancesRespondToSelector:;
+ (bool)isSubclassOfClass:;
+ (bool)conformsToProtocol:;
- (bool)isEqual:;
- (bool)isKindOfClass:;
- (bool)isMemberOfClass:;
- (bool)isProxy;
]]
class_override "NSBundle" [[
- (bool)isLoaded;
- (bool)load;
]]
class_override "NSNumber" [[
+ numberWithBool:(bool);
- (bool)boolValue;
- initWithBool:(bool);
- (bool)isEqualToNumber:;
]]
class_override "NSValue" [[
- (bool)isEqualToValue:;
]]
class_override "NSString" [[
- (bool)boolValue;
- (bool)isAbsolutePath;
- (bool)isEqualToString:;
- (bool)writeToFile:atomically:(bool);
- (bool)writeToURL:atomically:(bool);
]]
class_override "NSXMLParser" [[
- (bool)parse;
- setShouldProcessNamespaces:(bool);
- setShouldReportNamespacePrefixes:(bool);
- setShouldResolveExternalEntities:(bool);
- (bool)shouldProcessNamespaces;
- (bool)shouldReportNamespacePrefixes;
- (bool)shouldResolveExternalEntities;
]]
class_override "NSXMLDocument" [[
- initWithContentsOfURL:options:error:(out);
- initWithData:options:error:(out);
- initWithXMLString:options:error:(out);
- (bool)isStandalone;
- objectByApplyingXSLT:arguments:error:(out);
- objectByApplyingXSLTAtURL:arguments:error:(out);
- objectByApplyingXSLTString:arguments:error:(out);
- setStandalone:(bool);
- (bool)validateAndReturnError:(out);
]]

-- AppKit
class_override "NSColor" [[
- getRed:(out) green:(out) blue:(out) alpha:(out);
]]
