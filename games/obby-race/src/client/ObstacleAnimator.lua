-- Animates the course's moving obstacles locally. Every client derives the same
-- motion from the shared server clock, so everyone sees the obstacles in the
-- same place without the server streaming positions every frame.
--
-- Parts are picked up as they stream in, and dropped when they leave.
local RunService = game:GetService("RunService")

local ObstacleAnimator = {}

type Tracked = {
	kind: string,
	base: CFrame,
	speed: number,
	period: number,
	phase: number,
	onFraction: number,
}

local tracked: { [BasePart]: Tracked } = {}

-- How long before a vanishing tile disappears it starts to flicker.
local WARNING_SECONDS = 0.5

local function track(instance: Instance)
	if not instance:IsA("BasePart") then
		return
	end
	local kind = instance:GetAttribute("Anim")
	if not kind then
		return
	end
	tracked[instance] = {
		kind = kind,
		base = instance.CFrame,
		speed = instance:GetAttribute("Speed") or 0,
		period = instance:GetAttribute("Period") or 1,
		phase = instance:GetAttribute("Phase") or 0,
		onFraction = instance:GetAttribute("OnFraction") or 0.5,
	}
end

local function update()
	local now = workspace:GetServerTimeNow()
	for part, info in pairs(tracked) do
		if info.kind == "Spin" then
			part.CFrame = info.base * CFrame.Angles(0, math.rad((now * info.speed) % 360), 0)
		else
			local cycle = (now / info.period + info.phase) % 1
			local on = cycle < info.onFraction
			if info.kind == "Fade" then
				local warning = on and cycle > info.onFraction - WARNING_SECONDS / info.period
				part.CanCollide = on
				part.Transparency = if not on then 0.85 elseif warning then 0.45 else 0
			elseif info.kind == "Laser" then
				-- CanQuery off takes the beam out of the hazard check while it is dark.
				part.CanQuery = on
				part.Transparency = if on then 0.2 else 0.92
			end
		end
	end
end

function ObstacleAnimator.start()
	for _, descendant in ipairs(workspace:GetDescendants()) do
		track(descendant)
	end
	workspace.DescendantAdded:Connect(track)
	workspace.DescendantRemoving:Connect(function(descendant)
		tracked[descendant :: BasePart] = nil
	end)
	RunService.RenderStepped:Connect(update)
end

return ObstacleAnimator
