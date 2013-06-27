corona-styled-textwrap
======================

A pure-Lua text rendering module for Corona SDK which can handle basic HTML, fonts, and even basic font metrics.

I've made this library public in the hopes that we can fix the bugs and improve it.

It has a major flaw right now -- it cannot render styled text that is right/center justified.

However, for everything else, it is fantastic. I use it for my ebook app, and it is fast and flexible.


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
local t = textwrap.autoWrappedText(params)


Overview:
