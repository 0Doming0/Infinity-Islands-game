-- SkyDungeon - assistência de combate mobile.
--
-- Regra:
-- 1) Mobile + Attack pressionado + jogador movimentando manualmente:
--    apenas gira o personagem para o alvo. NUNCA usa auto-walk.
-- 2) Mobile + Attack pressionado + jogador parado:
--    gira para o alvo e usa auto-walk até distância confortável de melee.
-- 3) Ao jogador tocar no movimento durante auto-walk:
--    auto-walk é cancelado imediatamente e o joystick volta a ser soberano.
--
-- O alvo continua vindo do DungeonMobileSoftAimTarget.
-- Este script não concede dano, não ativa Tool e não envia alvo ao servidor.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local VERSION = "DungeonMobileCombatAssistV1"
local MANUAL_MOVE_THRESHOLD = 0.08
local AUTO_WALK_STOP_DISTANCE = 5.0
local AUTO_WALK_REFRESH_INTERVAL = 0.12
local ROTATION_RESPONSE = 18

local targetValue = playerGui:WaitForChild("DungeonMobileSoftAimTarget")

local controls
do
	local playerScripts = player:WaitForChild("PlayerScripts")
	local playerModule = playerScripts:FindFirstChild("PlayerModule")
		or playerScripts:WaitForChild("PlayerModule", 10)

	if playerModule then
		local okModule, module = pcall(require, playerModule)
		if okModule and module then
			local okControls, resolvedControls = pcall(function()
				return module:GetControls()
			end)
			if okControls then
				controls = resolvedControls
			end
		end
	end
end

local assistedHumanoid
local originalAutoRotate
local autoWalkActive = false
local autoWalkElapsed = 0

local function mobileActive()
	return player:GetAttribute("DungeonMobileMode") == true
end

local function attackHeld()
	return player:GetAttribute("DungeonMobileAttackHeld") == true
end

local function characterParts()
	local character = player.Character
	if not character then
		return nil, nil, nil
	end

	local humanoid = character:FindFirstChildOfClass("Humanoid")
	local root = character:FindFirstChild("HumanoidRootPart")

	if not humanoid
		or humanoid.Health <= 0
		or not root
		or player:GetAttribute("IsDowned") == true
		or character:GetAttribute("MovementLocked") == true
	then
		return character, nil, nil
	end

	return character, humanoid, root
end

local function targetParts()
	local target = targetValue.Value
	if not target or not target:IsA("Model") or not target.Parent then
		return nil, nil
	end

	local humanoid = target:FindFirstChildWhichIsA("Humanoid", true)
	local root = target:FindFirstChild("HumanoidRootPart", true)
		or target.PrimaryPart
		or target:FindFirstChildWhichIsA("BasePart", true)

	if not root or (humanoid and humanoid.Health <= 0) then
		return nil, nil
	end

	return target, root
end

local function manualMoveVector()
	if controls then
		local ok, vector = pcall(function()
			return controls:GetMoveVector()
		end)
		if ok and typeof(vector) == "Vector3" then
			return vector
		end
	end

	-- Fallback apenas se PlayerModule não estiver disponível.
	-- Como MoveTo também altera MoveDirection, este fallback é menos ideal,
	-- mas mantém o script funcional em ambientes incomuns.
	local _, humanoid = characterParts()
	return humanoid and humanoid.MoveDirection or Vector3.zero
end

local function manualMovementActive()
	return manualMoveVector().Magnitude > MANUAL_MOVE_THRESHOLD
end

local function takeRotationControl(humanoid)
	if assistedHumanoid == humanoid then
		return
	end

	if assistedHumanoid and assistedHumanoid.Parent and originalAutoRotate ~= nil then
		assistedHumanoid.AutoRotate = originalAutoRotate
	end

	assistedHumanoid = humanoid
	originalAutoRotate = humanoid.AutoRotate
	humanoid.AutoRotate = false
end

local function releaseRotationControl()
	if assistedHumanoid and assistedHumanoid.Parent and originalAutoRotate ~= nil then
		assistedHumanoid.AutoRotate = originalAutoRotate
	end
	assistedHumanoid = nil
	originalAutoRotate = nil
end

local function cancelAutoWalk(humanoid, root)
	if autoWalkActive and humanoid and root and humanoid.Parent and root.Parent then
		-- Cancela o destino anterior. O PlayerModule aplica o input manual
		-- normalmente no frame seguinte.
		humanoid:MoveTo(root.Position)
	end
	autoWalkActive = false
	autoWalkElapsed = 0
end

local function rotateToward(root, targetRoot, deltaTime)
	local offset = targetRoot.Position - root.Position
	local horizontal = Vector3.new(offset.X, 0, offset.Z)

	if horizontal.Magnitude <= 0.05 then
		return
	end

	local goal = CFrame.lookAt(
		root.Position,
		root.Position + horizontal.Unit,
		Vector3.yAxis
	)

	local alpha = 1 - math.exp(-ROTATION_RESPONSE * math.max(0, deltaTime))
	root.CFrame = root.CFrame:Lerp(goal, math.clamp(alpha, 0, 1))
end

local function setMode(mode, moving, distance)
	player:SetAttribute("DungeonMobileCombatAssistMode", mode)
	player:SetAttribute("DungeonMobileCombatAssistManualMoving", moving == true)
	player:SetAttribute("DungeonMobileCombatAssistAutoWalk", autoWalkActive)
	player:SetAttribute("DungeonMobileCombatAssistTargetDistance", distance)
end

local function releaseAll(reason)
	local _, humanoid, root = characterParts()
	cancelAutoWalk(humanoid, root)
	releaseRotationControl()

	player:SetAttribute("DungeonMobileCombatAssistMode", reason or "Inactive")
	player:SetAttribute("DungeonMobileCombatAssistManualMoving", false)
	player:SetAttribute("DungeonMobileCombatAssistAutoWalk", false)
	player:SetAttribute("DungeonMobileCombatAssistTargetDistance", nil)
end

RunService.RenderStepped:Connect(function(deltaTime)
	if not mobileActive() or not attackHeld() then
		if autoWalkActive or assistedHumanoid then
			releaseAll("Inactive")
		end
		return
	end

	local _, humanoid, root = characterParts()
	if not humanoid or not root then
		releaseAll("CharacterUnavailable")
		return
	end

	local _, targetRoot = targetParts()
	if not targetRoot then
		cancelAutoWalk(humanoid, root)
		releaseRotationControl()
		setMode("NoTarget", manualMovementActive(), nil)
		return
	end

	local flatOffset = Vector3.new(
		targetRoot.Position.X - root.Position.X,
		0,
		targetRoot.Position.Z - root.Position.Z
	)
	local distance = flatOffset.Magnitude
	local movingManually = manualMovementActive()

	takeRotationControl(humanoid)
	rotateToward(root, targetRoot, deltaTime)

	if movingManually then
		-- Regra principal pedida:
		-- movimentando + atacando => mira/rotação, SEM auto-walk.
		cancelAutoWalk(humanoid, root)
		setMode("ManualMoveRotateOnly", true, distance)
		return
	end

	-- Parado + atacando => mantém assistência de aproximação.
	if distance > AUTO_WALK_STOP_DISTANCE then
		autoWalkElapsed += deltaTime
		if not autoWalkActive or autoWalkElapsed >= AUTO_WALK_REFRESH_INTERVAL then
			autoWalkElapsed = 0
			autoWalkActive = true
			humanoid:MoveTo(Vector3.new(
				targetRoot.Position.X,
				root.Position.Y,
				targetRoot.Position.Z
			))
		end
		setMode("StationaryAutoWalk", false, distance)
	else
		cancelAutoWalk(humanoid, root)
		setMode("StationaryInRange", false, distance)
	end
end)

player.CharacterAdded:Connect(function()
	releaseAll("CharacterChanged")
end)

player:GetAttributeChangedSignal("DungeonMobileMode"):Connect(function()
	if not mobileActive() then
		releaseAll("MobileModeEnded")
	end
end)

player:GetAttributeChangedSignal("DungeonMobileAttackHeld"):Connect(function()
	if not attackHeld() then
		releaseAll("AttackReleased")
	end
end)

player:SetAttribute("DungeonMobileCombatAssistReady", true)
player:SetAttribute("DungeonMobileCombatAssistVersion", VERSION)
player:SetAttribute(
	"DungeonMobileCombatAssistPolicy",
	"ManualMoveRotateOnly_StationaryAutoWalkV1"
)
player:SetAttribute("DungeonMobileCombatAssistStopDistance", AUTO_WALK_STOP_DISTANCE)

script.Destroying:Connect(function()
	releaseAll("Destroyed")
end)
