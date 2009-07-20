#!/usr/bin/env lua
require "cocoa"
require "cocoa:AppKit"
if not arg[1] then
  io.write("usage: ",arg[0]," filename\n")
  return
end
local img = cocoa.NSImage:alloc():initWithContentsOfFile_(arg[1])
local size = img:size()
local width = size[1]
local height = size[2]
local repr = img:representations():objectAtIndex_(0)
io.output(arg[1]..".html")
io.write[[<html><head><style>
div.image>div{display:block;position:absolute;width:1px;height:1px;}
</style></head><body><div class="image">]]
for x = 0,width-1 do
  for y = 0,height-1 do
    local r,g,b,a = repr:colorAtX_y_(x,y):getRed_green_blue_alpha_()
    io.write(string.format([[<div style="left:%dpx;top:%dpx;background-color:rgba(%g,%g,%g,%g);"></div>
]],x,y,r*255,g*255,b*255,a*255))
  end
end
io.write[[</div></body></html>]]
