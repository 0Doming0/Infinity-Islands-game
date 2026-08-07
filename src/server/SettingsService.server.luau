local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SettingsPersistenceService = require(ReplicatedStorage.Shared.Utilities.SettingsPersistenceService)

SettingsPersistenceService.Start("Dungeon")
