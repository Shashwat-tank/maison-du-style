-- Builds a fresh random course for every race. The course runs along +Z, high in
-- the sky above the lobby. Each stage ends in a checkpoint pad; the last pad is
-- the finish.
--
-- Moving obstacles are animated on each client (see ObstacleAnimator), driven by
-- the shared server clock, so they move smoothly and line up for everyone. They
-- are tagged with attributes here:
--   Hazard = true                  touching it sends you back to your checkpoint
--   Anim = "Spin"  Speed           rotates about its own vertical axis (deg/s)
--   Anim = "Fade" | "Laser"        on for OnFraction of each Period, offset by Phase
--
-- Distances are tuned for the default character: a running jump clears about
-- 8.5 studs on the flat and rises about 7, so gaps top out at 6.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("Shared").Config)

local CourseBuilder = {}

local ORIGIN = Vector3.new(0, 150, 300)
local START_SIZE = Vector3.new(40, 1, 24)
local PAD_SIZE = Vector3.new(24, 1, 10)
local FINISH_SIZE = Vector3.new(32, 1, 18)

local HAZARD_COLOR = Color3.fromRGB(255, 70, 40)
local DARK = Color3.fromRGB(45, 45, 55)
local PAD_COLOR = Color3.fromRGB(85, 200, 110)
local GOLD = Color3.fromRGB(255, 200, 60)

export type Checkpoint = { top: Vector3, size: Vector3 }
export type Course = {
	folder: Folder,
	gate: BasePart,
	stageCount: number,
	stageNames: { string },
	checkpoints: { [number]: Checkpoint }, -- 0 is the start pad, stageCount is the finish
}

type Builder = { folder: Folder, rng: Random, color: Color3 }

type PartSpec = {
	name: string,
	size: Vector3,
	cframe: CFrame,
	color: Color3?,
	material: Enum.Material?,
	transparency: number?,
	canCollide: boolean?,
	attributes: { [string]: any }?,
	class: string?,
}

local function lerp(a: number, b: number, t: number): number
	return a + (b - a) * t
end

-- Attributes are set before parenting so clients receive the part fully tagged.
local function block(b: Builder, spec: PartSpec): BasePart
	local part = Instance.new(spec.class or "Part") :: BasePart
	part.Name = spec.name
	part.Anchored = true
	part.Size = spec.size
	part.CFrame = spec.cframe
	part.Color = spec.color or b.color
	part.Material = spec.material or Enum.Material.SmoothPlastic
	part.Transparency = spec.transparency or 0
	if spec.canCollide ~= nil then
		part.CanCollide = spec.canCollide
	end
	for key, value in pairs(spec.attributes or {}) do
		part:SetAttribute(key, value)
	end
	part.Parent = b.folder
	return part
end

-- A platform whose top surface is centred on `top`.
local function slab(b: Builder, name: string, size: Vector3, top: Vector3, color: Color3?, material: Enum.Material?): BasePart
	return block(b, {
		name = name,
		size = size,
		cframe = CFrame.new(top - Vector3.new(0, size.Y / 2, 0)),
		color = color,
		material = material,
	})
end

local function sign(part: BasePart, text: string, color: Color3)
	local gui = Instance.new("BillboardGui")
	gui.Size = UDim2.fromScale(14, 3)
	gui.StudsOffset = Vector3.new(0, 7, 0)
	gui.MaxDistance = 150
	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Text = text
	label.TextScaled = true
	label.Font = Enum.Font.GothamBlack
	label.TextColor3 = color
	label.TextStrokeTransparency = 0.3
	label.Parent = gui
	gui.Parent = part
end

-- Each stage takes the point where it starts (centre of the entry edge, at
-- standing height) and a difficulty from 0 to 1, and returns where the next
-- checkpoint pad should begin.
type StageBuild = (b: Builder, start: Vector3, difficulty: number) -> Vector3

local function jumps(b: Builder, s: Vector3, d: number): Vector3
	local rng = b.rng
	local size = lerp(7, 4.5, d)
	local rises = { -1, 0, 0, 1, 2 }
	local function gap(rising: boolean): number
		local g = rng:NextNumber(lerp(2.5, 4, d), lerp(4, 6, d))
		return rising and math.min(g, 4) or g
	end

	local x, y, z = 0, s.Y, s.Z + gap(false)
	for i = 1, 7 do
		slab(b, "Jump" .. i, Vector3.new(size, 1, size), Vector3.new(x, y, z + size / 2))
		local rise = rises[rng:NextInteger(1, #rises)]
		y += rise
		x = math.clamp(x + rng:NextNumber(-0.8, 0.8) * size, -9, 9)
		z += size + gap(rise > 0)
	end
	return Vector3.new(0, y, z)
end

local function lava(b: Builder, s: Vector3, d: number): Vector3
	local rng = b.rng
	local size = lerp(5, 3.5, d)
	local x, z = 0, s.Z + rng:NextNumber(2.5, 4)
	for i = 1, 9 do
		slab(b, "Stone" .. i, Vector3.new(size, 2, size), Vector3.new(x, s.Y, z + size / 2), nil, Enum.Material.Slate)
		z += size + rng:NextNumber(lerp(2.5, 4, d), lerp(3.5, 5.5, d))
		x = math.clamp(x + rng:NextNumber(-1, 1) * size, -9, 9)
	end
	local length = z - s.Z
	block(b, {
		name = "Lava",
		size = Vector3.new(24, 1, length),
		cframe = CFrame.new(0, s.Y - 2, s.Z + length / 2),
		color = HAZARD_COLOR,
		material = Enum.Material.Neon,
		attributes = { Hazard = true },
	})
	return Vector3.new(0, s.Y, z)
end

local function spinners(b: Builder, s: Vector3, d: number): Vector3
	local rng = b.rng
	local count = 2 + math.floor(d * 2.99)
	local spacing = 22
	local length = count * spacing + 8
	-- The floor is exactly as wide as the sweep, so there is no way around a bar.
	slab(b, "Floor", Vector3.new(spacing, 1, length), Vector3.new(0, s.Y, s.Z + length / 2))

	local speed = lerp(70, 140, d)
	for i = 1, count do
		local center = Vector3.new(0, s.Y, s.Z + 4 + (i - 0.5) * spacing)
		block(b, { name = "Hub" .. i, size = Vector3.new(2, 3, 2), cframe = CFrame.new(center + Vector3.new(0, 1.5, 0)), color = DARK })

		-- Later stages turn some single bars into crosses, spun a little slower so
		-- the gap between sweeps stays longer than a jump.
		local arms = (d > 0.5 and i % 2 == 0) and 2 or 1
		local direction = i % 2 == 0 and 1 or -1
		local phase = rng:NextNumber(0, 360)
		for arm = 1, arms do
			block(b, {
				name = "Spinner" .. i .. "_" .. arm,
				size = Vector3.new(spacing - 1, 1, 1),
				cframe = CFrame.new(center + Vector3.new(0, 1.3, 0)) * CFrame.Angles(0, math.rad(phase + (arm - 1) * 90), 0),
				color = HAZARD_COLOR,
				material = Enum.Material.Neon,
				canCollide = false,
				attributes = { Hazard = true, Anim = "Spin", Speed = direction * speed / arms ^ 0.5 },
			})
		end
	end
	return Vector3.new(0, s.Y, s.Z + length)
end

local function vanishing(b: Builder, s: Vector3, d: number): Vector3
	local rng = b.rng
	local period = lerp(3.2, 2.4, d)
	local x, z = 0, s.Z + 3
	for i = 1, 7 do
		block(b, {
			name = "Tile" .. i,
			size = Vector3.new(6, 1, 6),
			cframe = CFrame.new(x, s.Y - 0.5, z + 3),
			material = Enum.Material.Glass,
			-- Each tile lags the one before it, so the solid window travels
			-- forward at roughly running speed.
			attributes = { Anim = "Fade", Period = period, Phase = (-0.15 * i) % 1, OnFraction = 0.6 },
		})
		z += 6 + 2.5
		x = math.clamp(x + rng:NextNumber(-4, 4), -8, 8)
	end
	return Vector3.new(0, s.Y, z + 0.5)
end

local function tightrope(b: Builder, s: Vector3, d: number): Vector3
	local rng = b.rng
	local width = lerp(2, 1.2, d)
	local segments = 4
	local side = rng:NextInteger(0, 1) == 0 and -1 or 1
	local from = Vector3.new(0, s.Y, s.Z)
	for i = 1, segments do
		local to = Vector3.new(i == segments and 0 or side * 7, s.Y, from.Z + 12)
		side = -side
		local mid = (from + to) / 2 - Vector3.new(0, 0.5, 0)
		block(b, {
			name = "Beam" .. i,
			size = Vector3.new(width, 1, (to - from).Magnitude + 1),
			cframe = CFrame.lookAt(mid, mid + (to - from)),
		})
		slab(b, "Perch" .. i, Vector3.new(4, 1, 4), to)
		from = to
	end
	return Vector3.new(0, s.Y, from.Z + 2)
end

local function lasers(b: Builder, s: Vector3, d: number): Vector3
	local rng = b.rng
	local count = 3 + math.floor(d * 2.99)
	local spacing = 12
	local length = count * spacing + 6
	slab(b, "Floor", Vector3.new(12, 1, length), Vector3.new(0, s.Y, s.Z + length / 2))

	local period = lerp(2.4, 1.8, d)
	for i = 1, count do
		local z = s.Z + 3 + (i - 0.5) * spacing
		for _, side in ipairs({ -1, 1 }) do
			block(b, { name = "Emitter", size = Vector3.new(1, 10, 1), cframe = CFrame.new(side * 6.5, s.Y + 5, z), color = DARK })
		end
		-- Taller than a jump can clear, so the only way through is timing.
		block(b, {
			name = "Laser" .. i,
			size = Vector3.new(12, 9, 0.4),
			cframe = CFrame.new(0, s.Y + 4.5, z),
			color = HAZARD_COLOR,
			material = Enum.Material.Neon,
			transparency = 0.2,
			canCollide = false,
			attributes = { Hazard = true, Anim = "Laser", Period = period, Phase = rng:NextNumber(), OnFraction = 0.5 },
		})
	end
	return Vector3.new(0, s.Y, s.Z + length)
end

local function climb(b: Builder, s: Vector3, _d: number): Vector3
	local function truss(bottom: Vector3, height: number)
		block(b, {
			class = "TrussPart",
			name = "Truss",
			size = Vector3.new(2, height, 2),
			cframe = CFrame.new(bottom + Vector3.new(0, height / 2, 0)),
			color = DARK,
		})
	end

	local y0 = s.Y
	slab(b, "Base", Vector3.new(12, 1, 8), Vector3.new(0, y0, s.Z + 4))
	truss(Vector3.new(0, y0, s.Z + 9), 14)
	local y1 = y0 + 14
	slab(b, "Ledge1", Vector3.new(8, 1, 6), Vector3.new(0, y1, s.Z + 13))
	slab(b, "Ledge2", Vector3.new(8, 1, 8), Vector3.new(0, y1, s.Z + 23))
	truss(Vector3.new(0, y1, s.Z + 28), 12)
	local y2 = y1 + 12
	slab(b, "Ledge3", Vector3.new(8, 1, 6), Vector3.new(0, y2, s.Z + 32))
	return Vector3.new(0, y2, s.Z + 35)
end

local WARMUP = { name = "Jumps", build = jumps :: StageBuild }
local STAGES = {
	WARMUP,
	{ name = "Lava Floor", build = lava :: StageBuild },
	{ name = "Spinners", build = spinners :: StageBuild },
	{ name = "Vanishing Tiles", build = vanishing :: StageBuild },
	{ name = "Tightrope", build = tightrope :: StageBuild },
	{ name = "Laser Hall", build = lasers :: StageBuild },
	{ name = "Tower Climb", build = climb :: StageBuild },
}

-- Always open with the warm-up, then deal stages from a shuffled bag so every
-- type appears before any repeats, and never the same type twice in a row.
local function chooseStages(rng: Random, count: number)
	local order = { WARMUP }
	local bag = {}
	while #order < count do
		if #bag == 0 then
			bag = table.clone(STAGES)
			for i = #bag, 2, -1 do
				local j = rng:NextInteger(1, i)
				bag[i], bag[j] = bag[j], bag[i]
			end
		end
		local pick = table.remove(bag)
		if pick == order[#order] and #bag > 0 then
			bag[1], pick = pick, bag[1]
		end
		table.insert(order, pick)
	end
	return order
end

function CourseBuilder.build(seed: number): Course
	local existing = workspace:FindFirstChild("Course")
	if existing then
		existing:Destroy()
	end

	local folder = Instance.new("Folder")
	folder.Name = "Course"
	local rng = Random.new(seed)
	local count = Config.StageCount
	local stages = chooseStages(rng, count)

	local b: Builder = { folder = folder, rng = rng, color = Color3.new(1, 1, 1) }
	local checkpoints: { [number]: Checkpoint } = {}
	local names = {}

	local start = slab(b, "Start", START_SIZE, ORIGIN + Vector3.new(0, 0, START_SIZE.Z / 2), Color3.fromRGB(90, 90, 110))
	sign(start, "Stage 1 · " .. stages[1].name, Color3.new(1, 1, 1))
	checkpoints[0] = { top = ORIGIN + Vector3.new(0, 0, START_SIZE.Z / 2), size = START_SIZE }
	local gate = block(b, {
		name = "StartGate",
		size = Vector3.new(START_SIZE.X, 14, 1),
		cframe = CFrame.new(ORIGIN + Vector3.new(0, 7, START_SIZE.Z - 0.5)),
		color = Color3.fromRGB(120, 200, 255),
		material = Enum.Material.Glass,
		transparency = 0.6,
	})

	local cursor = ORIGIN + Vector3.new(0, 0, START_SIZE.Z)
	for i, stage in ipairs(stages) do
		names[i] = stage.name
		b.color = Color3.fromHSV((i - 1) / count, 0.45, 0.95)
		local exit = stage.build(b, cursor, (i - 1) / math.max(count - 1, 1))

		local isFinish = i == count
		local size = isFinish and FINISH_SIZE or PAD_SIZE
		local top = Vector3.new(0, exit.Y, exit.Z + size.Z / 2)
		local pad = slab(b, isFinish and "Finish" or ("Checkpoint" .. i), size, top, isFinish and GOLD or PAD_COLOR)
		checkpoints[i] = { top = top, size = size }

		if isFinish then
			pad.Material = Enum.Material.Neon
			sign(pad, "FINISH", GOLD)
		else
			sign(pad, string.format("Stage %d · %s", i + 1, stages[i + 1].name), Color3.new(1, 1, 1))
		end
		cursor = Vector3.new(0, exit.Y, exit.Z + size.Z)
	end

	folder.Parent = workspace

	ReplicatedStorage:SetAttribute("StageCount", count)
	ReplicatedStorage:SetAttribute("StageNames", table.concat(names, "|"))

	return {
		folder = folder,
		gate = gate,
		stageCount = count,
		stageNames = names,
		checkpoints = checkpoints,
	}
end

-- A plain lobby, only if the place does not already have a spawn.
function CourseBuilder.ensureLobby()
	if workspace:FindFirstChildWhichIsA("SpawnLocation", true) then
		return
	end
	local lobby = Instance.new("Folder")
	lobby.Name = "Lobby"
	local b: Builder = { folder = lobby, rng = Random.new(), color = Color3.fromRGB(70, 70, 90) }
	slab(b, "Floor", Vector3.new(80, 1, 80), Vector3.new(0, 0, 0))

	local spawn = Instance.new("SpawnLocation")
	spawn.Anchored = true
	spawn.Neutral = true
	spawn.Duration = 0
	spawn.Size = Vector3.new(12, 1, 12)
	spawn.Position = Vector3.new(0, 0.5, 0)
	spawn.Parent = lobby
	lobby.Parent = workspace
end

return CourseBuilder
