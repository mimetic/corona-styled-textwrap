-- main.lua

--[[
	Demonstration of textrender.lua, a module for rendering styled text.


	textrender parameters:

	text = text to render
	font = font name, e.g. "AvenirNext-DemiBoldItalic"
	size = font size in pixels
	lineHeight = line height in pixels
	color = text color in an RGBa color table, e.g. {250, 0, 0, 255}
	width = Width of the text column,
	alignment = text alignment: "Left", "Right", "Center"
	opacity = text opacity (between 0 and 1, or as a percent, e.g. "50%" or 0.5
	minCharCount = Minimum number of characters per line. Estimate low, e.g. 5
	targetDeviceScreenSize = String of target screen size, in the form, "width,height", e.g. e.g. "1024,768".  May be different from current screen size.
	letterspacing = (unused)
	maxHeight = Maximum height of the text column. Extra text will be hidden.
	minWordLen = Minimum length of a word shown at the end of a line. In good typesetting, we don't end our lines with single letter words like "a", so normally this value is 2.
	textstyles = A table of text styles, loaded using funx.loadTextStyles()
	defaultStyle = The name of the default text style for the text block
	cacheDir = the name of the cache folder to use inside system.CachesDirectory, e.g. "text_render_cache"
--]]


-- My useful function collection
local funx = require("funx")
local textwrap = require("textwrap")

-- Make a local copy of the application settings global
local screenW, screenH = display.contentWidth, display.contentHeight
local viewableScreenW, viewableScreenH = display.viewableContentWidth, display.viewableContentHeight
local screenOffsetW, screenOffsetH = display.contentWidth -	 display.viewableContentWidth, display.contentHeight - display.viewableContentHeight
local midscreenX = screenW*(0.5)
local midscreenY = screenH*(0.5)

local w = screenW/2


local textStyles = funx.loadTextStyles("textstyles.txt", system.ResourceDirectory)

local mytext = funx.loadFile("sampletext.txt")

-- To cache, set the cache directory
local cacheDir = ""
if (true) then
	funx.mkdir ("textrender_cache", "",false, system.CachesDirectory)
	cacheDir = "textrender_cache"
end


w = 200

local params = {
	text = mytext,
	font = "AvenirNext-Regular",
	size = "12",
	lineHeight = "16",
	color = {0, 0, 0, 255},
	width = w,
	alignment = "Left",
	opacity = "100%",
	minCharCount = 5,	-- 	Minimum number of characters per line. Start low.
	targetDeviceScreenSize = screenW..","..screenH,	-- Target screen size, may be different from current screen size
	letterspacing = 0,
	maxHeight = screenH - 50,
	minWordLen = 2,
	textstyles = textStyles,
	defaultStyle = "Normal",
	cacheDir = cacheDir,
}

-- Page background
local bkgd = display.newRect(0,0,screenW, screenH)
bkgd:setFillColor(255,255,255,255)

local t = textwrap.autoWrappedText(params)
t:setReferencePoint(display.TopLeftReferencePoint)
t.x = 50
t.y = 50

-- Frame the text
local textframe = display.newRect(0,0, w, t.height)
textframe:setFillColor(100,100,0,0) -- transparent
textframe:setStrokeColor(0,0,0,255)
textframe.strokeWidth = 1
textframe:setReferencePoint(display.TopLeftReferencePoint)
textframe.x = t.x
textframe.y = t.y

local p = display.newImage("p.png")
p:setReferencePoint(display.TopLeftReferencePoint)
p.x = 650
p.y = 200
