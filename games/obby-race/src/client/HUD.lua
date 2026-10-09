local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Config = require(ReplicatedStorage:WaitForChild("Shared").Config)

local HUD = {}

local player = Players.LocalPlayer

local WHITE = Color3.new(1, 1, 1)
local PANEL = Color3.fromRGB(20, 20, 28)
local GREEN = Color3.fromRGB(110, 230, 140)
local GOLD = Color3.fromRGB(255, 205, 70)

local function make(className: string, props: { [string]: any }, parent: Instance): any
	local instance = Instance.new(className)
	for key, value in pairs(props) do
		instance[key] = value
	end
	instance.Parent = parent
	return instance
end

local function panel(props: { [string]: any }, parent: Instance): TextLabel
	props.BackgroundColor3 = props.BackgroundColor3 or PANEL
	props.BackgroundTransparency = props.BackgroundTransparency or 0.3
	props.TextColor3 = props.TextColor3 or WHITE
	props.Font = props.Font or Enum.Font.GothamBold
	props.TextSize = props.TextSize or 18
	props.TextWrapped = true
	local label = make("TextLabel", props, parent)
	make("UICorner", { CornerRadius = UDim.new(0, 8) }, label)
	return label
end

local function ordinal(n: number): string
	local lastTwo = n % 100
	if lastTwo >= 11 and lastTwo <= 13 then
		return n .. "th"
	end
	return n .. (({ "st", "nd", "rd" })[n % 10] or "th")
end

local function clock(seconds: number): string
	return string.format("%d:%04.1f", seconds // 60, seconds % 60)
end

local function stageNames(): { string }
	return string.split(ReplicatedStorage:GetAttribute("StageNames") or "", "|")
end

function HUD.init()
	local gui = make("ScreenGui", { Name = "ObbyHUD", ResetOnSpawn = false }, player:WaitForChild("PlayerGui"))

	local status = panel({
		Size = UDim2.fromOffset(380, 40),
		Position = UDim2.new(0.5, 0, 0, 12),
		AnchorPoint = Vector2.new(0.5, 0),
	}, gui)

	-- Top-left: the top-right belongs to Roblox's player list.
	local stage = panel({
		Size = UDim2.fromOffset(240, 56),
		Position = UDim2.new(0, 12, 0, 12),
		Visible = false,
	}, gui)

	local bigText = make("TextLabel", {
		Size = UDim2.fromOffset(400, 140),
		Position = UDim2.fromScale(0.5, 0.35),
		AnchorPoint = Vector2.new(0.5, 0.5),
		BackgroundTransparency = 1,
		Font = Enum.Font.GothamBlack,
		TextSize = 110,
		TextColor3 = WHITE,
		TextStrokeTransparency = 0.2,
		Visible = false,
	}, gui)

	local toast = panel({
		Size = UDim2.fromOffset(380, 36),
		Position = UDim2.new(0.5, 0, 1, -90),
		AnchorPoint = Vector2.new(0.5, 1),
		TextSize = 16,
		Visible = false,
	}, gui)

	local results = panel({
		BackgroundTransparency = 0.1,
		Size = UDim2.fromOffset(420, 300),
		Position = UDim2.fromScale(0.5, 0.45),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Font = Enum.Font.GothamMedium,
		TextSize = 18,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Top,
		RichText = true,
		Visible = false,
	}, gui)
	make("UIPadding", {
		PaddingTop = UDim.new(0, 16),
		PaddingLeft = UDim.new(0, 20),
		PaddingRight = UDim.new(0, 20),
	}, results)

	-- Each timed message gets a token so an older timer can't hide a newer one.
	local tokens = {}
	local function showFor(label: GuiObject, seconds: number)
		tokens[label] = (tokens[label] or 0) + 1
		local token = tokens[label]
		label.Visible = true
		task.delay(seconds, function()
			if tokens[label] == token then
				label.Visible = false
			end
		end)
	end

	local function showToast(message: string, color: Color3?)
		toast.Text = message
		toast.TextColor3 = color or WHITE
		showFor(toast, 3)
	end

	local function isRacing(): boolean
		local state = ReplicatedStorage:GetAttribute("State")
		return player:GetAttribute("Checkpoint") ~= nil and (state == "Countdown" or state == "Racing")
	end

	local function refreshStage()
		local checkpoint = player:GetAttribute("Checkpoint")
		local count = ReplicatedStorage:GetAttribute("StageCount") or Config.StageCount
		stage.Visible = isRacing()
		if not checkpoint then
			return
		end
		local place = player:GetAttribute("Place")
		if place then
			stage.Text = "FINISHED\n" .. ordinal(place) .. " place"
			stage.TextColor3 = GOLD
		else
			local current = math.min(checkpoint + 1, count)
			stage.Text = string.format("Stage %d / %d\n%s", current, count, stageNames()[current] or "")
			stage.TextColor3 = WHITE
		end
	end

	local function statusText(): string
		local state = ReplicatedStorage:GetAttribute("State")
		local timeLeft = ReplicatedStorage:GetAttribute("TimeLeft") or 0
		if state == "Waiting" then
			return string.format("Waiting for players (%d/%d)", #Players:GetPlayers(), Config.MinPlayers)
		elseif state == "Intermission" then
			return string.format("Next race in %d", timeLeft)
		elseif state == "Countdown" then
			return "Get ready..."
		elseif state == "Racing" then
			local left = string.format("%d:%02d left", timeLeft // 60, timeLeft % 60)
			local startedAt = ReplicatedStorage:GetAttribute("RaceStartedAt")
			if isRacing() and not player:GetAttribute("Place") and startedAt then
				return clock(workspace:GetServerTimeNow() - startedAt) .. "   |   " .. left
			end
			return "Race in progress   |   " .. left
		elseif state == "Ended" then
			return "Race over"
		end
		return "Connecting..."
	end

	RunService.Heartbeat:Connect(function()
		status.Text = statusText()
	end)

	ReplicatedStorage:GetAttributeChangedSignal("State"):Connect(function()
		local state = ReplicatedStorage:GetAttribute("State")
		refreshStage()
		if state == "Racing" and player:GetAttribute("Checkpoint") ~= nil then
			bigText.Text = "GO!"
			bigText.TextColor3 = GREEN
			showFor(bigText, 1)
		elseif state ~= "Countdown" then
			bigText.Visible = false
		end
	end)

	ReplicatedStorage:GetAttributeChangedSignal("TimeLeft"):Connect(function()
		if ReplicatedStorage:GetAttribute("State") == "Countdown" and isRacing() then
			local timeLeft = ReplicatedStorage:GetAttribute("TimeLeft")
			if timeLeft and timeLeft > 0 then
				bigText.Text = tostring(timeLeft)
				bigText.TextColor3 = WHITE
				showFor(bigText, 1.2)
			end
		end
	end)

	local lastCheckpoint = 0
	player:GetAttributeChangedSignal("Checkpoint"):Connect(function()
		local checkpoint = player:GetAttribute("Checkpoint")
		local count = ReplicatedStorage:GetAttribute("StageCount") or Config.StageCount
		if checkpoint and checkpoint > lastCheckpoint and checkpoint < count then
			showToast(string.format("Checkpoint!  Stage %d / %d", checkpoint + 1, count), GREEN)
		end
		lastCheckpoint = checkpoint or 0
		refreshStage()
	end)
	player:GetAttributeChangedSignal("Place"):Connect(refreshStage)

	local api = {}

	function api.onReset()
		showToast("Oops! Back to your checkpoint")
	end

	function api.onPlayerFinished(name: string, place: number, seconds: number)
		local color = place == 1 and GOLD or WHITE
		showToast(string.format("%s finished %s  (%s)", name, ordinal(place), clock(seconds)), color)
	end

	function api.showResults(list: { any }, stageCount: number)
		local lines = { '<font size="26"><b>Race results</b></font>', "" }
		for i, entry in ipairs(list) do
			if i > 8 then
				table.insert(lines, string.format("...and %d more", #list - 8))
				break
			end
			local left = entry.place and ordinal(entry.place) or "DNF"
			local right = entry.place and clock(entry.time)
				or string.format("stage %d/%d", math.min(entry.checkpoint + 1, stageCount), stageCount)
			local line = string.format("<b>%s</b>   %s   <i>%s</i>   +%d coins", left, entry.name, right, entry.coins)
			if entry.name == player.DisplayName then
				line = '<font color="#FFCD46">' .. line .. "</font>"
			end
			table.insert(lines, line)
		end
		results.Text = table.concat(lines, "\n")
		showFor(results, Config.EndScreenSeconds)
		stage.Visible = false
	end

	return api
end

return HUD
