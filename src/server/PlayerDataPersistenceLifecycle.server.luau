-- PlayerDataPersistenceLifecycle
--
-- Autoridade unica do ciclo de vida de persistencia em producao.
-- Nao define schema e nao altera gameplay: apenas garante autosave, save na
-- saida do jogador e save no fechamento do servidor usando o servico canonico.
--
-- Studio fica explicitamente fora deste fluxo porque 000_StudioFreshPlayerData
-- usa perfis temporarios para testes e nunca deve tocar no DataStore real.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ServerScriptService = game:GetService("ServerScriptService")

local VERSION = "PlayerDataPersistenceLifecycleV1"
local AUTOSAVE_SECONDS = 60
local CLOSE_WAIT_SECONDS = 20

if RunService:IsStudio() then
	workspace:SetAttribute("DungeonPlayerDataPersistenceLifecycleVersion", VERSION)
	workspace:SetAttribute("DungeonPlayerDataPersistenceLifecyclePolicy", "StudioFreshData_NoPersistentWrites")
	workspace:SetAttribute("DungeonPlayerDataProductionAutosaveEnabled", false)
	return
end

local PlayerDataService = require(
	ServerScriptService.BlockParkour:WaitForChild("PlayerDataService_SkyDungeon_V10")
)

local shuttingDown = false
local leaving = setmetatable({}, { __mode = "k" })

local function savePlayer(player, reason)
	if not player or not PlayerDataService.CanSave(player) then
		return true
	end

	local ok, saved = pcall(PlayerDataService.Save, player, true)
	local success = ok and saved == true

	player:SetAttribute("DungeonLastPersistenceSaveReason", reason)
	player:SetAttribute("DungeonLastPersistenceSaveSucceeded", success)
	player:SetAttribute("DungeonLastPersistenceSaveAt", workspace:GetServerTimeNow())

	if not success then
		warn(string.format(
			"[PlayerDataPersistenceLifecycle] Falha ao salvar %s (%s): %s",
			player.Name,
			tostring(reason),
			tostring(ok and saved or "SaveException")
		))
	end

	return success
end

local function saveAndRelease(player, reason)
	if leaving[player] then
		return
	end
	leaving[player] = true

	savePlayer(player, reason)

	local ok, err = pcall(PlayerDataService.Release, player)
	if not ok then
		warn(string.format(
			"[PlayerDataPersistenceLifecycle] Falha ao liberar sessao de %s: %s",
			player.Name,
			tostring(err)
		))
	end
end

Players.PlayerRemoving:Connect(function(player)
	saveAndRelease(player, shuttingDown and "ServerClosing" or "PlayerRemoving")
end)

task.spawn(function()
	while not shuttingDown do
		task.wait(AUTOSAVE_SECONDS)
		if shuttingDown then
			break
		end

		for _, player in ipairs(Players:GetPlayers()) do
			task.spawn(savePlayer, player, "Autosave")
		end
	end
end)

game:BindToClose(function()
	if shuttingDown then
		return
	end
	shuttingDown = true

	local pending = 0
	for _, player in ipairs(Players:GetPlayers()) do
		if not leaving[player] then
			pending += 1
			task.spawn(function()
				saveAndRelease(player, "BindToClose")
				pending -= 1
			end)
		end
	end

	local deadline = os.clock() + CLOSE_WAIT_SECONDS
	while pending > 0 and os.clock() < deadline do
		task.wait(0.05)
	end

	workspace:SetAttribute("DungeonPlayerDataLastServerClosePendingSaves", pending)
end)

workspace:SetAttribute("DungeonPlayerDataPersistenceLifecycleVersion", VERSION)
workspace:SetAttribute("DungeonPlayerDataPersistenceLifecyclePolicy", "Autosave_PlayerRemoving_BindToClose")
workspace:SetAttribute("DungeonPlayerDataProductionAutosaveEnabled", true)
workspace:SetAttribute("DungeonPlayerDataProductionAutosaveSeconds", AUTOSAVE_SECONDS)
