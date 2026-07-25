-- ServerScriptService/MVPSystems/SwordCombatServer
-- V6: input local e RemoteEvent individual dentro de cada Tool.
-- O servidor continua autoritativo sobre combo, hitbox, alvos e dano.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CollectionService = game:GetService("CollectionService")
local Debris = game:GetService("Debris")
local RunService = game:GetService("RunService")
local HttpService = game:GetService("HttpService")

local combatFolder = ReplicatedStorage:WaitForChild("SwordCombat")
local Config = require(combatFolder:WaitForChild("CombatConfig"))
local DamageService = require(script.Parent:WaitForChild("CombatDamageService"))
local RelicService = require(script.Parent:WaitForChild("RelicService"))
RelicService.Start()

-- Remove o canal da arquitetura antiga para impedir dois sistemas concorrentes.
local legacyRemote = combatFolder:FindFirstChild("CombatRemote")
if legacyRemote and legacyRemote:IsA("RemoteEvent") then
	legacyRemote:Destroy()
end

local states = setmetatable({}, { __mode = "k" })
local boundTools = setmetatable({}, { __mode = "k" })
local animationCache = setmetatable({}, { __mode = "k" })
local watchedContainers = setmetatable({}, { __mode = "k" })

-- Forward declarations (definidos depois no arquivo, mas precisam ser visiveis em attack)
local resolveEquippedSword
local printTools

local function getState(player)
	local state = states[player]
	if not state then
		state = {
			LastAttackAt = -math.huge,
			NextAttackAt = 0,
			Combo = 0,
			Token = 0,
			HitSerial = 0,
		}
		states[player] = state
	end
	return state
end

local function getLivingCharacter(player)
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not character or not humanoid or humanoid.Health <= 0 or not root or not root:IsA("BasePart") then
		return nil
	end
	return character, humanoid, root
end

local function normalizeAnimationId(value)
	if typeof(value) == "number" and value > 0 then
		return "rbxassetid://" .. tostring(math.floor(value))
	end
	if typeof(value) ~= "string" or value == "" then
		return ""
	end
	if string.match(value, "^%d+$") then
		return "rbxassetid://" .. value
	end
	return value
end

local function getAnimationId(tool, slot)
	local folder = tool:FindFirstChild("Animations")
	local animation = folder and folder:FindFirstChild(slot)
	if animation and animation:IsA("Animation") and animation.AnimationId ~= "" then
		return normalizeAnimationId(animation.AnimationId)
	end

	local attributeId = normalizeAnimationId(tool:GetAttribute(slot .. "AnimationId"))
	if attributeId ~= "" then
		return attributeId
	end
	return normalizeAnimationId(Config.DefaultAnimationIds[slot])
end

local function getTrack(tool, humanoid, slot)
	local animator = humanoid:FindFirstChildOfClass("Animator")
	if not animator then
		animator = Instance.new("Animator")
		animator.Parent = humanoid
	end

	local toolCache = animationCache[tool]
	if not toolCache or toolCache.Animator ~= animator then
		toolCache = { Animator = animator, Tracks = {} }
		animationCache[tool] = toolCache
	end
	if toolCache.Tracks[slot] then
		return toolCache.Tracks[slot]
	end

	local animationId = getAnimationId(tool, slot)
	if animationId == "" then
		return nil
	end
	local animation = Instance.new("Animation")
	animation.AnimationId = animationId
	local success, track = pcall(function()
		return animator:LoadAnimation(animation)
	end)
	animation:Destroy()
	if not success then
		warn("[SwordCombatV6] Animacao " .. slot .. " falhou: " .. tostring(track))
		return nil
	end

	track.Priority = string.find(slot, "Attack") and Enum.AnimationPriority.Action4
		or Enum.AnimationPriority.Action
	track.Looped = slot == "Idle"
	toolCache.Tracks[slot] = track
	return track
end

local function playAnimation(tool, humanoid, slot, speed)
	local track = getTrack(tool, humanoid, slot)
	if track then
		track:Play(0.055, 1, speed or 1)
	end

	if humanoid.RigType == Enum.HumanoidRigType.R6 and string.find(slot, "Attack") then
		local combo = tonumber(string.match(slot, "%d+")) or 1
		local marker = Instance.new("StringValue")
		marker.Name = "toolanim"
		marker.Value = combo == 2 and "Lunge" or "Slash"
		marker.Parent = tool
		Debris:AddItem(marker, 0.25)
	end
end

local function findBlade(tool)
	local requested = tool:GetAttribute("TrailPartName")
	if typeof(requested) == "string" and requested ~= "" then
		local part = tool:FindFirstChild(requested, true)
		if part and part:IsA("BasePart") then
			return part
		end
	end
	local blade = tool:FindFirstChild("Blade", true)
	if blade and blade:IsA("BasePart") then
		return blade
	end
	local handle = tool:FindFirstChild("Handle")
	return handle and handle:IsA("BasePart") and handle or nil
end

local function ensureTrail(tool)
	local existing = tool:FindFirstChild("SwordTrail", true)
	if existing and existing:IsA("Trail") then
		existing.Enabled = false
		return existing
	end

	local blade = findBlade(tool)
	if not blade then
		return nil
	end
	local length = math.max(blade.Size.X, blade.Size.Y, blade.Size.Z)
	local axis
	if blade.Size.Y >= blade.Size.X and blade.Size.Y >= blade.Size.Z then
		axis = Vector3.new(0, length * 0.48, 0)
	elseif blade.Size.X >= blade.Size.Z then
		axis = Vector3.new(length * 0.48, 0, 0)
	else
		axis = Vector3.new(0, 0, length * 0.48)
	end

	local base = Instance.new("Attachment")
	base.Name = "SwordTrailBase"
	base.Position = -axis
	base.Parent = blade
	local tip = Instance.new("Attachment")
	tip.Name = "SwordTrailTip"
	tip.Position = axis
	tip.Parent = blade

	local trail = Instance.new("Trail")
	trail.Name = "SwordTrail"
	trail.Attachment0 = base
	trail.Attachment1 = tip
	trail.Color = Config.Visuals.TrailColor
	trail.Lifetime = Config.Visuals.TrailLifetime
	trail.WidthScale = Config.Visuals.TrailWidthScale
	trail.FaceCamera = true
	trail.LightEmission = 0.65
	trail.Enabled = false
	trail.Parent = blade
	return trail
end

local function animateTrail(tool, combo, attackSpeed)
	local trail = ensureTrail(tool)
	if not trail then
		return
	end
	task.delay(combo.TrailStart / attackSpeed, function()
		if trail.Parent and tool.Parent then
			trail.Enabled = true
			task.delay(combo.TrailDuration / attackSpeed, function()
				if trail.Parent then
					trail.Enabled = false
				end
			end)
		end
	end)
end

local function playSound(tool, soundId, volume, speed)
	if not soundId or soundId == "" then
		return
	end
	local handle = tool:FindFirstChild("Handle")
	if not handle or not handle:IsA("BasePart") then
		return
	end
	local sound = Instance.new("Sound")
	sound.SoundId = soundId
	sound.Volume = volume or 0.5
	sound.PlaybackSpeed = speed or 1
	sound.RollOffMaxDistance = 65
	sound.Parent = handle
	sound:Play()
	Debris:AddItem(sound, 3)
end

local function resolveModelFromPart(part, attackerCharacter)
	local ancestor = part
	while ancestor and ancestor ~= workspace do
		if ancestor:IsA("Model") then
			-- Nunca deixe a busca subir ate o modelo da ilha. Uma ilha pode conter
			-- monstros com Humanoid, mas isso nao transforma o terreno em personagem.
			if ancestor:GetAttribute("IsSkyIsland") == true then
				return nil
			end

			-- Personagens normais possuem o Humanoid diretamente no proprio Model.
			-- Para alvos explicitamente marcados, aceitamos rigs com o Humanoid em
			-- um submodelo, mas continuamos retornando somente o Model marcado.
			local humanoid = ancestor:FindFirstChildOfClass("Humanoid")
			if not humanoid and CollectionService:HasTag(ancestor, Config.TargetTag) then
				humanoid = ancestor:FindFirstChildWhichIsA("Humanoid", true)
			end

			if humanoid then
				if ancestor == attackerCharacter or humanoid.Health <= 0 then
					return nil
				end
				local root = ancestor:FindFirstChild("HumanoidRootPart", true)
					or ancestor:FindFirstChild("UpperTorso", true)
					or ancestor:FindFirstChild("Torso", true)
					or ancestor.PrimaryPart
					or ancestor:FindFirstChildWhichIsA("BasePart", true)
				if root and root:IsA("BasePart") then
					return ancestor, humanoid, root
				end
				return nil
			end
		end
		ancestor = ancestor.Parent
	end
	return nil
end

local function insideBox(boxCFrame, size, position)
	local point = boxCFrame:PointToObjectSpace(position)
	local half = size * 0.5
	return math.abs(point.X) <= half.X + 1.5
		and math.abs(point.Y) <= half.Y + 3.0
		and math.abs(point.Z) <= half.Z + 1.5
end

local function addTarget(list, seen, player, character, attackerRoot, model, humanoid, root)
	if not model or not humanoid or not root or humanoid.Health <= 0 then
		return
	end
	if model:GetAttribute("IsSkyIsland") == true then
		return
	end
	if model == character or seen[humanoid] or DamageService.IsFriendly(player, model, Config.FriendlyFire) then
		return
	end
	if model:GetAttribute("Invulnerable") == true or model:GetAttribute("NoSwordDamage") == true then
		return
	end
	local tutorialTargetUserId = model:GetAttribute("TutorialTargetUserId")
	if typeof(tutorialTargetUserId) == "number" and tutorialTargetUserId ~= player.UserId then
		return
	end
	local distance = (root.Position - attackerRoot.Position).Magnitude
	if distance > Config.MaxHitboxDimension then
		return
	end
	seen[humanoid] = true
	table.insert(list, {
		Model = model,
		Humanoid = humanoid,
		Root = root,
		Distance = distance,
	})
end

local function collectTargets(player, character, attackerRoot, boxCFrame, size)
	local targets, seen = {}, {}
	local overlap = OverlapParams.new()
	overlap.FilterType = Enum.RaycastFilterType.Exclude
	overlap.FilterDescendantsInstances = { character }
	overlap.MaxParts = 100

	for _, part in workspace:GetPartBoundsInBox(boxCFrame, size, overlap) do
		local model, humanoid, root = resolveModelFromPart(part, character)
		if model then
			addTarget(targets, seen, player, character, attackerRoot, model, humanoid, root)
		end
	end

	-- Caminho principal para os mobs: independe de CanQuery e da hierarquia das peças.
	for _, model in CollectionService:GetTagged(Config.TargetTag) do
		if model:IsA("Model") and model.Parent then
			local humanoid = model:FindFirstChildWhichIsA("Humanoid", true)
			local root = model:FindFirstChild("HumanoidRootPart", true)
				or model.PrimaryPart
				or model:FindFirstChildWhichIsA("BasePart", true)
			if humanoid and root and root:IsA("BasePart") and insideBox(boxCFrame, size, root.Position) then
				addTarget(targets, seen, player, character, attackerRoot, model, humanoid, root)
			end
		end
	end

	table.sort(targets, function(a, b)
		return a.Distance < b.Distance
	end)
	return targets
end

local function showHitbox(cframe, size)
	if not Config.DebugHitboxes then
		return
	end
	local part = Instance.new("Part")
	part.Name = "SwordHitboxDebug"
	part.Size = size
	part.CFrame = cframe
	part.Anchored = true
	part.CanCollide = false
	part.CanTouch = false
	part.CanQuery = false
	part.Material = Enum.Material.ForceField
	part.Color = Color3.fromRGB(255, 70, 70)
	part.Transparency = 0.68
	part.Parent = workspace
	Debris:AddItem(part, 0.16)
end

local function executeHit(player, tool, comboIndex, token)
	local state = getState(player)
	if state.Token ~= token then
		return
	end
	local character, _, attackerRoot = getLivingCharacter(player)
	if not character or tool.Parent ~= character or not Config.IsSword(tool) then
		return
	end

	local combo = Config.Combo[comboIndex]
	local rangeMultiplier = Config.GetClampedNumber(tool, "RangeMultiplier", 1, 0.8, 1.5)
	local size = Vector3.new(
		combo.HitboxSize.X * rangeMultiplier,
		combo.HitboxSize.Y,
		combo.HitboxSize.Z * rangeMultiplier
	)
	local boxCFrame = attackerRoot.CFrame
		* combo.HitboxOffset
		* CFrame.new(0, 0, -(rangeMultiplier - 1) * combo.HitboxSize.Z * 0.45)
	showHitbox(boxCFrame, size)
	local targets = collectTargets(player, character, attackerRoot, boxCFrame, size)

	local damage = Config.GetClampedNumber(
		tool,
		"BaseDamage",
		Config.DefaultWeapon.BaseDamage,
		Config.DamageLimits.Min,
		Config.DamageLimits.Max
	) * combo.DamageMultiplier
		* math.clamp(tonumber(player:GetAttribute("RunDamageDealtMultiplier")) or 1, 0.05, 1)
	local knockbackMultiplier = Config.GetClampedNumber(tool, "KnockbackMultiplier", 1, 0, 3)
		* math.clamp(tonumber(player:GetAttribute("RunKnockbackMultiplier")) or 1, 1, 5)
	local scoreMultiplier = Config.GetClampedNumber(tool, "ScoreMultiplier", 1, 1, 100)
	local attackSpeed = Config.GetAttackSpeed(tool)
		* math.clamp(tonumber(player:GetAttribute("RunAttackSpeedMultiplier")) or 1, 1, 2)
	local criticalChance = math.clamp(
		Config.GetClampedNumber(tool, "CriticalChance", 0, 0, 0.75)
			+ math.max(0, tonumber(player:GetAttribute("RunCriticalBonus")) or 0),
		0,
		0.85
	)
	local nextCombo = Config.Combo[comboIndex % Config.ComboCount + 1]
	-- Mantem o alvo interrompido ate a primeira janela real do proximo golpe.
	-- A duracao acompanha AttackSpeed, portanto espadas lentas nao deixam um
	-- pequeno intervalo no meio do combo em que o mob consegue atacar.
	local stunDuration
	if comboIndex < Config.ComboCount then
		stunDuration = (combo.Recovery + nextCombo.Windup) / attackSpeed + 0.08
	else
		stunDuration = math.max(0.42, combo.Recovery / attackSpeed + 0.08)
	end
	local attack = {
		Damage = math.clamp(damage, Config.DamageLimits.Min, Config.DamageLimits.Max),
		Knockback = combo.Knockback * knockbackMultiplier,
		UpwardKnockback = combo.UpwardKnockback * knockbackMultiplier,
		ScoreMultiplier = scoreMultiplier,
		StunDuration = stunDuration,
		Heavy = combo.Heavy,
	}

	local hitCount, killCount = 0, 0
	for index = 1, math.min(#targets, Config.MaxTargetsPerSwing) do
		local target = targets[index]
		local targetAttack = table.clone(attack)
		if math.random() < criticalChance then
			targetAttack.Damage = math.min(Config.DamageLimits.Max, targetAttack.Damage * 2)
			targetAttack.Critical = true
		end
		targetAttack = RelicService.PrepareAttack(player, target, targetAttack)
		local hit, killed = DamageService.ApplySwordHit(player, attackerRoot, target, targetAttack)
		if hit then
			hitCount += 1
			RelicService.ApplyAfterHit(player, attackerRoot, target, targetAttack)
			if killed then
				killCount += 1
			end
			if targetAttack.Critical then
				player:SetAttribute("LastCriticalHitSerial", (player:GetAttribute("LastCriticalHitSerial") or 0) + 1)
			end
		end
	end

	if hitCount > 0 then
		playSound(tool, Config.Sounds.Hit, combo.Heavy and 0.62 or 0.45, combo.Heavy and 0.86 or 1.05)
		state.HitSerial += 1
		player:SetAttribute("SwordHitHeavy", combo.Heavy)
		player:SetAttribute("SwordHitCount", hitCount)
		player:SetAttribute("SwordKillCount", killCount)
		player:SetAttribute("SwordHitSerial", state.HitSerial)
	end

	if Config.DebugCombat then
		print(string.format(
			"[SwordCombatV6] HIT %s combo=%d alvos=%d acertados=%d vidaDano=%.1f",
			player.Name,
			comboIndex,
			#targets,
			hitCount,
			attack.Damage
			))
	end
end

local function attack(player, tool)
	if player:GetAttribute("ShopOpen") == true then
		return
	end
	if not Config.IsSword(tool) then
		warn(
			"[REJEITADO] Config.IsSword falso",
			tool.Name,
			tool:GetAttribute("IsSword"),
			tool:GetAttribute("WeaponType")
		)
		return
	end

	local character = player.Character
	if not character then
		warn("[REJEITADO] Character nil")
		return
	end

	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not humanoid then
		warn("[REJEITADO] Humanoid ausente")
		return
	end

	if humanoid.Health <= 0 then
		warn("[REJEITADO] Humanoid morto:", humanoid.Health)
		return
	end

	local root = character:FindFirstChild("HumanoidRootPart")
	if not root then
		warn("[REJEITADO] HumanoidRootPart ausente")
		return
	end

	-- Tentar resolver o equipamento: aguardar replicacao ou equipar autoritativamente
	if tool.Parent ~= character then
		print("[SERVIDOR] Tool nao esta no Character; tentando resolver equipamento...")
		local deadline = os.clock() + 0.35
		while os.clock() < deadline do
			if tool.Parent == character then
				break
			end
			RunService.Heartbeat:Wait()
			character = player.Character
			if not character or not tool:IsDescendantOf(game) then
				break
			end
		end

		-- Se ainda nao esta no Character, tentar equipar autoritativamente
		if tool.Parent ~= character then
			if not resolveEquippedSword(player, tool) then
				warn(
					"[REJEITADO] Tool nao esta no Character",
					"Tool:", tool:GetFullName(),
					"Parent:", tool.Parent and tool.Parent:GetFullName() or "nil",
					"Character:", character and character:GetFullName() or "nil"
				)
				return
			end
		end
	end

	-- Re-validar apos resolucao do equipamento
	character = player.Character
	if not character then
		warn("[REJEITADO] Character nil (pos-resolucao)")
		return
	end
	humanoid = character:FindFirstChildOfClass("Humanoid")
	if not humanoid then
		warn("[REJEITADO] Humanoid ausente (pos-resolucao)")
		return
	end

	if humanoid.Health <= 0 then
		warn("[REJEITADO] Humanoid morto (pos-resolucao):", humanoid.Health)
		return
	end

	root = character:FindFirstChild("HumanoidRootPart")
	if not root then
		warn("[REJEITADO] HumanoidRootPart ausente (pos-resolucao)")
		return
	end

	if tool.Parent ~= character then
		warn(
			"[REJEITADO] Tool nao esta no Character (pos-resolucao)",
			"Tool:", tool:GetFullName(),
			"Parent:", tool.Parent and tool.Parent:GetFullName() or "nil",
			"Character:", character:GetFullName()
		)
		return
	end

	if not Config.IsSword(tool) then
		warn(
			"[REJEITADO] Config.IsSword falso (pos-resolucao)",
			tool.Name,
			tool:GetAttribute("IsSword"),
			tool:GetAttribute("WeaponType")
		)
		return
	end

	print("[SERVIDOR] Tool equipada confirmada")

	local state = getState(player)
	local now = os.clock()
	if now < state.NextAttackAt then
		return
	end
	if now - state.LastAttackAt > Config.ComboResetTime then
		state.Combo = 1
	else
		state.Combo = state.Combo % Config.ComboCount + 1
	end
	state.LastAttackAt = now
	state.Token += 1

	local comboIndex = state.Combo
	local combo = Config.Combo[comboIndex]
	local speed = Config.GetAttackSpeed(tool)
		* math.clamp(tonumber(player:GetAttribute("RunAttackSpeedMultiplier")) or 1, 1, 2)
	local windup = combo.Windup / speed
	state.NextAttackAt = now + (combo.Windup + combo.Recovery) / speed

	animateTrail(tool, combo, speed)
	playSound(
		tool,
		combo.Heavy and Config.Sounds.HeavySwing or Config.Sounds.Swing,
		0.52,
		math.clamp(speed, 0.8, 1.3)
	)
	if Config.DebugCombat then
		print(string.format("[SwordCombatV6] REQUEST %s combo=%d", player.Name, comboIndex))
	end

	local token = state.Token
	task.delay(windup, function()
		executeHit(player, tool, comboIndex, token)
	end)
end

local function sanitizeTool(tool)
	tool.Enabled = true
	tool.ManualActivationOnly = false
	for _, descendant in tool:GetDescendants() do
		if descendant:IsA("BaseScript") then
			-- ClassicSword do catálogo normalmente traz SwordScript/LocalScript próprios.
			-- A V6 usa o input central em StarterPlayerScripts.
			descendant.Disabled = true
		elseif descendant:IsA("BasePart") then
			descendant.CanCollide = false
			descendant.CanTouch = false
			descendant.Massless = true
		end
	end
end

function printTools(player)
	print("=== TOOLS DE", player.Name, "===")
	local containers = {
		player.Character,
		player:FindFirstChild("Backpack"),
		player:FindFirstChild("StarterGear"),
		game:GetService("StarterPack"),
	}
	for _, container in containers do
		if container then
			for _, child in container:GetChildren() do
				if child:IsA("Tool") then
					print(
						container:GetFullName(),
						child:GetFullName(),
						"SwordInstanceId:", child:GetAttribute("SwordInstanceId"),
						"Remote:", child:FindFirstChild(Config.ToolRemoteName)
					)
				end
			end
		end
	end
end

function resolveEquippedSword(player, tool)
	local character = player.Character
	local backpack = player:FindFirstChild("Backpack")
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not character or not humanoid or humanoid.Health <= 0 then
		return false
	end
	if tool.Parent == character then
		return true
	end
	if backpack and tool.Parent == backpack then
		print("[SERVIDOR] Tool no Backpack; equipando autoritativamente...")
		humanoid:EquipTool(tool)
		local deadline = os.clock() + 0.20
		while os.clock() < deadline do
			RunService.Heartbeat:Wait()
			if tool.Parent == character then
				return true
			end
		end
	end
	return false
end

local function bindTool(player, tool)
	if not Config.IsSword(tool) or boundTools[tool] then
		return
	end
	boundTools[tool] = true
	sanitizeTool(tool)
	ensureTrail(tool)

	if not tool:GetAttribute("SwordInstanceId") then
		tool:SetAttribute("SwordInstanceId", HttpService:GenerateGUID(false))
	end

	local attackRequest = tool:FindFirstChild(Config.ToolRemoteName)
	if not attackRequest then
		attackRequest = Instance.new("RemoteEvent")
		attackRequest.Name = Config.ToolRemoteName
		attackRequest.Parent = tool
	end
	if Config.DebugCombat then
		print("[SwordCombatV6] Tool vinculada:", tool:GetFullName(), "Remote:", attackRequest:GetFullName())
	end
	if not attackRequest:IsA("RemoteEvent") then
		warn("[SwordCombatV6] " .. Config.ToolRemoteName .. " existe, mas nao e RemoteEvent.")
		return
	end
	attackRequest.OnServerEvent:Connect(function(requestingPlayer)
		if requestingPlayer == player then
			attack(player, tool)
		end
	end)
	tool.Equipped:Connect(function()
		local character, humanoid = getLivingCharacter(player)
		if character and tool.Parent == character then
			playAnimation(tool, humanoid, "Equip", 1)
			local idle = getTrack(tool, humanoid, "Idle")
			if idle and not idle.IsPlaying then
				idle:Play(0.12, 1, 1)
			end
			playSound(tool, Config.Sounds.Equip, 0.42, 1)
		end
	end)
	tool.Unequipped:Connect(function()
		local cache = animationCache[tool]
		if cache then
			for _, track in cache.Tracks do
				if track.IsPlaying then
					track:Stop(0.10)
				end
			end
		end
	end)

	if Config.DebugCombat then
		print("[SwordCombatV6] Tool vinculada no servidor: " .. tool:GetFullName())
	end
end

local function watchContainer(player, container)
	if watchedContainers[container] then
		return
	end
	watchedContainers[container] = true
	container.ChildAdded:Connect(function(child)
		if child:IsA("Tool") then
			bindTool(player, child)
		end
	end)
	for _, child in container:GetChildren() do
		if child:IsA("Tool") then
			bindTool(player, child)
		end
	end
end

local function setupPlayer(player)
	getState(player)
	player.ChildAdded:Connect(function(child)
		if child:IsA("Backpack") then
			watchContainer(player, child)
		end
	end)
	player.CharacterAdded:Connect(function(character)
		states[player] = nil
		getState(player)
		watchContainer(player, character)
	end)

	local backpack = player:FindFirstChildOfClass("Backpack")
	if backpack then
		watchContainer(player, backpack)
	end
	if player.Character then
		watchContainer(player, player.Character)
	end
end

Players.PlayerAdded:Connect(setupPlayer)
for _, player in Players:GetPlayers() do
	task.spawn(setupPlayer, player)
end
Players.PlayerRemoving:Connect(function(player)
	states[player] = nil
end)

if Config.DebugCombat then
	print("[SwordCombatV6] Servidor iniciado; Remote individual por Tool.")
end
