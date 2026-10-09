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
