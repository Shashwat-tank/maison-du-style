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
