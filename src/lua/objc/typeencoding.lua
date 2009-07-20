local error = error
local string = require "string"
module "objc.typeencoding"

function skipqualifier(s)
  return string.match(s,"^[rnNoORV]*(.*)")
end
function skiptype(s)
  s = skipqualifier(s)
  if string.match(s,"^[cislqCISLQfdBv*@#:?]") then
    return string.match(s,"^.(.*)")
  elseif string.match(s,"^%b[]") then -- array
    return string.match(s,"^%b[](.*)")
  elseif string.match(s,"^%b{}") then -- structure
    return string.match(s,"^%b{}(.*)")
  elseif string.match(s,"^%b()") then -- union
    return string.match(s,"^%b()(.*)")
  elseif string.match(s,"^b%d+") then -- bitfield
    return string.match(s,"^b%d+(.*)")
  elseif string.match(s,"^%^") then -- pointer
    return skiptype(string.match(s,"^.(.*)"))
  elseif s == "" then
    error("unexpected end of type encoding")
  else
    error("invalid type encoding: '"..string.sub(s,1).."'")
  end
end
