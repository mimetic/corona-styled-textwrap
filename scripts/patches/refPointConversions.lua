local M = {}


function M.convertToGraphics2()
	function setAnchors(obj, pos)
		if 	   pos == display.TopLeftReferencePoint      then obj.anchorX, obj.anchorY = 0, 0
		elseif pos == display.TopCenterReferencePoint    then obj.anchorX, obj.anchorY = 0.5, 0
		elseif pos == display.TopRightReferencePoint     then obj.anchorX, obj.anchorY = 1, 0
		elseif pos == display.CenterLeftReferencePoint   then obj.anchorX, obj.anchorY = 0, 0.5
		elseif pos == display.CenterReferencePoint       then obj.anchorX, obj.anchorY = 0.5, 0.5
		elseif pos == display.CenterRightReferencePoint  then obj.anchorX, obj.anchorY = 1, 0.5
		elseif pos == display.BottomLeftReferencePoint   then obj.anchorX, obj.anchorY = 0, 1
		elseif pos == display.BottomCenterReferencePoint then obj.anchorX, obj.anchorY = 0.5, 1
		elseif pos == display.BottomRightReferencePoint  then obj.anchorX, obj.anchorY = 1, 1
		else obj.anchorX, obj.anchorY = 0.5, 0.5
		end
	end

	display.defaultNewGroup = display.newGroup
	display.defaultNewImageRect = display.newImageRect
	display.defaultNewImage = display.newImage
	display.defaultNewRect = display.newRect
	display.defaultNewRoundedRect = display.newRoundedRect
	display.defaultNewText = display.newText
	display.defaultNewEmbossedText = display.newEmbossedText
	display.defaultNewCircle = display.newCircle
	display.defaultNewLine = display.newLine
	display.defaultNewSprite = display.newSprite

	display.newGroup = function()
		local g = display.defaultNewGroup()
		function g:setReferencePoint(refPoint) setAnchors( self, refPoint ) end
		return g
	end
	display.newImageRect = function(...)
		local imgr = display.defaultNewImageRect(...)
		function imgr:setReferencePoint(refPoint) setAnchors( self, refPoint ) end
		return imgr
	end
	display.newImage = function(...)
		local img = display.defaultNewImage(...)
		function img:setReferencePoint(refPoint) setAnchors( self, refPoint ) end
		return img
	end
	display.newRect = function(...)
		local rect = display.defaultNewRect(...)
		function rect:setReferencePoint(refPoint) setAnchors( self, refPoint ) end
		return rect
	end
	display.newRoundedRect = function(...)
		local rrect = display.defaultNewRoundedRect(...)
		function rrect:setReferencePoint(refPoint) setAnchors( self, refPoint ) end
		return rrect
	end
	display.newText = function(...)
		local txt = display.defaultNewText(...)
		function txt:setReferencePoint(refPoint) setAnchors( self, refPoint ) end
		return txt
	end
	display.newEmbossedText = function(...)
		local etxt = display.defaultNewEmbossedText(...)
		function etxt:setReferencePoint(refPoint) setAnchors( self, refPoint ) end
		return etxt
	end
	display.newCircle = function(...)
		local c = display.defaultNewCircle(...)
		function c:setReferencePoint(refPoint) setAnchors( self, refPoint ) end
		return c
	end
	display.newLine = function(...)
		local l = display.defaultNewLine(...)
		function l:setReferencePoint(refPoint) setAnchors( self, refPoint ) end
		return l
	end
	display.newSprite = function(...)
		local l = display.defaultNewSprite(...)
		function l:setReferencePoint(refPoint) setAnchors( self, refPoint ) end
		return l
	end
end

M.convertToGraphics2()