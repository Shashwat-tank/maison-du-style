-- Provides spawn points and clue spots. If the place has no `Workspace.Map`,
-- a simple placeholder arena is generated so the game is playable immediately.
--
-- To use your own map: put a Model/Folder named "Map" in Workspace containing
-- a "Spawns" folder and a "ClueSpots" folder of BaseParts (any shape, invisible is fine).
local MapService = {}

local ARENA_CENTER = Vector3.new(0, 0, 300)
local ARENA_HALF = 60

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

local function markerFolder(parent: Instance, name: string): Folder
	local folder = Instance.new("Folder")
	folder.Name = name
	folder.Parent = parent
	return folder
end

local function ring(radius: number, count: number, angleOffset: number, y: number): { Vector3 }
	local points = {}
	for i = 0, count - 1 do
		local angle = math.rad(angleOffset + (360 / count) * i)
		table.insert(points, ARENA_CENTER + Vector3.new(math.cos(angle) * radius, y, math.sin(angle) * radius))
	end
	return points
end

local function buildLobby()
	if workspace:FindFirstChildWhichIsA("SpawnLocation", true) then
		return
	end
	local lobby = Instance.new("Folder")
	lobby.Name = "Lobby"
	lobby.Parent = workspace
	makePart(lobby, "Floor", Vector3.new(60, 1, 60), Vector3.new(0, 0, 0), Color3.fromRGB(70, 70, 90))

	local spawn = Instance.new("SpawnLocation")
	spawn.Anchored = true
	spawn.Neutral = true
	spawn.Duration = 0
	spawn.Size = Vector3.new(12, 1, 12)
	spawn.Position = Vector3.new(0, 1, 0)
	spawn.Parent = lobby
end

local function buildPlaceholderArena(): Folder
	local map = Instance.new("Folder")
	map.Name = "Map"
	map.Parent = workspace

	local floorColor = Color3.fromRGB(60, 70, 60)
	local wallColor = Color3.fromRGB(45, 45, 55)
	local coverColor = Color3.fromRGB(110, 80, 60)

	makePart(map, "Floor", Vector3.new(ARENA_HALF * 2, 1, ARENA_HALF * 2), ARENA_CENTER, floorColor)

	local wallHeight, wallThickness = 24, 2
	local wallY = wallHeight / 2 + 0.5
	local offset = ARENA_HALF + wallThickness / 2
	local span = ARENA_HALF * 2 + wallThickness * 2
	makePart(map, "WallN", Vector3.new(span, wallHeight, wallThickness), ARENA_CENTER + Vector3.new(0, wallY, offset), wallColor)
	makePart(map, "WallS", Vector3.new(span, wallHeight, wallThickness), ARENA_CENTER + Vector3.new(0, wallY, -offset), wallColor)
	makePart(map, "WallE", Vector3.new(wallThickness, wallHeight, span), ARENA_CENTER + Vector3.new(offset, wallY, 0), wallColor)
	makePart(map, "WallW", Vector3.new(wallThickness, wallHeight, span), ARENA_CENTER + Vector3.new(-offset, wallY, 0), wallColor)

	-- Cover boxes on two rings. Spawns (r=52) and clue spots (r=28) sit between them.
	local rng = Random.new(1337)
	local covers = ring(15, 6, 15, 0)
	for _, position in ipairs(ring(42, 6, 0, 0)) do
		table.insert(covers, position)
	end
	for index, position in ipairs(covers) do
		local height = rng:NextInteger(5, 9)
		local width = rng:NextInteger(5, 8)
		makePart(
			map,
			"Cover" .. index,
			Vector3.new(width, height, width),
			position + Vector3.new(0, height / 2 + 0.5, 0),
			coverColor
		)
	end

	local spawns = markerFolder(map, "Spawns")
	for index, position in ipairs(ring(52, 12, 0, 1)) do
		local marker = makePart(spawns, "Spawn" .. index, Vector3.new(2, 1, 2), position, Color3.new(1, 1, 1))
		marker.Transparency = 1
		marker.CanCollide = false
	end

	local clueSpots = markerFolder(map, "ClueSpots")
	for index, position in ipairs(ring(28, 12, 0, 1)) do
		local marker = makePart(clueSpots, "ClueSpot" .. index, Vector3.new(2, 1, 2), position, Color3.new(1, 1, 1))
		marker.Transparency = 1
		marker.CanCollide = false
	end

	return map
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
