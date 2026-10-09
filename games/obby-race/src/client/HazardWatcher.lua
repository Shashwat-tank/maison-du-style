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
