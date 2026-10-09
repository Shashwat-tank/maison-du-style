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
