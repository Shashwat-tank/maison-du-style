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
