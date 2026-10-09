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
