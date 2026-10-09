-- Single source of truth for round state. Stored as attributes on ReplicatedStorage
-- so the client HUD can read it without extra remotes.
--   State: "Waiting" | "Intermission" | "Starting" | "InRound" | "Ended"
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local RoundState = {}

function RoundState.set(state: string)
	ReplicatedStorage:SetAttribute("State", state)
end

function RoundState.get(): string?
	return ReplicatedStorage:GetAttribute("State")
end

function RoundState.isInRound(): boolean
	return RoundState.get() == "InRound"
end

function RoundState.setTimeLeft(seconds: number)
	ReplicatedStorage:SetAttribute("TimeLeft", seconds)
end

return RoundState
