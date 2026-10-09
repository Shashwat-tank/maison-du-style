--!nocheck
-- Maison du Style - Obby Race: one-paste Studio installer.
--
-- GENERATED FILE - do not edit by hand.
-- Regenerate with: python3 tools/build_installer.py
--
-- HOW TO USE
--   1. Open Roblox Studio and create a new Baseplate place.
--   2. View tab -> Command Bar. Also open View -> Output to see errors later.
--   3. Paste this whole file into the Command Bar and press Enter.
--   4. Test tab -> Play (solo works; Clients and Servers -> Players: 2+ to race others).
--
-- If the paste collapses into one line, the Command Bar has stripped the
-- newlines and this will not work. Use the .rbxmx files next to this one instead.
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
local Config = {
	-- One player is enough: a solo race is a time trial.
	MinPlayers = 1,

	IntermissionSeconds = 15,
	CountdownSeconds = 3,
	RaceSeconds = 240,
	-- Once someone finishes, everyone else has at most this long left.
	FinishWindowSeconds = 30,
	EndScreenSeconds = 8,

	-- Stages per course. Each race draws a fresh random course, getting harder
	-- toward the finish.
	StageCount = 8,

	Rewards = {
		Places = { 50, 30, 20 }, -- coins for 1st, 2nd, 3rd
		Finish = 10, -- coins for finishing outside the top places
		PerCheckpoint = 1, -- consolation coins for racers who do not finish
	},

	RemoteNames = { "PlayerFinished", "RaceResults" },
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
		root = "ServerScriptService",
		name = "Server",
		class = "Script",
		source = [==[
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Remotes = require(Shared.Remotes)

-- Create every remote up front so clients can WaitForChild them.
for _, name in ipairs(Config.RemoteNames) do
	Remotes.get(name)
end

local CourseBuilder = require(script.CourseBuilder)
local NoPlayerCollisions = require(script.NoPlayerCollisions)
local PlayerStats = require(script.PlayerStats)
local RaceManager = require(script.RaceManager)

CourseBuilder.ensureLobby()
NoPlayerCollisions.init()
PlayerStats.init()
RaceManager.start()
]==],
	},
	{
		root = "ServerScriptService",
		parent = "Server",
		name = "CourseBuilder",
		class = "ModuleScript",
		source = [==[
-- Builds a fresh random course for every race. The course runs along +Z, high in
-- the sky above the lobby. Each stage ends in a checkpoint pad; the last pad is
-- the finish.
--
-- Moving obstacles are animated on each client (see ObstacleAnimator), driven by
-- the shared server clock, so they move smoothly and line up for everyone. They
-- are tagged with attributes here:
--   Hazard = true                  touching it sends you back to your checkpoint
--   Anim = "Spin"  Speed           rotates about its own vertical axis (deg/s)
--   Anim = "Fade" | "Laser"        on for OnFraction of each Period, offset by Phase
--
-- Distances are tuned for the default character: a running jump clears about
-- 8.5 studs on the flat and rises about 7, so gaps top out at 6.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("Shared").Config)

local CourseBuilder = {}

local ORIGIN = Vector3.new(0, 150, 300)
local START_SIZE = Vector3.new(40, 1, 24)
local PAD_SIZE = Vector3.new(24, 1, 10)
local FINISH_SIZE = Vector3.new(32, 1, 18)

local HAZARD_COLOR = Color3.fromRGB(255, 70, 40)
local DARK = Color3.fromRGB(45, 45, 55)
local PAD_COLOR = Color3.fromRGB(85, 200, 110)
local GOLD = Color3.fromRGB(255, 200, 60)

export type Checkpoint = { top: Vector3, size: Vector3 }
export type Course = {
	folder: Folder,
	gate: BasePart,
	stageCount: number,
	stageNames: { string },
	checkpoints: { [number]: Checkpoint }, -- 0 is the start pad, stageCount is the finish
}

type Builder = { folder: Folder, rng: Random, color: Color3 }

type PartSpec = {
	name: string,
	size: Vector3,
	cframe: CFrame,
	color: Color3?,
	material: Enum.Material?,
	transparency: number?,
	canCollide: boolean?,
	attributes: { [string]: any }?,
	class: string?,
}

local function lerp(a: number, b: number, t: number): number
	return a + (b - a) * t
end

-- Attributes are set before parenting so clients receive the part fully tagged.
local function block(b: Builder, spec: PartSpec): BasePart
	local part = Instance.new(spec.class or "Part") :: BasePart
	part.Name = spec.name
	part.Anchored = true
	part.Size = spec.size
	part.CFrame = spec.cframe
	part.Color = spec.color or b.color
	part.Material = spec.material or Enum.Material.SmoothPlastic
	part.Transparency = spec.transparency or 0
	if spec.canCollide ~= nil then
		part.CanCollide = spec.canCollide
	end
	for key, value in pairs(spec.attributes or {}) do
		part:SetAttribute(key, value)
	end
	part.Parent = b.folder
	return part
end

-- A platform whose top surface is centred on `top`.
local function slab(b: Builder, name: string, size: Vector3, top: Vector3, color: Color3?, material: Enum.Material?): BasePart
	return block(b, {
		name = name,
		size = size,
		cframe = CFrame.new(top - Vector3.new(0, size.Y / 2, 0)),
		color = color,
		material = material,
	})
end

local function sign(part: BasePart, text: string, color: Color3)
	local gui = Instance.new("BillboardGui")
	gui.Size = UDim2.fromScale(14, 3)
	gui.StudsOffset = Vector3.new(0, 7, 0)
	gui.MaxDistance = 150
	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Text = text
	label.TextScaled = true
	label.Font = Enum.Font.GothamBlack
	label.TextColor3 = color
	label.TextStrokeTransparency = 0.3
	label.Parent = gui
	gui.Parent = part
end

-- Each stage takes the point where it starts (centre of the entry edge, at
-- standing height) and a difficulty from 0 to 1, and returns where the next
-- checkpoint pad should begin.
type StageBuild = (b: Builder, start: Vector3, difficulty: number) -> Vector3

local function jumps(b: Builder, s: Vector3, d: number): Vector3
	local rng = b.rng
	local size = lerp(7, 4.5, d)
	local rises = { -1, 0, 0, 1, 2 }
	local function gap(rising: boolean): number
		local g = rng:NextNumber(lerp(2.5, 4, d), lerp(4, 6, d))
		return rising and math.min(g, 4) or g
	end

	local x, y, z = 0, s.Y, s.Z + gap(false)
	for i = 1, 7 do
		slab(b, "Jump" .. i, Vector3.new(size, 1, size), Vector3.new(x, y, z + size / 2))
		local rise = rises[rng:NextInteger(1, #rises)]
		y += rise
		x = math.clamp(x + rng:NextNumber(-0.8, 0.8) * size, -9, 9)
		z += size + gap(rise > 0)
	end
	return Vector3.new(0, y, z)
end

local function lava(b: Builder, s: Vector3, d: number): Vector3
	local rng = b.rng
	local size = lerp(5, 3.5, d)
	local x, z = 0, s.Z + rng:NextNumber(2.5, 4)
	for i = 1, 9 do
		slab(b, "Stone" .. i, Vector3.new(size, 2, size), Vector3.new(x, s.Y, z + size / 2), nil, Enum.Material.Slate)
		z += size + rng:NextNumber(lerp(2.5, 4, d), lerp(3.5, 5.5, d))
		x = math.clamp(x + rng:NextNumber(-1, 1) * size, -9, 9)
	end
	local length = z - s.Z
	block(b, {
		name = "Lava",
		size = Vector3.new(24, 1, length),
		cframe = CFrame.new(0, s.Y - 2, s.Z + length / 2),
		color = HAZARD_COLOR,
		material = Enum.Material.Neon,
		attributes = { Hazard = true },
	})
	return Vector3.new(0, s.Y, z)
end

local function spinners(b: Builder, s: Vector3, d: number): Vector3
	local rng = b.rng
	local count = 2 + math.floor(d * 2.99)
	local spacing = 22
	local length = count * spacing + 8
	-- The floor is exactly as wide as the sweep, so there is no way around a bar.
	slab(b, "Floor", Vector3.new(spacing, 1, length), Vector3.new(0, s.Y, s.Z + length / 2))

	local speed = lerp(70, 140, d)
	for i = 1, count do
		local center = Vector3.new(0, s.Y, s.Z + 4 + (i - 0.5) * spacing)
		block(b, { name = "Hub" .. i, size = Vector3.new(2, 3, 2), cframe = CFrame.new(center + Vector3.new(0, 1.5, 0)), color = DARK })

		-- Later stages turn some single bars into crosses, spun a little slower so
		-- the gap between sweeps stays longer than a jump.
		local arms = (d > 0.5 and i % 2 == 0) and 2 or 1
		local direction = i % 2 == 0 and 1 or -1
		local phase = rng:NextNumber(0, 360)
		for arm = 1, arms do
			block(b, {
				name = "Spinner" .. i .. "_" .. arm,
				size = Vector3.new(spacing - 1, 1, 1),
				cframe = CFrame.new(center + Vector3.new(0, 1.3, 0)) * CFrame.Angles(0, math.rad(phase + (arm - 1) * 90), 0),
				color = HAZARD_COLOR,
				material = Enum.Material.Neon,
				canCollide = false,
				attributes = { Hazard = true, Anim = "Spin", Speed = direction * speed / arms ^ 0.5 },
			})
		end
	end
	return Vector3.new(0, s.Y, s.Z + length)
end

local function vanishing(b: Builder, s: Vector3, d: number): Vector3
	local rng = b.rng
	local period = lerp(3.2, 2.4, d)
	local x, z = 0, s.Z + 3
	for i = 1, 7 do
		block(b, {
			name = "Tile" .. i,
			size = Vector3.new(6, 1, 6),
			cframe = CFrame.new(x, s.Y - 0.5, z + 3),
			material = Enum.Material.Glass,
			-- Each tile lags the one before it, so the solid window travels
			-- forward at roughly running speed.
			attributes = { Anim = "Fade", Period = period, Phase = (-0.15 * i) % 1, OnFraction = 0.6 },
		})
		z += 6 + 2.5
		x = math.clamp(x + rng:NextNumber(-4, 4), -8, 8)
	end
	return Vector3.new(0, s.Y, z + 0.5)
end

local function tightrope(b: Builder, s: Vector3, d: number): Vector3
	local rng = b.rng
	local width = lerp(2, 1.2, d)
	local segments = 4
	local side = rng:NextInteger(0, 1) == 0 and -1 or 1
	local from = Vector3.new(0, s.Y, s.Z)
	for i = 1, segments do
		local to = Vector3.new(i == segments and 0 or side * 7, s.Y, from.Z + 12)
		side = -side
		local mid = (from + to) / 2 - Vector3.new(0, 0.5, 0)
		block(b, {
			name = "Beam" .. i,
			size = Vector3.new(width, 1, (to - from).Magnitude + 1),
			cframe = CFrame.lookAt(mid, mid + (to - from)),
		})
		slab(b, "Perch" .. i, Vector3.new(4, 1, 4), to)
		from = to
	end
	return Vector3.new(0, s.Y, from.Z + 2)
end

local function lasers(b: Builder, s: Vector3, d: number): Vector3
	local rng = b.rng
	local count = 3 + math.floor(d * 2.99)
	local spacing = 12
	local length = count * spacing + 6
	slab(b, "Floor", Vector3.new(12, 1, length), Vector3.new(0, s.Y, s.Z + length / 2))

	local period = lerp(2.4, 1.8, d)
	for i = 1, count do
		local z = s.Z + 3 + (i - 0.5) * spacing
		for _, side in ipairs({ -1, 1 }) do
			block(b, { name = "Emitter", size = Vector3.new(1, 10, 1), cframe = CFrame.new(side * 6.5, s.Y + 5, z), color = DARK })
		end
		-- Taller than a jump can clear, so the only way through is timing.
		block(b, {
			name = "Laser" .. i,
			size = Vector3.new(12, 9, 0.4),
			cframe = CFrame.new(0, s.Y + 4.5, z),
			color = HAZARD_COLOR,
			material = Enum.Material.Neon,
			transparency = 0.2,
			canCollide = false,
			attributes = { Hazard = true, Anim = "Laser", Period = period, Phase = rng:NextNumber(), OnFraction = 0.5 },
		})
	end
	return Vector3.new(0, s.Y, s.Z + length)
end

local function climb(b: Builder, s: Vector3, _d: number): Vector3
	local function truss(bottom: Vector3, height: number)
		block(b, {
			class = "TrussPart",
			name = "Truss",
			size = Vector3.new(2, height, 2),
			cframe = CFrame.new(bottom + Vector3.new(0, height / 2, 0)),
			color = DARK,
		})
	end

	local y0 = s.Y
	slab(b, "Base", Vector3.new(12, 1, 8), Vector3.new(0, y0, s.Z + 4))
	truss(Vector3.new(0, y0, s.Z + 9), 14)
	local y1 = y0 + 14
	slab(b, "Ledge1", Vector3.new(8, 1, 6), Vector3.new(0, y1, s.Z + 13))
	slab(b, "Ledge2", Vector3.new(8, 1, 8), Vector3.new(0, y1, s.Z + 23))
	truss(Vector3.new(0, y1, s.Z + 28), 12)
	local y2 = y1 + 12
	slab(b, "Ledge3", Vector3.new(8, 1, 6), Vector3.new(0, y2, s.Z + 32))
	return Vector3.new(0, y2, s.Z + 35)
end

local WARMUP = { name = "Jumps", build = jumps :: StageBuild }
local STAGES = {
	WARMUP,
	{ name = "Lava Floor", build = lava :: StageBuild },
	{ name = "Spinners", build = spinners :: StageBuild },
	{ name = "Vanishing Tiles", build = vanishing :: StageBuild },
	{ name = "Tightrope", build = tightrope :: StageBuild },
	{ name = "Laser Hall", build = lasers :: StageBuild },
	{ name = "Tower Climb", build = climb :: StageBuild },
}

-- Always open with the warm-up, then deal stages from a shuffled bag so every
-- type appears before any repeats, and never the same type twice in a row.
local function chooseStages(rng: Random, count: number)
	local order = { WARMUP }
	local bag = {}
	while #order < count do
		if #bag == 0 then
			bag = table.clone(STAGES)
			for i = #bag, 2, -1 do
				local j = rng:NextInteger(1, i)
				bag[i], bag[j] = bag[j], bag[i]
			end
		end
		local pick = table.remove(bag)
		if pick == order[#order] and #bag > 0 then
			bag[1], pick = pick, bag[1]
		end
		table.insert(order, pick)
	end
	return order
end

function CourseBuilder.build(seed: number): Course
	local existing = workspace:FindFirstChild("Course")
	if existing then
		existing:Destroy()
	end

	local folder = Instance.new("Folder")
	folder.Name = "Course"
	local rng = Random.new(seed)
	local count = Config.StageCount
	local stages = chooseStages(rng, count)

	local b: Builder = { folder = folder, rng = rng, color = Color3.new(1, 1, 1) }
	local checkpoints: { [number]: Checkpoint } = {}
	local names = {}

	local start = slab(b, "Start", START_SIZE, ORIGIN + Vector3.new(0, 0, START_SIZE.Z / 2), Color3.fromRGB(90, 90, 110))
	sign(start, "Stage 1 · " .. stages[1].name, Color3.new(1, 1, 1))
	checkpoints[0] = { top = ORIGIN + Vector3.new(0, 0, START_SIZE.Z / 2), size = START_SIZE }
	local gate = block(b, {
		name = "StartGate",
		size = Vector3.new(START_SIZE.X, 14, 1),
		cframe = CFrame.new(ORIGIN + Vector3.new(0, 7, START_SIZE.Z - 0.5)),
		color = Color3.fromRGB(120, 200, 255),
		material = Enum.Material.Glass,
		transparency = 0.6,
	})

	local cursor = ORIGIN + Vector3.new(0, 0, START_SIZE.Z)
	for i, stage in ipairs(stages) do
		names[i] = stage.name
		b.color = Color3.fromHSV((i - 1) / count, 0.45, 0.95)
		local exit = stage.build(b, cursor, (i - 1) / math.max(count - 1, 1))

		local isFinish = i == count
		local size = isFinish and FINISH_SIZE or PAD_SIZE
		local top = Vector3.new(0, exit.Y, exit.Z + size.Z / 2)
		local pad = slab(b, isFinish and "Finish" or ("Checkpoint" .. i), size, top, isFinish and GOLD or PAD_COLOR)
		checkpoints[i] = { top = top, size = size }

		if isFinish then
			pad.Material = Enum.Material.Neon
			sign(pad, "FINISH", GOLD)
		else
			sign(pad, string.format("Stage %d · %s", i + 1, stages[i + 1].name), Color3.new(1, 1, 1))
		end
		cursor = Vector3.new(0, exit.Y, exit.Z + size.Z)
	end

	folder.Parent = workspace

	ReplicatedStorage:SetAttribute("StageCount", count)
	ReplicatedStorage:SetAttribute("StageNames", table.concat(names, "|"))

	return {
		folder = folder,
		gate = gate,
		stageCount = count,
		stageNames = names,
		checkpoints = checkpoints,
	}
end

-- A plain lobby, only if the place does not already have a spawn.
function CourseBuilder.ensureLobby()
	if workspace:FindFirstChildWhichIsA("SpawnLocation", true) then
		return
	end
	local lobby = Instance.new("Folder")
	lobby.Name = "Lobby"
	local b: Builder = { folder = lobby, rng = Random.new(), color = Color3.fromRGB(70, 70, 90) }
	slab(b, "Floor", Vector3.new(80, 1, 80), Vector3.new(0, 0, 0))

	local spawn = Instance.new("SpawnLocation")
	spawn.Anchored = true
	spawn.Neutral = true
	spawn.Duration = 0
	spawn.Size = Vector3.new(12, 1, 12)
	spawn.Position = Vector3.new(0, 0.5, 0)
	spawn.Parent = lobby
	lobby.Parent = workspace
end

return CourseBuilder
]==],
	},
	{
		root = "ServerScriptService",
		parent = "Server",
		name = "NoPlayerCollisions",
		class = "ModuleScript",
		source = [==[
-- Racers pass through each other, so nobody can block a narrow beam or shove
-- someone off a platform.
local Players = game:GetService("Players")
local PhysicsService = game:GetService("PhysicsService")

local NoPlayerCollisions = {}

local GROUP = "Racers"

local function assign(instance: Instance)
	if instance:IsA("BasePart") then
		instance.CollisionGroup = GROUP
	end
end

local function onCharacter(character: Model)
	for _, descendant in ipairs(character:GetDescendants()) do
		assign(descendant)
	end
	character.DescendantAdded:Connect(assign)
end

local function onPlayer(player: Player)
	player.CharacterAdded:Connect(onCharacter)
	if player.Character then
		onCharacter(player.Character)
	end
end

function NoPlayerCollisions.init()
	if not PhysicsService:IsCollisionGroupRegistered(GROUP) then
		PhysicsService:RegisterCollisionGroup(GROUP)
	end
	PhysicsService:CollisionGroupSetCollidable(GROUP, GROUP, false)

	Players.PlayerAdded:Connect(onPlayer)
	for _, player in ipairs(Players:GetPlayers()) do
		onPlayer(player)
	end
end

return NoPlayerCollisions
]==],
	},
	{
		root = "ServerScriptService",
		parent = "Server",
		name = "PlayerStats",
		class = "ModuleScript",
		source = [==[
-- Wins and Coins on the in-game leaderboard. Session-only for now: they reset
-- when the player leaves. Saving them is a DataStore job for later.
local Players = game:GetService("Players")

local PlayerStats = {}

local STATS = { "Wins", "Coins" }

local function setup(player: Player)
	local leaderstats = Instance.new("Folder")
	leaderstats.Name = "leaderstats"
	for _, name in ipairs(STATS) do
		local value = Instance.new("IntValue")
		value.Name = name
		value.Parent = leaderstats
	end
	leaderstats.Parent = player
end

function PlayerStats.init()
	Players.PlayerAdded:Connect(setup)
	for _, player in ipairs(Players:GetPlayers()) do
		setup(player)
	end
end

function PlayerStats.add(player: Player, stat: string, amount: number)
	local leaderstats = player:FindFirstChild("leaderstats")
	local value = leaderstats and leaderstats:FindFirstChild(stat)
	if value then
		value.Value += amount
	end
end

return PlayerStats
]==],
	},
	{
		root = "ServerScriptService",
		parent = "Server",
		name = "RaceManager",
		class = "ModuleScript",
		source = [==[
-- The race loop: wait for players, build a course, count down, race, award.
--
-- Progress is server-authoritative: ten times a second each racer's position is
-- checked against their *next* checkpoint only, so checkpoints must be reached
-- in order and nobody can skip to the finish. Clients never report progress.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Remotes = require(Shared.Remotes)

local CourseBuilder = require(script.Parent.CourseBuilder)
local PlayerStats = require(script.Parent.PlayerStats)
local RoundState = require(script.Parent.RoundState)

local RaceManager = {}

type Racer = { checkpoint: number, place: number?, time: number? }

local course: CourseBuilder.Course? = nil
local racers: { [Player]: Racer } = {}

local SPAWN_HEIGHT = 3.5

local function respawnPoint(index: number): Vector3
	assert(course, "no course")
	return course.checkpoints[index].top + Vector3.new(0, SPAWN_HEIGHT, 0)
end

local function setCheckpoint(player: Player, racer: Racer, index: number)
	racer.checkpoint = index
	player:SetAttribute("Checkpoint", index)
	player:SetAttribute("RespawnAt", respawnPoint(index))
end

-- Facing down the course (+Z).
local function place(player: Player, position: Vector3)
	pcall(player.RequestStreamAroundAsync, player, position)
	local character = player.Character
	if character and character:FindFirstChild("HumanoidRootPart") then
		character:PivotTo(CFrame.lookAt(position, position + Vector3.new(0, 0, 1)))
	end
end

-- The point is inside the column above a checkpoint pad. The column is tall so a
-- racer jumping across the pad still counts.
local function reached(checkpoint: CourseBuilder.Checkpoint, position: Vector3): boolean
	local offset = position - checkpoint.top
	return math.abs(offset.X) <= checkpoint.size.X / 2 + 1
		and math.abs(offset.Z) <= checkpoint.size.Z / 2 + 1
		and offset.Y >= -2
		and offset.Y <= 16
end

local function clearPlayer(player: Player)
	player:SetAttribute("Checkpoint", nil)
	player:SetAttribute("RespawnAt", nil)
	player:SetAttribute("Place", nil)
end

local function countdown(state: string, seconds: number, needsPlayers: boolean): boolean
	RoundState.set(state)
	for t = seconds, 1, -1 do
		RoundState.setTimeLeft(t)
		task.wait(1)
		if needsPlayers and #Players:GetPlayers() < Config.MinPlayers then
			return false
		end
	end
	RoundState.setTimeLeft(0)
	return true
end

local function startPositions(count: number): { Vector3 }
	assert(course, "no course")
	local start = course.checkpoints[0]
	local columns = 6
	local positions = {}
	for i = 0, count - 1 do
		local column, row = i % columns, i // columns
		local x = (column - (columns - 1) / 2) * 5
		local z = -start.size.Z / 2 + 4 + (row % 4) * 4
		table.insert(positions, start.top + Vector3.new(x, SPAWN_HEIGHT, z))
	end
	return positions
end

local function lineUp()
	local players = Players:GetPlayers()
	local positions = startPositions(#players)
	for i, player in ipairs(players) do
		if not player.Character then
			player:LoadCharacter()
		end
		local racer = { checkpoint = 0 }
		racers[player] = racer
		setCheckpoint(player, racer, 0)
		task.spawn(place, player, positions[i])
	end
end

local function race(): number
	assert(course, "no course")
	local started = os.clock()
	local deadline = started + Config.RaceSeconds
	local finished = 0
	local starters = 0
	for _ in pairs(racers) do
		starters += 1
	end

	while true do
		local now = os.clock()
		local stillRacing = 0
		for player, racer in pairs(racers) do
			if racer.place then
				continue
			end
			local character = player.Character
			local root = character and character:FindFirstChild("HumanoidRootPart")
			local nextIndex = racer.checkpoint + 1
			if root and reached(course.checkpoints[nextIndex], (root :: BasePart).Position) then
				setCheckpoint(player, racer, nextIndex)
				if nextIndex == course.stageCount then
					finished += 1
					racer.place = finished
					racer.time = now - started
					player:SetAttribute("Place", finished)
					Remotes.get("PlayerFinished"):FireAllClients(player.DisplayName, finished, racer.time)
					if finished == 1 then
						deadline = math.min(deadline, now + Config.FinishWindowSeconds)
					end
					continue
				end
			end
			stillRacing += 1
		end

		if stillRacing == 0 or now >= deadline then
			break
		end
		RoundState.setTimeLeft(math.ceil(deadline - now))
		task.wait(0.1)
	end
	return starters
end

local function award(starters: number)
	assert(course, "no course")
	local results = {}
	for player, racer in pairs(racers) do
		local coins
		if racer.place then
			coins = Config.Rewards.Places[racer.place] or Config.Rewards.Finish
			-- A win only counts against at least one other racer.
			if racer.place == 1 and starters >= 2 then
				PlayerStats.add(player, "Wins", 1)
			end
		else
			coins = racer.checkpoint * Config.Rewards.PerCheckpoint
		end
		PlayerStats.add(player, "Coins", coins)
		table.insert(results, {
			name = player.DisplayName,
			place = racer.place,
			time = racer.time,
			checkpoint = racer.checkpoint,
			coins = coins,
		})
	end

	-- Finishers by place, then everyone else by how far they got.
	table.sort(results, function(a, b)
		if a.place and b.place then
			return a.place < b.place
		elseif a.place or b.place then
			return a.place ~= nil
		end
		return a.checkpoint > b.checkpoint
	end)
	Remotes.get("RaceResults"):FireAllClients(results, course.stageCount)
end

local function cleanup()
	for player in pairs(racers) do
		clearPlayer(player)
		if player.Parent then
			player:LoadCharacter()
		end
	end
	racers = {}
	if course then
		course.folder:Destroy()
		course = nil
	end
	ReplicatedStorage:SetAttribute("RaceStartedAt", nil)
end

local function onCharacterAdded(player: Player, character: Model)
	-- A racer who resets mid-race goes straight back to their checkpoint.
	local racer = racers[player]
	local state = RoundState.get()
	if racer and (state == "Countdown" or state == "Racing") then
		character:WaitForChild("HumanoidRootPart", 5)
		place(player, respawnPoint(racer.checkpoint))
	end
end

function RaceManager.start()
	Players.RespawnTime = 1
	Players.PlayerAdded:Connect(function(player)
		player.CharacterAdded:Connect(function(character)
			onCharacterAdded(player, character)
		end)
	end)
	for _, player in ipairs(Players:GetPlayers()) do
		player.CharacterAdded:Connect(function(character)
			onCharacterAdded(player, character)
		end)
	end
	Players.PlayerRemoving:Connect(function(player)
		racers[player] = nil
	end)

	task.spawn(function()
		while true do
			RoundState.set("Waiting")
			while #Players:GetPlayers() < Config.MinPlayers do
				task.wait(1)
			end

			-- Build now so the course streams to clients during intermission.
			course = CourseBuilder.build(os.time())
			if not countdown("Intermission", Config.IntermissionSeconds, true) then
				cleanup()
				continue
			end

			lineUp()
			countdown("Countdown", Config.CountdownSeconds, false)
			assert(course, "no course").gate:Destroy()
			ReplicatedStorage:SetAttribute("RaceStartedAt", workspace:GetServerTimeNow())
			RoundState.set("Racing")

			local starters = race()

			RoundState.set("Ended")
			award(starters)
			task.wait(Config.EndScreenSeconds)
			cleanup()
		end
	end)
end

return RaceManager
]==],
	},
	{
		root = "ServerScriptService",
		parent = "Server",
		name = "RoundState",
		class = "ModuleScript",
		source = [==[
-- Single source of truth for race state, stored as attributes on ReplicatedStorage
-- so the client HUD can read it without extra remotes.
--   State: "Waiting" | "Intermission" | "Countdown" | "Racing" | "Ended"
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local RoundState = {}

function RoundState.set(state: string)
	ReplicatedStorage:SetAttribute("State", state)
end

function RoundState.get(): string?
	return ReplicatedStorage:GetAttribute("State")
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

local Remotes = require(ReplicatedStorage:WaitForChild("Shared").Remotes)

local HUD = require(script.HUD)
local HazardWatcher = require(script.HazardWatcher)
local ObstacleAnimator = require(script.ObstacleAnimator)

local hud = HUD.init()
ObstacleAnimator.start()
HazardWatcher.start(hud.onReset)

Remotes.get("PlayerFinished").OnClientEvent:Connect(hud.onPlayerFinished)
Remotes.get("RaceResults").OnClientEvent:Connect(hud.showResults)
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
local RunService = game:GetService("RunService")

local Config = require(ReplicatedStorage:WaitForChild("Shared").Config)

local HUD = {}

local player = Players.LocalPlayer

local WHITE = Color3.new(1, 1, 1)
local PANEL = Color3.fromRGB(20, 20, 28)
local GREEN = Color3.fromRGB(110, 230, 140)
local GOLD = Color3.fromRGB(255, 205, 70)

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

local function ordinal(n: number): string
	local lastTwo = n % 100
	if lastTwo >= 11 and lastTwo <= 13 then
		return n .. "th"
	end
	return n .. (({ "st", "nd", "rd" })[n % 10] or "th")
end

local function clock(seconds: number): string
	return string.format("%d:%04.1f", seconds // 60, seconds % 60)
end

local function stageNames(): { string }
	return string.split(ReplicatedStorage:GetAttribute("StageNames") or "", "|")
end

function HUD.init()
	local gui = make("ScreenGui", { Name = "ObbyHUD", ResetOnSpawn = false }, player:WaitForChild("PlayerGui"))

	local status = panel({
		Size = UDim2.fromOffset(380, 40),
		Position = UDim2.new(0.5, 0, 0, 12),
		AnchorPoint = Vector2.new(0.5, 0),
	}, gui)

	-- Top-left: the top-right belongs to Roblox's player list.
	local stage = panel({
		Size = UDim2.fromOffset(240, 56),
		Position = UDim2.new(0, 12, 0, 12),
		Visible = false,
	}, gui)

	local bigText = make("TextLabel", {
		Size = UDim2.fromOffset(400, 140),
		Position = UDim2.fromScale(0.5, 0.35),
		AnchorPoint = Vector2.new(0.5, 0.5),
		BackgroundTransparency = 1,
		Font = Enum.Font.GothamBlack,
		TextSize = 110,
		TextColor3 = WHITE,
		TextStrokeTransparency = 0.2,
		Visible = false,
	}, gui)

	local toast = panel({
		Size = UDim2.fromOffset(380, 36),
		Position = UDim2.new(0.5, 0, 1, -90),
		AnchorPoint = Vector2.new(0.5, 1),
		TextSize = 16,
		Visible = false,
	}, gui)

	local results = panel({
		BackgroundTransparency = 0.1,
		Size = UDim2.fromOffset(420, 300),
		Position = UDim2.fromScale(0.5, 0.45),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Font = Enum.Font.GothamMedium,
		TextSize = 18,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Top,
		RichText = true,
		Visible = false,
	}, gui)
	make("UIPadding", {
		PaddingTop = UDim.new(0, 16),
		PaddingLeft = UDim.new(0, 20),
		PaddingRight = UDim.new(0, 20),
	}, results)

	-- Each timed message gets a token so an older timer can't hide a newer one.
	local tokens = {}
	local function showFor(label: GuiObject, seconds: number)
		tokens[label] = (tokens[label] or 0) + 1
		local token = tokens[label]
		label.Visible = true
		task.delay(seconds, function()
			if tokens[label] == token then
				label.Visible = false
			end
		end)
	end

	local function showToast(message: string, color: Color3?)
		toast.Text = message
		toast.TextColor3 = color or WHITE
		showFor(toast, 3)
	end

	local function isRacing(): boolean
		local state = ReplicatedStorage:GetAttribute("State")
		return player:GetAttribute("Checkpoint") ~= nil and (state == "Countdown" or state == "Racing")
	end

	local function refreshStage()
		local checkpoint = player:GetAttribute("Checkpoint")
		local count = ReplicatedStorage:GetAttribute("StageCount") or Config.StageCount
		stage.Visible = isRacing()
		if not checkpoint then
			return
		end
		local place = player:GetAttribute("Place")
		if place then
			stage.Text = "FINISHED\n" .. ordinal(place) .. " place"
			stage.TextColor3 = GOLD
		else
			local current = math.min(checkpoint + 1, count)
			stage.Text = string.format("Stage %d / %d\n%s", current, count, stageNames()[current] or "")
			stage.TextColor3 = WHITE
		end
	end

	local function statusText(): string
		local state = ReplicatedStorage:GetAttribute("State")
		local timeLeft = ReplicatedStorage:GetAttribute("TimeLeft") or 0
		if state == "Waiting" then
			return string.format("Waiting for players (%d/%d)", #Players:GetPlayers(), Config.MinPlayers)
		elseif state == "Intermission" then
			return string.format("Next race in %d", timeLeft)
		elseif state == "Countdown" then
			return "Get ready..."
		elseif state == "Racing" then
			local left = string.format("%d:%02d left", timeLeft // 60, timeLeft % 60)
			local startedAt = ReplicatedStorage:GetAttribute("RaceStartedAt")
			if isRacing() and not player:GetAttribute("Place") and startedAt then
				return clock(workspace:GetServerTimeNow() - startedAt) .. "   |   " .. left
			end
			return "Race in progress   |   " .. left
		elseif state == "Ended" then
			return "Race over"
		end
		return "Connecting..."
	end

	RunService.Heartbeat:Connect(function()
		status.Text = statusText()
	end)

	ReplicatedStorage:GetAttributeChangedSignal("State"):Connect(function()
		local state = ReplicatedStorage:GetAttribute("State")
		refreshStage()
		if state == "Racing" and player:GetAttribute("Checkpoint") ~= nil then
			bigText.Text = "GO!"
			bigText.TextColor3 = GREEN
			showFor(bigText, 1)
		elseif state ~= "Countdown" then
			bigText.Visible = false
		end
	end)

	ReplicatedStorage:GetAttributeChangedSignal("TimeLeft"):Connect(function()
		if ReplicatedStorage:GetAttribute("State") == "Countdown" and isRacing() then
			local timeLeft = ReplicatedStorage:GetAttribute("TimeLeft")
			if timeLeft and timeLeft > 0 then
				bigText.Text = tostring(timeLeft)
				bigText.TextColor3 = WHITE
				showFor(bigText, 1.2)
			end
		end
	end)

	local lastCheckpoint = 0
	player:GetAttributeChangedSignal("Checkpoint"):Connect(function()
		local checkpoint = player:GetAttribute("Checkpoint")
		local count = ReplicatedStorage:GetAttribute("StageCount") or Config.StageCount
		if checkpoint and checkpoint > lastCheckpoint and checkpoint < count then
			showToast(string.format("Checkpoint!  Stage %d / %d", checkpoint + 1, count), GREEN)
		end
		lastCheckpoint = checkpoint or 0
		refreshStage()
	end)
	player:GetAttributeChangedSignal("Place"):Connect(refreshStage)

	local api = {}

	function api.onReset()
		showToast("Oops! Back to your checkpoint")
	end

	function api.onPlayerFinished(name: string, place: number, seconds: number)
		local color = place == 1 and GOLD or WHITE
		showToast(string.format("%s finished %s  (%s)", name, ordinal(place), clock(seconds)), color)
	end

	function api.showResults(list: { any }, stageCount: number)
		local lines = { '<font size="26"><b>Race results</b></font>', "" }
		for i, entry in ipairs(list) do
			if i > 8 then
				table.insert(lines, string.format("...and %d more", #list - 8))
				break
			end
			local left = entry.place and ordinal(entry.place) or "DNF"
			local right = entry.place and clock(entry.time)
				or string.format("stage %d/%d", math.min(entry.checkpoint + 1, stageCount), stageCount)
			local line = string.format("<b>%s</b>   %s   <i>%s</i>   +%d coins", left, entry.name, right, entry.coins)
			if entry.name == player.DisplayName then
				line = '<font color="#FFCD46">' .. line .. "</font>"
			end
			table.insert(lines, line)
		end
		results.Text = table.concat(lines, "\n")
		showFor(results, Config.EndScreenSeconds)
		stage.Visible = false
	end

	return api
end

return HUD
]==],
	},
	{
		root = "StarterPlayerScripts",
		parent = "Client",
		name = "HazardWatcher",
		class = "ModuleScript",
		source = [==[
-- Sends the local character back to its checkpoint when it touches a hazard or
-- falls off the course. This runs on the client because obstacles move on the
-- client (see ObstacleAnimator), and it is safe to trust: the only thing a
-- client can do with it is send itself backwards.
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local HazardWatcher = {}

local player = Players.LocalPlayer

local FALL_DEPTH = 30
-- Roughly the character's body, from just below the feet to the head.
local BODY_SIZE = Vector3.new(2.6, 5.4, 2.2)
local BODY_OFFSET = CFrame.new(0, -0.6, 0)
local RESET_COOLDOWN = 0.5

function HazardWatcher.start(onReset: () -> ())
	local overlap = OverlapParams.new()
	overlap.FilterType = Enum.RaycastFilterType.Exclude
	local lastReset = 0

	RunService.Heartbeat:Connect(function()
		local respawnAt = player:GetAttribute("RespawnAt")
		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
		if typeof(respawnAt) ~= "Vector3" or not root or os.clock() - lastReset < RESET_COOLDOWN then
			return
		end

		local hit = root.Position.Y < respawnAt.Y - FALL_DEPTH
		if not hit then
			overlap.FilterDescendantsInstances = { character :: Model }
			for _, part in ipairs(workspace:GetPartBoundsInBox(root.CFrame * BODY_OFFSET, BODY_SIZE, overlap)) do
				if part:GetAttribute("Hazard") then
					hit = true
					break
				end
			end
		end
		if not hit then
			return
		end

		lastReset = os.clock()
		local target = respawnAt + Vector3.new(math.random(-4, 4), 0, math.random(-2, 2))
		;(character :: Model):PivotTo(CFrame.lookAt(target, target + Vector3.new(0, 0, 1)))
		root.AssemblyLinearVelocity = Vector3.zero
		onReset()
	end)
end

return HazardWatcher
]==],
	},
	{
		root = "StarterPlayerScripts",
		parent = "Client",
		name = "ObstacleAnimator",
		class = "ModuleScript",
		source = [==[
-- Animates the course's moving obstacles locally. Every client derives the same
-- motion from the shared server clock, so everyone sees the obstacles in the
-- same place without the server streaming positions every frame.
--
-- Parts are picked up as they stream in, and dropped when they leave.
local RunService = game:GetService("RunService")

local ObstacleAnimator = {}

type Tracked = {
	kind: string,
	base: CFrame,
	speed: number,
	period: number,
	phase: number,
	onFraction: number,
}

local tracked: { [BasePart]: Tracked } = {}

-- How long before a vanishing tile disappears it starts to flicker.
local WARNING_SECONDS = 0.5

local function track(instance: Instance)
	if not instance:IsA("BasePart") then
		return
	end
	local kind = instance:GetAttribute("Anim")
	if not kind then
		return
	end
	tracked[instance] = {
		kind = kind,
		base = instance.CFrame,
		speed = instance:GetAttribute("Speed") or 0,
		period = instance:GetAttribute("Period") or 1,
		phase = instance:GetAttribute("Phase") or 0,
		onFraction = instance:GetAttribute("OnFraction") or 0.5,
	}
end

local function update()
	local now = workspace:GetServerTimeNow()
	for part, info in pairs(tracked) do
		if info.kind == "Spin" then
			part.CFrame = info.base * CFrame.Angles(0, math.rad((now * info.speed) % 360), 0)
		else
			local cycle = (now / info.period + info.phase) % 1
			local on = cycle < info.onFraction
			if info.kind == "Fade" then
				local warning = on and cycle > info.onFraction - WARNING_SECONDS / info.period
				part.CanCollide = on
				part.Transparency = if not on then 0.85 elseif warning then 0.45 else 0
			elseif info.kind == "Laser" then
				-- CanQuery off takes the beam out of the hazard check while it is dark.
				part.CanQuery = on
				part.Transparency = if on then 0.2 else 0.92
			end
		end
	end
end

function ObstacleAnimator.start()
	for _, descendant in ipairs(workspace:GetDescendants()) do
		track(descendant)
	end
	workspace.DescendantAdded:Connect(track)
	workspace.DescendantRemoving:Connect(function(descendant)
		tracked[descendant :: BasePart] = nil
	end)
	RunService.RenderStepped:Connect(update)
end

return ObstacleAnimator
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

print(string.format("Obby Race installed - %d instances created:", #created))
for _, path in ipairs(created) do
	print("   " .. path)
end
print("Next: Test tab -> Play (solo works; Clients and Servers -> Players: 2+ to race others)")
