-- SkyDungeon legacy entrypoint guard V1
-- O Place de Dungeon possui um bootstrap canonico. Sistemas antigos aguardam a
-- identificacao do Place e encerram antes de registrar eventos ou criar mundo.
do
	local ReplicatedStorage = game:GetService("ReplicatedStorage")
	local isDungeonPlace = false
	local shared = ReplicatedStorage:FindFirstChild("Shared")
	local configs = shared and shared:FindFirstChild("Configs")
	local placeConfigModule = configs and configs:FindFirstChild("PlaceConfig")
	if placeConfigModule then
		local ok, placeConfig = pcall(require, placeConfigModule)
		isDungeonPlace = ok
			and type(placeConfig) == "table"
			and tonumber(placeConfig.DungeonPlaceId) ~= nil
			and tonumber(placeConfig.DungeonPlaceId) > 0
			and game.PlaceId == tonumber(placeConfig.DungeonPlaceId)
	end
	local placeType = workspace:GetAttribute("GamePlaceType")
	if not isDungeonPlace and placeType == nil then
		local deadline = os.clock() + 8
		repeat
			task.wait(0.05)
			placeType = workspace:GetAttribute("GamePlaceType")
		until placeType ~= nil
			or workspace:GetAttribute("DungeonRuntimeManaged") == true
			or os.clock() >= deadline
	end
	if isDungeonPlace
		or placeType == "Dungeon"
		or workspace:GetAttribute("DungeonRuntimeManaged") == true
	then
		return
	end
end

-- Bootstrap de compatibilidade. A implementacao autoritativa vive no modulo
-- SanctuaryService para ser reutilizada pela agua, combate e respawn.

local SanctuaryService = require(script.Parent:WaitForChild("SanctuaryService"))

SanctuaryService.Start()
