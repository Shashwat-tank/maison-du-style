local Config = {
	-- One player is enough: a solo race is a time trial.
	MinPlayers = 1,

	IntermissionSeconds = 15,
	CountdownSeconds = 3,
	RaceSeconds = 240,
	-- Once someone finishes, everyone else has at most this long left.
	FinishWindowSeconds = 30,
	EndScreenSeconds = 8,

	-- Stages per course. Each race draws a fresh random course, getting harder
	-- toward the finish.
	StageCount = 8,

	Rewards = {
		Places = { 50, 30, 20 }, -- coins for 1st, 2nd, 3rd
		Finish = 10, -- coins for finishing outside the top places
		PerCheckpoint = 1, -- consolation coins for racers who do not finish
	},

	RemoteNames = { "PlayerFinished", "RaceResults" },
}

return Config
