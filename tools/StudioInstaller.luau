--!nocheck
-- Maison du Style - Murder Mystery: one-paste Studio installer.
--
-- GENERATED FILE - do not edit by hand.
-- Regenerate with: python3 tools/build_installer.py
--
-- HOW TO USE
--   1. Open Roblox Studio and create a new Baseplate place.
--   2. View tab -> Command Bar. Also open View -> Output to see errors later.
--   3. Paste this whole file into the Command Bar and press Enter.
--   4. Test tab -> Clients and Servers -> Players: 2 -> Start.
--
-- If the paste collapses into one line, the Command Bar has stripped the
-- newlines and this will not work. Use the .rbxmx files in tools/rbxmx instead.
--
-- Re-running this is safe: it replaces its own previous install. It never
-- touches Workspace, so a map you built yourself is left alone.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local StarterPlayer = game:GetService("StarterPlayer")

local ROOTS = {
	ReplicatedStorage = ReplicatedStorage,
	ServerScriptService = ServerScriptService,
	StarterPlayerScripts = StarterPlayer:FindFirstChildOfClass("StarterPlayerScripts")
		or StarterPlayer:WaitForChild("StarterPlayerScripts"),
}


local ENTRIES = {
	{
		root = "ReplicatedStorage",
		name = "Shared",
		class = "Folder",
	},
	{
		root = "ReplicatedStorage",
		parent = "Shared",
		name = "Config",
		class = "ModuleScript",
		source = [==[
local RunService = game:GetService("RunService")

local Config = {
	-- Fewer players are needed in Studio so you can test with 2 local clients.
	MinPlayers = RunService:IsStudio() and 2 or 3,

	IntermissionSeconds = 20,
	RoundSeconds = 180,
	EndScreenSeconds = 8,
	LobbyRespawnSeconds = 3,

	-- Combat
	StabRange = 7,
	StabCooldown = 1,
	ShotRange = 300,
	ShotCooldown = 4,

	-- Clues
	ClueCount = 10,

	-- Arena. HalfSize is half the floor width, so the floor is twice this across.
	-- Raise it for a bigger map; cover, spawns and clue spots scale with it.
	Arena = {
		HalfSize = 110,
		WallHeight = 26,
	},

	Rewards = {
		InnocentWin = 25,
		MurdererWin = 50,
	},

	Roles = {
		Murderer = "Murderer",
		Detective = "Detective",
		Innocent = "Innocent",
	},

	Winners = {
		Murderer = "Murderer",
		Innocents = "Innocents",
	},

	RemoteNames = { "RoleAssigned", "ClueFound", "RoundEnded", "Shoot" },
}

return Config
]==],
	},
	{
		root = "ReplicatedStorage",
		parent = "Shared",
		name = "Remotes",
		class = "ModuleScript",
		source = [==[
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Remotes = {}

local function getFolder()
	if RunService:IsServer() then
		local folder = ReplicatedStorage:FindFirstChild("Remotes")
		if not folder then
			folder = Instance.new("Folder")
			folder.Name = "Remotes"
			folder.Parent = ReplicatedStorage
		end
		return folder
	end
	return ReplicatedStorage:WaitForChild("Remotes")
end

-- Server: creates the RemoteEvent if missing. Client: waits for it to exist.
function Remotes.get(name: string): RemoteEvent
	local folder = getFolder()
	if RunService:IsServer() then
		local remote = folder:FindFirstChild(name)
		if not remote then
			remote = Instance.new("RemoteEvent")
			remote.Name = name
			remote.Parent = folder
		end
		return remote
	end
	return folder:WaitForChild(name)
end

return Remotes
]==],
	},
	{
		root = "ReplicatedStorage",
		parent = "Shared",
		name = "Util",
		class = "ModuleScript",
		source = [==[
local Util = {}

local rng = Random.new()

-- In-place Fisher-Yates shuffle. Returns the same list for chaining.
function Util.shuffle(list: { any }): { any }
	for i = #list, 2, -1 do
		local j = rng:NextInteger(1, i)
		list[i], list[j] = list[j], list[i]
	end
	return list
end

return Util
]==],
	},
	{
		root = "ServerScriptService",
		name = "Server",
		class = "Script",
		source = [==[
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- The round manager decides when characters spawn.
Players.CharacterAutoLoads = false

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Remotes = require(Shared.Remotes)

-- Create every remote up front so clients can WaitForChild them.
for _, name in ipairs(Config.RemoteNames) do
	Remotes.get(name)
end

local MapService = require(script.MapService)
local CombatService = require(script.CombatService)
local RoundManager = require(script.RoundManager)

MapService.ensure()
CombatService.init()
RoundManager.start()
]==],
	},
	{
		root = "ServerScriptService",
		parent = "Server",
		name = "ClueService",
		class = "ModuleScript",
		source = [==[
-- The clue system is what makes this game different from a plain "hunt the killer" loop.
--
-- Clues spawn around the map. When an innocent examines one, the murderer's display name
-- is partly revealed to everyone ("_ a _ _ o _"), one more letter per clue. The murderer
-- can examine clues too, but that destroys them without revealing anything.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Remotes = require(Shared.Remotes)
local Util = require(Shared.Util)

local RoleService = require(script.Parent.RoleService)
local RoundState = require(script.Parent.RoundState)
local MapService = require(script.Parent.MapService)

local ClueService = {}

type Session = {
	chars: { string },
	order: { number }, -- reveal order (indices into chars)
	revealedCount: number,
	maxReveal: number,
}

local clues: { Instance } = {}
local session: Session? = nil

local function splitChars(text: string): { string }
	local chars = {}
	for _, codepoint in utf8.codes(text) do
		table.insert(chars, utf8.char(codepoint))
	end
	return chars
end

local function buildMask(current: Session): string
	local revealed = {}
	for i = 1, current.revealedCount do
		revealed[current.order[i]] = true
	end
	local out = {}
	for index, char in ipairs(current.chars) do
		table.insert(out, revealed[index] and char or "_")
	end
	return table.concat(out, " ")
end

local function onExamined(clue: Instance, player: Player)
	local current = session
	if not current or not RoundState.isInRound() then
		return
	end
	local role = RoleService.get(player)
	if not role or not RoleService.aliveHumanoid(player) then
		return
	end
	if not clue.Parent then
		return -- someone else got there first
	end

	local remote = Remotes.get("ClueFound")
	clue:Destroy()

	if role == Config.Roles.Murderer then
		remote:FireClient(player, "You destroyed a clue.", nil)
		return
	end

	if current.revealedCount >= current.maxReveal then
		remote:FireClient(player, "This clue tells you nothing new.", nil)
		return
	end

	current.revealedCount += 1
	local mask = buildMask(current)
	local message = player.DisplayName .. " found a clue!"
	for _, participant in ipairs(RoleService.participants()) do
		remote:FireClient(participant, message, mask)
	end
end

local function spawnClue(position: Vector3)
	local clue = Instance.new("Part")
	clue.Name = "Clue"
	clue.Shape = Enum.PartType.Ball
	clue.Size = Vector3.new(1.5, 1.5, 1.5)
	clue.Anchored = true
	clue.CanCollide = false
	clue.Material = Enum.Material.Neon
	clue.Color = Color3.fromRGB(255, 205, 80)
	clue.Position = position + Vector3.new(0, 1, 0)

	local prompt = Instance.new("ProximityPrompt")
	prompt.ActionText = "Examine"
	prompt.ObjectText = "Clue"
	prompt.HoldDuration = 0.5
	prompt.MaxActivationDistance = 8
	prompt.RequiresLineOfSight = false
	prompt.Triggered:Connect(function(player)
		onExamined(clue, player)
	end)
	prompt.Parent = clue

	clue.Parent = workspace
	table.insert(clues, clue)
end

function ClueService.start(murderer: Player)
	ClueService.stop()

	local chars = splitChars(murderer.DisplayName)
	local order = {}
	for index = 1, #chars do
		table.insert(order, index)
	end
	Util.shuffle(order)

	session = {
		chars = chars,
		order = order,
		revealedCount = 0,
		-- Never reveal more than half the name, so it stays a puzzle.
		maxReveal = math.max(1, #chars // 2),
	}

	local spots = Util.shuffle(MapService.getClueSpots())
	for index = 1, math.min(Config.ClueCount, #spots) do
		spawnClue(spots[index])
	end
end

function ClueService.stop()
	for _, clue in ipairs(clues) do
		clue:Destroy()
	end
	table.clear(clues)
	session = nil
end

return ClueService
]==],
	},
	{
		root = "ServerScriptService",
		parent = "Server",
		name = "CombatService",
		class = "ModuleScript",
		source = [==[
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Remotes = require(Shared.Remotes)

local RoleService = require(script.Parent.RoleService)
local RoundState = require(script.Parent.RoundState)

local CombatService = {}

-- Weak keys so entries disappear when a player leaves.
local lastStab: { [Player]: number } = setmetatable({}, { __mode = "k" })
local lastShot: { [Player]: number } = setmetatable({}, { __mode = "k" })

local function makeTool(name: string, handleSize: Vector3, color: Color3): Tool
	local tool = Instance.new("Tool")
	tool.Name = name
	tool.CanBeDropped = false
	tool.RequiresHandle = true

	local handle = Instance.new("Part")
	handle.Name = "Handle"
	handle.Size = handleSize
	handle.Color = color
	handle.Material = Enum.Material.Metal
	handle.Parent = tool

	return tool
end

local function giveAndEquip(player: Player, tool: Tool)
	local backpack = player:FindFirstChildOfClass("Backpack")
	if not backpack then
		tool:Destroy()
		return
	end
	tool.Parent = backpack
	local humanoid = RoleService.aliveHumanoid(player)
	if humanoid then
		humanoid:EquipTool(tool)
	end
end

local function stab(player: Player)
	if not RoundState.isInRound() or RoleService.get(player) ~= Config.Roles.Murderer then
		return
	end
	if not RoleService.aliveHumanoid(player) then
		return
	end

	local now = os.clock()
	if now - (lastStab[player] or 0) < Config.StabCooldown then
		return
	end
	lastStab[player] = now

	local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
	if not root then
		return
	end

	-- Hit the nearest living player within range and roughly in front of us.
	local bestHumanoid: Humanoid? = nil
	local bestDistance = Config.StabRange
	for _, other in ipairs(RoleService.participants()) do
		if other ~= player then
			local humanoid = RoleService.aliveHumanoid(other)
			local otherRoot = humanoid and other.Character and other.Character:FindFirstChild("HumanoidRootPart")
			if otherRoot then
				local offset = otherRoot.Position - root.Position
				local distance = offset.Magnitude
				local inFront = distance < 1 or offset.Unit:Dot(root.CFrame.LookVector) > 0.2
				if distance <= bestDistance and inFront then
					bestDistance = distance
					bestHumanoid = humanoid
				end
			end
		end
	end

	if bestHumanoid then
		bestHumanoid.Health = 0
	end
end

local function shoot(player: Player, aimPosition: any)
	-- Never trust the client: validate the argument type and magnitude.
	if typeof(aimPosition) ~= "Vector3" then
		return
	end
	if not RoundState.isInRound() or RoleService.get(player) ~= Config.Roles.Detective then
		return
	end
	if not RoleService.aliveHumanoid(player) then
		return
	end

	local now = os.clock()
	if now - (lastShot[player] or 0) < Config.ShotCooldown then
		return
	end
	lastShot[player] = now

	local character = player.Character
	local head = character and character:FindFirstChild("Head")
	if not head then
		return
	end

	local direction = aimPosition - head.Position
	local magnitude = direction.Magnitude
	if not (magnitude >= 1 and magnitude < 1e5) then -- also rejects NaN / inf
		return
	end

	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { character }
	local result = workspace:Raycast(head.Position, direction.Unit * Config.ShotRange, params)
	if not result then
		return
	end

	local model = result.Instance:FindFirstAncestorOfClass("Model")
	local victim = model and Players:GetPlayerFromCharacter(model)
	local victimRole = victim and RoleService.get(victim)
	local victimHumanoid = victim and RoleService.aliveHumanoid(victim)
	if not victim or not victimRole or not victimHumanoid then
		return
	end

	victimHumanoid.Health = 0

	-- Shooting an innocent is fatal for the detective too.
	if victimRole ~= Config.Roles.Murderer then
		local selfHumanoid = RoleService.aliveHumanoid(player)
		if selfHumanoid then
			selfHumanoid.Health = 0
		end
	end
end

function CombatService.giveKnife(player: Player)
	local tool = makeTool("Knife", Vector3.new(0.4, 0.4, 3), Color3.fromRGB(200, 40, 40))
	tool.Activated:Connect(function()
		stab(player)
	end)
	giveAndEquip(player, tool)
end

function CombatService.giveGun(player: Player)
	-- The client reads the "Revolver" name to hook up aiming (see GunController).
	local tool = makeTool("Revolver", Vector3.new(0.4, 0.8, 1.6), Color3.fromRGB(60, 60, 200))
	giveAndEquip(player, tool)
end

function CombatService.init()
	Remotes.get("Shoot").OnServerEvent:Connect(shoot)
end

return CombatService
]==],
	},
	{
		root = "ServerScriptService",
		parent = "Server",
		name = "MapService",
		class = "ModuleScript",
		source = [==[
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
]==],
	},
	{
		root = "ServerScriptService",
		parent = "Server",
		name = "RoleService",
		class = "ModuleScript",
		source = [==[
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Util = require(Shared.Util)

local RoleService = {}

-- Roles are server-only. Each client is told only its own role.
local roles: { [Player]: string } = {}

function RoleService.assign(players: { Player })
	table.clear(roles)
	local pool = Util.shuffle(table.clone(players))
	for index, player in ipairs(pool) do
		if index == 1 then
			roles[player] = Config.Roles.Murderer
		elseif index == 2 and #pool >= 3 then
			roles[player] = Config.Roles.Detective
		else
			roles[player] = Config.Roles.Innocent
		end
	end
end

function RoleService.get(player: Player): string?
	return roles[player]
end

function RoleService.remove(player: Player)
	roles[player] = nil
end

function RoleService.clear()
	table.clear(roles)
end

function RoleService.participants(): { Player }
	local list = {}
	for player in pairs(roles) do
		table.insert(list, player)
	end
	return list
end

function RoleService.findByRole(role: string): Player?
	for player, assigned in pairs(roles) do
		if assigned == role then
			return player
		end
	end
	return nil
end

function RoleService.aliveHumanoid(player: Player): Humanoid?
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if humanoid and humanoid.Health > 0 then
		return humanoid
	end
	return nil
end

return RoleService
]==],
	},
	{
		root = "ServerScriptService",
		parent = "Server",
		name = "RoundManager",
		class = "ModuleScript",
		source = [==[
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Remotes = require(Shared.Remotes)
local Util = require(Shared.Util)

local RoundState = require(script.Parent.RoundState)
local RoleService = require(script.Parent.RoleService)
local MapService = require(script.Parent.MapService)
local CombatService = require(script.Parent.CombatService)
local ClueService = require(script.Parent.ClueService)

local RoundManager = {}

local function addCoins(player: Player, amount: number)
	local stats = player:FindFirstChild("leaderstats")
	local coins = stats and stats:FindFirstChild("Coins")
	if coins then
		coins.Value += amount
	end
end

-- Lobby respawn: players who die outside a round (or who aren't in it) come back after a short delay.
local function setupPlayer(player: Player)
	local stats = Instance.new("Folder")
	stats.Name = "leaderstats"
	local coins = Instance.new("IntValue")
	coins.Name = "Coins"
	coins.Parent = stats
	stats.Parent = player

	player.CharacterAdded:Connect(function(character)
		local humanoid = character:WaitForChild("Humanoid")
		humanoid.Died:Connect(function()
			if RoleService.get(player) then
				return -- in a round: stay dead until it ends
			end
			task.delay(Config.LobbyRespawnSeconds, function()
				if player.Parent and not RoleService.get(player) then
					player:LoadCharacter()
				end
			end)
		end)
	end)

	player:LoadCharacter()
end

local function resetToLobby()
	ClueService.stop()
	RoleService.clear()
	for _, player in ipairs(Players:GetPlayers()) do
		task.spawn(function()
			player:LoadCharacter()
		end)
	end
end

local function waitForPlayers()
	while true do
		if #Players:GetPlayers() >= Config.MinPlayers then
			local stillEnough = true
			for remaining = Config.IntermissionSeconds, 1, -1 do
				if #Players:GetPlayers() < Config.MinPlayers then
					stillEnough = false
					break
				end
				RoundState.set("Intermission")
				RoundState.setTimeLeft(remaining)
				task.wait(1)
			end
			if stillEnough then
				return
			end
		end
		RoundState.set("Waiting")
		task.wait(1)
	end
end

-- Returns true when the round actually started.
local function startRound(): boolean
	RoundState.set("Starting")

	local participants = Players:GetPlayers()
	RoleService.assign(participants)

	local spawns = Util.shuffle(MapService.getSpawns())
	for index, player in ipairs(participants) do
		if player.Parent then
			player:LoadCharacter()
			local character = player.Character
			local root = character and character:WaitForChild("HumanoidRootPart", 5)
			if root and #spawns > 0 then
				local spawnPosition = spawns[(index - 1) % #spawns + 1]
				character:PivotTo(CFrame.new(spawnPosition + Vector3.new(0, 3, 0)))
			end
		end
	end

	-- Players may have left while characters were loading.
	local murderer = RoleService.findByRole(Config.Roles.Murderer)
	if not murderer or #RoleService.participants() < 2 then
		resetToLobby()
		return false
	end

	local roleRemote = Remotes.get("RoleAssigned")
	for _, player in ipairs(RoleService.participants()) do
		local role = RoleService.get(player)
		roleRemote:FireClient(player, role)
		if role == Config.Roles.Murderer then
			CombatService.giveKnife(player)
		elseif role == Config.Roles.Detective then
			CombatService.giveGun(player)
		end
	end

	ClueService.start(murderer)
	RoundState.set("InRound")
	return true
end

-- Returns "Murderer", "Innocents", or nil if the round is still going.
local function evaluate(): string?
	local murdererAlive = false
	local innocentsAlive = 0
	for _, player in ipairs(RoleService.participants()) do
		if RoleService.aliveHumanoid(player) then
			if RoleService.get(player) == Config.Roles.Murderer then
				murdererAlive = true
			else
				innocentsAlive += 1
			end
		end
	end

	if not murdererAlive then
		return Config.Winners.Innocents
	elseif innocentsAlive == 0 then
		return Config.Winners.Murderer
	end
	return nil
end

local function playRound()
	local murderer = RoleService.findByRole(Config.Roles.Murderer)
	local murdererName = murderer and murderer.DisplayName or "Unknown"

	local endsAt = os.clock() + Config.RoundSeconds
	local winner: string? = nil
	while not winner and os.clock() < endsAt do
		RoundState.setTimeLeft(math.ceil(endsAt - os.clock()))
		task.wait(0.25)
		winner = evaluate()
	end
	-- Surviving until the timer runs out is a win for the innocents.
	local result = winner or Config.Winners.Innocents

	RoundState.set("Ended")
	for _, player in ipairs(RoleService.participants()) do
		local role = RoleService.get(player)
		local isMurderer = role == Config.Roles.Murderer
		if result == Config.Winners.Murderer and isMurderer then
			addCoins(player, Config.Rewards.MurdererWin)
		elseif result == Config.Winners.Innocents and not isMurderer then
			addCoins(player, Config.Rewards.InnocentWin)
		end
	end

	Remotes.get("RoundEnded"):FireAllClients(result, murdererName)
	task.wait(Config.EndScreenSeconds)
	resetToLobby()
end

function RoundManager.start()
	Players.PlayerAdded:Connect(setupPlayer)
	for _, player in ipairs(Players:GetPlayers()) do
		task.spawn(setupPlayer, player)
	end
	Players.PlayerRemoving:Connect(function(player)
		RoleService.remove(player)
	end)

	task.spawn(function()
		while true do
			waitForPlayers()
			if startRound() then
				playRound()
			end
		end
	end)
end

return RoundManager
]==],
	},
	{
		root = "ServerScriptService",
		parent = "Server",
		name = "RoundState",
		class = "ModuleScript",
		source = [==[
-- Single source of truth for round state. Stored as attributes on ReplicatedStorage
-- so the client HUD can read it without extra remotes.
--   State: "Waiting" | "Intermission" | "Starting" | "InRound" | "Ended"
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local RoundState = {}

function RoundState.set(state: string)
	ReplicatedStorage:SetAttribute("State", state)
end

function RoundState.get(): string?
	return ReplicatedStorage:GetAttribute("State")
end

function RoundState.isInRound(): boolean
	return RoundState.get() == "InRound"
end

function RoundState.setTimeLeft(seconds: number)
	ReplicatedStorage:SetAttribute("TimeLeft", seconds)
end

return RoundState
]==],
	},
	{
		root = "StarterPlayerScripts",
		name = "Client",
		class = "LocalScript",
		source = [==[
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Remotes = require(Shared.Remotes)

local HUD = require(script.HUD)
local GunController = require(script.GunController)

local hud = HUD.init()
GunController.init()

Remotes.get("RoleAssigned").OnClientEvent:Connect(hud.showRole)
Remotes.get("ClueFound").OnClientEvent:Connect(hud.showClue)
Remotes.get("RoundEnded").OnClientEvent:Connect(hud.showEnd)
]==],
	},
	{
		root = "StarterPlayerScripts",
		parent = "Client",
		name = "GunController",
		class = "ModuleScript",
		source = [==[
-- Hooks the detective's "Revolver" tool: on click, sends the aim point to the server.
-- The server does all validation and the actual raycast.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Remotes = require(Shared.Remotes)

local GunController = {}

function GunController.init()
	local player = Players.LocalPlayer
	local mouse = player:GetMouse()
	local shootRemote = Remotes.get("Shoot")
	local hooked: { [Instance]: boolean } = setmetatable({}, { __mode = "k" })

	local function hookTool(tool: Instance)
		if not tool:IsA("Tool") or tool.Name ~= "Revolver" or hooked[tool] then
			return
		end
		hooked[tool] = true
		tool.Activated:Connect(function()
			shootRemote:FireServer(mouse.Hit.Position)
		end)
	end

	local function watch(container: Instance)
		for _, child in ipairs(container:GetChildren()) do
			hookTool(child)
		end
		container.ChildAdded:Connect(hookTool)
	end

	local function onCharacter(character: Model)
		watch(character)
		watch(player:WaitForChild("Backpack"))
	end

	player.CharacterAdded:Connect(onCharacter)
	if player.Character then
		task.spawn(onCharacter, player.Character)
	end
end

return GunController
]==],
	},
	{
		root = "StarterPlayerScripts",
		parent = "Client",
		name = "HUD",
		class = "ModuleScript",
		source = [==[
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)

local HUD = {}

local WHITE = Color3.new(1, 1, 1)
local PANEL = Color3.fromRGB(20, 20, 28)

local ROLE_STYLE = {
	[Config.Roles.Murderer] = {
		color = Color3.fromRGB(220, 60, 60),
		blurb = "Eliminate everyone. Destroy clues. Stay hidden.",
	},
	[Config.Roles.Detective] = {
		color = Color3.fromRGB(80, 140, 255),
		blurb = "Find the murderer. A wrong shot kills you too.",
	},
	[Config.Roles.Innocent] = {
		color = Color3.fromRGB(90, 200, 120),
		blurb = "Collect clues and survive. Work out who the murderer is.",
	},
}

local function make(className: string, props: { [string]: any }, parent: Instance): any
	local instance = Instance.new(className)
	for key, value in pairs(props) do
		instance[key] = value
	end
	instance.Parent = parent
	return instance
end

local function panel(props: { [string]: any }, parent: Instance): TextLabel
	props.BackgroundColor3 = props.BackgroundColor3 or PANEL
	props.BackgroundTransparency = props.BackgroundTransparency or 0.3
	props.TextColor3 = props.TextColor3 or WHITE
	props.Font = props.Font or Enum.Font.GothamBold
	props.TextSize = props.TextSize or 18
	props.TextWrapped = true
	local label = make("TextLabel", props, parent)
	make("UICorner", { CornerRadius = UDim.new(0, 8) }, label)
	return label
end

function HUD.init()
	local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui")
	local gui = make("ScreenGui", { Name = "MysteryHUD", ResetOnSpawn = false }, playerGui)

	local status = panel({
		Size = UDim2.fromOffset(380, 40),
		Position = UDim2.new(0.5, 0, 0, 12),
		AnchorPoint = Vector2.new(0.5, 0),
	}, gui)

	local roleLabel = panel({
		Size = UDim2.fromOffset(220, 36),
		Position = UDim2.new(0, 12, 0, 12),
		Visible = false,
	}, gui)

	-- Left side, stacked under the role label: the top-right is occupied by
	-- Roblox's own player list.
	local clueBoard = panel({
		Size = UDim2.fromOffset(260, 56),
		Position = UDim2.new(0, 12, 0, 56),
		TextSize = 16,
		Visible = false,
	}, gui)

	local toast = panel({
		Size = UDim2.fromOffset(340, 36),
		Position = UDim2.new(0.5, 0, 1, -90),
		AnchorPoint = Vector2.new(0.5, 1),
		TextSize = 16,
		Visible = false,
	}, gui)

	local banner = panel({
		BackgroundTransparency = 0.1,
		Size = UDim2.fromOffset(520, 110),
		Position = UDim2.new(0.5, 0, 0.3, 0),
		AnchorPoint = Vector2.new(0.5, 0.5),
		TextSize = 34,
		Visible = false,
	}, gui)
	local bannerSub = make("TextLabel", {
		Size = UDim2.new(1, -20, 0, 40),
		Position = UDim2.new(0, 10, 1, -48),
		BackgroundTransparency = 1,
		TextColor3 = WHITE,
		Font = Enum.Font.Gotham,
		TextSize = 18,
		TextWrapped = true,
		Text = "",
	}, banner)
	banner.TextYAlignment = Enum.TextYAlignment.Top

	local function refreshStatus()
		local state = ReplicatedStorage:GetAttribute("State")
		local timeLeft = ReplicatedStorage:GetAttribute("TimeLeft") or 0
		local text
		if state == "Waiting" then
			text = string.format("Waiting for players (%d/%d)", #Players:GetPlayers(), Config.MinPlayers)
		elseif state == "Intermission" then
			text = string.format("Next round in %d", timeLeft)
		elseif state == "Starting" then
			text = "Round starting..."
		elseif state == "InRound" then
			text = string.format("Time left  %d:%02d", math.floor(timeLeft / 60), timeLeft % 60)
		elseif state == "Ended" then
			text = "Round over"
		else
			text = "Connecting..."
		end
		status.Text = text
	end

	ReplicatedStorage:GetAttributeChangedSignal("State"):Connect(refreshStatus)
	ReplicatedStorage:GetAttributeChangedSignal("TimeLeft"):Connect(refreshStatus)
	Players.PlayerAdded:Connect(refreshStatus)
	Players.PlayerRemoving:Connect(function()
		task.defer(refreshStatus)
	end)
	refreshStatus()

	-- Each banner/toast gets a token so an older timer can't hide a newer message.
	local bannerToken = 0
	local toastToken = 0

	local function showBanner(title: string, subtitle: string, color: Color3, seconds: number)
		bannerToken += 1
		local token = bannerToken
		banner.Text = title
		banner.TextColor3 = color
		bannerSub.Text = subtitle
		banner.Visible = true
		task.delay(seconds, function()
			if token == bannerToken then
				banner.Visible = false
			end
		end)
	end

	local function showToast(message: string)
		toastToken += 1
		local token = toastToken
		toast.Text = message
		toast.Visible = true
		task.delay(5, function()
			if token == toastToken then
				toast.Visible = false
			end
		end)
	end

	local api = {}

	function api.showRole(role: string)
		local style = ROLE_STYLE[role] or ROLE_STYLE[Config.Roles.Innocent]
		roleLabel.Text = "You are: " .. role
		roleLabel.TextColor3 = style.color
		roleLabel.Visible = true
		clueBoard.Text = "Murderer's name:\n(no clues found yet)"
		clueBoard.Visible = true
		showBanner(role, style.blurb, style.color, 5)
	end

	function api.showClue(message: string, mask: string?)
		showToast(message)
		if mask then
			clueBoard.Text = "Murderer's name:\n" .. mask
		end
	end

	function api.showEnd(winner: string, murdererName: string)
		local innocentsWon = winner == Config.Winners.Innocents
		showBanner(
			innocentsWon and "Innocents win!" or "The murderer wins!",
			"The murderer was " .. murdererName,
			innocentsWon and ROLE_STYLE[Config.Roles.Innocent].color or ROLE_STYLE[Config.Roles.Murderer].color,
			Config.EndScreenSeconds
		)
		roleLabel.Visible = false
		clueBoard.Visible = false
	end

	return api
end

return HUD
]==],
	},
}

-- Replace any previous install so re-running this script is idempotent.
for _, entry in ipairs(ENTRIES) do
	if not entry.parent then
		local existing = ROOTS[entry.root]:FindFirstChild(entry.name)
		if existing then
			existing:Destroy()
		end
	end
end

local containers = {}
local created = {}

for _, entry in ipairs(ENTRIES) do
	local parent = ROOTS[entry.root]
	if entry.parent then
		parent = containers[entry.root .. "/" .. entry.parent]
		if not parent then
			error("installer: container missing for " .. entry.name)
		end
	end

	local instance = Instance.new(entry.class)
	instance.Name = entry.name
	if entry.source then
		-- Writable from the Command Bar, which runs at plugin permission level.
		instance.Source = entry.source
	end
	instance.Parent = parent

	if not entry.parent then
		containers[entry.root .. "/" .. entry.name] = instance
	end

	local prefix = entry.parent and (entry.parent .. ".") or ""
	table.insert(created, entry.root .. "." .. prefix .. entry.name)
end

print(string.format("Murder Mystery installed - %d instances created:", #created))
for _, path in ipairs(created) do
	print("   " .. path)
end
print("Next: Test tab -> Clients and Servers -> Players: 2 -> Start")
