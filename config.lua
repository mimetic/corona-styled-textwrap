-- config.lua
application =
{
	content =
	{
        width = 768,
        height = 1024,
        scale = "letterbox",
		antialias = false,
		xalign = "center",
		yalign = "center",

		imageSuffix =
		{
            ["@0-5"] = 0.5, -- for smaller devices
            ["@2x"] = 2,    -- for iPad 3
		}
	}
}
