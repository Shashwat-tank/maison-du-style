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
