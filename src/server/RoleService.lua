local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Util = require(Shared.Util)

local RoleService = {}

-- Roles are server-only. Each client is told only its own role.
local roles: { [Player]: string } = {}

function RoleService.assign(players: { Player })
	table.clear(roles)
	local pool = Util.shuffle(table.clone(players))
	for index, player in ipairs(pool) do
		if index == 1 then
			roles[player] = Config.Roles.Murderer
		elseif index == 2 and #pool >= 3 then
			roles[player] = Config.Roles.Detective
		else
			roles[player] = Config.Roles.Innocent
		end
	end
end

function RoleService.get(player: Player): string?
	return roles[player]
end

function RoleService.remove(player: Player)
	roles[player] = nil
end

function RoleService.clear()
	table.clear(roles)
end

function RoleService.participants(): { Player }
	local list = {}
	for player in pairs(roles) do
		table.insert(list, player)
	end
	return list
end

function RoleService.findByRole(role: string): Player?
	for player, assigned in pairs(roles) do
		if assigned == role then
			return player
		end
	end
	return nil
end

function RoleService.aliveHumanoid(player: Player): Humanoid?
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if humanoid and humanoid.Health > 0 then
		return humanoid
	end
	return nil
end

return RoleService
