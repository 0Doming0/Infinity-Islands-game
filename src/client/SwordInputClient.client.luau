--[[
	Infinity Islands - Task 14
	SwordInputClient V7 - Mobile Melee Assist

	The original security model is preserved:
	- client captures manual Tool.Activated;
	- client plays immediate animation;
	- client sends only the attack request;
	- server remains authoritative for hitbox/targets/damage.

	Touch improvements:
	1. Soft facing assist toward the best nearby IslandCombatManaged target.
	2. Existing CombatConfig.InputBufferTime is now actually used.
	3. No custom attack HUD/button is created.
	4. No auto attack.
	5. No auto walk, pull, dash or teleport.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Debris = game:GetService("Debris")
local CollectionService = game:GetService("CollectionService")
local UserInputService = game:GetService("UserInputService")

local player = Players.LocalPlayer

local Config = require(
	ReplicatedStorage
		:WaitForChild("SwordCombat")
		:WaitForChild("CombatConfig")
)

local MobileAssist = require(
	ReplicatedStorage
		:WaitForChild("Shared")
		:WaitForChild("Configs")
		:WaitForChild("MobileMeleeAssistConfig")
)

local boundTools =
	setmetatable({}, { __mode = "k" })

local animationCache =
	setmetatable({}, { __mode = "k" })

local state = {
	Combo = 0,
	LastAttackAt = -math.huge,
	NextAttackAt = 0,

	BufferSerial = 0,
	BufferedTool = nil,

	FacingSerial = 0,
}

local function touchAssistEnabled()
	if MobileAssist.Enabled ~= true then
		return false
	end

	if MobileAssist.TouchOnly == true
		and UserInputService.TouchEnabled ~= true
	then
		return false
	end

	return true
end

local function normalizeAnimationId(value)
	if typeof(value) == "number"
		and value > 0
	then
		return "rbxassetid://"
			.. tostring(
				math.floor(value)
			)
	end

	if typeof(value) ~= "string"
		or value == ""
	then
		return ""
	end

	if string.match(value, "^%d+$") then
		return "rbxassetid://" .. value
	end

	return value
end

local function getAnimationId(
	tool,
	slot
)
	local folder =
		tool:FindFirstChild(
			"Animations"
		)

	local animation =
		folder
			and folder:FindFirstChild(
				slot
			)

	if animation
		and animation:IsA("Animation")
		and animation.AnimationId ~= ""
	then
		return normalizeAnimationId(
			animation.AnimationId
		)
	end

	local attributeId =
		normalizeAnimationId(
			tool:GetAttribute(
				slot .. "AnimationId"
			)
		)

	if attributeId ~= "" then
		return attributeId
	end

	return normalizeAnimationId(
		Config.DefaultAnimationIds[
			slot
		]
	)
end

local function getTrack(
	tool,
	slot
)
	local character =
		player.Character

	local humanoid =
		character
			and character
				:FindFirstChildOfClass(
					"Humanoid"
				)

	if not humanoid then
		return nil
	end

	local animator =
		humanoid
			:FindFirstChildOfClass(
				"Animator"
			)

	if not animator then
		return nil
	end

	local cache =
		animationCache[tool]

	if not cache
		or cache.Animator ~= animator
	then
		cache = {
			Animator = animator,
			Tracks = {},
		}

		animationCache[tool] = cache
	end

	if cache.Tracks[slot] then
		return cache.Tracks[slot]
	end

	local animationId =
		getAnimationId(
			tool,
			slot
		)

	if animationId == "" then
		return nil
	end

	local animation =
		Instance.new("Animation")

	animation.AnimationId =
		animationId

	local success,
		track =
			pcall(function()
				return animator:LoadAnimation(
					animation
				)
			end)

	animation:Destroy()

	if not success then
		warn(
			"[SwordInputV7] Animacao "
				.. slot
				.. " falhou: "
				.. tostring(track)
		)

		return nil
	end

	track.Priority =
		Enum.AnimationPriority.Action4

	cache.Tracks[slot] = track

	return track
end

local function playAttackAnimation(
	tool,
	comboIndex,
	speed
)
	local track =
		getTrack(
			tool,
			"Attack" .. comboIndex
		)

	if track then
		track:Play(
			0.045,
			1,
			Config.Combo[
				comboIndex
			].AnimationSpeed
				* speed
		)
	end

	local humanoid =
		player.Character
			and player.Character
				:FindFirstChildOfClass(
					"Humanoid"
				)

	if humanoid
		and humanoid.RigType
			== Enum.HumanoidRigType.R6
	then
		local marker =
			Instance.new("StringValue")

		marker.Name = "toolanim"
		marker.Value =
			comboIndex == 2
				and "Lunge"
				or "Slash"

		marker.Parent = tool

		Debris:AddItem(
			marker,
			0.25
		)
	end
end

local function targetRoot(model)
	if not model
		or not model:IsA("Model")
	then
		return nil
	end

	return model:FindFirstChild(
		"HumanoidRootPart",
		true
	)
		or model.PrimaryPart
		or model:FindFirstChildWhichIsA(
			"BasePart",
			true
		)
end

local function targetAlive(model)
	local humanoid =
		model
			and model:FindFirstChildWhichIsA(
				"Humanoid",
				true
			)

	return humanoid ~= nil
		and humanoid.Health > 0
end

local function horizontalUnit(vector)
	local horizontal =
		Vector3.new(
			vector.X,
			0,
			vector.Z
		)

	if horizontal.Magnitude
		<= 0.001
	then
		return nil
	end

	return horizontal.Unit
end

local function playerAimDirection(
	root,
	humanoid
)
	if MobileAssist.UseMoveDirection == true
		and humanoid
	then
		local move =
			horizontalUnit(
				humanoid.MoveDirection
			)

		if move
			and humanoid.MoveDirection.Magnitude
				>= MobileAssist
					.MoveDirectionThreshold
		then
			return move
		end
	end

	return horizontalUnit(
		root.CFrame.LookVector
	)
		or Vector3.new(0, 0, -1)
end

local function sameCombatIsland(target)
	if MobileAssist.RequireSameCombatIsland
		~= true
	then
		return true
	end

	local playerIndex =
		tonumber(
			player:GetAttribute(
				"CurrentGlobalIslandIndex"
			)
		)

	local targetIndex =
		tonumber(
			target:GetAttribute(
				"GlobalIslandIndex"
			)
		)

	-- During the first frame after entry an index may not yet be replicated.
	-- Missing metadata should not make melee feel broken.
	if not playerIndex
		or not targetIndex
	then
		return true
	end

	return math.floor(playerIndex)
		== math.floor(targetIndex)
end

local function validAssistTarget(
	target,
	root
)
	if not target
		or not target:IsA("Model")
		or not target.Parent
	then
		return false
	end

	if target:GetAttribute(
		"Peaceful"
	) == true
	then
		return false
	end

	if MobileAssist
			.RequireIslandCombatManaged
		== true
		and target:GetAttribute(
			"IslandCombatManaged"
		) ~= true
	then
		return false
	end

	if not sameCombatIsland(target) then
		return false
	end

	if not targetAlive(target) then
		return false
	end

	local targetPart =
		targetRoot(target)

	if not targetPart
		or not targetPart.Parent
	then
		return false
	end

	local delta =
		Vector3.new(
			targetPart.Position.X
				- root.Position.X,
			0,
			targetPart.Position.Z
				- root.Position.Z
		)

	return delta.Magnitude
		<= MobileAssist
			.MaximumTargetDistance
end

local function bestAssistTarget(
	root,
	humanoid
)
	if not touchAssistEnabled() then
		return nil
	end

	local aimDirection =
		playerAimDirection(
			root,
			humanoid
		)

	local minimumDot =
		math.cos(
			math.rad(
				MobileAssist
					.MaximumAssistAngleDegrees
			)
		)

	local bestTarget
	local bestPart
	local bestScore = math.huge
	local bestDistance
	local bestAngle

	for _, target in ipairs(
		CollectionService:GetTagged(
			Config.TargetTag
		)
	) do
		if not validAssistTarget(
			target,
			root
		)
		then
			continue
		end

		local part =
			targetRoot(target)

		local delta =
			Vector3.new(
				part.Position.X
					- root.Position.X,
				0,
				part.Position.Z
					- root.Position.Z
			)

		local distance =
			delta.Magnitude

		if distance <= 0.001 then
			continue
		end

		local direction =
			delta.Unit

		local dot =
			math.clamp(
				aimDirection:Dot(
					direction
				),
				-1,
				1
			)

		if dot < minimumDot then
			continue
		end

		local angle =
			math.acos(dot)

		local normalizedDistance =
			math.clamp(
				distance
					/ MobileAssist
						.MaximumTargetDistance,
				0,
				1
			)

		local normalizedAngle =
			math.clamp(
				angle
					/ math.rad(
						MobileAssist
							.MaximumAssistAngleDegrees
					),
				0,
				1
			)

		local score =
			normalizedDistance
				* MobileAssist.DistanceWeight
			+ normalizedAngle
				* MobileAssist.AngleWeight

		if score < bestScore then
			bestScore = score
			bestTarget = target
			bestPart = part
			bestDistance = distance
			bestAngle =
				math.deg(angle)
		end
	end

	return bestTarget,
		bestPart,
		bestDistance,
		bestAngle
end

local function applyMobileFacingAssist()
	if not touchAssistEnabled() then
		return nil
	end

	local character =
		player.Character

	local humanoid =
		character
			and character
				:FindFirstChildOfClass(
					"Humanoid"
				)

	local root =
		character
			and character:FindFirstChild(
				"HumanoidRootPart"
			)

	if not humanoid
		or not root
		or humanoid.Health <= 0
	then
		return nil
	end

	local target,
		targetPart,
		distance,
		angle =
			bestAssistTarget(
				root,
				humanoid
			)

	if not target
		or not targetPart
	then
		player:SetAttribute(
			"MobileMeleeAssistTarget",
			nil
		)

		return nil
	end

	local flatTarget =
		Vector3.new(
			targetPart.Position.X,
			root.Position.Y,
			targetPart.Position.Z
		)

	if (
		flatTarget
			- root.Position
	).Magnitude <= 0.001
	then
		return nil
	end

	local desired =
		CFrame.lookAt(
			root.Position,
			flatTarget
		)

	local strength =
		math.clamp(
			MobileAssist.FacingStrength,
			0,
			1
		)

	state.FacingSerial += 1
	local serial = state.FacingSerial

	local previousAutoRotate =
		humanoid.AutoRotate

	humanoid.AutoRotate = false

	root.CFrame =
		root.CFrame:Lerp(
			desired,
			strength
		)

	player:SetAttribute(
		"MobileMeleeAssistTarget",
		target.Name
	)
	player:SetAttribute(
		"MobileMeleeAssistTargetDistance",
		distance
	)
	player:SetAttribute(
		"MobileMeleeAssistTargetAngle",
		angle
	)
	player:SetAttribute(
		"MobileMeleeAssistSerial",
		(
			tonumber(
				player:GetAttribute(
					"MobileMeleeAssistSerial"
				)
			) or 0
		) + 1
	)

	task.delay(
		MobileAssist.FacingHoldSeconds,
		function()
			if state.FacingSerial ~= serial then
				return
			end

			if humanoid.Parent
				and humanoid.Health > 0
			then
				humanoid.AutoRotate =
					previousAutoRotate
			end
		end
	)

	return target
end

local function canAttack(tool)
	local character =
		player.Character

	return character ~= nil
		and tool.Parent == character
		and Config.IsSword(tool)
		and player:GetAttribute(
			"IsDowned"
		) ~= true
		and character:GetAttribute(
			"MovementLocked"
		) ~= true
end

local function sendAttack(tool)
	if not canAttack(tool) then
		return false
	end

	local now = os.clock()

	if now < state.NextAttackAt then
		return false
	end

	if now - state.LastAttackAt
		> Config.ComboResetTime
	then
		state.Combo = 1
	else
		state.Combo =
			state.Combo
				% Config.ComboCount
				+ 1
	end

	state.LastAttackAt = now

	local speed =
		Config.GetAttackSpeed(tool)

	local combo =
		Config.Combo[state.Combo]

	state.NextAttackAt =
		now
			+ (
				combo.Windup
					+ combo.Recovery
			) / speed

	-- Touch assistance changes only local facing. The RemoteEvent still carries
	-- no target argument, so the server never trusts this selection.
	applyMobileFacingAssist()

	playAttackAnimation(
		tool,
		state.Combo,
		speed
	)

	local request =
		tool:FindFirstChild(
			Config.ToolRemoteName
		)
			or tool:WaitForChild(
				Config.ToolRemoteName,
				2
			)

	if not request
		or not request:IsA("RemoteEvent")
	then
		warn(
			"[SwordInputV7] "
				.. Config.ToolRemoteName
				.. " nao encontrado em "
				.. tool:GetFullName()
		)

		return false
	end

	request:FireServer()

	player:SetAttribute(
		"SwordInputBuffered",
		false
	)

	if Config.DebugCombat then
		print(
			string.format(
				"[SwordInputV7] ataque combo=%d touchAssist=%s",
				state.Combo,
				tostring(
					touchAssistEnabled()
				)
			)
		)
	end

	return true
end

local function clearBufferedAttack()
	state.BufferSerial += 1
	state.BufferedTool = nil

	player:SetAttribute(
		"SwordInputBuffered",
		false
	)
end

local function bufferAttack(
	tool,
	remaining
)
	if Config.InputBufferTime <= 0
		or remaining <= 0
		or remaining
			> Config.InputBufferTime
	then
		return false
	end

	state.BufferSerial += 1
	local serial = state.BufferSerial

	state.BufferedTool = tool

	player:SetAttribute(
		"SwordInputBuffered",
		true
	)
	player:SetAttribute(
		"SwordInputBufferRemaining",
		remaining
	)

	task.delay(
		remaining,
		function()
			if serial ~= state.BufferSerial
				or state.BufferedTool
					~= tool
			then
				return
			end

			state.BufferedTool = nil

			player:SetAttribute(
				"SwordInputBuffered",
				false
			)

			sendAttack(tool)
		end
	)

	return true
end

local function activate(tool)
	if not canAttack(tool) then
		return
	end

	local now = os.clock()

	if now < state.NextAttackAt then
		local remaining =
			state.NextAttackAt - now

		bufferAttack(
			tool,
			remaining
		)

		return
	end

	clearBufferedAttack()
	sendAttack(tool)
end

local function bindTool(tool)
	if not Config.IsSword(tool)
		or boundTools[tool]
	then
		return
	end

	boundTools[tool] = true

	tool.Activated:Connect(function()
		activate(tool)
	end)

	if Config.DebugCombat then
		print(
			"[SwordInputV7] Tool vinculada: "
				.. tool:GetFullName()
		)
	end
end

local function bindCharacter(character)
	clearBufferedAttack()

	state.Combo = 0
	state.LastAttackAt = -math.huge
	state.NextAttackAt = 0
	state.FacingSerial += 1

	character.ChildAdded:Connect(
		function(child)
			if child:IsA("Tool") then
				bindTool(child)
			end
		end
	)

	for _, child in ipairs(
		character:GetChildren()
	) do
		if child:IsA("Tool") then
			bindTool(child)
		end
	end
end

local shakeSerial = 0

local function shakeCamera(strength)
	shakeSerial += 1

	local serial = shakeSerial
	local started = os.clock()

	local bindName =
		"SwordHitShake_"
			.. player.UserId

	RunService:UnbindFromRenderStep(
		bindName
	)

	RunService:BindToRenderStep(
		bindName,
		Enum.RenderPriority.Camera.Value
			+ 1,
		function()
			local alpha =
				(os.clock() - started)
					/ 0.11

			if serial ~= shakeSerial
				or alpha >= 1
			then
				RunService
					:UnbindFromRenderStep(
						bindName
					)

				return
			end

			local camera =
				workspace.CurrentCamera

			if camera then
				local fade = 1 - alpha

				camera.CFrame *=
					CFrame.new(
						(math.random() - 0.5)
							* strength
							* fade,
						(math.random() - 0.5)
							* strength
							* fade,
						0
					)
			end
		end
	)
end

player:GetAttributeChangedSignal(
	"SwordHitSerial"
):Connect(function()
	local heavy =
		player:GetAttribute(
			"SwordHitHeavy"
		) == true

	shakeCamera(
		heavy
			and Config.Visuals
				.HeavyCameraShake
			or Config.Visuals
				.CameraShake
	)
end)

player:GetAttributeChangedSignal(
	"IsDowned"
):Connect(function()
	if player:GetAttribute(
		"IsDowned"
	) ~= true
	then
		state.NextAttackAt = 0
		return
	end

	clearBufferedAttack()

	state.Combo = 0
	state.LastAttackAt = -math.huge
	state.NextAttackAt = math.huge
	state.FacingSerial += 1

	for _, cache in pairs(
		animationCache
	) do
		for slot, track in pairs(
			cache.Tracks or {}
		) do
			if string.find(
				slot,
				"Attack"
			)
				and track.IsPlaying
			then
				track:Stop(0.05)
			end
		end
	end
end)

player.CharacterAdded:Connect(
	bindCharacter
)

if player.Character then
	bindCharacter(player.Character)
end

player:SetAttribute(
	"MobileMeleeAssistVersion",
	MobileAssist.Version
)

player:SetAttribute(
	"MobileMeleeAssistEnabled",
	touchAssistEnabled()
)

player:SetAttribute(
	"MobileMeleeAssistPolicy",
	"ManualAttackSoftFacingV1"
)

player:SetAttribute(
	"MobileMeleeAutoAttack",
	false
)

player:SetAttribute(
	"MobileMeleeAutoMovement",
	false
)

if Config.DebugCombat then
	print(
		"[SwordInputV7] iniciado. Touch assist="
			.. tostring(
				touchAssistEnabled()
			)
	)
end
