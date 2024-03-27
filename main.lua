-- TODO: Does gamma need handling?

local mathsies = require("lib.mathsies")
local mat4 = mathsies.mat4
local vec3 = mathsies.vec3
local quat = mathsies.quat

local saveCanvas = require("save-canvas")

local tau = math.pi * 2
local forwardVector = vec3(0, 0, 1)
local upVector = vec3(0, 1, 0)
local rightVector = vec3(1, 0, 0)
local skyColour = {0.05, 0.025, 0.075}
local starColour = {1, 1, 1}
local farDistance = 100000
local nearDistance = 0.1
local minStarAngularRadius = 0.002
local maxStarAngularRadius = 0.006
local glowRadiusMultiplier = 30
local skySideSize = 1024

local mouseDx, mouseDy
local stars, camera
local canvas, dummyTexture, starShader, planeMesh
local sideCanvas, outCanvas

local function normaliseOrZero(v)
	local zeroVector = vec3()
	return v == zeroVector and zeroVector or vec3.normalise(v)
end

local function limitVectorLength(v, m)
	local l = #v
	if l > m then
		return normaliseOrZero(v) * m
	end
	return vec3.clone(v)
end

local function randomOnSphere()
	local phi = love.math.random() * tau
	local cosTheta = love.math.random() * 2 - 1

	local theta = math.acos(cosTheta)
	return vec3.fromAngles(theta, phi)
end

local function hsv2rgb(h, s, v)
	if s == 0 then
		return v, v, v
	end
	local _h = h / 60
	local i = math.floor(_h)
	local f = _h - i
	local p = v * (1 - s)
	local q = v * (1 - f * s)
	local t = v * (1 - (1 - f) * s)
	if i == 0 then
		return v, t, p
	elseif i == 1 then
		return q, v, p
	elseif i == 2 then
		return p, v, t
	elseif i == 3 then
		return p, q, v
	elseif i == 4 then
		return t, p, v
	elseif i == 5 then
		return v, p, q
	end
end

local function drawScene(camera)
	local canvas = love.graphics.getCanvas()
	love.graphics.clear(skyColour)
	love.graphics.setShader(starShader)
	love.graphics.setBlendMode("add")

	local perspectiveProjectionMatrix = mat4.perspectiveLeftHanded(
		canvas:getWidth() / canvas:getHeight(),
		camera.verticalFOV,
		farDistance,
		nearDistance
	)
	local cameraMatrix = mat4.camera(camera.position, camera.orientation)
	local cameraMatrixStationary = mat4.camera(vec3(), camera.orientation)
	local worldToScreen = perspectiveProjectionMatrix * cameraMatrix
	local clipToSky = mat4.inverse(perspectiveProjectionMatrix * cameraMatrixStationary)

	for _, star in ipairs(stars) do
		local cameraToStar = star.position - camera.position
		local intensityMultiplier = 1 / vec3.length(cameraToStar) -- Not going to research astronomy/optics/whatever to find the right terms and formulae right now
		local directionToStar = vec3.normalise(cameraToStar)
		local orientation = quat.fromAxisAngle( -- Make star face camera
			vec3.normalise(vec3.cross(forwardVector, directionToStar)) * -- Axis
			math.acos(vec3.dot(directionToStar, forwardVector)) -- Angle
		)
		orientation = orientation * quat.fromAxisAngle( -- Rotate star by per-star angle as it faces camera
			forwardVector * -- Axis
			star.extraRotation -- Angle
		)
		local radius = star.strength * intensityMultiplier
		local angularRadius = math.asin(radius / #cameraToStar)
		local angularRadiusLimited = math.max(minStarAngularRadius, math.min(maxStarAngularRadius, angularRadius))
		local radiusLimited = #cameraToStar * math.sin(angularRadiusLimited) -- The input to sin won't be greater than tau / 4; this will not be a wave
		local modelToWorld = mat4.transform(
			star.position,
			orientation,
			radiusLimited
		)
		local modelToScreen = worldToScreen * modelToWorld
		starShader:send("modelToScreen", {mat4.components(modelToScreen)})
		love.graphics.setColor(starColour)
		starShader:send("fade", false)
		love.graphics.draw(planeMesh)
		local modelToWorld = mat4.transform(
			star.position,
			orientation,
			radiusLimited * glowRadiusMultiplier
		)
		local modelToScreen = worldToScreen * modelToWorld
		starShader:send("modelToScreen", {mat4.components(modelToScreen)})
		love.graphics.setColor(star.glowColour)
		starShader:send("fade", true)
		love.graphics.draw(planeMesh)
	end
	love.graphics.setColor(1, 1, 1)

	love.graphics.setBlendMode("alpha", "alphamultiply")
	love.graphics.setShader()
end

local function export()
	local function getCamera(rotation)
		return {
			position = camera.position,
			orientation = camera.orientation * quat.fromAxisAngle(rotation),
			verticalFOV = tau / 4
		}
	end

	love.graphics.setCanvas(outCanvas)
	love.graphics.clear()

	-- Forward
	love.graphics.setCanvas(sideCanvas)
	drawScene(getCamera(vec3(0, 0, 0)))
	love.graphics.setCanvas(outCanvas)
	love.graphics.draw(sideCanvas, skySideSize * 1, skySideSize * (1 + 1), 0, 1, -1)

	-- Backward
	love.graphics.setCanvas(sideCanvas)
	drawScene(getCamera(vec3(0, tau / 2, 0)))
	love.graphics.setCanvas(outCanvas)
	love.graphics.draw(sideCanvas, skySideSize * 2, skySideSize * (0 + 1), 0, 1, -1)

	-- Left
	love.graphics.setCanvas(sideCanvas)
	drawScene(getCamera(vec3(0, -tau / 4, 0)))
	love.graphics.setCanvas(outCanvas)
	love.graphics.draw(sideCanvas, skySideSize * 0, skySideSize * (1 + 1), 0, 1, -1)

	-- Right
	love.graphics.setCanvas(sideCanvas)
	drawScene(getCamera(vec3(0, tau / 4, 0)))
	love.graphics.setCanvas(outCanvas)
	love.graphics.draw(sideCanvas, skySideSize * 2, skySideSize * (1 + 1), 0, 1, -1)

	-- Top
	love.graphics.setCanvas(sideCanvas)
	drawScene(getCamera(vec3(-tau / 4, 0, 0)))
	love.graphics.setCanvas(outCanvas)
	love.graphics.draw(sideCanvas, skySideSize * 1, skySideSize * (0 + 1), 0, 1, -1)

	-- Bottom
	love.graphics.setCanvas(sideCanvas)
	drawScene(getCamera(vec3(tau / 4, 0, 0)))
	love.graphics.setCanvas(outCanvas)
	love.graphics.draw(sideCanvas, skySideSize * 0, skySideSize * (0 + 1), 0, 1, -1)

	love.graphics.setCanvas()
	saveCanvas(outCanvas, "export")
end

function love.keypressed(key)
	if key == "x" then
		export()
	end
end

function love.load(args)
	local numStars = tonumber(args[1]) or 2000
	local starSphereRadius = tonumber(args[2]) or 1000
	local starSphereSquashZ = tonumber(args[3]) or 0.2
	local minStarStrength = tonumber(args[4]) or 1
	local maxStarStrength = tonumber(args[5]) or 400
	local starStrengthPower = tonumber(args[6]) or 4
	local sphereOffsetX = tonumber(args[7]) or 500
	local sphereOffsetY = tonumber(args[8]) or 0
	local sphereOffsetZ = tonumber(args[9]) or 0
	local centreDistancePower = tonumber(args[10]) or (1 / 3) -- 1 / 3 is uniform, below pushes them outwards, above pushes them towards the centre
	local baseGlowHue = tonumber(args[11]) or 45
	local glowHueRandomisationPower = tonumber(args[12]) or 3
	local glowSaturation = tonumber(args[13]) or 0.75
	local glowValue = tonumber(args[14]) or 0.05
	local unsquishedStarChance = tonumber(args[15]) or 0.25

	local sphereOffset = vec3(sphereOffsetX, sphereOffsetY, sphereOffsetZ)

	stars = {}
	for i = 1, numStars do
		local distanceFactor = love.math.random() ^ centreDistancePower
		stars[i] = {
			position = randomOnSphere() * distanceFactor * starSphereRadius * vec3(1, 1, love.math.random() < unsquishedStarChance and 1 or starSphereSquashZ) + sphereOffset,
			strength = love.math.random() ^ (starStrengthPower * (1 - distanceFactor)) * (maxStarStrength - minStarStrength) + minStarStrength,
			colour = {1, 1, 1},
			glowColour = {hsv2rgb(
				(baseGlowHue + 360 * love.math.random() ^ glowHueRandomisationPower) % 360,
				glowSaturation,
				glowValue
			)},
			extraRotation = love.math.random() * tau
		}
	end

	camera = {
		position = vec3(),
		orientation = quat.normalise(quat(-0.42, 0.53, -0.71, 0.17)),
		verticalFOV = math.rad(70)
	}

	canvas = love.graphics.newCanvas(love.graphics.getDimensions())
	dummyTexture = love.graphics.newImage(love.image.newImageData(1, 1))
	starShader = love.graphics.newShader("star.glsl")
	planeMesh = love.graphics.newMesh(
		{
			{"VertexPosition", "float", 3},
			{"VertexTexCoord", "float", 2}
		},
		{
			{-1, -1, 0, 0, 0},
			{-1, 1, 0, 0, 1},
			{1, -1, 0, 1, 0},
			{-1, 1, 0, 0, 1},
			{1, -1, 0, 1, 0},
			{1, 1, 0, 1, 1}
		},
		"triangles",
		"static"
	)
	sideCanvas = love.graphics.newCanvas(skySideSize, skySideSize)
	outCanvas = love.graphics.newCanvas(skySideSize * 3, skySideSize * 2)
end

function love.mousemoved(_, _, dx, dy)
	mouseDx, mouseDy = dx, dy
end

function love.mousepressed()
	love.mouse.setRelativeMode(not love.mouse.getRelativeMode())
end

function love.update(dt)
	if not (mouseDx and mouseDy) or love.mouse.getRelativeMode() == false then
		mouseDx = 0
		mouseDy = 0
	end

	local speed = love.keyboard.isDown("lshift") and 200 or 50
	local translation = vec3()
	if love.keyboard.isDown("d") then translation = translation + rightVector end
	if love.keyboard.isDown("a") then translation = translation - rightVector end
	if love.keyboard.isDown("e") then translation = translation + upVector end
	if love.keyboard.isDown("q") then translation = translation - upVector end
	if love.keyboard.isDown("w") then translation = translation + forwardVector end
	if love.keyboard.isDown("s") then translation = translation - forwardVector end
	camera.position = camera.position + vec3.rotate(normaliseOrZero(translation) * speed, camera.orientation) * dt

	local maxAngularSpeed = tau * 2
	local keyboardRotationSpeed = tau / 4
	local keyboardRotationMultiplier = keyboardRotationSpeed / maxAngularSpeed
	local mouseMovementForMaxSpeed = 2.5
	local mouseMovementMultiplier = 1 / (mouseMovementForMaxSpeed * maxAngularSpeed)
	local rotation = vec3()
	if love.keyboard.isDown("k") then rotation = rotation + rightVector * keyboardRotationMultiplier end
	if love.keyboard.isDown("i") then rotation = rotation - rightVector * keyboardRotationMultiplier end
	if love.keyboard.isDown("l") then rotation = rotation + upVector * keyboardRotationMultiplier end
	if love.keyboard.isDown("j") then rotation = rotation - upVector * keyboardRotationMultiplier end
	if love.keyboard.isDown("u") then rotation = rotation + forwardVector * keyboardRotationMultiplier end
	if love.keyboard.isDown("o") then rotation = rotation - forwardVector * keyboardRotationMultiplier end
	rotation = rotation + upVector * mouseDx * mouseMovementMultiplier
	rotation = rotation + rightVector * mouseDy * mouseMovementMultiplier
	camera.orientation = quat.normalise(camera.orientation * quat.fromAxisAngle(limitVectorLength(rotation, 1) * maxAngularSpeed * dt))

	mouseDx, mouseDy = nil, nil
end

function love.draw()
	love.graphics.setCanvas(canvas)
	drawScene(camera)
	love.graphics.setCanvas()
	love.graphics.draw(canvas, 0, love.graphics.getHeight(), 0, 1, -1)
end
