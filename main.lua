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
local textwrap = require("textrender")

-- Make a local copy of the application settings global
local screenW, screenH = display.contentWidth, display.contentHeight
local viewableScreenW, viewableScreenH = display.viewableContentWidth, display.viewableContentHeight
local screenOffsetW, screenOffsetH = display.contentWidth -	 display.viewableContentWidth, display.contentHeight - display.viewableContentHeight
local midscreenX = screenW*(0.5)
local midscreenY = screenH*(0.5)

local w = screenW/2 - 50
--w = 270

local textStyles = funx.loadTextStyles("textstyles.txt", system.ResourceDirectory)

local mytext = funx.readFile("sampletext.txt")

-- To cache, set the cache directory
local cacheDir = "textrender_cache"
funx.mkdir (cacheDir, "",false, system.CachesDirectory)




------------------------------------------------------------
------------------------------------------------------------

local reps = 1

------------------------------------------------------------
------------------------------------------------------------


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
	cacheDir = "",
	cacheToDB = true,
	isHTML = true,
	useHTMLSpacing = true,
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




local tmsg = ""




-- Page background
local bkgd = display.newRect(0,0,screenW, screenH)
bkgd:setFillColor(255,255,255,255)
bkgd:setReferencePoint(display.TopLeftReferencePoint)
bkgd.x = 0
bkgd.y = 0
bkgd.strokeWidth = 20
bkgd:setStrokeColor(0,200,200)

local t, t2, textframe, textframe2
local gobutton

local function go()

	gobutton.isVisible = false

	------------
	-- We clear the cache before begining, so first render creates a cache, second uses it.
	textwrap.clearAllCaches(cacheDir)

	if t then 
		t:removeSelf()
		t = nil
	end

	if t2 then 
		t2:removeSelf()
		t2 = nil
	end

	if textframe then 
		textframe:removeSelf()
		textframe = nil
	end

	if textframe2 then 
		textframe2:removeSelf()
		textframe2 = nil
	end


	if (reps > 10) then 
		params.cacheDir = ""
		params.cacheToDB = false
		params.text = mytext
		
		-- RENDER WITHOUT CACHING
		local tdiffNoCache = drawAndDelete(params,reps)

		params.cacheDir = ""
		params.cacheToDB = true
		params.text = mytext
		
		-- RENDER USING THE CACHE
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



	-- PRINT THE RESULTS
	
	params.text = mytext .. tmsg
	params.cacheDir = nil
	params.cacheToDB = true

	t = textwrap.autoWrappedText(params)
	t.x = 20
	t.y = 100 + t.yAdjustment

	params.testing = false

	params.cacheDir = ""
	params.cacheToDB = true
	t2 = textwrap.autoWrappedText(params)
	t2.x = w + 50
	t2.y = 100 + t.yAdjustment


	local yAdjustment = t.yAdjustment
	
	-- Labels
	local label1 = display.newText("This Text is from XML", 0, 0, nil, 18)
	label1:setReferencePoint(display.BottomLeftReferencePoint)
	label1.x = 20
	label1.y = 90
	label1:setFillColor(100,100,0) -- transparent
	
	local label2 = display.newText("This Text is from the Cache", 0, 0, nil, 18)
	label2:setReferencePoint(display.BottomLeftReferencePoint)
	label2.x = t2.x
	label2.y = 90
	label2:setFillColor(100,100,0) -- transparent
	
	-- Frame the text
	textframe = display.newRect(0,0, w+2, t.height + 2)
	textframe:setFillColor(100,100,0,20) -- transparent
	textframe:setStrokeColor(0,0,0,255)
	textframe.strokeWidth = 1
	textframe:setReferencePoint(display.TopLeftReferencePoint)
	textframe.x = 20
	textframe.y = 100
	textframe:toBack()


	-- Frame the text
	textframe2 = display.newRect(0,0, w+2, t.height + 2)
	textframe2:setFillColor(100,100,0,20) -- transparent
	textframe2:setStrokeColor(0,0,0,255)
	textframe2.strokeWidth = 1
	textframe2:setReferencePoint(display.TopLeftReferencePoint)
	textframe2.x = t2.x
	textframe2.y = 100
	textframe2:toBack()
	
	bkgd:toBack()
	
	gobutton.isVisible = true

end




if textwrap.db and textwrap.db:isopen() then
	textwrap.db:close()
	print ("MAIN TESTING: Close DB. The textwrap database was left open?")
end



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


gobutton = widget.newButton{
			label = "GO",
			labelColor = { default={ 200, 1, 1 }, over={ 250, 0, 0, 0.5 } },
			fontSize = 20,
			x =screenW - 200,
			y=50,
			onRelease = go,
		}
gobutton:toFront()

-- Run if we're not testing reps
if (reps == 1) then
	go()
end
