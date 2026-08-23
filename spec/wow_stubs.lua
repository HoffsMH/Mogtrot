-- The whole WoW mock. Two string helpers is all the extracted modules touch; if
-- this file starts growing, the module that made it grow is not pure yet.

-- Blizzard's strtrim defaults to this character set.
local DEFAULT_TRIM = " \t\r\n"

function strtrim(s, chars)
	chars = chars or DEFAULT_TRIM
	local class = "[" .. chars:gsub("(%W)", "%%%1") .. "]"
	return (s:gsub("^" .. class .. "*", ""):gsub(class .. "*$", ""))
end

strlower = string.lower
