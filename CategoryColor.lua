local _, ns = ...
if type(ns) ~= "table" then ns = {} end

local CategoryColor = {}

CategoryColor.MIN_SATURATION = 0.45
CategoryColor.MAX_SATURATION = 0.70
CategoryColor.MIN_VALUE = 0.65
CategoryColor.MAX_VALUE = 0.85
CategoryColor.DEFAULT = { r = 0.45, g = 0.55, b = 0.75 }

local function Channel(value)
	return type(value) == "number" and value >= 0 and value <= 1 and value == value
end

function CategoryColor.IsValid(color)
	return type(color) == "table"
		and Channel(color.r) and Channel(color.g) and Channel(color.b)
end

function CategoryColor.Normalize(color)
	if CategoryColor.IsValid(color) then
		return { r = color.r, g = color.g, b = color.b }
	end
	return { r = CategoryColor.DEFAULT.r, g = CategoryColor.DEFAULT.g,
		b = CategoryColor.DEFAULT.b }
end

function CategoryColor.FromHSV(h, s, v)
	local sector = math.floor(h * 6)
	local fraction = h * 6 - sector
	local p = v * (1 - s)
	local q = v * (1 - fraction * s)
	local t = v * (1 - (1 - fraction) * s)
	sector = sector % 6
	if sector == 0 then return { r = v, g = t, b = p } end
	if sector == 1 then return { r = q, g = v, b = p } end
	if sector == 2 then return { r = p, g = v, b = t } end
	if sector == 3 then return { r = p, g = q, b = v } end
	if sector == 4 then return { r = t, g = p, b = v } end
	return { r = v, g = p, b = q }
end

function CategoryColor.Random(random)
	random = random or math.random
	local h = random()
	local s = CategoryColor.MIN_SATURATION
		+ random() * (CategoryColor.MAX_SATURATION - CategoryColor.MIN_SATURATION)
	local v = CategoryColor.MIN_VALUE
		+ random() * (CategoryColor.MAX_VALUE - CategoryColor.MIN_VALUE)
	return CategoryColor.FromHSV(h, s, v)
end

ns.CategoryColor = CategoryColor
return CategoryColor
