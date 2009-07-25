local _G = _G
local type,tonumber,assert,error,pcall = type,tonumber,assert,error,pcall
local pairs,ipairs,rawset,select,unpack  = pairs,ipairs,rawset,select,unpack
local string  = require "string"
local table   = require "table"
local io      = require "io"
local os      = require "os"
local lxp     = require "lxp" -- expat
local objc    = require "objc"
local runtime = require "objc.runtime"
local ffi     = require "objc.runtime.ffi"
local typeencoding = require "objc.typeencoding"
module "objc.bridgesupport"
local skipqualifier,skiptype = typeencoding.skipqualifier,typeencoding.skiptype

local function DEBUG_print(...)
  local e = os.getenv "LOBJC_DEBUG" or ""
  if e:find("print",1,true) then
    _G.print(...)
  end
end

-- frameworkname(".../AppKit.framework") -> "AppKit"
local function frameworkname(path)
  local name = string.match(path,"([^/]+).framework/?$")
  assert(name,"bad framework path")
  return name
end
--[[
assert(frameworkname("/System/Library/Frameworks/AppKit.framework") == "AppKit")
assert(frameworkname("/System/Library/Frameworks/Foundation.framework/") == "Foundation")
]]


local function parsexml(data)
  local callbacks,results = {},{}
  function callbacks.StartElement(parser,name,attr)
    local t = {tag = name}
    for k,v in pairs(attr) do
      if type(k) == "string" then
        t[k] = v
      end
    end
    table.insert(results,t)
    local results0 = results
    results = t
    local EndElement0 = callbacks.EndElement
    callbacks.EndElement = function(parser,name2)
      assert(name == name2,"StartElement and EndElement do not match")
      results = results0
      callbacks.EndElement = EndElement0
    end
  end
  local p = lxp.new(callbacks)
  p:parse(data)
  p:close()
  if not results[1] then return nil,"no root element" end
  return results[1]
end

local choose64
if runtime._PTRSIZE == 8 then -- 64bit
  choose64 = function(hoge,hoge64)
    return hoge64 or hoge
  end
else -- 32bit
  choose64 = function(hoge,hoge64)
    return hoge
  end
end

local NSString = objc.classes.NSString

DEBUG_fnenc = {}

local function tobool(x,default)
  if x == "true" then return true
  elseif x == "false" then return false
  elseif x == nil then return default
  else error("BridgeSupport: invalid boolean: "..x) end
end

local function loadBS(b,bspath,bsinline)
  assert(b.tag == "signatures","bad BridgeSupport format in file: "..bspath)
  --assert(b.version == "1.0","bad BridgeSupport signature version")
  local handle_depends_on
  local handle_struct,handle_cftype,handle_opaque
  local handle_constant,handle_string_constant,handle_enum
  local handle_function,handle_function_alias
  local handle_informal_protocol,handle_class

  function handle_depends_on(e)
    objc.loadFrameworkByPath(e.path)
  end

  function handle_struct(e)
    local name = e.name
    local type = choose64(e.type,e.type64)
    local opaque = tobool(e.opaque,false)
    if not opaque then
      local tagname = string.match(type,"^{([^=])+=")
      objc.structures[name] = function(...)
        return objc.runtime.struct.new(tagname,...)
      end
    else
--      DEBUG_print("BridgeSupport: <struct>: opaque "..name.." "..type)
    end
  end

  function handle_cftype(e)
    local name = e.name
    local type = choose64(e.type,e.type64)
    local tollfree = e.tollfree
    local gettypeid_func = e.gettypeid_func
--    DEBUG_print("BridgeSupport: <cftype>: "..name.." "..type.." "..(tollfree or "").." "..(gettypeid_func or ""))
  end

  function handle_opaque(e)
    --DEBUG_print("BridgeSupport: <opaque>: "..e.name.." "..e.type)
  end

  function handle_constant(e)
    local name = e.name
    local type = choose64(e.type,e.type64)
    local magic_cookie = tobool(e.magic_cookie,false)
    if magic_cookie then
      --DEBUG_print("BridgeSupport: magic_cookie: "..name.." "..type)
      return
    end
    local value = ffi.getglobal(ffi.RTLD_DEFAULT,name,type)
    if objc.constants[e.name] and objc.constants[e.name] ~= value then
      DEBUG_print("BridgeSupport: duplicate constant name in file: "..bspath)
    end
    rawset(objc.constants,name,value)
  end

  function handle_string_constant(e)
    local value = e.value
    local nsstring = tobool(e.nsstring,false)
    if nsstring then
      value = NSString:stringWithUTF8String_(value)
    end
    if objc.constants[e.name] and objc.constants[e.name] ~= value then
      DEBUG_print("BridgeSupport: duplicate string constant name in file: "..bspath,e.name,objc.constants[e.name],value)
    end
    rawset(objc.constants,e.name,value)
  end

  function handle_enum(e)
    if tobool(e.ignore,false) then
      return
    end
    local value = choose64(e.value,e.value64)
    if not value then
      if runtime._ENDIAN == "little" then
        value = e.le_value
      elseif runtime._ENDIAN == "big" then
        value = e.be_value
      end
    end
    if value then
      value = assert(tonumber(value))
      if objc.constants[e.name] and objc.constants[e.name] ~= value then
        DEBUG_print("BridgeSupport: duplicate enum name in file: ",e.name)
        DEBUG_print("BridgeSupport: duplicate enum name in file: ",bspath.." "..e.name.." "..objc.constants[e.name].."<=>"..value)
      end
      rawset(objc.constants,e.name,value)
    end
  end

  function handle_function(e)
    local variadic = tobool(e.variadic,false)
    local inline = tobool(e.inline,false)
    if variadic then
      -- not supported yet
      return
    end
    local mod = inline and bsinline or ffi.RTLD_DEFAULT
    local args = {}
    local ret = "v"
    local already_retained = false
    for _,a in ipairs(e) do
      -- mandatory
      local type = choose64(a.type,a.type64)
      -- optional
      local function_pointer = tobool(a.function_pointer,false)
      local sel_of_type = choose64(a.sel_of_type,a.sel_of_type64)
      if a.tag == "arg" then
        -- optional
        local type_modifier = a.type_modifier or ""
        local null_accepted = tobool(a.null_accepted,true)
        local printf_format = tobool(a.printf_format,false)
        table.insert(args,type_modifier..type)
      elseif a.tag == "retval" then
        -- optional
        already_retained = tobool(a.already_retained,false)
        ret = type
      end
    end
    local sig = ret..table.concat(args)
    DEBUG_fnenc[e.name] = sig
    local f = ffi.loadfunction(mod,e.name,sig,#args,already_retained)
    objc.functions[e.name] = f
  end

  function handle_function_alias(e)
    if objc.functions[e.original] then
      objc.functions[e.name] = objc.functions[e.original]
    else
      DEBUG_print("non-existent function alias "..e.name.." -> "..e.original.." ignored in file: "..bspath)
    end
  end

  function handle_informal_protocol(e)
    local name = e.name
    objc.informal_protocols[name] = objc.informal_protocols[name] or {}
    local protocol = objc.informal_protocols[name]
    protocol.name = name
    protocol.methods = protocol.methods or {}
    for _,m in ipairs(e) do
      if m.tag ~= "method" then
        error("BridgeSupport: unknown tag in <informal_protocol>:"..m.tag)
      end
      -- mandatory
      local selector = m.selector
      local type = choose64(m.type,m.type64)
      -- optional
      local class_method = tobool(m.class_method,false)
      if not type then
        -- method does not exist in this environment
      elseif class_method then
        -- not supported
--        DEBUG_print("class_method in informal_protocol "..name.." "..selector.." "..type)
      else
        protocol.methods[selector] = {type=type}
      end
    end
  end

  function handle_class(e)
    local class = objc.classes[e.name]
    if not class then
      error("BridgeSupport: class '"..e.name.."' is mentioned in BridgeSupport, but does not exist")
    end
    for _,m in ipairs(e) do
      if m.tag ~= "method" then
        error("BridgeSupport: unknown tag in <class>:"..m.tag)
      end
      -- mandatory
      local selector = m.selector
      -- optional
      local class_method = tobool(m.class_method,false)
      local variadic = tobool(m.variadic,false)
      local ignore = tobool(m.ignore,false)
      local method
      if class_method then
        method = runtime.class_getClassMethod(class,selector)
      else
        method = runtime.class_getInstanceMethod(class,selector)
      end
      local encoding = method and assert(runtime.method_getTypeEncoding(method))
      for _,a in ipairs(m) do
        -- optional
        local type = choose64(a.type,a.type64)
        --local c_array_of_***
        local function_pointer = tobool(a.function_pointer,false)
        local sel_of_type = choose64(a.sel_of_type,a.sel_of_type64)
        local idx
        local type_modifier
        if a.tag == "arg" then
          -- mandatory
          local index = tonumber(a.index) -- zero-based
          -- optional
          type_modifier = a.type_modifier
          local null_accepted = tobool(a.null_accepted,true)
          local printf_format = tobool(a.printf_format,false)
--          type = type and type_modifier..type --TODO: type_modifierだけが指定された場合はどうするのか
          idx = index+3 -- selfと_cmdの次から
        elseif a.tag == "retval" then
          -- optional
          local already_retained = tobool(a.already_retained,false)
          idx = 0
        end
        if encoding and (type or type_modifier) then
          local s = encoding
          for _=1,idx do
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
      if method and encoding then
        runtime.overridesignature(method,encoding)
      end
    end
  end

  local delay_call = {}
  local function delay_pcall(f,...)
    table.insert(delay_call,{f=f,n=select("#",...),...})
  end
  local orig_pcall=pcall
  local function pcall(f,...)
    local s,e = orig_pcall(f,...)
    if not s then DEBUG_print("ignoring error:",e) end
  end

  for _,e in ipairs(b) do
    if e.tag == "depends_on" then pcall(handle_depends_on,e)
    elseif e.tag == "struct" then pcall(handle_struct,e)
    elseif e.tag == "cftype" then pcall(handle_cftype,e)
    elseif e.tag == "opaque" then pcall(handle_opaque,e)
    elseif e.tag =="constant"then pcall(handle_constant,e)
    elseif e.tag == "string_constant" then pcall(handle_string_constant,e)
    elseif e.tag == "enum"   then pcall(handle_enum,e)
    elseif e.tag =="function"then pcall(handle_function,e)
    elseif e.tag == "function_alias"  then delay_pcall(handle_function_alias,e)
    elseif e.tag =="informal_protocol"then pcall(handle_informal_protocol,e)
    elseif e.tag == "class"  then pcall(handle_class,e)
    else error("BridgeSupport: unknown tag: "..e.tag.." in file: "..bspath) end
  end
  for _,t in ipairs(delay_call) do
    pcall(t.f,unpack(t,1,t.n))
  end
  return true
end


local loaded,loaded_inline = {},{}

function loadBridgeSupportFile(fwpath,force)
  if loaded[fwpath] and not force then return true,"already loaded" end
  loaded[fwpath] = true
--DEBUG_print("loadBridgeSupportFile:",fwpath)
  -- NSBundleを使うべき?
  local fwname = frameworkname(fwpath)
  local bsname = fwname..".bridgesupport"
  local bsinline_name = fwname..".dylib"
  local dirs = {
    fwpath.."/Resources/BridgeSupport",
    "/System/Library/BridgeSupport",
    "/Library/BridgeSupport",
    "~/Library/BridgeSupport",
  }
  local f,e,bspath,bsinline_path
  for _,dir in ipairs(dirs) do
    bspath = dir.."/"..bsname
    f,e = io.open(bspath)
    if f then
      bsinline_path =dir.."/"..bsinline_name
      break
    end
  end
  if not f then return f,"could not load BridgeSupport file: "..e end
  local data = f:read("*a")
  f:close()
  local x,e = parsexml(data)
  if not x then return x,e end
  if not loaded_inline[bsinline_path] then
    loaded_inline[bsinline_path] = ffi.opendylib(bsinline_path)
  end
  return loadBS(x,bspath,loaded_inline[bsinline_path])
end

