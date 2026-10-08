-- The clue system is what makes this game different from a plain "hunt the killer" loop.
--
-- Clues spawn around the map. When an innocent examines one, the murderer's display name
-- is partly revealed to everyone ("_ a _ _ o _"), one more letter per clue. The murderer
-- can examine clues too, but that destroys them without revealing anything.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Remotes = require(Shared.Remotes)
local Util = require(Shared.Util)

local RoleService = require(script.Parent.RoleService)
local RoundState = require(script.Parent.RoundState)
local MapService = require(script.Parent.MapService)

local ClueService = {}

type Session = {
	chars: { string },
	order: { number }, -- reveal order (indices into chars)
	revealedCount: number,
	maxReveal: number,
}

local clues: { Instance } = {}
local session: Session? = nil

local function splitChars(text: string): { string }
	local chars = {}
	for _, codepoint in utf8.codes(text) do
		table.insert(chars, utf8.char(codepoint))
	end
	return chars
end

local function buildMask(current: Session): string
	local revealed = {}
	for i = 1, current.revealedCount do
		revealed[current.order[i]] = true
	end
	local out = {}
	for index, char in ipairs(current.chars) do
		table.insert(out, revealed[index] and char or "_")
	end
	return table.concat(out, " ")
end

local function onExamined(clue: Instance, player: Player)
	local current = session
	if not current or not RoundState.isInRound() then
		return
	end
	local role = RoleService.get(player)
	if not role or not RoleService.aliveHumanoid(player) then
		return
	end
	if not clue.Parent then
		return -- someone else got there first
	end

	local remote = Remotes.get("ClueFound")
	clue:Destroy()

	if role == Config.Roles.Murderer then
		remote:FireClient(player, "You destroyed a clue.", nil)
		return
	end

	if current.revealedCount >= current.maxReveal then
		remote:FireClient(player, "This clue tells you nothing new.", nil)
		return
	end

	current.revealedCount += 1
	local mask = buildMask(current)
	local message = player.DisplayName .. " found a clue!"
	for _, participant in ipairs(RoleService.participants()) do
		remote:FireClient(participant, message, mask)
	end
end

local function spawnClue(position: Vector3)
	local clue = Instance.new("Part")
	clue.Name = "Clue"
	clue.Shape = Enum.PartType.Ball
	clue.Size = Vector3.new(1.5, 1.5, 1.5)
	clue.Anchored = true
	clue.CanCollide = false
	clue.Material = Enum.Material.Neon
	clue.Color = Color3.fromRGB(255, 205, 80)
	clue.Position = position + Vector3.new(0, 1, 0)

	local prompt = Instance.new("ProximityPrompt")
	prompt.ActionText = "Examine"
	prompt.ObjectText = "Clue"
	prompt.HoldDuration = 0.5
	prompt.MaxActivationDistance = 8
	prompt.RequiresLineOfSight = false
	prompt.Triggered:Connect(function(player)
		onExamined(clue, player)
	end)
	prompt.Parent = clue

	clue.Parent = workspace
	table.insert(clues, clue)
end

function ClueService.start(murderer: Player)
	ClueService.stop()

	local chars = splitChars(murderer.DisplayName)
	local order = {}
	for index = 1, #chars do
		table.insert(order, index)
	end
	Util.shuffle(order)

	session = {
		chars = chars,
		order = order,
		revealedCount = 0,
		-- Never reveal more than half the name, so it stays a puzzle.
		maxReveal = math.max(1, #chars // 2),
	}

	local spots = Util.shuffle(MapService.getClueSpots())
	for index = 1, math.min(Config.ClueCount, #spots) do
		spawnClue(spots[index])
	end
end

function ClueService.stop()
	for _, clue in ipairs(clues) do
		clue:Destroy()
	end
	table.clear(clues)
	session = nil
end

return ClueService
