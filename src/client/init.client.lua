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
