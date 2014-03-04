-- textwrap.lua
--
-- Version 2.1
--
-- Copyright (C) 2013 David I. Gross. All Rights Reserved.
--
-- This software is is protected by the author's copyright, and may not be used, copied,
-- modified, merged, published, distributed, sublicensed, and/or sold, without
-- written permission of the author.
--
-- The above copyright notice and this permission notice shall be included in all copies
-- or substantial portions of the Software.
--
-- THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED,
-- INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR
-- PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE
-- FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR
-- OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER
-- DEALINGS IN THE SOFTWARE.
--
--[[

	Create a block text, wrapped to fit a rectangular boundary.
	Formats text using basic HTML.
	@return 	textblock	A display group containing the wrapped text.



	Pass params in a table, e.g. options = { ... }
	Inside of the options table:
	@param	hyperlinkFillColor	An RGBa string, e.g. "150,200,120,50", of the color for hyperlinks.


]]


-- TESTING
local testing = false


-- Main var for this module
local T = {}


local funx = require ("funx")
local html = require ("html")
local entities = require ("entities")

-- functions
local max = math.max
local lower = string.lower
local gmatch = string.gmatch
local gsub = string.gsub
local strlen = string.len
local substring = string.sub
local find = string.find
local floor = math.floor
local gfind = string.gfind


-- Useful constants
local OPAQUE = 255
local TRANSPARENT = 0

-- Be sure a caches dir is set up inside the system caches
local textWrapCacheDir = "textwrap"
--funx.mkdir (textWrapCacheDir, "",false, system.CachesDirectory)


-- testing function
local function showTestLine(group, y, isFirstTextInBlock, i)
	local q = display.newLine(group, 0,y,200,y)
	i = i or 1
	if (isFirstTextInBlock) then
		q:setColor(250,0,0)
	else
		q:setColor(80 * i,80 * i, 80)
	end
	q.strokeWidth = 2
end



-- Use "." at the beginning of a line to add spaces before it.
local usePeriodsForLineBeginnings = false

-------------------------------------------------
-- font metrics module, for knowing text heights and baselines
-- variations, for knowing the names of font variations, e.g. italic
-- Corona doesn't do this so we must.
-------------------------------------------------
local fontMetricsLib = require("fontmetrics")
local fontMetrics = fontMetricsLib.new()
local fontFaces = fontMetrics.metrics.variations or {}


-------------------------------------------------
-- HTML/XML tags that are inline tags, e.g. <b>
-- This table can be used to check if a tag is an inline tag:
-- if (inline[tag]) then...
-------------------------------------------------
--[[
local inline = {
	a = true,
	abbr = true,
	acronym = true,
	applet = true,
	b = true,
	basefont = true,
	bdo = true,
	big = true,
	br = true,
	button = true,
	cite = true,
	code = true,
	dfn = true,
	em = true,
	font = true,
	i = true,
	iframe = true,
	img = true,
	input = true,
	kbd = true,
	label = true,
	map = true,
	object = true,
	q = true,
	s = true,
	samp = true,
	select = true,
	small = true,
	span = true,
	strike = true,
	strong = true,
	sub = true,
	sup = true,
	textarea = true,
	tt = true,
	u = true,
	var = true,
}
--]]

--------------------------------------------------------
-- Common functions redefined for speed
--------------------------------------------------------

--------------------------------------------------------
-- Convert pt values to pixels, for font sizing.
-- Basically, I think we should just use the pt sizing as
-- px sizing. Or, we could use the screen pixel sizing?
-- We could use funx.getDeviceMetrics()
-- Using 72 pixels per point:
-- 12pt => 72/72  * 12pt => 12px
-- 12pt => 132/72 * 12pt => 24px
--------------------------------------------------------
local function convertValuesToPixels (t, deviceMetrics)
	t = funx.trim(t)
	local _, _, n = find(t, "^(%d+)")
	local _, _, u = find(t, "(%a%a)$")

	if (u == "pt" and deviceMetrics) then
		n = n * (deviceMetrics.ppi/72)
	end
	return tonumber(n)
end


--------------------------------------------------------
-- Get tag formatting values
--------------------------------------------------------
local function getTagFormatting(fontFaces, tag, currentfont, variation, attr)
	local font, basename
			------------
			-- If the fontfaces list has our font transformation, use it,
			-- otherwise try to figure it out.
			------------
			local function getFontFace (basefont, variation)
				local newFont = ""

				if (fontFaces[basefont .. variation]) then
					newFont = fontFaces[basefont .. variation]
				else
					-- Some name transformations...
					-- -Roman becomes -Italic or -Bold or -BoldItalic
					newFont = basefont:gsub("-Roman","") .. variation
				end
				return newFont
			end
			------------

	if (type(currentfont) ~= "string") then
		return {}
	end

	local basefont = gsub(currentfont, "%-.*$","")
	--local _,_,variation = find(currentfont, "%-(.-)$")
	variation = variation or ""

	local format = {}

	if (tag == "em" or tag == "i") then
		if (variation == "Bold" or variation == "BoldItalic") then
			format.font = getFontFace (basefont, "-BoldItalic")
			format.fontvariation = "BoldItalic"
		else
			format.font = getFontFace (basefont, "-Italic")
			format.fontvariation = "Italic"
		end
	elseif (tag == "strong" or tag == "b") then
		if (variation == "Italic" or variation == "BoldItalic") then
			format.font = getFontFace (basefont, "-BoldItalic")
			format.fontvariation = "BoldItalic"
		else
			format.font = getFontFace (basefont, "-Bold")
			format.fontvariation = "Bold"
		end
	elseif (tag == "font" and attr) then
		format = attr
		format.font = attr.name
		--format.basename = attr.name
	elseif (attr) then
		-- get style info
		local style = {}
		local p = funx.split(attr.style, ";", true) or {}
		for i,j in pairs( p ) do
			local c = funx.split(j,":",true)
			if (c[1] and c[2]) then
				style[c[1]] = c[2]
			end
		end
		format = funx.tableMerge(attr, style)
		--format.basename = attr.font
	end

	return format

end



--------------------------------------------------------
-- Break text into paragraphs using <p>
-- Any carriage returns inside any element is remove!
local function breakTextIntoParagraphs(text)

	-- remove CR inside of <p>
	local count = 1
	while (count > 0) do
		text, count = text:gsub("(%<.-)%s*[\r\n]%s*(.-<%/.->)","%1 %2")
	end

	text = text:gsub("%<p(.-)%>","<p%1>\r")
	text = text:gsub("%<%/p%>","</p>\r")
	return text

end


--------------------------------------------------------
-- Convert <h> tags into  paragraph tags but set the style to the header, e.g. h1
-- Hopefully, the style will exist!
-- @param tag, attr
-- @return tag, attr
local function convertHeaders(tag, attr)
	if ( tag and find(tag, "[hH]%d") ) then
		attr.class = lower(tag)
		tag = "p"
	end

	return tag, attr
end


--------------------------------------------------------
-- CACHE of textwrap!!!
--------------------------------------------------------
local function saveTextWrapToCache(id, cache, cacheDir)
	if (cacheDir and cacheDir ~= "") then
		funx.mkdirTree (cacheDir .. "/" .. textWrapCacheDir, system.CachesDirectory)
		--funx.mkdir (cacheDir .. "/" .. textWrapCacheDir, "",false, system.CachesDirectory)
		-- Developing: delete the cache
		if (true) then
			local fn =  cacheDir .. "/" .. textWrapCacheDir .. "/" ..  id .. ".json"
			funx.saveTable(cache, fn , system.CachesDirectory)
		end
	end
end

--------------------------------------------------------
local function loadTextWrapFromCache(id, cacheDir)
	if (cacheDir) then
		local fn = cacheDir .. "/" .. textWrapCacheDir .. "/" ..  id .. ".json"

		local p = {}
		if (funx.fileExists(fn, system.CachesDirectory)) then
			p = funx.loadTable(fn, system.CachesDirectory)
--print ("cacheTemplatizedPage: found page "..fn )
			return p
		end
	end
	return false
end


--------------------------------------------------------
local function iteratorOverCacheText (t)
	local i = 0
	local n = table.getn(t)
	return function ()
		i = i + 1
		if i <= n then
			return t[i], ""
		end
	end
end

-- Create a cache chunk table from either an existing cache entry or for a chunk of XML for the cache table.
-- A chunk may have multiple lines.
-- Weird to use separate tables for each attribute? But this allows us to iterate over the words
-- instead of over the cache entry, allowing us to use the existing for-do structure.
local function newCacheChunk ( cachedChunk )
	
	cachedChunk = {
						text = {}, 
						item = {},
					}
	
	return cachedChunk
end


-- Get a chunk entry from the cache table
local function getCachedChunkItem(t, i)
	return t.item[i]
end

local function updateCachedChunk (t, args)
	local i = args.index or 1
	-- Write all in one entry
	t.item[i] = args
	-- Write text table for iteration
	t.text[i] = args.text
	return t
end


--------------------------------------------------------
-- Make a box that is the right size for touching.
-- Problem is, the font sizes are so big, they overlap lines.
-- This box will be a nicer size.
-- NOte, there is no stroke, so we don't x+1/y+1
local function touchableBox(g, referencePoint, x,y, width, height, fillColor)

	local touchme = display.newRect(0,0,width, height)
	funx.setFillColorFromString(touchme, fillColor)

	g:insert(touchme)
	touchme:setReferencePoint(referencePoint)
	touchme.x = x
	touchme.y = y
	touchme:toBack()

	return touchme
end


--------------------------------------------------------
-- Add a tap handler to the object and pass it the tag attributes, e.g. href
-- @param obj A display object, probably text
-- @param id String: ID of the object?
-- @param attr table: the attributes of the tag, e.g. href or target, HTML stuff, !!! also the text tapped should be in "text" in attr
-- @param handler table A function to handle link values, like "goToPage". These should work with the button handler in slideView
local function attachLinkToObj(obj, attr, handler)

	local function comboListener( event )
		local object = event.target
		if not ( event.phase ) then
			local attr = event.target._attr
			--print( "Tap event on word!", attr.text)


			if (handler) then
				handler(event)
				--print( "Tap event on word!", attr.text)
				--print ("Tapped on ", attr.text)
			else
				print ("WARNING: textwrap:attachLinkToObj says no handler set for this event.")
			end
		end
		return true
	end

	obj.id = attr.id or (attr.id or "")
	obj._attr = attr
	obj:addEventListener( "tap", comboListener )
	obj:addEventListener( "touch", comboListener )
end

--------------------------------------------------------
-- Wrap text to a width
-- Blank lines are ignored.
-- *** To show a blank line, put a space on it.
-- The minCharCount is the number of chars to assume are in the line, which means
-- fewer calculations to figure out first line's.
-- It starts at 25, about 5 words or so, which is probabaly fine in 99% of the cases.
-- You can raise lower this for very narrow columns.
-- opacity : 0.0-1.0
-- "minWordLen" is the shortest word a line can end with, usually 2, i.e, don't end with single letter words.
-- NOTE: the "floor" is crucial in the y-position of the lines. If they are not integer values, the text blurs!
--
-- Look for CR codes. Since clumsy XML, such as that from inDesign, cannot include line breaks,
-- we have to allow for a special code for line breaks: [[[cr]]]
--------------------------------------------------------

local function autoWrappedText(text, font, size, lineHeight, color, width, alignment, opacity, minCharCount, targetDeviceScreenSize, letterspacing, maxHeight, minWordLen, textstyles, defaultStyle, cacheDir)

	-- Set the width/height of screen. Might have changed from when module loaded due to orientation change
	local screenW, screenH = display.contentWidth, display.contentHeight
	local viewableScreenW, viewableScreenH = display.viewableContentWidth, display.viewableContentHeight
	local screenOffsetW, screenOffsetH = display.contentWidth -  display.viewableContentWidth, display.contentHeight - display.viewableContentHeight
	local midscreenX = screenW*(0.5)
	local midscreenY = screenH*(0.5)

	if (testing) then
		print ("autoWrappedText: testing flag is true.")
		print ("----------")
		--print (text.text)
		--print ("----------")
	end

	-- table for useful settings. We need fewer upvalues, and this is a way to do that
	local settings = {}

	settings.deviceMetrics = funx.getDeviceMetrics( )

	settings.minWordLen = 2

	settings.isHTML = false

	-- handler for links
	settings.handler = {}

	--if text == '' then return false end
	local result = display.newGroup()

	-- Get from the funx textStyles variable.
	local textstyles = textstyles or {}

	local hyperlinkFillColor

	-- If table passed, then extract values
	if (type(text) == "table") then
		font = text.font
		size = text.size
		lineHeight = text.lineHeight
		color = text.color
		width = text.width
		alignment = text.textAlignment
		opacity = text.opacity
		minCharCount = text.minCharCount
		targetDeviceScreenSize = text.targetDeviceScreenSize
		letterspacing = text.letterspacing
		maxHeight = text.maxHeight
		settings.minWordLen = text.minWordLen
		textstyles = text.textstyles or textstyles
		settings.isHTML = text.isHTML or false
		defaultStyle = text.defaultStyle or ""
		cacheDir = text.cacheDir
		settings.handler = text.handler
		hyperlinkFillColor = text.hyperlinkFillColor or "0,0,255,"..TRANSPARENT

		-- restore text
		text = text.text
	end

	-- Caching values
	-- Name the cache with the width, too, so the same text isn't wrapped to the wrong
	-- width based on the cache.
	local textUID = 0
	local textwrapIsCached = false
	local cache = { { text = "", width = "", } }
	local cacheIndex = 1
	
	-- Interpret the width so we can get it right caching:
	width = funx.percentOfScreenWidth(width) or display.contentWidth

	if ( cacheDir and cacheDir ~= "" ) then
		textUID = "cache"..funx.checksum(text).."_"..tostring(width)
		local res = loadTextWrapFromCache(textUID, cacheDir)
		if (res) then
			textwrapIsCached = true
			cache = res
			--print ("***** CACHE LOADED")
		end
	end


	-- default
	settings.minWordLen = settings.minWordLen or 2
	text = text or ""
	if (text == "") then
		return result
	end

	-- alignment is the initial setting for the text block, but sub-elements may differ
	local textAlignment = funx.fixCapsForReferencePoint(alignment) or "Left"

	-- Just in case
	text = tostring(text)

	--[[
	------------------------
	-- HANDLING LINE BREAKS:
	-- This is also a standard XML paragraph separator used by Unicode
	See:   http://www.fileformat.info/info/unicode/char/2028/index.htm

	Unicode introduced separator				<textblock>
					<text>
						Fish are ncie to me.
						I sure like them!
						They're great!
					</text>
				</textblock>


	In an attempt to simplify the several newline characters used in legacy text, UCS introduces its own newline characters to separate either lines or paragraphs: U+2028 line separator (HTML: &#8232; LSEP) and U+2029 paragraph separator (HTML: &#8233; PSEP). These characters are text formatting only, and not <control> characters.


	Unicode Decimal Code &#8233; 
	Symbol Name:	Paragraph Separator
	Html Entity:
	Hex Code:	&#x2029;
	Decimal Code:	&#8233;
	Unicode Group:	General Punctuation

	InDesign also uses &#8221; instead of double-quote marks when exporting quotes in XML. WTF?

	]]


	-- This is &#8221;
	--local doubleRtQuote

	-- Strip InDesign end-of-line values, since we now use a kind of HTML from
	-- InDesign.

	local lineSeparatorCode = "%E2%80%A8"
	local paragraphSeparatorCode = "%E2%80%A9"	-- This is ;&#8233;
	text = text:gsub(funx.unescape(lineSeparatorCode),"")
	text = text:gsub(funx.unescape(paragraphSeparatorCode),"")

	-- Convert entities in the text, .e.g. "&#8211;"
	text = entities.unescape(text)



	--[[
	-- NOT IN USE: THIS IS BEFORE WE PARSED INDESIGN INTO HTML

	-- For text fields, NOT HTML fields, add CR after every line that comes from InDesign.
	-- InDesign uses the above separators, which suck.
	-- Note the spaces after the returns! This prevents the return from being stripped as
	-- simply extra blank space!

	-- We check later WHICH line end we use, and format appropriately
	if (not settings.isHTML) then
		text = text:gsub(funx.unescape(lineSeparatorCode),"\r ")
		text = text:gsub(funx.unescape(paragraphSeparatorCode),"\n ")

	end
	--]]
	--- THEN, TOO, THERE'S MY OWN FLAVOR OF LINE BREAK!
	-- Replace our special line break code with a return!
	text = text:gsub("%[%[%[br%]%]%]","<br>")

	------------------------

	maxHeight = tonumber(maxHeight) or 0


	-- Minimum number of characters per line. Start low.
	--local minLineCharCount = minCharCount or 5

	-- This will cause problems with Android
--	font = font or "Helvetica" --native.systemFont
--	size = tonumber(size) or 12
--	color = color or {0,0,0,0}
--	width = funx.percentOfScreenWidth(width) or display.contentWidth
--	opacity = funx.applyPercent(opacity, OPAQUE) or OPAQUE
--	targetDeviceScreenSize = targetDeviceScreenSize or screenW..","..screenH
	-- case can be ALL_CAPS or NORMAL
	--local case = "NORMAL";
	-- Space before/after paragraph
	--local spaceBefore = 0
	--local spaceAfter = 0
	--local firstLineIndent = 0
	--local currentFirstLineIndent = 0
	--local leftIndent = 0
	--local rightIndent = 0
	--local bullet = "&#9679;"

	-- Combine a bunch of local variables into a settings array because we have too many "upvalues"!!!
	settings.font = font or "Helvetica" --native.systemFont
	 -- used to restore from bold, bold-italic, etc. since some names aren't clear, e.g. FoozleSemiBold might be the only bold for a font
	settings.fontvariation = ""
	settings.size = tonumber(size) or 12
	settings.color = color or {0,0,0,0}
	settings.width = width
	settings.opacity = funx.applyPercent(opacity, OPAQUE) or OPAQUE
	settings.targetDeviceScreenSize = targetDeviceScreenSize or screenW..","..screenH
	settings.case = "NORMAL"
	settings.spaceBefore = 0
	settings.spaceAfter = 0
	settings.firstLineIndent = 0
	settings.currentFirstLineIndent = 0
	settings.leftIndent =0
	settings.rightIndent = 0
	settings.bullet = "&#9679;"
	settings.minLineCharCount = minCharCount or 5
	settings.maxHeight = tonumber(maxHeight) or 0

	------ POSITIONING RECT
	-- Need a positioning rect so that indents work.
	-- Width must be full-width so the right-justified works.
	-- THIS HAS A PROBLEM...IF THE ALIGN IS CENTER BUT THE TEXT LINE REALLY ISN'T CENTER,
	-- THIS WILL FAIL. SO, IF THE "ALIGN" IS SET TO CENTER, FOR SOME LEGACY REASON, BUT THE FIRST
	-- LINE IS OTHERWISE, THIS WILL FAIL. FUCK.
	--local r = display.newRect(0,0,width,10)
	--[[
	local r = display.newRect(0,0,5,5)
	r:setFillColor(255,0,0,OPAQUE)
	result:insert(r)
	result._positionRect = r
	r.strokeWidth=0
	r.anchorX, r.anchorY = 0,0
	r.x = 0
	r.y = 0
	r.isVisible = testing
	--]]


 	lineHeight = funx.applyPercent(lineHeight, settings.size) or floor(settings.size * 1.3)

	-- Scaling for device
	-- Scale the text proportionally
	-- We don't need this if we set use the Corona Dynamic Content Scaling!
	-- Set in the config.lua
	-- Actually, we do, for the width, because that doesn't seem to be shrinking!
	-- WHAT TO DO? WIDTH DOES NOT ADJUST, AND WE DON'T KNOW THE
	-- ACTUAL SCREEN WIDTH. WHAT NOW?

	local scalingRatio = funx.scaleFactorForRetina()

	local currentLine = ''
	local lineCount = 0
	-- x is start of line
	local lineY = 0
	local x = 0

	local defaultSettings = {}

		---------------------------------------------------------------------------
		-- Style setting functions
		---------------------------------------------------------------------------

		-- get all style settings so we can save them in a table
		local function getAllStyleSettings ()
			local params = {}

			params.font = settings.font
			params.fontvariation = settings.fontvariation
			-- font size
			params.size = settings.size
			params.minLineCharCount = settings.minLineCharCount
			params.lineHeight = lineHeight
			params.color = settings.color
			params.width = settings.width
			params.opacity = settings.opacity
			-- case (upper/normal)
			params.case = settings.case
			-- space before paragraph
			params.spaceBefore = settings.spaceBefore or 0
			-- space after paragraph
			params.spaceAfter = settings.spaceAfter or 0
			-- First Line Indent
			params.firstLineIndent =firstLineIndent
			-- Left Indent
			params.leftIndent = settings.leftIndent
			-- Right Indent
			params.rightIndent = settings.rightIndent
			params.textAlignment = textAlignment
			return params
		end


		-- Set style settings which were saved using the function above.
		-- These are set using the values from internal variables, e.g. font or size,
		-- NOT from the style sheet parameters.
		local function setStyleSettings (params)
			if (params.font ) then settings.font = params.font end
			if (params.fontvariation) then settings.fontvariation = params.fontvariation end
				-- font size
			if (params.size ) then settings.size = params.size end
			if (params.minLineCharCount ) then settings.minLineCharCount = params.minLineCharCount end
			if (params.lineHeight ) then lineHeight = params.lineHeight end
			if (params.color ) then settings.color = params.color end
			if (params.width ) then settings.width = params.width end
			if (params.opacity ) then settings.opacity = params.opacity end
				-- case (upper/normal)
			if (params.case ) then settings.case = params.case end
				-- space before paragraph
			if (params.spaceBefore ) then settings.spaceBefore = tonumber(params.spaceBefore) end
				-- space after paragraph
			if (params.spaceAfter ) then settings.spaceAfter = tonumber(params.spaceAfter) end
				-- First Line Indent
			if (params.firstLineIndent ) then params.firstLineIndent = tonumber(firstLineIndent) end
				-- Left Indent
			if (params.leftIndent ) then settings.leftIndent = tonumber(params.leftIndent) end
				-- Right Indent
			if (params.rightIndent ) then settings.rightIndent = tonumber(params.rightIndent) end
			if (params.textAlignment ) then textAlignment = params.textAlignment end
	--[[
			if (lower(textAlignment) == "right") then
				x = settings.width - settings.rightIndent
				settings.currentFirstLineIndent = 0
				settings.firstLineIndent = 0
			elseif (lower(textAlignment) == "left") then
				x = 0
			else
				local currentWidth = settings.width - settings.leftIndent - settings.rightIndent -- settings.firstLineIndent
				x = floor(currentWidth/2) --+ settings.firstLineIndent
			end
	]]
		end



		-- set style from params in a ### set, ... command line in the text
		-- This depends on the closure for variables, such as font, size, etc.
		local function setStyleFromCommandLine (params)
			-- font
			if (params[2] and params[2] ~= "") then settings.font = funx.trim(params[2]) end
			-- font size
			if (params[3] and params[3] ~= "") then
				settings.size = tonumber(params[3])
				--size = scaleToScreenSize(tonumber(params[3]), scalingRatio)
				-- reset min char count in case we loaded a BIG font
				settings.minLineCharCount = minCharCount or 5
			end

			-- line height
			if (params[4] and params[4] ~= "") then
				lineHeight = tonumber(params[4])
				--lineHeight = scaleToScreenSize(tonumber(params[4]), scalingRatio)
			end
			-- color
			if ((params[5] and params[5] ~= "") and (params[6] and params[6] ~= "") and (params[7] and params[7] ~= "")) then
				-- Handle opacity as RGBa or HDRa, not by itself
				if (params[9] and params[9] ~= "") then
					settings.color = {tonumber(params[5]), tonumber(params[6]), tonumber(params[7]), funx.applyPercent(params[9], OPAQUE) }
				else
					settings.color = {tonumber(params[5]), tonumber(params[6]), tonumber(params[7], OPAQUE) }
				end
			end
			-- width of the text block
			if (params[8] and params[8] ~= "") then
				if (params[8] == "reset" or params[8] == "r") then
					settings.width = defaultSettings.width
				else
					settings.width = tonumber(funx.percentOfScreenWidth(params[8]) or defaultSettings.width)
				end
				settings.minLineCharCount = minCharCount or 5
			end
			-- opacity (Now always 100%)
			--if (params[9] and params[9] ~= "") then settings.opacity = funx.applyPercent(params[9], OPAQUE) end
			settings.opacity = 1.0
			-- case (upper/normal)
			if (params[10] and params[10] ~= "") then settings.case = funx.trim(params[10]) end

			-- space before paragraph
			if (params[12] and params[12] ~= "") then settings.spaceBefore = tonumber(params[12]) end
			-- space after paragraph
			if (params[13] and params[13] ~= "") then settings.spaceAfter = tonumber(params[13]) end
			-- First Line Indent
			if (params[14] and params[14] ~= "") then settings.firstLineIndent = tonumber(params[14]) end
			-- Left Indent
			if (params[15] and params[15] ~= "") then settings.leftIndent = tonumber(params[15]) end
			-- Right Indent
			if (params[16] and params[16] ~= "") then settings.rightIndent = tonumber(params[16]) end

			-- alignment (note, set first line indent, etc., first!
			if (params[11] and params[11] ~= "") then
				textAlignment = funx.fixCapsForReferencePoint(params[11])
				-- set the line starting point to match the alignment
				if (lower(textAlignment) == "right") then
					x = settings.width - settings.rightIndent
					settings.currentFirstLineIndent = 0
					settings.firstLineIndent = 0
				elseif (lower(textAlignment) == "center") then
					local currentWidth = settings.width - settings.leftIndent - settings.rightIndent -- settings.firstLineIndent
					x = floor(currentWidth/2) --+ settings.firstLineIndent
				else
					x = 0
				end
			end
		end



		-- set style from the attributes of an XML tag, from the style attribute,
		-- e.g. <p style="font:Helvetica;"/>
		-- This depends on the closure for variables, such as font, size, etc.
		-- fontFaces, font are in the closure!
		local function setStyleFromTag (tag, attr)

			local format = getTagFormatting(fontFaces, tag, settings.font, settings.fontvariation, attr)
			if (not format or format == {}) then
				return 
			end
			-- font
			if (format.font) then
				settings.font = funx.trim(format.font)
				settings.fontvariation = format.fontvariation
			end
			-- font with CSS:
			if (format['font-family']) then
				settings.font = funx.trim(format['font-family'])
				settings.fontvariation = format.fontvariation
			end

			-- font size
			if (format['font-size'] or format['size']) then
				if (format['font-size']) then
					-- convert pt values to px
					settings.size = convertValuesToPixels(format['font-size'], settings.deviceMetrics)
				else
					settings.size = convertValuesToPixels(format['size'], settings.deviceMetrics)
				end

				--size = scaleToScreenSize(tonumber(params[3]), scalingRatio)
				-- reset min char count in case we loaded a BIG font
				settings.minLineCharCount = minCharCount or 5
			end

			-- lineHeight (HTML property)
			if (format.lineHeight) then
				lineHeight = convertValuesToPixels (format.lineHeight, settings.deviceMetrics)
			end


			-- lineHeight (CSS property)
			if (format['line-height']) then
				lineHeight = convertValuesToPixels (format['line-height'], settings.deviceMetrics)
			end

			-- color
			-- We're using decimal, e.g. 12,24,55 not hex (#ffeeff)
			if (format.color) then
				local _, _, c = find(format.color, "%((.*)%)")
				local s = funx.stringToColorTable(c)
				if (s) then
					settings.color = { s[1], s[2], s[3], s[4] }
				end
			end

			-- width of the text block
			if (format.width) then
				if (format.width == "reset" or format.width == "r") then
					settings.width = defaultSettings.width
				else
					-- Remove "px" from the width value if it is there.
					format.width = format.width:gsub("px$","")
					settings.width = tonumber(funx.percentOfScreenWidth(format.width) or defaultSettings.width)
				end
				settings.minLineCharCount = minCharCount or 5
			end

			-- opacity
			-- Now built into the color, e.g. RGBa color
			--if (format.opacity) then settings.opacity = funx.applyPercent(format.opacity, OPAQUE) end

			-- case (upper/normal) using legacy coding ("case")
			if (format.case) then
				settings.case = lower(funx.trim(format.case))
				if (case == "none") then
					settings.case = "normal"
				end
			end

			-- case, using CSS, e.g. "text-transform:uppercase"
			if (format['text-transform']) then settings.case = funx.trim(format.case) end

			-- space before paragraph
			if (format['margin-top']) then settings.spaceBefore = convertValuesToPixels(format['margin-top'], settings.deviceMetrics) end

			-- space after paragraph
			if (format['margin-bottom']) then settings.spaceAfter = convertValuesToPixels(format['margin-bottom'], settings.deviceMetrics) end

			-- First Line Indent
			if (format['text-indent']) then settings.firstLineIndent = convertValuesToPixels(format['text-indent'], settings.deviceMetrics) end

			-- Left Indent
			if (format['margin-left']) then settings.leftIndent = convertValuesToPixels(format['margin-left'], settings.deviceMetrics) end

			-- Right Indent
			if (format['margin-right']) then settings.rightIndent = convertValuesToPixels(format['margin-right'], settings.deviceMetrics) end

			-- alignment (note, set first line indent, etc., first!
			if (format['text-align']) then
				textAlignment = funx.fixCapsForReferencePoint(format['text-align'])
				-- set the line starting point to match the alignment
				if (lower(textAlignment) == "right") then
					x = settings.width - settings.rightIndent
					settings.currentFirstLineIndent = 0
					settings.firstLineIndent = 0
				elseif (lower(textAlignment) == "center") then
					-- Center
					local currentWidth = settings.width - settings.leftIndent - settings.rightIndent -- settings.firstLineIndent
					x = floor(currentWidth/2) --+ settings.firstLineIndent
				else
					x = 0
				end

			end

			-- list bullet
			if (format['bullet']) then
				settings.bullet = format['bullet'] or "&#9679;"
			end
		end



		---------------------------------------------------------------------------

	-- Load default style if it exists
	if (defaultStyle ~= "") then
		local params = textstyles[defaultStyle]
		if (params) then
			setStyleFromCommandLine (params)
		end
	end

	local defaultSettings = {
		font = settings.font,
		size = settings.size,
		lineHeight = lineHeight,
		color = settings.color,
		width = settings.width,
		opacity = settings.opacity,
	}



	-- Typesetting corrections
	-- InDesign uses tighter typesetting, so we'll try to correct a little
	-- with some fudge-factors.
	local widthCorrection = 1
	if (true) then
		widthCorrection = 1.01--0.999
	end


	-- This is ;&#8232;
	--local lineSeparatorCode = "%E2%80%A8"
	-- This is ;&#8233;
	--local paragraphSeparatorCode = "%E2%80%A9"
	-- Get lines with ending command, e.g. CR or LF
	--	for line in gmatch(text, "[^\n]+") do
	local linebreak = funx.unescape(lineSeparatorCode)
	local paragraphbreak = funx.unescape(paragraphSeparatorCode)
	local oneLinePattern = "[^\n^\r]+"
	local oneLinePattern = ".-[\n\r]"

	-- NO: In fact, we should make HTML into one big block
	-- Split the text into paragraphs using <p>
	--text = breakTextIntoParagraphs(text)
	local t1 = text
	if (settings.isHTML) then
		--print ("Autowrap: line 500 : text is HTML!")
		text = funx.trim(text:gsub("[\n\r]",""))
	end

	-- Be sure the text block ends with a return, so the line chopper below finds the last line!
	if (substring(text,1,-1) ~= "\n") then
		text = text .. "\n"
	end

	local lineBreakType,prevLineBreakType,prevFont,prevSize

	-- Set the initial left side to 0
	-- (FYI, the var is defined far above here!)
	x = 0
	local isFirstTextInBlock = true
	local isFirstLine = true


	-- And adjustment to better position the text.
	-- Corona positions type incorrectly, at the descender line, not the baseline.
	local yAdjustment = 0

	-- The output x,y for any given chunk of text
	local cursorX, cursorY = 0,0

	-- Repeat for each block of text (ending with a carriage return)
	-- Usually, this will be a paragraph
	-- Text from InDesign should be one large block,
	-- which is right since it is escaped HTML.
	for line in gmatch(text, oneLinePattern) do
		local command, commandline
		local currentSpaceAfter, currentSpaceBefore

		local lineEnd = substring(line,-1,-1)
		local q = funx.escape(lineEnd)

		-- CR means end of paragraph, LF = soft-return
		prevLineBreakType = lineBreakType or "hard"
		if (lineEnd == "\r") then
			lineBreakType = "soft"
		else
			lineBreakType = "hard"
		end

		line = funx.trim(line)

		-----------------------------------------
		-- COMMAND LINES:
		-- command line: reset, set, textalign
		-- set is followed by: font, size, red,green,blue, width, opacity
		-- Command line?
		if (currentLine == "" and substring(line,1,3) == "###") then
			currentLine = ''
			commandline = substring(line,4,-1)	-- get end of line
			local params = funx.split(commandline, ",", true)
			command = funx.trim(params[1])
			if (command == "reset") then
				settings.font = defaultSettings.font
				settings.size = defaultSettings.size
				lineHeight = defaultSettings.lineHeight
				settings.color = defaultSettings.color
				settings.width = defaultSettings.width
				settings.opacity = defaultSettings.opacity
				textAlignment = "Left"
				x = 0
				settings.currentFirstLineIndent = settings.firstLineIndent
				settings.leftIndent = 0
				settings.rightIndent = 0
				settings.bullet = "&#9679;"
			elseif (command == "style") then
				local styleName = params[2] or "MISSING"
				if (textstyles and textstyles[styleName] ) then
					params = textstyles[styleName]
					setStyleFromCommandLine (params)
				else
					print ("WARNING: funx.autoWrappedText tried to use a missing text style ("..styleName..")")
				end
			elseif (command == "set") then
				setStyleFromCommandLine (params)
			elseif (command == "textalign") then
				-- alignment
				if (params[2] and params[2] ~= "") then
					textAlignment = funx.fixCapsForReferencePoint(params[2])
					-- set the line starting point to match the alignment
					if (lower(textAlignment) == "right") then
						x = settings.width - settings.rightIndent
						settings.currentFirstLineIndent = 0
						settings.firstLineIndent = 0
					elseif  (lower(textAlignment) == "center") then
						local currentWidth = settings.width - settings.leftIndent - settings.rightIndent -- settings.currentFirstLineIndent
						x = floor(currentWidth/2) --+ settings.currentFirstLineIndent
					else
						x = 0
					end
				end



			elseif (command == "blank") then
				local lh
				if (params[2]) then
					--lh = scaleToScreenSize(tonumber(params[2]), scalingRatio, true)
					lh = tonumber(params[2])
				else
					lh = lineHeight
				end
				lineCount = lineCount + 1
				lineY = lineY + lh

			elseif (command == "setline") then
				-- set the x of the line
				if (params[2]) then
					x = tonumber(params[2])
				end
				-- set the y of the line
				if (params[3]) then
				    lineY = tonumber(params[3])
				end
				-- set the y based on the line count, i.e. the line to write to
				if (params[4]) then
					lineCount = tonumber(params[4])
					lineY = floor(lineHeight * (lineCount - 1))
				end



			end
		else
			local restOLine = substring(line, strlen(currentLine)+1)


			------------------------------------------------------------
			------------------------------------------------------------
			-- Render parsed XML block
			-- stick this here cuz it needs the closure variables
			---------
			local function renderXML (xmlChunk)

				local result = display.newGroup()
				--result.anchorChildren = true

if (not settings.width) then print ("textwrap: line 844: Damn, the width is wacked"); end


				settings.width = settings.width or 300
				--[[
				local r = display.newRect(0,0,width,2)
				r:setFillColor(100,250,0)
				result:insert(r)
				r:setReferencePoint(display.TopLeftReferencePoint)
				r.x = 0
				r.y = 0
				r.isVisible = testing
				--]]

				-- Set text alignment
				local textDisplayReferencePoint
				if (textAlignment and textAlignment ~= "") then
					textAlignment = funx.fixCapsForReferencePoint(textAlignment)
				else
					textAlignment = "Left"
				end
				textDisplayReferencePoint = display["Bottom"..textAlignment.."ReferencePoint"]

				local shortword = ""
				local restOLineLen = strlen(restOLine)

				-- Set paragraph wide stuff, indents and spacing
				settings.currentFirstLineIndent = settings.firstLineIndent
				currentSpaceBefore = settings.spaceBefore
				currentSpaceAfter = settings.spaceAfter

				if (lineBreakType == "hard") then
					settings.currentFirstLineIndent = settings.firstLineIndent
					currentSpaceBefore = settings.spaceBefore
					currentSpaceAfter = settings.spaceAfter
					isFirstLine = true
				end

				if (lineBreakType == "soft") then
					currentSpaceBefore = settings.spaceBefore
					currentSpaceAfter = 0
				end

				-- If previous paragraph had a soft return, don't add space before, nor indent the 1st line
				if (prevLineBreakType == "soft") then
					settings.currentFirstLineIndent = 0
					currentSpaceAfter = 0
					currentSpaceBefore = 0
				end

				-- ALIGN TOP OF TEXT FRAME TO CAP HEIGHT!!!
				-- If this is the first line in the block of text, DON'T apply the space before settings
				-- Tell the function which called this to raise the entire block to the cap-height
				-- of the first line.

				local fontInfo = fontMetrics.getMetrics(settings.font)
				local currentLineHeight = lineHeight
				local baselineAdjustment = 0

				-- Get the iOS bounding box size for this particular font!!!
				-- This must be done for each size and font, since it changes unpredictably
				local samplefont = display.newText("X", 0, 0, settings.font, settings.size)
				local boxHeight = samplefont.height
				samplefont:removeSelf()
				samplefont = nil

				-- boxHeight used size, so it is correct here.
				local baseline = boxHeight + (settings.size * fontInfo.descent)

				-- change case
				if (case) then
					settings.case = lower(case)
					if (case == "all_caps" or settings.case == "uppercase") then
						restOLine = string.upper(restOLine)
					end
				end

				-- If something is too high, it is turned into a scrolling text block, so this
				-- doesn't apply:
					-- Don't bother to render longer than the screen!
					--if (lineY > (2*screenH) ) then
						--print ("WARNING: (textwrap.lua) : tried to render text more than 2x higher than screen.")
						--[[
						--print ("Here is a sample : ", substring(line, 50) )

						result:setReferencePoint(display.CenterReferencePoint)
						result.yAdjustment = yAdjustment
						return result
						--]]
					--end


				-- Width of the text column (not including indents which are paragraph based)
				local currentWidth = settings.width
				--local currentWidth = width - settings.leftIndent - settings.rightIndent - settings.currentFirstLineIndent

				-- Get min characters to start with
				-- We now know the max char width in a font,
				-- so we can start with a minimum based on that.
				-- IF the metric was set!
				if (fontInfo.maxHorizontalAdvance) then
					settings.minLineCharCount = floor((currentWidth * widthCorrection) / (settings.size * fontInfo.maxCharWidth) )
				end



				-- Remember the font we start with to handle bold/italic changes
				local basefont = settings.font

				-- Offset from left or right of the current chunk of text
				-- As we add chunks to previous chunks of text (building a line)
				-- we need to know where the next chunk goes.
				local currentXOffset = 0

				local prevTextInLine = ""


				local prevFont = settings.font
				local prevSize = settings.size


				------------------------------------------------------------
				-- Parse the line of text (ending with CR) into a table, if it is XML
				-- or leave it as text if it is not.
				local parsedText = html.parsestr(xmlChunk)

				-- Start rendering this text at the margin
				local renderTextFromMargin = true

				-- Track which element we are rendering. Only the first element starts at the margin,
				-- all following elements continue on the lines and are wrapped, unless
				-- there is a line break.
				local elementCounter = 1

				-- First <p> tag means start a paragraph
				local pOpen = true


				------------------------------------------------------------
				-- RENDERING
				-- Now broken up into functions so we can recurse.
				-- This function will render
				------------------------------------------------------------
				local function renderParsedText(parsedText, tag, attr, parseDepth, stacks)

					local result = display.newGroup()

					parseDepth = parseDepth or 0
					parseDepth = parseDepth + 1

					-- Init stacks
					stacks = stacks or { list = { ptr = 1 } }

					------------------------------------------------
					-- Get the ascent of a font, which is how we position text.
					-- Set InDesign to position from the box top using leading
					------------------------------------------------
					local function getFontAscent(font, size)
						local fontInfo = fontMetrics.getMetrics(font)

						-- Get the iOS bounding box size for this particular font!!!
						-- This must be done for each size and font, since it changes unpredictably
						local samplefont = display.newText("X", 0, 0, font, size)
						local boxHeight = samplefont.height
						samplefont:removeSelf()
						samplefont = nil

						-- Set the new baseline from the font metrics
						local baseline = boxHeight + (size * fontInfo.descent)
						--local yAdjustment = (settings.size * fontInfo.capheight) - baseline
						local ascent = fontInfo.ascent * size
						local baselineAdjustment = floor((size * fontInfo.capheight) - baseline)
						return 0
					end




					------------------------------------------------------------
					-- Function to render one parsed XML element, i.e a block of text
					-- An element would be, for example: <b>piece of text</b>
					-- NOT a <p>, but perhaps something inside <p></p>
					------------------------------------------------------------
					local function renderParsedElement(elementNum, element, tag, attr)


							local tempLineWidth, words
							local firstWord = true
							local words
							local nextChunk, nextChunkLen
							local cachedChunk
							local cachedChunkIndex = 1
							local currentWidth
							local tempDisplayLineTxt
							local result, resultPosRect
							local tempLine, allTextInLine
							local xOffset = 0
							local wordlen = 0


							-- ----------------------------------------------------------
							-- <A> tag box. If we make the text itself touchable, it is easy to miss it...your touch
							-- goes through the white spaces around letter strokes!
							local function createLinkingBox(newDisplayLineGroup, newDisplayLineText, textDisplayReferencePoint, alttext, testBkgdColor )

								testBkgdColor = testBkgdColor or {250,250,100,30}

								-- when drawing the box, we compensate for the stroke, thus -2
								local r = display.newRect(0, 0, newDisplayLineText.width-2, newDisplayLineText.height-2)
								r.strokeWidth=1
								newDisplayLineGroup:insert(r)
								r:setReferencePoint(textDisplayReferencePoint)
								r.x = newDisplayLineText.x+1
								r.y = newDisplayLineText.y+1

								r:setFillColor(unpack(testBkgdColor))
								r:setStrokeColor(0,250,250,125)

								r.isVisible = testing

								if (tag == "a") then
									local touchme = touchableBox(result, textDisplayReferencePoint, newDisplayLineGroup.x, newDisplayLineGroup.y - (fontInfo.capheight * settings.size)/4,  newDisplayLineText.width-2, fontInfo.capheight * settings.size, hyperlinkFillColor)

									attr.text = alttext
									attachLinkToObj(newDisplayLineGroup, attr, settings.handler)
								end
							end


							-- Trim the text for the line depending on alignment
							-- Note, for right-to-left languages, you'd have to change the trimming.
							local function trimByAlignment(t)
								local ta = lower(textAlignment)

								if (ta == "center") then
									t = funx.trim(t)
								elseif (ta == "right") then
									t = funx.rtrim(t)
								else
									--t = funx.rtrim(t)
								end
								return t
							end



							-- Align the text on the row
							local function positionNewDisplayLineX(newDisplayLineGroup, w, currentWidth)
								local ta = lower(textAlignment)

								if (ta == "center") then
									newDisplayLineGroup.x = x + settings.currentLeftIndent + xOffset + currentWidth/2
								elseif (ta == "right") then
									newDisplayLineGroup.x = currentWidth + x + settings.currentLeftIndent + settings.currentFirstLineIndent + xOffset
								else
									newDisplayLineGroup.x = x + settings.currentLeftIndent + settings.currentFirstLineIndent + xOffset
								end

							end

							-- Align the text on the row
							local function setCurrentXOffset(newDisplayLineText)
								local ta = lower(textAlignment)

								if (ta == "center") then
									currentXOffset = newDisplayLineText.x
								elseif (ta == "right") then
									currentXOffset = currentXOffset + newDisplayLineText.width
								else
									currentXOffset = currentXOffset + settings.currentLeftIndent + settings.currentFirstLineIndent + newDisplayLineText.width
								end
							end





							-- flag to indicate the text line to be rendered is the last line of the previously
							-- rendered text (true) or is the continuation of that text (false)
							-- Starts true for first item, then is false unless changed later.
							if (elementCounter == 1) then
								--renderTextFromMargin = true
							end

							nextChunk = element or ""
							nextChunkLen = strlen(nextChunk)

							-- Apply the tag, e.g. bold or italic
							if (tag) then
								setStyleFromTag (tag, attr)
							end


							-- Set the current width of the column, factoring in indents
							-- IS THIS RIGHT?!?!?!?
							currentWidth = settings.width - settings.leftIndent - settings.rightIndent - settings.currentFirstLineIndent


							------------------------------------------------
							-- Refigure font metrics if font has changed
							------------------------------------------------
							if (settings.font ~= prevFont or settings.size ~= prevSize) then
								-- ALIGN TOP OF TEXT FRAME TO CAP HEIGHT!!!
								-- If this is the first line in the block of text, DON'T apply the space before settings
								-- Tell the function which called this to raise the entire block to the cap-height
								-- of the first line.
								fontInfo = fontMetrics.getMetrics(settings.font)

								-- Get the iOS bounding box size for this particular font!!!
								-- This must be done for each size and font, since it changes unpredictably
								local samplefont = display.newText("X", 0, 0, settings.font, settings.size)
								local boxHeight = samplefont.height
								samplefont:removeSelf()
								samplefont = nil

								-- Set the new baseline from the font metrics
								baseline = boxHeight + (settings.size * fontInfo.descent)
								prevFont = settings.font
								prevSize = settings.size
							end
							------------------------------------------------

							----------------
							-- IF this is the first line of the text box, figure out the corrections
							-- to position the ENTIRE box properly (yAdjustment).
							-- The current line height is NOT the leading/lineheight as with other lines,
							-- since the box should start at the Cap Height (ascender).

							------
							-- Calc the adjustment so we position text at its baseline, not top-left corner
							-- For rendering using Reference Point TopLeft
							baselineAdjustment = 0

							------------------------------------------------
							-- RENDER TEXT OBJECT
							------------------------------------------------
							--[[
							 Render a chunk of the text object.
							 Requires all the nice closure variables, so we can't move this very well...
							 This could be a paragraph <p>chunk</p> or a piece of text in a paragraph (<span>chunk</span>)
							 So, we don't know if this requires an end-of-line at the end!

							 A chunk to render is ALWAYS pure text. All HTML formatting is outside it.
							--]]


							result = display.newGroup()
							result.anchorX, result.anchorY = 0, 0

							-- Set the reference point to match the text alignment
							textDisplayReferencePoint = display["Bottom"..textAlignment.."ReferencePoint"]

							-- Preserve initial padding before first word
							local  _, _, padding = find(nextChunk, "^([%s%-]*)")
							padding = padding or ""

							-- Get chunks of text to iterate over to figure out line line wrap

							-- If the line wrapping is cached, get it
							if (textwrapIsCached) then
								cachedChunk = cache[cacheIndex]
								--words = gmatch(cachedChunk.text, "[^\r\n]+")
								words = iteratorOverCacheText(cachedChunk.text)
							else
								cachedChunk = newCacheChunk()
								words = gmatch(nextChunk, "([^%s%-]+)([%s%-]*)")
							end
							
							local textAlignmentForRender = lower(textAlignment) or "left"


-- ============================================================
-- CACHED RENDER
-- ============================================================

if (textwrapIsCached) then
	if (testing) then
		print ("Rendering from cache.")
	end
	
	for cachedChunkIndex, text in pairs(cachedChunk.text) do
		
		local cachedItem = getCachedChunkItem(cachedChunk, cachedChunkIndex)

		if (cachedItem.isFirstLine) then
			isFirstLine = false
			currentLineHeight = lineHeight
			currentSpaceBefore = settings.spaceBefore
			settings.currentFirstLineIndent = settings.firstLineIndent
			-- If first line of a block of text, then we must start on a new line.
			-- Jump to next line to start this text
			if (renderTextFromMargin ) then
				lineY = lineY + currentLineHeight + currentSpaceBefore
			end
			--renderTextFromMargin = true
		else
			currentLineHeight = lineHeight
			settings.currentFirstLineIndent = 0
			currentSpaceBefore = 0
			-- Not first line in a block of text, there might be something before it on the line,
			-- e.g. a Bold/Italic block, so do not jump to next row
			--lineY = lineY + currentLineHeight
		end

		if (cachedItem.renderTextFromMargin) then
			xOffset = 0
			settings.currentLeftIndent = settings.leftIndent
			renderTextFromMargin = false
		else
			xOffset = currentXOffset
			settings.currentFirstLineIndent = 0
			settings.currentLeftIndent = 0
			--isFirstLine = false
		end
		
		
		-- Cached values
		currentSpaceBefore = cachedItem.currentSpaceBefore
		lineHeight = cachedItem.lineHeight
		xOffset = cachedItem.xOffset
		
		textDisplayReferencePoint = display["Bottom"..textAlignment.."ReferencePoint"]
		

								local newDisplayLineGroup = display.newGroup()
								--newDisplayLineGroup.anchorChildren = true
								
								local newDisplayLineText = display.newText({
									parent = newDisplayLineGroup,
									text = text,
									x = 0, y = 0,
									font = cachedItem.font,
									fontSize = cachedItem.fontSize,
									align = cachedItem.align,
								})

								newDisplayLineText:setFillColor(unpack(cachedItem.color))
								newDisplayLineText:setReferencePoint(textDisplayReferencePoint)
								newDisplayLineText.x, newDisplayLineText.y = 0,0
								--newDisplayLineText.alpha = settings.opacity

								result:insert(newDisplayLineGroup)
								newDisplayLineGroup:setReferencePoint(textDisplayReferencePoint)
								newDisplayLineGroup.x, newDisplayLineGroup.y = cachedItem.x, cachedItem.y

								--positionNewDisplayLineX(newDisplayLineGroup, xOffset, currentWidth)

								lineCount = lineCount + 1

								-- Use once, then set to zero.
								settings.currentFirstLineIndent = 0

								-- <A> tag box. If we make the text itself touchable, it is easy to miss it...your touch
								-- goes through the white spaces around letter strokes!
								createLinkingBox(newDisplayLineGroup, newDisplayLineText, textDisplayReferencePoint, currentLine, {250,0,250,30} )
								
								lineCount = lineCount + 1
								
								if (not yAdjustment or yAdjustment == 0) then
									--yAdjustment = (settings.size * fontInfo.ascent )- newDisplayLineGroup.height
									yAdjustment = ( (settings.size / fontInfo.sampledFontSize ) * fontInfo.textHeight)- newDisplayLineGroup.height
								end


	end -- for
	
	cacheIndex = cacheIndex + 1
	return result

else

-- ============================================================
-- UNCACHED RENDER (writes to cache)
-- ============================================================


	if (testing) then
		print ("Rendering from XML, not cache.")
	end

							---------------------------------------------
							--local word,spacer
							local word, spacer, longword
							for word, spacer in words do

								if (not textwrapIsCached) then
									if (firstWord) then
										word = padding .. word
										firstWord = false
									end

									tempLine = currentLine..shortword..word..spacer
								else
									spacer = ""
									tempLine = word
									--currentLine = word
								end
								allTextInLine = prevTextInLine .. tempLine

								-- Grab the first words of the line, until "minLineCharCount" hit
								if (textwrapIsCached or (strlen(allTextInLine) > settings.minLineCharCount)) then
									-- Allow for lines with beginning spaces, for positioning
									if (usePeriodsForLineBeginnings and substring(currentLine,1,1) == ".") then
										currentLine = substring(currentLine,2,-1)
									end
									
									-- If a word is less than the minimum word length, force it to be with the next word,so lines don't end with single letter words.
									if (not textwrapIsCached and (strlen(allTextInLine) < nextChunkLen) and strlen(word) < settings.minWordLen) then
										shortword = shortword..word..spacer
									else
										if (not textwrapIsCached) then
											-- Draw the text as a line.								-- Trim based on alignment!
											tempDisplayLineTxt = display.newText({
												text=trimByAlignment(tempLine),
												x=0,
												y=0,
												font = settings.font,
												fontSize = settings.size,
												align = textAlignmentForRender or "left",
											})

											tempDisplayLineTxt:setReferencePoint(display.TopLeftReferencePoint)
											tempDisplayLineTxt.x = 0
											tempDisplayLineTxt.y = 0
											
											tempLineWidth = tempDisplayLineTxt.width
											
											-- Is this line of text too long? In which case we render the line
											-- as text, then move down a line on the screen and start again.
											if (renderTextFromMargin) then
												tempLineWidth = tempDisplayLineTxt.width
												if (isFirstLine) then
													settings.currentFirstLineIndent = settings.firstLineIndent
												else
													settings.currentFirstLineIndent = 0
												end
											else
												tempLineWidth = tempDisplayLineTxt.width + currentXOffset
												settings.currentFirstLineIndent = 0
											end
											
											display.remove(tempDisplayLineTxt);
											tempDisplayLineTxt=nil;

										else
											-- CACHED LINE
											tempLineWidth = cachedChunk.width[cachedChunkIndex]

											if (renderTextFromMargin) then
												if (isFirstLine) then
													settings.currentFirstLineIndent = settings.firstLineIndent
												else
													settings.currentFirstLineIndent = 0
												end
											else
												tempLineWidth = tempLineWidth + currentXOffset
												settings.currentFirstLineIndent = 0
											end

										end


										-- Since indents may change per line, we have to reset this each time.
										currentWidth = settings.width - settings.leftIndent - settings.rightIndent - settings.currentFirstLineIndent
										
										if (tempLineWidth <= currentWidth * widthCorrection)  then
											-- Do not render line, unless it is the last word,
											-- in which case render ("C" render)
											currentLine = tempLine
										else
											if ( settings.maxHeight==0 or (lineY <= settings.maxHeight - currentLineHeight)) then

												-- It is possible the first word is so long that it doesn't fit
												-- the margins (a 'B' line render, below), and in that case, the currentLine is empty.
												if (strlen(currentLine) > 0) then

	-- ============================================================
	-- A: Render text that fills the entire line, that will continue on a following line.
	-- This line always has text that continues on the next line.
	-- ============================================================



													if (testing) then
														print ()
														print ("----------------------------")
														print ("A: Render line: ["..currentLine .. "]")
														print ("Font: [".. settings.font .. "]")
														print ("currentWidth",currentWidth)
														print ("isFirstLine", isFirstLine)
														print ("renderTextFromMargin: ", renderTextFromMargin)
														print ("   newDisplayLineGroup.y = ",lineY + baselineAdjustment .. "+" .. baselineAdjustment)
													end

													if (isFirstLine) then
														currentLineHeight = lineHeight
														currentSpaceBefore = settings.spaceBefore
														isFirstLine = false
														settings.currentFirstLineIndent = settings.firstLineIndent
														if (renderTextFromMargin) then
															lineY = lineY + currentLineHeight + currentSpaceBefore
														end
													else
														currentLineHeight = lineHeight
														currentSpaceBefore = 0
														settings.currentFirstLineIndent = 0
													end


													if (renderTextFromMargin) then
														settings.currentLeftIndent = settings.leftIndent
														xOffset = 0
													else
														xOffset = currentXOffset
														settings.currentFirstLineIndent = 0
														settings.currentLeftIndent = 0
													end
													
													if (not textwrapIsCached) then
														-- Works for left-aligned...right is a mess anyway.
														if (renderTextFromMargin or isFirstLine) then
															currentLine = funx.trim(currentLine)
														end
														currentLine = trimByAlignment(currentLine)
														--cachedChunk.text[cachedChunkIndex] = currentLine
														--cachedChunk.width[cachedChunkIndex] = tempLineWidth	
													end
													
													local newDisplayLineGroup = display.newGroup()

													local newDisplayLineText = display.newText({
														parent=newDisplayLineGroup,
														text=currentLine,
														x=0, y=0,
														font=settings.font,
														fontSize = settings.size,
														align = textAlignmentForRender,
													})
													newDisplayLineText:setFillColor(unpack(settings.color))
													newDisplayLineText:setReferencePoint(textDisplayReferencePoint)
													newDisplayLineText.x, newDisplayLineText.y = 0, 0
													--newDisplayLineText.alpha = settings.opacity

													result:insert(newDisplayLineGroup)
													newDisplayLineGroup:setReferencePoint(textDisplayReferencePoint)

													-- Adjust Y to the baseline, not top-left corner of the font bounding-box
													newDisplayLineGroup.y = lineY + baselineAdjustment

													positionNewDisplayLineX(newDisplayLineGroup, newDisplayLineText.width, currentWidth)

													-- CACHE this line
													if (not textwrapIsCached) then
														updateCachedChunk (cachedChunk, { 
																	index = cachedChunkIndex, 
																	text = currentLine,
																	width = tempLineWidth,
																	x = newDisplayLineGroup.x,
																	y = newDisplayLineGroup.y,
																	font=settings.font,
																	fontSize = settings.size,
																	align = textAlignmentForRender,
																	color = settings.color,
																	lineHeight = lineHeight,
																	lineY = lineY,
																	currentSpaceBefore = currentSpaceBefore,
																	xOffset = xOffset,
																})
													end

													-- Update cache chunk index counter
													cachedChunkIndex = cachedChunkIndex + 1



													lineCount = lineCount + 1

													-- Use once, then set to zero.
													settings.currentFirstLineIndent = 0

													-- Use the current line to estimate how many chars
													-- we can use to make a line.
													if (not fontInfo.maxHorizontalAdvance) then
														settings.minLineCharCount = strlen(currentLine)
													end

													word = shortword..word

													-- We have wrapped, don't need text from previous chunks of this line.
													prevTextInLine = ""

													-- If next word is not too big to fit the text column, start the new line with it.
													-- Otherwise, make a whole new line from it. Not sure how that would help.
													wordlen = 0
													if (textwrapIsCached) then
														wordlen = cachedChunk.width[cachedChunkIndex]
													elseif ( word ~= nil ) then
														wordlen = strlen(word) * (settings.size * fontInfo.maxCharWidth)
														
														local tempWord = display.newText({
														    text=word,
														    x=0, y=0,
														    font=settings.font,
														    fontSize = settings.size,
														    align = textAlignmentForRender,
													    })
													    wordlen = tempWord.width
													    tempWord:removeSelf()
													    tempWord =  nil
						
													else
													    wordlen = 0
													end

													-- <A> tag box. If we make the text itself touchable, it is easy to miss it...your touch
													-- goes through the white spaces around letter strokes!
													createLinkingBox(newDisplayLineGroup, newDisplayLineText, textDisplayReferencePoint, currentLine )

													-- This line has now wrapped around, and the next one should start at the margin.
													renderTextFromMargin = true
													currentXOffset = 0

													-- And, we should now move our line cursor to the next row.
													-- We know nothing can continue on this line because we've filled it up.
													lineY = lineY + currentLineHeight

													-- Text lines can vary in height depending on whether there are upper case letters, etc.
													-- Not predictable! So, we capture the height of the first line, and that is the basis of
													-- our y adjustment for the entire block, to position it correctly.
													if (not yAdjustment or yAdjustment == 0) then
														--yAdjustment = (settings.size * fontInfo.ascent )- newDisplayLineGroup.height
														yAdjustment = ( (settings.size / fontInfo.sampledFontSize ) * fontInfo.textHeight)- newDisplayLineGroup.height
													end




												else

													--longword = true
													renderTextFromMargin = true
													currentXOffset = 0
													lineY = lineY + currentLineHeight
												end


												-- --------
												-- END 'A' RENDER
												-- --------




												if (textwrapIsCached or (not longword and wordlen <= currentWidth * widthCorrection) ) then
													if (textwrapIsCached) then
														currentLine = word
													else
														currentLine = word..spacer
													end
												else
													currentLineHeight = lineHeight

-- ----------------------------------------------------
-- ----------------------------------------------------
-- B: The word at the end of a line is too long to fit the text column! Very rare.
-- Example: <span>Cows are nice to <span><span>elep|hants.<span>
-- Where | is the column end.
-- ----------------------------------------------------
-- ----------------------------------------------------

													word = trimByAlignment(word)

													if (textwrapIsCached) then
														currentLine = word
--													else
--														cachedChunk.text[cachedChunkIndex] = word
--														cachedChunk.width[cachedChunkIndex] = wordlen
													end
													--cachedChunkIndex = cachedChunkIndex + 1

--print ("B")
if (testing) then
	print ()
	print ("----------------------------")
	print ("B: render a word: "..word)
	print ("\nrenderTextFromMargin reset to TRUE.")
	print ("isFirstLine", isFirstLine)
	print ("   newDisplayLineGroup.y",lineY + baselineAdjustment, baselineAdjustment)
	print ("leftIndent + currentFirstLineIndent + xOffset", settings.leftIndent, settings.currentFirstLineIndent, xOffset)
end

													if (isFirstLine) then
														currentLineHeight = lineHeight
														currentSpaceBefore = settings.spaceBefore
														isFirstLine = false
														settings.currentFirstLineIndent = settings.firstLineIndent
														if (renderTextFromMargin) then
															lineY = lineY + currentLineHeight + currentSpaceBefore
														end
													else
														currentLineHeight = lineHeight
														currentSpaceBefore = 0
														settings.currentFirstLineIndent = 0
													end


													if (renderTextFromMargin) then
														settings.currentLeftIndent = settings.leftIndent
														xOffset = 0
													else
														xOffset = currentXOffset
														settings.currentFirstLineIndent = 0
														settings.currentLeftIndent = 0
													end

													local newDisplayLineGroup = display.newGroup()
													--newDisplayLineGroup.anchorChildren = true
													
													local newDisplayLineText = display.newText({
														parent = newDisplayLineGroup,
														text = word,
														x = 0, y = 0,
														font = settings.font,
														fontSize = settings.size,
														align = textAlignmentForRender,
													})

													newDisplayLineText:setFillColor(unpack(settings.color))
													newDisplayLineText:setReferencePoint(textDisplayReferencePoint)
													newDisplayLineText.x, newDisplayLineText.y = 0, 0
													--newDisplayLineText.alpha = settings.opacity

													result:insert(newDisplayLineGroup)
													newDisplayLineGroup:setReferencePoint(textDisplayReferencePoint)
													newDisplayLineGroup.x, newDisplayLineGroup.y = x, lineY + baselineAdjustment

													positionNewDisplayLineX(newDisplayLineGroup, xOffset, currentWidth)

													lineCount = lineCount + 1
													currentLine = ''

													-- Use once, then set to zero.
													settings.currentFirstLineIndent = 0

													-- <A> tag box. If we make the text itself touchable, it is easy to miss it...your touch
													-- goes through the white spaces around letter strokes!
													createLinkingBox(newDisplayLineGroup, newDisplayLineText, textDisplayReferencePoint, currentLine, {250,0,250,30} )


													-- CACHE this line
													if (not textwrapIsCached) then
														updateCachedChunk (cachedChunk, { 
																	index = cachedChunkIndex, 
																	text = word,
																	width = tempLineWidth,
																	x = newDisplayLineGroup.x,
																	y = newDisplayLineGroup.y,
																	font=settings.font,
																	fontSize = settings.size,
																	align = textAlignmentForRender,
																	color = settings.color,
																	lineHeight = lineHeight,
																	lineY = lineY,
																	currentSpaceBefore = currentSpaceBefore,
																	xOffset = xOffset,
																})
													end
													
													cachedChunkIndex = cachedChunkIndex + 1


													-- This is a line too long to fit,
													-- so the next line surely must be the beginning
													-- a new line. We know nothing can continue on this line because we've filled it up.
													lineY = lineY + currentLineHeight

													renderTextFromMargin = true
													currentXOffset = 0

												end	-- end B




												-- Get min characters to start with
												-- We now know the max char width in a font,
												-- so we can start with a minimum based on that.
												-- IF the metric was set!
												if (not textwrapIsCached and not fontInfo.maxHorizontalAdvance) then
													-- Get stats for next line
													-- Set the new min char count to the current line length, minus a few for protection
													-- (20 is chosen from a few tests)
													settings.minLineCharCount = max(settings.minLineCharCount - 20,1)
												end

											end
										end
										shortword = ""
									end

								else
									currentLine = tempLine
								end
							end

							---------------------------------------------
							-- end for
							---------------------------------------------


							-- Allow for lines with beginning spaces, for positioning
							if (usePeriodsForLineBeginnings and substring(currentLine,1,1) == ".") then
								currentLine = substring(currentLine,2,-1)
							end

---------------------------------------------
-- C: line render
-- C: SHORT LINE or FINAL LINE OF PARAGRAPH
-- Add final line that didn't need wrapping
-- (note, we add a space to the text to deal with a weirdo bug that was deleting final words. ????)
---------------------------------------------

							-- IF content remains, render it.
							-- It is possible get the tailing space of block
							if (strlen(currentLine) > 0) then


								if (testing) then
									print ()
									print ("----------------------------")
									print ("C: Final line: ["..currentLine.."]", "length=" .. strlen(currentLine))
									print ("Font: [".. settings.font .. "]")
									print ("isFirstLine", isFirstLine)
									print ("renderTextFromMargin: ", renderTextFromMargin)
									print ("Width,", settings.width)
									print ("C) currentWidth", currentWidth)

								end


								if (isFirstLine) then
									isFirstLine = false
									currentLineHeight = lineHeight
									currentSpaceBefore = settings.spaceBefore
									settings.currentFirstLineIndent = settings.firstLineIndent
									-- If first line of a block of text, then we must start on a new line.
									-- Jump to next line to start this text
									if (renderTextFromMargin ) then
										lineY = lineY + currentLineHeight + currentSpaceBefore
									end
									--renderTextFromMargin = true
								else
									currentLineHeight = lineHeight
									settings.currentFirstLineIndent = 0
									currentSpaceBefore = 0
									-- Not first line in a block of text, there might be something before it on the line,
									-- e.g. a Bold/Italic block, so do not jump to next row
									--lineY = lineY + currentLineHeight
								end

								if (renderTextFromMargin) then
									xOffset = 0
									settings.currentLeftIndent = settings.leftIndent
									renderTextFromMargin = false
								else
									xOffset = currentXOffset
									settings.currentFirstLineIndent = 0
									settings.currentLeftIndent = 0
									--isFirstLine = false
								end

								-- We have the current line from the code above if this is not cached text.
--								if (not textwrapIsCached) then
--									cachedChunk.text[cachedChunkIndex] = currentLine
--									cachedChunk.width[cachedChunkIndex] = currentWidth
--								end
--								cachedChunkIndex = cachedChunkIndex + 1


								if (testing) then
									print ("Previous Line:", "["..prevTextInLine.."]", strlen(prevTextInLine))
									print ("lineY:",lineY)
									print ("currentSpaceBefore:",currentSpaceBefore, settings.spaceBefore)
									print ("currentSpaceAfter:",currentSpaceAfter, settings.spaceAfter)
									if (currentSpaceBefore > 0) then
										print ("************")
									end
								end

								--print ("C: render a line:", currentLine)

								local newDisplayLineGroup = display.newGroup()
								--newDisplayLineGroup.anchorChildren = true
								
								currentLine = trimByAlignment(currentLine)
								local newDisplayLineText = display.newText({
									parent = newDisplayLineGroup,
									text = currentLine,
									x = 0, y = 0,
									font = settings.font,
									fontSize = settings.size,
									align = textAlignmentForRender,
								})
								newDisplayLineText:setFillColor(unpack(settings.color))
								newDisplayLineText:setReferencePoint(textDisplayReferencePoint)
								newDisplayLineText.x, newDisplayLineText.y = 0, 0
								--newDisplayLineText.alpha = settings.opacity

								result:insert(newDisplayLineGroup)
								newDisplayLineGroup:setReferencePoint(textDisplayReferencePoint)
								newDisplayLineGroup.x, newDisplayLineGroup.y = x, lineY

								positionNewDisplayLineX(newDisplayLineGroup, xOffset, currentWidth)

								newDisplayLineGroup.y = lineY + baselineAdjustment

								-- We don't know if we have added a line...this text might be inside another line.
								-- So we don't increment line count
								-- lineCount = lineCount + 1

								-- We know this is a short line, and it is possible the next chunk of text
								-- will begin on the same line, so we capture the x value. So, set the
								-- currentXOffset value so the next text starts in the right column.
								setCurrentXOffset(newDisplayLineText, xOffset)

								-- CACHE this line
								if (not textwrapIsCached) then
									updateCachedChunk (cachedChunk, { 
												index = cachedChunkIndex, 
												text = currentLine,
												width = tempLineWidth,
												x = newDisplayLineGroup.x,
												y = newDisplayLineGroup.y,
												font=settings.font,
												fontSize = settings.size,
												align = textAlignmentForRender,
												color = settings.color,
												lineHeight = lineHeight,
												lineY = lineY,
												currentSpaceBefore = currentSpaceBefore,
												xOffset = xOffset,
											})
								end
								
								cachedChunkIndex = cachedChunkIndex + 1




								-- Save the current line if we started at the margin
								-- So the next line, if it has to, can start where this one ends.
								prevTextInLine = prevTextInLine .. currentLine

								-- Since line heights are not predictable, we capture the yAdjustment based on
								-- the actual height the first rendered line of text
								if (not yAdjustment or yAdjustment == 0) then
									--yAdjustment = (settings.size * fontInfo.ascent )- newDisplayLineGroup.height
									yAdjustment = ( (settings.size / fontInfo.sampledFontSize ) * fontInfo.textHeight)- newDisplayLineGroup.height
								end

								createLinkingBox(newDisplayLineGroup, newDisplayLineText, textDisplayReferencePoint, currentLine, {250,0,0,30})

								-- Clear the current line
								currentLine = ""

							end
							
							if (not textwrapIsCached) then
								cache[cacheIndex] = cachedChunk
							end
							cacheIndex = cacheIndex + 1
							return result
							
end

						end -- renderParsedElement()

					-- save the style settings as they are before
					-- anything modifies them inside this tag.
					local styleSettings = getAllStyleSettings()

					tag, attr = convertHeaders(tag, attr)
					tag = lower(tag)

					local listIdentDistance = 20

					------------------------------------------------------------
					-- Handle formatting tags: p, div, br
					------------------------------------------------------------
					
					if (tag == "p" or tag == "div" or tag == "li" or tag == "ul" or tag == "ol") then

						-- Reset margins, cursor, etc. to defaults
						renderTextFromMargin = true
						currentXOffset = 0
						x = 0
						settings.leftIndent = 0
						settings.rightIndent = 0
						
						-- Apply style based on tag, e.g. <ol> or <p>
						if (textstyles and textstyles[tag] ) then
							local params = textstyles[tag]
							setStyleFromCommandLine (params)
						end
						
						-- Next, apply style settings
						local styleName = "Normal"
						if (attr.class) then
							styleName = lower(attr.class)
							if (textstyles and textstyles[styleName] ) then
								local params = textstyles[styleName]
								setStyleFromCommandLine (params)
							else
								print ("WARNING: funx.autoWrappedText tried to use a missing text style ("..styleName..")")
							end
						end
						setStyleFromTag (tag, attr)

						currentSpaceBefore = settings.spaceBefore
						currentSpaceAfter = settings.spaceAfter


						-- LISTS
						if (tag == "ol" or tag == "ul" ) then
							-- Nested lists require indentation (which isn't happening yet) and a new line.
							local indent = 0
							if (stacks.list[stacks.list.ptr] and stacks.list[stacks.list.ptr].tag) then
								lineY = lineY + lineHeight + currentSpaceAfter
								-- Indent starting at 2nd level
								indent = listIdentDistance
							end
							settings.leftIndent = settings.leftIndent + indent
							stacks.list.ptr =  stacks.list.ptr + 1
							local b = ""
							if (tag == "ul") then
								if (attr.bullet == "disc") then
									b = "&#9679;"
								elseif (attr.b == "square") then
									b = "&#9632;"
								elseif (attr.bullet == "circle") then
									b = "&#9675;"
								elseif (attr.bullet == "triangle") then
									b = "&#9658;"
								elseif (attr.bullet == "dash") then
									b = "&#8211;"
								elseif (attr.bullet == "mdash") then
									b = "&#8212;"
								elseif (attr.bullet == "none") then
									b = ""
								else
									b = "&#9679;"
								end
								b = entities.convert(b)
							end
							stacks.list[stacks.list.ptr] = { tag = tag, line = 1, bullet = b, indent = indent}
						end

					elseif (tag == "br") then
 					end

					if (tag == "a") then
						setStyleFromTag (tag, attr)
					end


					-- LIST ITEMS: add a bullet or number
					if (tag == "li") then
						-- default for list is a disk.
						local t = ""
						-- If number, use the number instead
						if (stacks.list[stacks.list.ptr].tag == "ol" ) then
							t = stacks.list[stacks.list.ptr].line .. ". "
							stacks.list[stacks.list.ptr].line = stacks.list[stacks.list.ptr].line + 1
						else
							t = stacks.list[stacks.list.ptr].bullet

						end
						-- add a space after the bullet
						t = t .. " "
						local e = renderParsedElement(1, t, "", "")
						-- Add one to the element counter so the next thing won't be on a new line
						elementCounter = elementCounter + 1
						result:insert(e)
					end


					--endOfLine = false
					for n, element in ipairs(parsedText) do
						--local styleSettings = {}
						if (type(element) == "table") then
--print ("A-Tag",tag)
							local saveStyleSettings = getAllStyleSettings()
							-- Apply a font formatting tag, e.g. bold or italic
							if (tag == "b" or tag == "i" or tag == "em" or tag == "strong" or tag == "font" ) then
								setStyleFromTag (tag, attr)
							end

							local e = renderParsedText(element, element._tag, element._attr, parseDepth, stacks)
							result:insert(e)
							e.anchorX, e.anchorY = 0, 0
							setStyleSettings(saveStyleSettings)
						else
							if (not element) then
								print ("***** WARNING, EMPTY ELEMENT**** ")
							end
--print ("B-Tag",tag)
							local saveStyleSettings = getAllStyleSettings()
							local e = renderParsedElement(n, element, tag, attr)
							result:insert(e)
							e.anchorX, e.anchorY = 0, 0
							elementCounter = elementCounter + 1
							setStyleSettings(saveStyleSettings)
						end

					end -- end for

					-- Close tags
					-- AFTER rendering (so add afterspacing!)
					if (tag == "p" or tag == "div") then
						setStyleFromTag (tag, attr)
						renderTextFromMargin = true
						lineY = lineY + currentSpaceAfter
						-- Reset the first line of paragraph flag
						isFirstLine = true
						--lineY = lineY + lineHeight + currentSpaceAfter
						elementCounter = 1
					elseif (tag == "li") then
						setStyleFromTag (tag, attr)
						renderTextFromMargin = true
						lineY = lineY + currentSpaceAfter
						-- Reset the first line of paragraph flag
						isFirstLine = true
						elementCounter = 1
					elseif (tag == "ul") then
						setStyleFromTag (tag, attr)
						renderTextFromMargin = true
						--lineY = lineY + lineHeight + currentSpaceAfter
						--leftIndent = settings.leftIndent - stacks.list[stacks.list.ptr].indent
						stacks.list[stacks.list.ptr] = nil
						stacks.list.ptr = stacks.list.ptr -1
						elementCounter = 1
					elseif (tag == "ol") then
						setStyleFromTag (tag, attr)
						renderTextFromMargin = true
						--lineY = lineY + lineHeight + currentSpaceAfter
						--leftIndent = settings.leftIndent - stacks.list[stacks.list.ptr].indent
						stacks.list[stacks.list.ptr] = nil
						stacks.list.ptr = stacks.list.ptr -1
						-- Reset the first line of paragraph flag
						isFirstLine = true
						elementCounter = 1
					elseif (tag == "br") then
						renderTextFromMargin = true
						currentXOffset = 0
						setStyleFromTag (tag, attr)
						lineY = lineY + currentSpaceAfter
						-- Reset the first line of paragraph flag
						isFirstLine = true
						elementCounter = 1
					elseif (tag == "#document") then
						-- lines from non-HTML text will be tagged #document
						-- and this will handle them.
						renderTextFromMargin = true
						currentXOffset = 0
						setStyleFromTag (tag, attr)
						lineY = lineY + currentSpaceAfter
--						elementCounter = 1
					end

					--print ("Restore style settings", settings.color[1], tag)
					-- Restore style settings to what they were before
					-- entering the tag

					setStyleSettings(styleSettings)
					return result
				end -- end function renderParsedText

				------------------------------------------------------------
				-- Render one block of text (or an XML chunk of some sort)
				-- This could be the opening to a paragraph, e.g. <p class="myclass">
				-- or some text, or another XML chunk, e.g. <font name="Times">my text</font>
				------------------------------------------------------------

				local e = renderParsedText(parsedText, parsedText._tag, parsedText._attr)
				result:insert(e)
				e.anchorX, e.anchorY = 0, 0

				-- This keeps centered/right aligned objects in the right place
				-- The line is built inside a rect of the correct width
				--e:setReferencePoint(display["Center" .. textAlignment .. "ReferencePoint"])
				--e.x = 0
				--e.y = 0

				isFirstTextInBlock = false

				return result

			end -- end renderXML


			-- Render this chunk of XML
			local oneXMLBlock = renderXML(restOLine)
			result:insert(oneXMLBlock)
			oneXMLBlock.anchorX, oneXMLBlock.anchorY = 0, 0

		end -- html elements for one paragraph

	end

	-----------------------------
	-- Finished rendering all blocks of text (all paragraphs).
	-- Anchor the text block TOP-LEFT by default
	-----------------------------
	result.anchorChildren = true
	result.anchorX, result.anchorY = 0,0

	--print ("textwrap.lua: yAdjustment is turned OFF because it wasn't working! No idea why.")
	result.yAdjustment = yAdjustment
	--print ("textDisplayReferencePoint",textDisplayReferencePoint)

	saveTextWrapToCache(textUID, cache, cacheDir)

	return result
end

T.autoWrappedText = autoWrappedText

return T