-- Bootstrap de compatibilidade. A implementacao autoritativa vive no modulo
-- SanctuaryService para ser reutilizada pela agua, combate e respawn.

local SanctuaryService = require(script.Parent:WaitForChild("SanctuaryService"))

SanctuaryService.Start()
