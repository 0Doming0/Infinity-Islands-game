-- Inicializador canonico e primeiro guard do Place de Dungeon.
-- Estes atributos precisam existir antes dos scripts legados iniciarem.
workspace:SetAttribute("GamePlaceType", "Dungeon")
workspace:SetAttribute("DungeonRuntimeManaged", true)
workspace:SetAttribute("DungeonCanonicalBootstrap", script:GetFullName())

local DungeonRuntimeService = require(script.Parent.Parent.DungeonRuntime.DungeonRuntimeService)
DungeonRuntimeService.Start()
