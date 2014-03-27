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

-- Patches to allow Graphics 1.0 calls while using Graphics 2.0
require( 'scripts.dmc.dmc_kompatible' )
--require( 'scripts.dmc.dmc_kolor' )
--require ( 'scripts.patches.refPointConversions' )

-- Default anchor settings
--display.setDefault( "anchorX", 0 )
--display.setDefault( "anchorY", 0 )


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
w = 270

local textStyles = funx.loadTextStyles("textstyles.txt", system.ResourceDirectory)

local mytext = funx.loadFile("sampletext.txt")

-- To cache, set the cache directory
local cacheDir = ""
if (true) then
	funx.mkdir ("textrender_cache", "",false, system.CachesDirectory)
	cacheDir = "textrender_cache"
end

-- To prevent caching, set the cache dir to empty
--cacheDir = ""

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
	isHTML = true,
}

------------
-- Speed tests, cache vs. no cache

local function drawAndDelete(params, reps)
	local startTime = system.getTimer()
	reps = reps or 10
	for i = 1, reps do
		--print ("Render text #" .. i)
		local t = textwrap.autoWrappedText(params)
		t:setReferencePoint(display.TopLeftReferencePoint)
		t.x = 50
		t.y = 50
		t:removeSelf()
		t = nil
	end
	local tdiff = system.getTimer() - startTime
	return tdiff
end





local reps = 1
local tmsg = ""

if (reps > 10) then 
	params.cacheDir = ""
	local tdiffNoCache = drawAndDelete(params,reps)

	params.cacheDir = cacheDir
	local tdiffCached = drawAndDelete(params, reps)

	------------

	tmsg = "RENDERING TIME\n"
	tmsg = tmsg .. "<br>"
	tmsg = tmsg .. "<br>"
	tmsg = tmsg .. "<br>"
	tmsg = tmsg .. "<p>"
	tmsg = tmsg .. "NO CACHE: ("..reps.. " times) Time elapsed = " .. math.floor(tdiffNoCache) .. " microseconds (".. tdiffNoCache/1000 .." seconds) (average = " .. (math.floor(tdiffNoCache)/reps) .. " microseconds)"
	tmsg = tmsg .. "</p>"
	tmsg = tmsg .. "<p>"
	tmsg = tmsg .. "\nCACHED: ("..reps.. " times) Time elapsed = " .. math.floor(tdiffCached) .. " microseconds (".. tdiffCached/1000 .." seconds) (average = " .. (math.floor(tdiffCached)/reps) .. " microseconds)"
	tmsg = tmsg .. "</p>"
	--params.text = tmsg
	--local tout = textwrap.autoWrappedText(tmsg)
	--tout:setReferencePoint(display.TopLeftReferencePoint)
	--tout.x = 200
	--tout.y = 100


end


------------
-- We clear the cache before begining, so first render creates a cache, second uses it.
textwrap.clearAllCaches(cacheDir)

params.text = mytext .. tmsg
params.cacheDir = cacheDir

local t = textwrap.autoWrappedText(params)
t.x = 20
t.y = 100 + t.yAdjustment

params.testing = false

params.cacheDir = cacheDir
local t2 = textwrap.autoWrappedText(params)
t2.x = w + 50
t2.y = 100 + t.yAdjustment


yAdjustment = t.yAdjustment

-- Frame the text
local textframe = display.newRect(0,0, w+2, t.height + 2)
textframe:setFillColor(100,100,0,20) -- transparent
textframe:setStrokeColor(0,0,0,255)
textframe.strokeWidth = 1
textframe:setReferencePoint(display.TopLeftReferencePoint)
textframe.x = 20
textframe.y = 100
textframe:toBack()


-- Frame the text
local textframe = display.newRect(0,0, w+2, t.height + 2)
textframe:setFillColor(100,100,0,20) -- transparent
textframe:setStrokeColor(0,0,0,255)
textframe.strokeWidth = 1
textframe:setReferencePoint(display.TopLeftReferencePoint)
textframe.x = t2.x
textframe.y = 100
textframe:toBack()


-- Page background
local bkgd = display.newRect(0,0,screenW, screenH)
bkgd:setFillColor(255,255,255,255)
bkgd:setReferencePoint(display.TopLeftReferencePoint)
bkgd.x = 0
bkgd.y = 0
bkgd:toBack()



	local widget = require ( "widget" )
	local wf = false
	local function toggleWireframe()
		wf = not wf
		display.setDrawMode( "wireframe", wf )
		if (not wf) then
			display.setDrawMode( "forceRender" )
		end
		print ("WF = ",wf)
	end

	local wfb = widget.newButton{
				label = "WIREFRAME",
				labelColor = { default={ 200, 1, 1 }, over={ 250, 0, 0, 0.5 } },
				fontSize = 20,
				x =screenW - 100,
				y=50,
				onRelease = toggleWireframe,
			}
	wfb:toFront()

