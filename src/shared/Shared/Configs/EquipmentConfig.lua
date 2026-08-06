local EquipmentConfig = {
	Wings = {
		AzureWings = { DisplayName = "Asas do Ceu", AssetName = "AzureWings" },
		RoyalWings = { DisplayName = "Asas Reais", AssetName = "RoyalWings" },
		CelestialWings = { DisplayName = "Asas Celestiais", AssetName = "CelestialWings" },
	},
	Abilities = {
		GroundSlam = { DisplayName = "Impacto no Chao", AssetName = "GroundSlam" },
	},
}

function EquipmentConfig.Get(category, equipmentId)
	local entries = EquipmentConfig[category]
	return entries and entries[equipmentId] or nil
end

return EquipmentConfig
