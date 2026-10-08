local RunService = game:GetService("RunService")

local Config = {
	-- Fewer players are needed in Studio so you can test with 2 local clients.
	MinPlayers = RunService:IsStudio() and 2 or 3,

	IntermissionSeconds = 20,
	RoundSeconds = 180,
	EndScreenSeconds = 8,
	LobbyRespawnSeconds = 3,

	-- Combat
	StabRange = 7,
	StabCooldown = 1,
	ShotRange = 300,
	ShotCooldown = 4,

	-- Clues
	ClueCount = 10,

	-- Arena. HalfSize is half the floor width, so the floor is twice this across.
	-- Raise it for a bigger map; cover, spawns and clue spots scale with it.
	Arena = {
		HalfSize = 110,
		WallHeight = 26,
	},

	Rewards = {
		InnocentWin = 25,
		MurdererWin = 50,
	},

	Roles = {
		Murderer = "Murderer",
		Detective = "Detective",
		Innocent = "Innocent",
	},

	Winners = {
		Murderer = "Murderer",
		Innocents = "Innocents",
	},

	RemoteNames = { "RoleAssigned", "ClueFound", "RoundEnded", "Shoot" },
}

return Config
