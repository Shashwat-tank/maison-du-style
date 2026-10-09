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
