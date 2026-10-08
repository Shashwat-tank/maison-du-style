local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Remotes = require(Shared.Remotes)

local RoleService = require(script.Parent.RoleService)
local RoundState = require(script.Parent.RoundState)

local CombatService = {}

-- Weak keys so entries disappear when a player leaves.
local lastStab: { [Player]: number } = setmetatable({}, { __mode = "k" })
local lastShot: { [Player]: number } = setmetatable({}, { __mode = "k" })

local function makeTool(name: string, handleSize: Vector3, color: Color3): Tool
	local tool = Instance.new("Tool")
	tool.Name = name
	tool.CanBeDropped = false
	tool.RequiresHandle = true

	local handle = Instance.new("Part")
	handle.Name = "Handle"
	handle.Size = handleSize
	handle.Color = color
	handle.Material = Enum.Material.Metal
	handle.Parent = tool

	return tool
end

local function giveAndEquip(player: Player, tool: Tool)
	local backpack = player:FindFirstChildOfClass("Backpack")
	if not backpack then
		tool:Destroy()
		return
	end
	tool.Parent = backpack
	local humanoid = RoleService.aliveHumanoid(player)
	if humanoid then
		humanoid:EquipTool(tool)
	end
end

local function stab(player: Player)
	if not RoundState.isInRound() or RoleService.get(player) ~= Config.Roles.Murderer then
		return
	end
	if not RoleService.aliveHumanoid(player) then
		return
	end

	local now = os.clock()
	if now - (lastStab[player] or 0) < Config.StabCooldown then
		return
	end
	lastStab[player] = now

	local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
	if not root then
		return
	end

	-- Hit the nearest living player within range and roughly in front of us.
	local bestHumanoid: Humanoid? = nil
	local bestDistance = Config.StabRange
	for _, other in ipairs(RoleService.participants()) do
		if other ~= player then
			local humanoid = RoleService.aliveHumanoid(other)
			local otherRoot = humanoid and other.Character and other.Character:FindFirstChild("HumanoidRootPart")
			if otherRoot then
				local offset = otherRoot.Position - root.Position
				local distance = offset.Magnitude
				local inFront = distance < 1 or offset.Unit:Dot(root.CFrame.LookVector) > 0.2
				if distance <= bestDistance and inFront then
					bestDistance = distance
					bestHumanoid = humanoid
				end
			end
		end
	end

	if bestHumanoid then
		bestHumanoid.Health = 0
	end
end

local function shoot(player: Player, aimPosition: any)
	-- Never trust the client: validate the argument type and magnitude.
	if typeof(aimPosition) ~= "Vector3" then
		return
	end
	if not RoundState.isInRound() or RoleService.get(player) ~= Config.Roles.Detective then
		return
	end
	if not RoleService.aliveHumanoid(player) then
		return
	end

	local now = os.clock()
	if now - (lastShot[player] or 0) < Config.ShotCooldown then
		return
	end
	lastShot[player] = now

	local character = player.Character
	local head = character and character:FindFirstChild("Head")
	if not head then
		return
	end

	local direction = aimPosition - head.Position
	local magnitude = direction.Magnitude
	if not (magnitude >= 1 and magnitude < 1e5) then -- also rejects NaN / inf
		return
	end

	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { character }
	local result = workspace:Raycast(head.Position, direction.Unit * Config.ShotRange, params)
	if not result then
		return
	end

	local model = result.Instance:FindFirstAncestorOfClass("Model")
	local victim = model and Players:GetPlayerFromCharacter(model)
	local victimRole = victim and RoleService.get(victim)
	local victimHumanoid = victim and RoleService.aliveHumanoid(victim)
	if not victim or not victimRole or not victimHumanoid then
		return
	end

	victimHumanoid.Health = 0

	-- Shooting an innocent is fatal for the detective too.
	if victimRole ~= Config.Roles.Murderer then
		local selfHumanoid = RoleService.aliveHumanoid(player)
		if selfHumanoid then
			selfHumanoid.Health = 0
		end
	end
end

function CombatService.giveKnife(player: Player)
	local tool = makeTool("Knife", Vector3.new(0.4, 0.4, 3), Color3.fromRGB(200, 40, 40))
	tool.Activated:Connect(function()
		stab(player)
	end)
	giveAndEquip(player, tool)
end

function CombatService.giveGun(player: Player)
	-- The client reads the "Revolver" name to hook up aiming (see GunController).
	local tool = makeTool("Revolver", Vector3.new(0.4, 0.8, 1.6), Color3.fromRGB(60, 60, 200))
	giveAndEquip(player, tool)
end

function CombatService.init()
	Remotes.get("Shoot").OnServerEvent:Connect(shoot)
end

return CombatService
