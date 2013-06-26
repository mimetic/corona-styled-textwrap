-- textwrap.lua

local funx = require ("funx")
local html = require ("html")
local entities = require ("entities")

local max = math.max
local lower = string.lower


-- Be sure a caches dir is set up inside the system caches
local textWrapCacheDir = "textwrap"
--funx.mkdir (textWrapCacheDir, "",false, system.CachesDirectory)



-- functions
local floor = math.floor

-- testing function
local function showTestLine(group, y, isFirstTextInBlock, i)
	local q = display.newLine(group, 0,y,200,y)
	i = i or 1
	if (isFirstTextInBlock) then
		q:setColor(250,0,0)
	else
		q:setColor(80 * i,80 * i, 80)
	end
	q.width = 2
end



-- Main var for this module
local T = {}


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


--------------------------------------------------------
-- Common functions redefined for speed
--------------------------------------------------------

local strlen = string.len
local substring = string.sub
local stringFind = string.find
local floor = math.floor


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
	local _, _, n = string.find(t, "^(%d+)")
	local _, _, u = string.find(t, "(%a%a)$")

	if (u == "pt" and deviceMetrics) then
		n = n * (deviceMetrics.ppi/72)
	end
	return n
end


--------------------------------------------------------
-- Get tag formatting values
--------------------------------------------------------
local function getTagFormatting(fontFaces, tag, currentfont, attr)
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

	local basefont = string.gsub(currentfont, "%-.*$","")
	local _,_,variation = stringFind(currentfont, "%-(.-)$")
	variation = variation or ""

	local format = {}

	if (tag == "em" or tag == "i") then
		if (variation == "Bold") then
			format.font = getFontFace (basefont, "-BoldItalic")
		else
			format.font = getFontFace (basefont, "-Italic")
		end
	elseif (tag == "strong" or tag == "b") then
		if (variation == "Italic") then
			format.font = getFontFace (basefont, "-BoldItalic")
		else
			format.font = getFontFace (basefont, "-Bold")
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
	if ( tag and string.find(tag, "[hH]%d") ) then
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
		funx.mkdir (cacheDir .. "/" .. textWrapCacheDir, "",false, system.CachesDirectory)
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

	local testing = true
	if (testing) then
		print ("autoWrappedText: testing flag is true")
	end

	local deviceMetrics = funx.getDeviceMetrics( )

--if text == '' then return false end
	local result = display.newGroup()
	local minWordLen = 2
	-- Get from the funx textStyles variable.
	local myTextStyles = textstyles

	local parseDepth = 0

	local isHTML = false

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
		minWordLen = text.minWordLen
		myTextStyles = text.textstyles or myTextStyles
		isHTML = text.isHTML or false
		defaultStyle = text.defaultStyle or ""
		cacheDir = text.cacheDir
		-- restore text
		text = text.text
	end

	-- Caching values
	local textUID = 0
	local textwrapIsCached = false
	local cache = { { text = "", width = "", } }
	local cacheChunkCtr = 1

	if ( cacheDir and cacheDir ~= "" ) then
		textUID = funx.checksum(text)
		local res = loadTextWrapFromCache(textUID, cacheDir)
		if (res) then
			textwrapIsCached = true
			cache = res
		end
	end


	-- default
	minWordLen = minWordLen or 2
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

	--[[
	-- NOT IN USE: THIS IS BEFORE WE PARSED INDESIGN INTO HTML

	-- For text fields, NOT HTML fields, add CR after every line that comes from InDesign.
	-- InDesign uses the above separators, which suck.
	-- Note the spaces after the returns! This prevents the return from being stripped as
	-- simply extra blank space!

	-- We check later WHICH line end we use, and format appropriately
	if (not isHTML) then
		text = text:gsub(funx.unescape(lineSeparatorCode),"\r ")
		text = text:gsub(funx.unescape(paragraphSeparatorCode),"\n ")

	end
	--]]
	--- THEN, TOO, THERE'S MY OWN FLAVOR OF LINE BREAK!
	-- Replace our special line break code with a return!
	text = text:gsub("%[%[%[br%]%]%]","<br>")

	------------------------

	maxHeight = tonumber(maxHeight) or 0


	-- Min text size
	local minTextSize = 12

	-- Minimum number of characters per line. Start low.
	local minLineCharCount = minCharCount or 5

	-- This will cause problems with Android
	font = font or native.systemFont
	size = tonumber(size) or 12
	color = color or {255, 255, 255}
	width = funx.applyPercent(width, screenW) or display.contentWidth
	opacity = funx.applyPercent(opacity, 1) or 1
	targetDeviceScreenSize = targetDeviceScreenSize or screenW..","..screenH
	-- case can be ALL_CAPS or NORMAL
	local case = "NORMAL";
	-- Space before/after paragraph
	local spaceBefore = 0
	local spaceAfter = 0
	local firstLineIndent = 0
	local currentFirstLineIndent = 0
	local leftIndent = 0
	local rightIndent = 0
	local bullet = "&#9679;"

	------ POSITIONING RECT
	-- Need a positioning rect so that indents work.
	-- Width must be full-width so the right-justified works.
	-- THIS HAS A PROBLEM...IF THE ALIGN IS CENTER BUT THE TEXT LINE REALLY ISN'T CENTER,
	-- THIS WILL FAIL. SO, IF THE "ALIGN" IS SET TO CENTER, FOR SOME LEGACY REASON, BUT THE FIRST
	-- LINE IS OTHERWISE, THIS WILL FAIL. FUCK.
	--local r = display.newRect(0,0,width,10)
	local r = display.newRect(0,0,0,1)
	r:setFillColor(255,0,0)
	result:insert(r)
	result._positionRect = r
	r.strokeWidth=0
	r:setReferencePoint(display["Bottom" .. textAlignment .. "ReferencePoint"])
	--r:setReferencePoint(display["Bottom" .. "Left" .. "ReferencePoint"])
	r.x = 0
	r.y = 0
	r.isVisible = testing


 	lineHeight = funx.applyPercent(lineHeight, size) or floor(size * 1.3)

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

			params.font = font
			-- font size
			params.size = size
			params.minLineCharCount = minLineCharCount
			params.lineHeight = lineHeight
			params.color = color
			params.width = width
			params.opacity = opacity
			-- case (upper/normal)
			params.case = case
			-- space before paragraph
			params.spaceBefore = spaceBefore
			-- space after paragraph
			params.spaceAfter = spaceAfter
			-- First Line Indent
			params.firstLineIndent =firstLineIndent
			-- Left Indent
			params.leftIndent = leftIndent
			-- Right Indent
			params.rightIndent = rightIndent
			params.textAlignment = textAlignment

			return params
		end


		-- Set style settings which were saved using the function above.
		-- These are set using the values from internal variables, e.g. font or size,
		-- NOT from the style sheet parameters.
		local function setStyleSettings (params)
			if (params.font ) then font = params.font end
				-- font size
			if (params.size ) then size = params.size end
			if (params.minLineCharCount ) then minLineCharCount = params.minLineCharCount end
			if (params.lineHeight ) then lineHeight = params.lineHeight end
			if (params.color ) then color = params.color end
			if (params.width ) then width = params.width end
			if (params.opacity ) then opacity = params.opacity end
				-- case (upper/normal)
			if (params.case ) then case = params.case end
				-- space before paragraph
			if (params.spaceBefore ) then spaceBefore = params.spaceBefore end
				-- space after paragraph
			if (params.spaceAfter ) then spaceAfter = params.spaceAfter end
				-- First Line Indent
			if (params.firstLineIndent ) then params.firstLineIndent = firstLineIndent end
				-- Left Indent
			if (params.leftIndent ) then leftIndent = params.leftIndent end
				-- Right Indent
			if (params.rightIndent ) then rightIndent = params.rightIndent end
			if (params.textAlignment ) then textAlignment = params.textAlignment end
	--[[
			if (lower(textAlignment) == "Right") then
				x = width - rightIndent
				currentFirstLineIndent = 0
				firstLineIndent = 0
			elseif (lower(textAlignment) == "Left") then
				x = 0
			else
				local currentWidth = width - leftIndent - rightIndent -- firstLineIndent
				x = floor(currentWidth/2) --+ firstLineIndent
			end
	]]
		end



		-- set style from params in a ### set, ... command line in the text
		-- This depends on the closure for variables, such as font, size, etc.
		local function setStyleFromCommandLine (params)
			-- font
			if (params[2] and params[2] ~= "") then font = funx.trim(params[2]) end
			-- font size
			if (params[3] and params[3] ~= "") then
				size = tonumber(params[3])
				--size = scaleToScreenSize(tonumber(params[3]), scalingRatio)
				-- reset min char count in case we loaded a BIG font
				minLineCharCount = minCharCount or 5
			end

			-- line height
			if (params[4] and params[4] ~= "") then
				lineHeight = tonumber(params[4])
				--lineHeight = scaleToScreenSize(tonumber(params[4]), scalingRatio)
			end
			-- color
			if ((params[5] and params[5] ~= "") and (params[6] and params[6] ~= "") and (params[7] and params[7] ~= "")) then color = {tonumber(params[5]), tonumber(params[6]), tonumber(params[7])} end
			-- width of the text block
			if (params[8] and params[8] ~= "") then
				if (params[8] == "reset" or params[8] == "r") then
					width = defaultSettings.width
				else
					width = tonumber(funx.applyPercent(params[8], screenW) or defaultSettings.width)
				end
				minLineCharCount = minCharCount or 5
			end
			-- opacity
			if (params[9] and params[9] ~= "") then opacity = funx.applyPercent(params[9],1) end
			-- case (upper/normal)
			if (params[10] and params[10] ~= "") then case = funx.trim(params[10]) end

			-- space before paragraph
			if (params[12] and params[12] ~= "") then spaceBefore = funx.trim(params[12]) end
			-- space after paragraph
			if (params[13] and params[13] ~= "") then spaceAfter = funx.trim(params[13]) end
			-- First Line Indent
			if (params[14] and params[14] ~= "") then firstLineIndent = funx.trim(params[14]) end
			-- Left Indent
			if (params[15] and params[15] ~= "") then leftIndent = funx.trim(params[15]) end
			-- Right Indent
			if (params[16] and params[16] ~= "") then rightIndent = funx.trim(params[16]) end

			-- alignment (note, set first line indent, etc., first!
			if (params[11] and params[11] ~= "") then
				textAlignment = funx.fixCapsForReferencePoint(params[11])
				-- set the line starting point to match the alignment
				if (lower(textAlignment) == "right") then
					x = width - rightIndent
					currentFirstLineIndent = 0
					firstLineIndent = 0
				elseif (lower(textAlignment) == "left") then
					x = 0
				else
					local currentWidth = width - leftIndent - rightIndent -- firstLineIndent
					x = floor(currentWidth/2) --+ firstLineIndent
				end

			end
		end



		-- set style from the attributes of an XML tag, from the style attribute,
		-- e.g. <p style="font:Helvetica;"/>
		-- This depends on the closure for variables, such as font, size, etc.
		-- fontFaces, font are in the closure!
		local function setStyleFromTag (tag, attr)

			local format = getTagFormatting(fontFaces, tag, font, attr)

			-- font
			if (format.font) then font = funx.trim(format.font) end
			-- font with CSS:
			if (format['font-family']) then font = funx.trim(format['font-family']) end

			-- font size
			if (format['font-size'] or format['size']) then
				if (format['font-size']) then
					-- convert pt values to px
					size = convertValuesToPixels(format['font-size'])
				else
					size = convertValuesToPixels(format['size'])
				end

				--size = scaleToScreenSize(tonumber(params[3]), scalingRatio)
				-- reset min char count in case we loaded a BIG font
				minLineCharCount = minCharCount or 5
			end

			-- lineHeight (HTML property)
			if (format.lineHeight) then
				lineHeight = convertValuesToPixels (format.lineHeight)
			end


			-- lineHeight (CSS property)
			if (format['line-height']) then
				lineHeight = convertValuesToPixels (format['line-height'])
			end

			-- color
			-- We're using decimal, e.g. 12,24,55 not hex (#ffeeff)
			if (format.color) then
				local _, _, c = string.find(format.color, "%((.*)%)")
				local s = funx.stringToColorTable(c)
				if (s) then
					color = { s[1], s[2], s[3], s[4] }
				end
			end


			-- width of the text block
			if (format.width) then
				if (format.width == "reset" or format.width == "r") then
					width = defaultSettings.width
				else
					width = tonumber(funx.applyPercent(format.width, screenW) or defaultSettings.width)
				end
				minLineCharCount = minCharCount or 5
			end

			-- opacity
			if (format.opacity) then opacity = funx.applyPercent(format.opacity,1) end

			-- case (upper/normal) using legacy coding ("case")
			if (format.case) then
				case = lower(funx.trim(format.case))
				if (case == "none") then
					case = "normal"
				end
			end

			-- case, using CSS, e.g. "text-transform:uppercase"
			if (format['text-transform']) then case = funx.trim(format.case) end

			-- space before paragraph
			if (format['margin-top']) then spaceBefore = convertValuesToPixels(format['margin-top']) end

			-- space after paragraph
			if (format['margin-bottom']) then spaceAfter = convertValuesToPixels(format['margin-bottom']) end

			-- First Line Indent
			if (format['text-indent']) then firstLineIndent = convertValuesToPixels(format['text-indent']) end

			-- Left Indent
			if (format['margin-left']) then leftIndent = convertValuesToPixels(format['margin-left']) end

			-- Right Indent
			if (format['margin-right']) then rightIndent = convertValuesToPixels(format['margin-right']) end

			-- alignment (note, set first line indent, etc., first!
			if (format['text-align']) then
				textAlignment = funx.fixCapsForReferencePoint(format['text-align'])
				-- set the line starting point to match the alignment
				if (lower(textAlignment) == "right") then
					x = width - rightIndent
					currentFirstLineIndent = 0
					firstLineIndent = 0
				elseif (lower(textAlignment) == "center") then
					-- Center
					local currentWidth = width - leftIndent - rightIndent -- firstLineIndent
					x = floor(currentWidth/2) --+ firstLineIndent
				else
					x = 0
				end

			end

			-- list bullet
			if (format['bullet']) then
				bullet = format['bullet'] or "&#9679;"
			end
		end



		---------------------------------------------------------------------------

	-- Load default style if it exists
	if (defaultStyle ~= "") then
		local params = myTextStyles[defaultStyle]
		if (params) then
			setStyleFromCommandLine (params)
		end
	end

	local defaultSettings = {
		font=font,
		size=size,
		lineHeight=lineHeight,
		color=color,
		width=width,
		opacity=opacity,
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
	--	for line in string.gmatch(text, "[^\n]+") do
	local linebreak = funx.unescape(lineSeparatorCode)
	local paragraphbreak = funx.unescape(paragraphSeparatorCode)
	local oneLinePattern = "[^\n^\r]+"
	local oneLinePattern = ".-[\n\r]"

	-- NO: In fact, we should make HTML into one big block
	-- Split the text into paragraphs using <p>
	--text = breakTextIntoParagraphs(text)
	local t1 = text
	if (isHTML) then
		--print ("Autowrap: line 500 : text is HTML!")
		text = funx.trim(text:gsub("[\n\r]",""))
	end

	-- Be sure the text block ends with a return, so the line chopper below finds the last line!
	if (string.sub(text,1,-1) ~= "\n") then
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


	-- Repeat for each block of text (ending with a carriage return)
	-- Usually, this will be a paragraph
	-- Text from InDesign should be one large block,
	-- which is right since it is escaped HTML.
	for line in string.gmatch(text, oneLinePattern) do
		local command, commandline
		local currentFirstLineIndent, currentSpaceAfter, currentSpaceBefore

		local lineEnd = string.sub(line,-1,-1)
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
				font = defaultSettings.font
				size = defaultSettings.size
				lineHeight = defaultSettings.lineHeight
				color = defaultSettings.color
				width = defaultSettings.width
				opacity = defaultSettings.opacity
				textAlignment = "Left"
				x = 0
				currentFirstLineIndent = firstLineIndent
				leftIndent = 0
				rightIndent = 0
				bullet = "&#9679;"
			elseif (command == "style") then
				local styleName = params[2] or "MISSING"
				if (myTextStyles and myTextStyles[styleName] ) then
					params = myTextStyles[styleName]
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
						x = width - rightIndent
						currentFirstLineIndent = 0
						firstLineIndent = 0
					elseif (lower(textAlignment) == "left") then
						x = 0
					else
						local currentWidth = width - leftIndent - rightIndent -- currentFirstLineIndent
						x = floor(currentWidth/2) --+ currentFirstLineIndent
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

				-- Need a positioning rect so that indents work.
if (not width) then print ("textwrap: line 844: Damn, the width is wacked"); end


				width = width or 300
				--[[
				local r = display.newRect(0,0,width,2)
				r:setFillColor(100,250,0)
				result:insert(r)
				r:setReferencePoint(display.TopLeftReferencePoint)
				r.x = 0
				r.y = 0
				r.isVisible = testing
				--]]

				local textDisplayReferencePoint
				if (textAlignment and textAlignment ~= "") then
					textAlignment = funx.fixCapsForReferencePoint(textAlignment)
					textDisplayReferencePoint = display["Bottom"..textAlignment.."ReferencePoint"]
				else
					textAlignment = "Left"
					textDisplayReferencePoint = display.CenterLeftReferencePoint
				end



				-- Set text alignment
				textDisplayReferencePoint = display["Bottom"..textAlignment.."ReferencePoint"]

				local shortword = ""
				local restOLineLen = strlen(restOLine)

				-- Set paragraph wide stuff, indents and spacing
				currentFirstLineIndent = firstLineIndent
				currentSpaceBefore = spaceBefore
				currentSpaceAfter = spaceAfter

				if (lineBreakType == "hard") then
					currentFirstLineIndent = firstLineIndent
					currentSpaceBefore = spaceBefore
					currentSpaceAfter = spaceAfter
				end

				if (lineBreakType == "soft") then
					currentSpaceBefore = spaceBefore
					currentSpaceAfter = 0
				end

				-- If previous paragraph had a soft return, don't add space before, nor indent the 1st line
				if (prevLineBreakType == "soft") then
					currentFirstLineIndent = 0
					currentSpaceBefore = 0
				end

				-- ALIGN TOP OF TEXT FRAME TO CAP HEIGHT!!!
				-- If this is the first line in the block of text, DON'T apply the space before settings
				-- Tell the function which called this to raise the entire block to the cap-height
				-- of the first line.

				local fontInfo = fontMetrics.getMetrics(font)
				local currentLineHeight = lineHeight
				local baselineAdjustment = 0

				-- Get the iOS bounding box size for this particular font!!!
				-- This must be done for each size and font, since it changes unpredictably
				local samplefont = display.newText("X", 0, 0, font, size)
				local boxHeight = samplefont.height
				samplefont:removeSelf()
				samplefont = nil

				-- boxHeight used size, so it is correct here.
				local baseline = boxHeight + (size * fontInfo.descent)

				-- change case
				if (case) then
					case = lower(case)
					if (case == "all_caps" or case == "uppercase") then
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


				-- Width of the text column
				local currentWidth = width - leftIndent - rightIndent - currentFirstLineIndent
				-- Get min characters to start with
				-- We now know the max char width in a font,
				-- so we can start with a minimum based on that.
				-- IF the metric was set!
				if (fontInfo.maxHorizontalAdvance) then
					minLineCharCount = floor((currentWidth * widthCorrection) / (size * fontInfo.maxCharWidth) )
				end



				-- Remember the font we start with to handle bold/italic changes
				local basefont = font

				-- Offset from left or right of the current chunk of text
				-- As we add chunks to previous chunks of text (building a line)
				-- we need to know where the next chunk goes.
				local currentXOffset = 0

				local prevTextInLine = ""


				local prevFont = font
				local prevSize = size


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
					local function getFontAscent(font,size)
						local fontInfo = fontMetrics.getMetrics(font)

						-- Get the iOS bounding box size for this particular font!!!
						-- This must be done for each size and font, since it changes unpredictably
						local samplefont = display.newText("X", 0, 0, font, size)
						local boxHeight = samplefont.height
						samplefont:removeSelf()
						samplefont = nil

						-- Set the new baseline from the font metrics
						local baseline = boxHeight + (size * fontInfo.descent)
						--local yAdjustment = (size * fontInfo.capheight) - baseline
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


--print ("  ")
--print ("  ")
--print ("  ")
--print ("elementNum, element, tag, attr")
--print (tag)
--funx.dump(attr)
--print (element)


							local result = display.newGroup();
							-- flag to indicate the text line to be rendered is the last line of the previously
							-- rendered text (true) or is the continuation of that text (false)
							-- Starts true for first item, then is false unless changed later.
							renderTextFromMargin = (elementCounter == 1)

							local nextChunk = element or ""

							local nextChunkLen = strlen(nextChunk)

							--local styleSettings = getAllStyleSettings()

							-- Apply the tag, e.g. bold or italic
							if (tag) then
								setStyleFromTag (tag, attr)
							end

							------------------------------------------------
							-- Refigure font metrics if font has changed
							------------------------------------------------
							if (font ~= prevFont or size ~= prevSize) then
								-- ALIGN TOP OF TEXT FRAME TO CAP HEIGHT!!!
								-- If this is the first line in the block of text, DON'T apply the space before settings
								-- Tell the function which called this to raise the entire block to the cap-height
								-- of the first line.
								fontInfo = fontMetrics.getMetrics(font)

								-- Get the iOS bounding box size for this particular font!!!
								-- This must be done for each size and font, since it changes unpredictably
								local samplefont = display.newText("X", 0, 0, font, size)
								local boxHeight = samplefont.height
								samplefont:removeSelf()
								samplefont = nil

								-- Set the new baseline from the font metrics
								baseline = boxHeight + (size * fontInfo.descent)
								prevFont = font
								prevSize = size
							end
							------------------------------------------------

							----------------
							-- IF this is the first line of the text box, figure out the corrections
							-- to position the ENTIRE box properly (yAdjustment).
							-- The current line height is NOT the leading/lineheight as with other lines,
							-- since the box should start at the Cap Height (ascender).

							if (isFirstTextInBlock) then
								currentSpaceBefore = 0
								-- position ascent of font at initial y value
								-- yAdjustment is used by calling functions to adjust
								-- where they place the text block to get it right.
								--yAdjustment = (size * fontInfo.capheight) - baseline
								-- For rendering using ReferencePoint at Bottom
								--yAdjustment = size - (size * fontInfo.ascent)
								isFirstTextInBlock = false
							end

							------
							-- Calc the adjustment so we position text at its baseline, not top-left corner
							-- For rendering using Reference Point TopLeft
							--baselineAdjustment = floor((size * fontInfo.capheight) - baseline)
							-- For rendering using Reference Point BottomLeft
							--baselineAdjustment = floor((size * fontInfo.capheight) - baseline)
							baselineAdjustment = 0--(size/fontInfo.sampledFontSize) * fontInfo.textHeight
--print ("Baseline Adjustment for size "..size.." is "..baselineAdjustment)
--funx.dump(fontInfo)
--print ("  ")

							------------------------------------------------
							--[[
							 Render a chunk of the text object.
							 Requires all the nice closure variables, so we can't move this very well...
							 This could be a paragraph <p>chunk</p> or a piece of text in a paragraph (<span>chunk</span>)
							 So, we don't know if this requires an end-of-line at the end!

							 A chunk to render is ALWAYS pure text. All HTML formatting is outside it.
							--]]
							----------------
							local function renderChunk()
print ("renderChunk ------------------------------")
								local tempLineWidth, words
								local tempDisplayLine, tempDisplayLineTxt, tempDisplayLineR

								local result = display.newGroup()

								-- Set the reference point to match the text alignment
								textDisplayReferencePoint = display["Bottom"..textAlignment.."ReferencePoint"]

								-- Preserve initial padding before first word
								local  _, _, padding = stringFind(nextChunk, "^(%s*)")
								padding = padding or ""
								local firstWord = true

								-- Get chunks of text to iterate over to figure out line line wrap
								local words

								-- If the line wrapping is cached, get it
								local cachedChunk
								local cachedChunkLine = 1
								if (textwrapIsCached) then
									cachedChunk = cache[cacheChunkCtr]
									--words = string.gmatch(cachedChunk.text, "[^\r\n]+")
									words = iteratorOverCacheText(cachedChunk.text)
								else
									cachedChunk = { text = {}, width = {} }
									words = string.gmatch(nextChunk, "([^%s%-]+)([%s%-]*)")
								end

								local tempLine, allTextInLine

								---------------------------------------------
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
									end
									allTextInLine = prevTextInLine .. tempLine

									-- Grab the first words of the line, until "minLineCharCount" hit
									if (textwrapIsCached or (strlen(allTextInLine) > minLineCharCount)) then

										-- Allow for lines with beginning spaces, for positioning
										if (substring(currentLine,1,1) == ".") then
											currentLine = substring(currentLine,2,-1)
										end

										-- If a word is less than the minimum word length, force it to be with the next word,so lines don't end with single letter words.
										if (not textwrapIsCached and (strlen(allTextInLine) < nextChunkLen) and strlen(word) < minWordLen) then
											shortword = shortword..word..spacer

										else
											if (not textwrapIsCached) then
												-- add a word
												--local tempLine = currentLine..shortword..word..spacer

												-- Draw the text as a line.
												tempDisplayLine = display.newGroup()
												--local tempDisplayLineTxt = display.newText(tempDisplayLine, funx.trim(tempLine), x, 0, font, size)

												tempDisplayLineTxt = display.newText(tempDisplayLine, tempLine, x, 0, font, size)
												tempDisplayLineTxt:setReferencePoint(display.TopLeftReferencePoint)
												tempDisplayLineTxt.x = 0
												tempDisplayLineTxt.y = 0
												tempDisplayLineR = display.newRect(tempDisplayLine, 0,0,1,1)
												tempDisplayLineR:setReferencePoint(display.TopLeftReferencePoint)
												tempDisplayLineR.x = 0
												tempDisplayLineR.y = 0

												-- Is this line of text too long? In which case we render the line
												-- as text, then move down a line on the screen and start again.
												if (renderTextFromMargin) then
													tempLineWidth = tempDisplayLine.width
												else
													tempLineWidth = tempDisplayLine.width + currentXOffset
												end


											else
												-- CACHED LINE
												tempLineWidth = cachedChunk.width[cachedChunkLine]
											end



											if (tempLineWidth <= currentWidth * widthCorrection )  then
												currentLine = tempLine
											else
												if ( maxHeight==0 or (lineY <= maxHeight - currentLineHeight)) then

				-- A: line render
				--[[
				print ()
				print ("------------------------------")
				print ("A: render a line: ["..currentLine.."] (start at margin?)", renderTextFromMargin)
				--]]

													if (isFirstLine) then
														currentLineHeight = 0
														isFirstLine = false
													else
														currentLineHeight = lineHeight
													end

													local xOffset = 0
													-- This new line is at the old line baseline + leading
													if (renderTextFromMargin) then
														lineY = lineY + currentLineHeight
													else
														xOffset = currentXOffset
													end
				--print ("xOffset, currentXOffset",xOffset, currentXOffset)

													if (textwrapIsCached) then
														currentLine = word
													else
														cachedChunk.text[cachedChunkLine] = currentLine
														cachedChunk.width[cachedChunkLine] = tempLineWidth
													end
													cachedChunkLine = cachedChunkLine + 1

													local newDisplayLine = display.newText(currentLine, 0, 0, font, size)
													newDisplayLine:setTextColor(color[1], color[2], color[3])
													newDisplayLine.alpha = opacity
													result:insert(newDisplayLine)
													newDisplayLine:setReferencePoint(textDisplayReferencePoint)
													if (lower(textAlignment) == "Center") then
														newDisplayLine.x = floor(currentWidth/2)  + x + leftIndent + currentFirstLineIndent + xOffset
													elseif (lower(textAlignment) == "right") then
														newDisplayLine.x = x - xOffset
													else
														newDisplayLine.x = x + leftIndent + currentFirstLineIndent + xOffset
													end

													-- record the width of the current line
													-- in case we need to add the next
													-- chunk to the end of it
													--currentXOffset = newDisplayLine.x + newDisplayLine.width
if (testing) then
	print ()
	print ("----------------------------")
	print ("A: Render line: "..currentLine)
	print ("\nRender a line (start at margin?)", renderTextFromMargin)
	print ("isFirstLine", isFirstLine)
	print ("   newDisplayLine.y",lineY + baselineAdjustment, baselineAdjustment)
	print ("   newDisplayLine HEIGHT:",newDisplayLine.height)
	print ("leftIndent + currentFirstLineIndent + xOffset", leftIndent, currentFirstLineIndent, xOffset)
end
													-- Adjust Y to the baseline, not top-left corner of the font bounding-box
													newDisplayLine.y = lineY + baselineAdjustment
													lineCount = lineCount + 1

													-- Use once, then set to zero.
													currentFirstLineIndent = 0

													-- Use the current line to estimate how many chars
													-- we can use to make a line.
													if (not fontInfo.maxHorizontalAdvance) then
														minLineCharCount = strlen(currentLine)
													end

													word = shortword..word

													-- We have wrapped, don't need text from previous chunks of this line.
													prevTextInLine = ""






													-- If next word is not too big to fit the text column, start the new line with it.
													-- Otherwise, make a whole new line from it. Not sure how that would help.
													local wordlen = 0
													if (textwrapIsCached) then
														wordlen = cachedChunk.width[cachedChunkLine]
													else
														wordlen = strlen(word) * (size * fontInfo.maxCharWidth)
													end

													-- *** This is needed so right/center justified lines are correctly positioned!!!
													if (true) then
														local w
														if (renderTextFromMargin) then
															w = currentWidth
														else
															w = newDisplayLine.width
														end

														-- compensate for the stroke
														local r = display.newRect(0,0,w-2,newDisplayLine.height-2)
														r:setStrokeColor(0,250,250,100)
														r.strokeWidth=1
														result:insert(r)
														r:setReferencePoint(textDisplayReferencePoint)
														r.x = newDisplayLine.x+1
														r.y = newDisplayLine.y+1
														r.isVisible = testing
														r:setFillColor(0,255,0,0)

														if (renderTextFromMargin) then
															r:setStrokeColor(0,250,250,100)
														else
															r:setStrokeColor(0,250,50,100)
														end


													end

													-- This line has now wrapped around, and the next one should
													-- start at the margin.
													renderTextFromMargin = true
													currentXOffset = 0

													-- Text lines can vary in height depending on whether there are upper case letters, etc.
													-- Not predictable! So, we capture the height of the first line, and that is the basis of
													-- our y adjustment for the entire block, to position it correctly.
													if (not yAdjustment) then
														--yAdjustment = (size * fontInfo.ascent )- newDisplayLine.height
														yAdjustment = ( (size / fontInfo.sampledFontSize ) * fontInfo.textHeight)- newDisplayLine.height

													end

													if (textwrapIsCached or (wordlen <= currentWidth * widthCorrection) ) then

														if (textwrapIsCached) then
															currentLine = word
														else
															currentLine = word..spacer
														end
													else
														currentLineHeight = lineHeight

														------------------------------------------------------
														------------------------------------------------------
														-- B: Render a short line following a wrapped line.
														------------------------------------------------------

														-- A new line was begun, add to the new line
														--lineY = lineY + currentLineHeight + currentSpaceBefore
														lineY = lineY + currentLineHeight

														if (textwrapIsCached) then
															currentLine = word
														else
															cachedChunk.text[cachedChunkLine] = word
															cachedChunk.width[cachedChunkLine] = wordlen
														end
														cachedChunkLine = cachedChunkLine + 1

--print ("B")
if (testing) then
	print ()
	print ("----------------------------")
	print ("B: render a word: "..word)
	print ("\nrenderTextFromMargin reset to TRUE.")
	print ("isFirstLine", isFirstLine)
	print ("   newDisplayLine.y",lineY + baselineAdjustment, baselineAdjustment)
	print ("   newDisplayLine HEIGHT:",newDisplayLine.height)
	print ("leftIndent + currentFirstLineIndent + xOffset", leftIndent, currentFirstLineIndent, xOffset)
end

														local newDisplayLine = display.newText(word, x, lineY, font, size)
														newDisplayLine:setTextColor(color[1], color[2], color[3])
														newDisplayLine.alpha = opacity
														result:insert(newDisplayLine)
														newDisplayLine:setReferencePoint(textDisplayReferencePoint)

				--print ("textAlignment",textAlignment)
				--print ("x + leftIndent + currentFirstLineIndent + currentXOffset", x, leftIndent, currentFirstLineIndent, currentXOffset)
														if (lower(textAlignment) ~= "right") then
															newDisplayLine.x = x + leftIndent + currentFirstLineIndent + currentXOffset
														else
															newDisplayLine.x = x - currentXOffset
														end
														newDisplayLine.y = lineY + baselineAdjustment
														lineCount = lineCount + 1
														currentLine = ''
--print ("B: newDisplayLine.y",lineY + baselineAdjustment)
														-- This line has now wrapped around, and the next one should
														-- start at the margin.
													-- ????
														--renderTextFromMargin = true
														--currentXOffset = 0

														if (isFirstLine) then
															currentLineHeight = 0
															isFirstLine = false
														else
															-- If this is the first line of a new paragraph, move to next line
															currentLineHeight = lineHeight
														end



													end	-- end B




													-- Get min characters to start with
													-- We now know the max char width in a font,
													-- so we can start with a minimum based on that.
													-- IF the metric was set!
													if (not textwrapIsCached and not fontInfo.maxHorizontalAdvance) then
														-- Get stats for next line
														-- Set the new min char count to the current line length, minus a few for protection
														-- (20 is chosen from a few tests)
														minLineCharCount = max(minLineCharCount - 20,1)
													end

												end
											end

											if (not textwrapIsCached) then
												display.remove(tempDisplayLine);
												tempDisplayLine=nil;
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
								if (substring(currentLine,1,1) == ".") then
									currentLine = substring(currentLine,2,-1)
								end

								-- C: line render
								-------- C: SHORT LINE or FINAL LINE OF PARAGRAPH
								-- Add final line that didn't need wrapping
								-- Add a space to deal with a weirdo bug that was deleting final words. ????

								if (isFirstLine) then
									currentLineHeight = 0
									isFirstLine = false
									lineY = lineY + currentSpaceBefore
								else
									-- If this is the first line of a new paragraph, move to next line
									currentLineHeight = lineHeight

									if (renderTextFromMargin) then
										currentXOffset = 0
										lineY = lineY + currentLineHeight + currentSpaceBefore
									end
								end

								if (not textwrapIsCached) then
									cachedChunk.text[cachedChunkLine] = currentLine
									cachedChunk.width[cachedChunkLine] = currentWidth
								end
								cachedChunkLine = cachedChunkLine + 1


if (testing) then
	print ()
	print ("----------------------------")
	print ("C: Final line: ["..currentLine.."]", strlen(currentLine))
	print ("\nStart at margin)", renderTextFromMargin)
	print ("Previous Line:", "["..prevTextInLine.."]", strlen(prevTextInLine))
	print ("isFirstLine", isFirstLine)
	print ("lineY:",lineY)
	print ("currentSpaceBefore:",currentSpaceBefore)
	if (currentSpaceBefore > 0) then
		print ("************")
	end
end
								-- IF content remains, render it.
								-- It is possible get the tailing space of block
								if (strlen(currentLine) > 0) then

--print ("C: render a line:", currentLine)

									local newDisplayLine = display.newText(currentLine, x, lineY, font, size)
									newDisplayLine.alpha = opacity
									result:insert(newDisplayLine)
									newDisplayLine:setReferencePoint(textDisplayReferencePoint)

									local ta = lower(textAlignment)
--print ("Warning: textwrap has alignment to the left for everything in C section.")
--ta = "left"

									if (ta == "right") then
										newDisplayLine.x = x + currentXOffset
										currentXOffset = newDisplayLine.x - newDisplayLine.width
										--test:
										--newDisplayLine.x = x
										--currentXOffset = newDisplayLine.x + newDisplayLine.width
										--newDisplayLine:setReferencePoint(display["BottomRightReferencePoint"])
									elseif (ta == "center") then
										-- position from left because there is a rect giving us 0,0 positioning
										newDisplayLine.x = x + leftIndent + currentXOffset
										--newDisplayLine.x = floor(currentWidth/2) + leftIndent + firstLineIndent

										currentXOffset = newDisplayLine.x + newDisplayLine.width
									else
										newDisplayLine.x = x + leftIndent + currentXOffset
										currentXOffset = newDisplayLine.x + newDisplayLine.width
									end
									newDisplayLine.y = lineY + baselineAdjustment
									newDisplayLine:setTextColor(color[1], color[2], color[3])

if (testing) then
	print ("C:"..currentLine)
	print ("   newDisplayLine.y",lineY + baselineAdjustment)
	print ("   newDisplayLine HEIGHT:",newDisplayLine.height)
	print ("  ")

	newDisplayLine:setTextColor(0,250,100,255)




end
									-- Save the current line if we started at the margin
									-- So the next line, if it has to, can start where this one ends.
									prevTextInLine = prevTextInLine .. currentLine
									currentLine = ""

									-- Since line heights are not predictable, we capture the yAdjustment based on
									-- the actual height the first rendered line of text
									if (not yAdjustment) then
										--yAdjustment = (size * fontInfo.ascent )- newDisplayLine.height
										yAdjustment = ( (size / fontInfo.sampledFontSize ) * fontInfo.textHeight)- newDisplayLine.height
									end

									-- *** This is needed so right/center justified lines are correctly positioned!!!
									if (true) then
										local w
										if (renderTextFromMargin) then
											w = currentWidth
										else
											w = currentWidth - newDisplayLine.width
										end

										-- compensate for the stroke
										local r = display.newRect(0,0,w-2,newDisplayLine.height-2)
										r:setStrokeColor(250,0,0,100)
										r.strokeWidth=1
										result:insert(r)
										r:setReferencePoint(textDisplayReferencePoint)
										r.x = newDisplayLine.x+1
										r.y = newDisplayLine.y+1
										r.isVisible = testing
										r:setFillColor(0,255,0,0) -- transparent
									end

								end



								cache[cacheChunkCtr] = cachedChunk
								cacheChunkCtr = cacheChunkCtr + 1
								return result
							end

							------------------------------------------------------------
							-- end renderChunk
							------------------------------------------------------------




							local chunk = renderChunk()
							result:insert(chunk)


							-- Restore style settings
							-- If we came in with italics set, then the tag set the font
							-- to bold-italic, this will restore the font back to italic.
							--setStyleSettings(styleSettings)

							return result
						end -- renderParsedElement()

					-- save the style settings as they are before
					-- anything modifies them inside this tag.
					-- *** LOCAL OR NOT??? I USED TO HAVE IT LOCAL, THEN NOT, NOW AGAIN... EEEK!
					local styleSettings = getAllStyleSettings()

					tag, attr = convertHeaders(tag, attr)

					local listIdentDistance = 20

					------------------------------------------------------------
					-- Handle formatting tags: p, div, br
					------------------------------------------------------------

					if (tag == "p" or tag == "div" or tag == "li" or tag == "ul" or tag == "ol") then

						-- Apply style settings
						renderTextFromMargin = true
						currentXOffset = 0
						local styleName = "MISSING"
						if (attr.class) then
							styleName = lower(attr.class)
						end
						if (attr.class) then
							if (myTextStyles and myTextStyles[styleName] ) then
								local params = myTextStyles[styleName]
								setStyleFromCommandLine (params)
							else
								print ("WARNING: funx.autoWrappedText tried to use a missing text style ("..styleName..")")
							end
						end
						setStyleFromTag (tag, attr)

						-- LISTS
						if (tag == "ol" or tag == "ul" ) then
							-- Nested lists require indentation (which isn't happening yet) and a new line.
							local indent = 0
							if (stacks.list[stacks.list.ptr] and stacks.list[stacks.list.ptr].tag) then
								lineY = lineY + lineHeight + currentSpaceAfter
								-- Indent starting at 2nd level
								indent = listIdentDistance
							end
							leftIndent = leftIndent + indent
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
								else
									b = "&#9679;"
								end
								b = entities.convert(b)
							end
							stacks.list[stacks.list.ptr] = { tag = tag, line = 1, bullet = b, indent = indent}
						end

					elseif (tag == "br") then
					end


					-- LIST ITEMS: add a bullet or number
					if (tag == "li") then
						-- default for list is a disk.
						local t = stacks.list[stacks.list.ptr].bullet
						-- If number, use the number instead
						if (stacks.list[stacks.list.ptr].tag == "ol" ) then
							t = stacks.list[stacks.list.ptr].line .. ". "
							stacks.list[stacks.list.ptr].line = stacks.list[stacks.list.ptr].line + 1
						end
						local e = renderParsedElement(1, t, "", "")
						-- Add one to the element counter so the next thing won't be on a new line
						elementCounter = elementCounter + 1
						result:insert(e)
					end


					--endOfLine = false

					for n, element in ipairs(parsedText) do

						--local styleSettings = {}
						if (type(element) == "table") then
							local e = renderParsedText(element, element._tag, element._attr, parseDepth, stacks)
							result:insert(e)
						else
							if (not element) then
								print ("***** WARNING, EMPTY ELEMENT**** ")
							end

							local e = renderParsedElement(n, element, tag, attr)

							result:insert(e)

							elementCounter = elementCounter + 1
						end

					end -- end for

					-- Close tags
					-- AFTER rendering (so add afterspacing!)
					if (tag == "p" or tag == "div") then
						setStyleFromTag (tag, attr)
						renderTextFromMargin = true
						lineY = lineY + currentSpaceAfter
						--lineY = lineY + lineHeight + currentSpaceAfter
			elementCounter = 1
					elseif (tag == "li") then
						setStyleFromTag (tag, attr)
						renderTextFromMargin = true
						lineY = lineY + currentSpaceAfter
			elementCounter = 1
					elseif (tag == "ul") then
						setStyleFromTag (tag, attr)
						renderTextFromMargin = true
						--lineY = lineY + lineHeight + currentSpaceAfter
						--leftIndent = leftIndent - stacks.list[stacks.list.ptr].indent
						stacks.list[stacks.list.ptr] = nil
						stacks.list.ptr = stacks.list.ptr -1
			elementCounter = 1
					elseif (tag == "ol") then
						setStyleFromTag (tag, attr)
						renderTextFromMargin = true
						--lineY = lineY + lineHeight + currentSpaceAfter
						--leftIndent = leftIndent - stacks.list[stacks.list.ptr].indent
						stacks.list[stacks.list.ptr] = nil
						stacks.list.ptr = stacks.list.ptr -1
			elementCounter = 1
					elseif (tag == "br") then
						renderTextFromMargin = true
						currentXOffset = 0
						setStyleFromTag (tag, attr)
						lineY = lineY + currentSpaceAfter
			elementCounter = 1
					elseif (tag == "#document") then
						-- lines from non-HTML text will be tagged #document
						-- and this will handle them.
						renderTextFromMargin = true
						currentXOffset = 0
						setStyleFromTag (tag, attr)
						lineY = lineY + currentSpaceAfter
--			elementCounter = 1
					end

					--print ("Restore style settings", color[1], tag)
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


		end -- html elements for one paragraph

	end

	-----------------------------
	-- Finished rendering all blocks of text (all paragraphs).
	-----------------------------

	result:setReferencePoint(display.CenterReferencePoint)

	--print ("textwrap.lua: yAdjustment is turned OFF because it wasn't working! No idea why.")
	result.yAdjustment = yAdjustment
	--print ("textDisplayReferencePoint",textDisplayReferencePoint)

	saveTextWrapToCache(textUID, cache, cacheDir)

	return result
end

T.autoWrappedText = autoWrappedText

return T