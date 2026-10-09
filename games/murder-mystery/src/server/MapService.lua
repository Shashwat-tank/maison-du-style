-- Provides spawn points and clue spots. If the place has no `Workspace.Map`,
-- a placeholder arena is generated so the game is playable immediately.
--
-- To use your own map: put a Model/Folder named "Map" in Workspace containing
-- a "Spawns" folder and a "ClueSpots" folder of BaseParts (any shape, invisible
-- is fine). Only their positions are used.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("Shared").Config)

local MapService = {}

local ARENA_CENTER = Vector3.new(0, 0, 300)
local HALF = Config.Arena.HalfSize

-- Rings of {radiusFraction, count, angleOffset}. Radii are fractions of HALF so
-- that changing Config.Arena.HalfSize rescales the whole layout. Cover rings sit
-- between the spawn and clue rings, so nobody spawns boxed in.
local COVER_RINGS = { { 0.23, 6, 0 }, { 0.47, 9, 20 }, { 0.71, 12, 10 }, { 0.86, 14, 25 } }
local SPAWN_RING = { 0.95, 14, 12 }
local CLUE_RINGS = { { 0.36, 8, 15 }, { 0.60, 10, 5 }, { 0.80, 10, 20 } }

-- Cover footprints are fractions of HALF too, which keeps the outermost ring
-- clear of the wall at any map size: 0.86 + 0.11 < 1. Heights stay absolute,
-- since what matters there is the character, not the map.
local WALL_LENGTH = { 0.13, 0.22 }
local BLOCK_WIDTH = { 0.055, 0.09 }
local COVER_HEIGHT = { 7, 13 }

local function makePart(parent: Instance, name: string, size: Vector3, position: Vector3, color: Color3): Part
	local part = Instance.new("Part")
	part.Name = name
	part.Anchored = true
	part.Size = size
	part.Position = position
	part.Color = color
	part.Material = Enum.Material.SmoothPlastic
	part.Parent = parent
	return part
end

local function pointOnRing(radiusFraction: number, angleDeg: number, y: number): Vector3
	local angle = math.rad(angleDeg)
	local radius = HALF * radiusFraction
	return ARENA_CENTER + Vector3.new(math.cos(angle) * radius, y, math.sin(angle) * radius)
end

local function makeFolder(parent: Instance, name: string): Folder
	local folder = Instance.new("Folder")
	folder.Name = name
	folder.Parent = parent
	return folder
end

local function addMarkers(folder: Folder, prefix: string, spec: { number }, startIndex: number): number
	local radiusFraction, count, offset = spec[1], spec[2], spec[3]
	for i = 0, count - 1 do
		local position = pointOnRing(radiusFraction, offset + (360 / count) * i, 1)
		local marker = makePart(folder, prefix .. (startIndex + i), Vector3.new(2, 1, 2), position, Color3.new(1, 1, 1))
		marker.Transparency = 1
		marker.CanCollide = false
	end
	return startIndex + count
end

local function buildLobby()
	if workspace:FindFirstChildWhichIsA("SpawnLocation", true) then
		return
	end
	local lobby = makeFolder(workspace, "Lobby")
	makePart(lobby, "Floor", Vector3.new(60, 1, 60), Vector3.new(0, 0, 0), Color3.fromRGB(70, 70, 90))

	local spawn = Instance.new("SpawnLocation")
	spawn.Anchored = true
	spawn.Neutral = true
	spawn.Duration = 0
	spawn.Size = Vector3.new(12, 1, 12)
	spawn.Position = Vector3.new(0, 1, 0)
	spawn.Parent = lobby
end

-- Mixes squat blocks with long thin walls. The walls break sightlines across the
-- open floor, which is what makes hiding possible on a map this size.
local function addCover(map: Folder)
	local rng = Random.new(1337)
	local index = 0
	for _, spec in ipairs(COVER_RINGS) do
		local radiusFraction, count, offset = spec[1], spec[2], spec[3]
		for i = 0, count - 1 do
			index += 1
			local angleDeg = offset + (360 / count) * i
			local position = pointOnRing(radiusFraction, angleDeg, 0)

			local height = rng:NextInteger(COVER_HEIGHT[1], COVER_HEIGHT[2])
			local size
			if rng:NextNumber() < 0.4 then
				size = Vector3.new(HALF * rng:NextNumber(WALL_LENGTH[1], WALL_LENGTH[2]), height, 2)
			else
				size = Vector3.new(
					HALF * rng:NextNumber(BLOCK_WIDTH[1], BLOCK_WIDTH[2]),
					height,
					HALF * rng:NextNumber(BLOCK_WIDTH[1], BLOCK_WIDTH[2])
				)
			end

			local part = makePart(
				map,
				"Cover" .. index,
				size,
				position + Vector3.new(0, height / 2 + 0.5, 0),
				Color3.fromRGB(110, 80, 60)
			)
			-- Roughly tangent to the ring, jittered so the layout does not read
			-- as a perfect circle.
			part.CFrame = CFrame.new(part.Position)
				* CFrame.Angles(0, -math.rad(angleDeg) + math.rad(rng:NextInteger(-35, 35)), 0)
		end
	end
end

local function buildPlaceholderArena()
	local map = makeFolder(workspace, "Map")

	makePart(map, "Floor", Vector3.new(HALF * 2, 1, HALF * 2), ARENA_CENTER, Color3.fromRGB(60, 70, 60))

	local wallHeight, thickness = Config.Arena.WallHeight, 2
	local wallY = wallHeight / 2 + 0.5
	local offset = HALF + thickness / 2
	local span = HALF * 2 + thickness * 2
	local wallColor = Color3.fromRGB(45, 45, 55)
	makePart(map, "WallN", Vector3.new(span, wallHeight, thickness), ARENA_CENTER + Vector3.new(0, wallY, offset), wallColor)
	makePart(map, "WallS", Vector3.new(span, wallHeight, thickness), ARENA_CENTER + Vector3.new(0, wallY, -offset), wallColor)
	makePart(map, "WallE", Vector3.new(thickness, wallHeight, span), ARENA_CENTER + Vector3.new(offset, wallY, 0), wallColor)
	makePart(map, "WallW", Vector3.new(thickness, wallHeight, span), ARENA_CENTER + Vector3.new(-offset, wallY, 0), wallColor)

	addCover(map)

	addMarkers(makeFolder(map, "Spawns"), "Spawn", SPAWN_RING, 1)

	local clueSpots = makeFolder(map, "ClueSpots")
	local nextIndex = 1
	for _, spec in ipairs(CLUE_RINGS) do
		nextIndex = addMarkers(clueSpots, "ClueSpot", spec, nextIndex)
	end
end

function MapService.ensure()
	buildLobby()
	if not workspace:FindFirstChild("Map") then
		buildPlaceholderArena()
	end
end

local function positionsIn(folderName: string): { Vector3 }
	local map = workspace:FindFirstChild("Map")
	local folder = map and map:FindFirstChild(folderName)
	local positions = {}
	if folder then
		for _, child in ipairs(folder:GetChildren()) do
			if child:IsA("BasePart") then
				table.insert(positions, child.Position)
			end
		end
	end
	return positions
end

function MapService.getSpawns(): { Vector3 }
	return positionsIn("Spawns")
end

function MapService.getClueSpots(): { Vector3 }
	return positionsIn("ClueSpots")
end

return MapService
