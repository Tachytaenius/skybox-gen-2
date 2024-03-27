return function(canvas, canvasName)
	local info = love.filesystem.getInfo("exports")
	if not info then
		print("Couldn't find exports folder. Creating")
		love.filesystem.createDirectory("exports")
	elseif info.type ~= "directory" then
		print("There is already a non-folder item called exports. Rename it or move it to take a screenshot")
		return
	end

	local dateTime = os.date("%Y-%m-%d %H-%M-%S") -- Can't use colons!

	local currentIdentifier = 1
	local currentPath
	local function generatePath()
		currentPath =
			"exports/" ..
			dateTime .. " " ..
			(canvasName and canvasName .. " " or "") ..
			currentIdentifier ..
			".png"
	end
	generatePath()
	while love.filesystem.getInfo(currentPath) do
		currentIdentifier = currentIdentifier + 1
		generatePath()
	end

	canvas:newImageData():encode("png", currentPath)
end
