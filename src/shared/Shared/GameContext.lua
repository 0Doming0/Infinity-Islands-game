local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local PlaceConfig = require(script.Parent.Configs.PlaceConfig)

local GameContext = {
	CurrentPlaceType = "Dungeon",
}

local function inferredPlaceType()
	if PlaceConfig.LobbyPlaceId > 0 and game.PlaceId == PlaceConfig.LobbyPlaceId then
		return "Lobby"
	end
	return "Dungeon"
end

GameContext.CurrentPlaceType = inferredPlaceType()

function GameContext.SetCurrentPlaceType(placeType)
	assert(placeType == "Lobby" or placeType == "Dungeon", "GameContext invalido")
	GameContext.CurrentPlaceType = placeType
	if RunService:IsServer() then
		local shared = ReplicatedStorage:FindFirstChild("Shared")
		if shared then
			shared:SetAttribute("CurrentPlaceType", placeType)
		end
	end
end

function GameContext.GetCurrentPlaceType()
	local shared = ReplicatedStorage:FindFirstChild("Shared")
	local replicated = shared and shared:GetAttribute("CurrentPlaceType")
	if replicated == "Lobby" or replicated == "Dungeon" then
		GameContext.CurrentPlaceType = replicated
	end
	return GameContext.CurrentPlaceType
end

function GameContext.IsLobby()
	return GameContext.GetCurrentPlaceType() == "Lobby"
end

function GameContext.IsDungeon()
	return GameContext.GetCurrentPlaceType() == "Dungeon"
end

return GameContext
