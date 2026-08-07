$ErrorActionPreference = "Stop"

$expectedBranch = "agent/lobby-mvp-integration"
$currentBranch = (git branch --show-current).Trim()

if ($currentBranch -ne $expectedBranch) {
    throw "Branch atual: '$currentBranch'. Troque para '$expectedBranch' antes de executar."
}

$dirty = git status --porcelain
if ($dirty) {
    throw "O working tree possui alteracoes locais. Commit/stash essas alteracoes antes de aplicar este fix para nao misturar escopos."
}

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$patchPath = Join-Path $scriptDir "infinity-islands-onboarding-teleport-fix.patch"

if (-not (Test-Path $patchPath)) {
    throw "Patch nao encontrado ao lado deste script: $patchPath"
}

git apply --check $patchPath
git apply $patchPath
git diff --check

$paths = @(
    "tools/MigrateGameContent.server.luau",
    "src/server/DungeonRuntime/PhaseRegistry.lua",
    "src/lobby/server/LobbyGuidedIntroProgressService.lua",
    "src/lobby/server/LobbyGuidedIntroRedirectService.lua",
    "src/lobby/server/LobbyBootstrap.server.luau",
    "src/lobby/server/TeleportCoordinator.lua",
    "lobby.project.json",
    "src/server/DungeonGuidedIntroBootstrap.server.luau"
)

git add -- $paths
git diff --cached --check

git commit -m "fix onboarding and dungeon teleport"
git push origin $expectedBranch

Write-Host ""
Write-Host "Fix aplicado e enviado para $expectedBranch."
Write-Host "Agora sincronize/publice primeiro a Dungeon e depois o Lobby no Roblox Studio."
