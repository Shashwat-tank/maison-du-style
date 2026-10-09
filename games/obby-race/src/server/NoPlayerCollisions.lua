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
