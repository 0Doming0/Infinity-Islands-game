$ErrorActionPreference = "Stop"

$RepoRoot = Split-Path -Parent $PSScriptRoot
$RuntimePath = Join-Path $RepoRoot "src/server/DungeonRuntime/DungeonRuntimeService.lua"

if (-not (Test-Path $RuntimePath)) {
    throw "DungeonRuntimeService.lua nao encontrado: $RuntimePath"
}

$text = Get-Content -Raw -Path $RuntimePath

# Backup once.
$backup = "$RuntimePath.cleanboot.bak"
if (-not (Test-Path $backup)) {
    Copy-Item $RuntimePath $backup
}

# 1) ObjectiveSequenceService is only a facade over CombatRouteProgressionService.
$objectiveFacadePattern = '(?ms)local ObjectiveSequenceService = require\(\s*script\.Parent\.ObjectiveSequenceService\s*\)\s*'
$objectiveFacadeReplacement = @'
local CombatRouteProgressionService = require(
	script.Parent.CombatRouteProgressionService
)

'@
$text = [regex]::Replace(
    $text,
    $objectiveFacadePattern,
    $objectiveFacadeReplacement
)

# 2) Remove legacy services from the runtime critical require path.
$legacyNames = @(
    "ObjectiveService",
    "DungeonPacingService",
    "ObjectiveEncounterService",
    "RewardIslandService",
    "RunRewardLedgerService",
    "MobCollectibleService",
    "OptionalIslandService",
    "BossService",
    "BossEncounterDirector",
    "DungeonLegacyIsolationService"
)

foreach ($name in $legacyNames) {
    $pattern = "(?ms)local $name = require\(\s*script\.Parent\.$name\s*\)\s*"
    $text = [regex]::Replace($text, $pattern, "")
}

# DungeonLegacyIsolationService was only necessary while old auto scripts were allowed to start.
$text = [regex]::Replace(
    $text,
    '(?m)^\s*DungeonLegacyIsolationService\.Start\(\)\s*$',
    ''
)

# Direct progression authority.
$text = $text.Replace(
    "ObjectiveSequenceService",
    "CombatRouteProgressionService"
)

# 3) Remove the compatibility-shell startup block entirely.
$compatPattern = '(?ms)local function startCompatibilityShells\(\).*?^end\s*\r?\n\s*\r?\nlocal function startRouteProgression\(\)'
$text = [regex]::Replace(
    $text,
    $compatPattern,
    'local function startRouteProgression()'
)

$text = [regex]::Replace(
    $text,
    '(?m)^\s*startCompatibilityShells\(\)\s*$',
    ''
)

# 4) Replace legacy public snapshots with inert compatibility responses.
$legacyApiPattern = '(?ms)function DungeonRuntimeService\.GetObjectiveSnapshot\(\).*?(?=function DungeonRuntimeService\.GetRecoverySnapshot\(player\))'
$legacyApiReplacement = @'
local function legacyDisabledSnapshot(serviceName)
	return {
		Ready = false,
		Disabled = true,
		Service = serviceName,
		Reason = "SimplifiedCombatMVP",
	}
end

function DungeonRuntimeService.GetObjectiveSnapshot()
	return CombatRouteProgressionService.GetSnapshot()
end

function DungeonRuntimeService.GetObjectiveSequenceSnapshot()
	return CombatRouteProgressionService.GetSnapshot()
end

function DungeonRuntimeService.GetPacingSnapshot()
	return legacyDisabledSnapshot("DungeonPacingService")
end

function DungeonRuntimeService.GetEncounterSnapshot()
	return legacyDisabledSnapshot("ObjectiveEncounterService")
end

function DungeonRuntimeService.GetRewardSnapshot(_player)
	return legacyDisabledSnapshot("RewardIslandService")
end

function DungeonRuntimeService.ClaimRoundReward(...)
	return false, "RewardIslandsDisabled"
end

function DungeonRuntimeService.GetRunRewardLedgerSnapshot()
	return legacyDisabledSnapshot("RunRewardLedgerService")
end

function DungeonRuntimeService.SetEncounterCombatEnabled(_enabled)
	return true, "LegacyDisabled"
end

function DungeonRuntimeService.GetBossSnapshot()
	return legacyDisabledSnapshot("BossService")
end

function DungeonRuntimeService.ActivateBossForTesting(...)
	return false, "BossDisabled"
end

function DungeonRuntimeService.GetBossDirectorSnapshot()
	return legacyDisabledSnapshot("BossEncounterDirector")
end

function DungeonRuntimeService.GetMobCollectibleSnapshot()
	return legacyDisabledSnapshot("MobCollectibleService")
end

function DungeonRuntimeService.GetOptionalIslandSnapshot(_player)
	return legacyDisabledSnapshot("OptionalIslandService")
end

function DungeonRuntimeService.ClaimOptionalIslandReward(...)
	return false, "OptionalIslandsDisabled"
end

'@

if ([regex]::IsMatch($text, $legacyApiPattern)) {
    $text = [regex]::Replace(
        $text,
        $legacyApiPattern,
        $legacyApiReplacement
    )
} else {
    Write-Warning "Bloco de APIs legadas nao encontrado; nenhuma substituicao feita nessa secao."
}

Set-Content -Path $RuntimePath -Value $text -Encoding UTF8

# 5) Remove source files that are definitely auto-running legacy systems.
$legacyFiles = @(
    "src/server/BlockParkour/WaterRiseSystem_SkyDungeon_V10.server.luau",
    "src/server/PlayerSpawnSystem.server.luau",
    "src/server/SafeZoneProtection_V2.server.luau",
    "src/server/WorldEventService.server.luau",
    "src/server/PersonalSkyMerchantWorld.server.luau",
    "src/server/GlobalLeaderboardService.server.luau",
    "src/server/TutorialService.server.luau",
    "src/server/StartScreenPreviewAssets.server.luau",
    "src/server/VillagerAI.server.luau",
    "src/server/VillagerSystem.server.luau",
    "src/server/PartyBootstrap.server.luau",
    "src/server/RewardBootstrap.server.luau",
    "src/server/MonetizationBootstrap.server.luau",
    "src/server/ItemPickupController.server.luau",
    "src/server/MonsterAIService.server.luau",
    "src/server/MVPSystems/GenerationCloudService.server.luau",
    "src/server/MVPSystems/MVPHouses.server.luau",
    "src/server/MVPSystems/PersonalSkyMerchantTargetService.server.luau",
    "src/server/MVPSystems/InventoryBootstrap.server.luau",
    "src/server/DungeonGuidedIntroBootstrap.server.luau",
    "src/server/CompanionBootstrap.server.luau",
    "src/server/RelicBootstrap.server.luau",
    "src/server/RespawnProtectionService.server.luau"
)

foreach ($relative in $legacyFiles) {
    $path = Join-Path $RepoRoot $relative
    if (Test-Path $path) {
        Remove-Item -Force $path
        Write-Host "REMOVIDO: $relative"
    }
}

# The second HUD recovery system is unnecessary; the project now loads only EarlyClone.
$hudRecovery = Join-Path $RepoRoot "src/client/DungeonHUDRecovery.client.luau"
if (Test-Path $hudRecovery) {
    Remove-Item -Force $hudRecovery
    Write-Host "REMOVIDO: src/client/DungeonHUDRecovery.client.luau"
}

Write-Host ""
Write-Host "Clean Dungeon Boot aplicado."
Write-Host "Agora reinicie o Rojo usando dungeon.project.json e inicie um Play novo."
