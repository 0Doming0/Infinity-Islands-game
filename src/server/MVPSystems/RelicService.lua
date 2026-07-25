-- Compra, equipamento e efeitos passivos das relíquias.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local RelicCatalog = require(ReplicatedStorage:WaitForChild("RelicCatalog"))
local PlayerDataService = require(script.Parent.Parent.BlockParkour:WaitForChild("PlayerDataService_SkyDungeon_V10"))
local ScoreService = require(script.Parent.Parent.BlockParkour:WaitForChild("ScoreService_SkyDungeon_V10"))
local DamageService = require(script.Parent:WaitForChild("CombatDamageService"))

local RelicService = {}
local started = false
local combatStates = setmetatable({}, { __mode = "k" })
local burnStates = setmetatable({}, { __mode = "k" })

local function getPlayerState(player)
	local state = combatStates[player]
	if not state then
		state = setmetatable({}, { __mode = "k" })
		combatStates[player] = state
	end
	return state
end

local function getTargetState(player, model)
	local playerState = getPlayerState(player)
	local state = playerState[model]
	if not state then
		state = {
			IceHits = 0,
			IceLastHitAt = 0,
			StoneHits = 0,
			StoneLastHitAt = 0,
			StoneCharged = false,
		}
		playerState[model] = state
	end
	return state
end

local function equippedDefinition(player)
	local relicId = player:GetAttribute("EquippedRelic")
	return type(relicId) == "string" and RelicCatalog.Get(relicId) or nil
end

local function replicateEquippedRelic(player, relicId)
	local definition = type(relicId) == "string" and RelicCatalog.Get(relicId) or nil
	player:SetAttribute("EquippedRelic", definition and definition.RelicId or nil)
	player:SetAttribute("EquippedRelicName", definition and definition.DisplayName or nil)
	player:SetAttribute("EquippedRelicImageId", definition and definition.ImageId or nil)
	player:SetAttribute("EquippedRelicIcon", definition and definition.Icon or nil)
	player:SetAttribute("EquippedRelicColor", definition and definition.Color or nil)
end

local function markRelicProc(player, definition, targetModel)
	if not definition or not player or player.Parent ~= Players then
		return
	end
	local serial = (tonumber(player:GetAttribute("LastRelicProcSerial")) or 0) + 1
	player:SetAttribute("LastRelicProcSerial", serial)
	player:SetAttribute("LastRelicProcId", definition.RelicId)
	player:SetAttribute("LastRelicProcName", definition.DisplayName)
	player:SetAttribute("LastRelicProcAt", workspace:GetServerTimeNow())
	if targetModel and targetModel.Parent then
		targetModel:SetAttribute("LastRelicEffect", definition.Effect)
		targetModel:SetAttribute("LastRelicEffectByUserId", player.UserId)
		targetModel:SetAttribute("LastRelicEffectAt", workspace:GetServerTimeNow())
	end
end

local function setupPlayer(player)
	local data = PlayerDataService.Load(player)
	replicateEquippedRelic(player, data.EquippedRelic)
	local count = 0
	for _, owned in pairs(data.OwnedRelics) do
		if owned then
			count += 1
		end
	end
	player:SetAttribute("OwnedRelicCount", count)
end

function RelicService.Start()
	if started then
		return
	end
	started = true
	ScoreService.Start()
	Players.PlayerAdded:Connect(setupPlayer)
	Players.PlayerRemoving:Connect(function(player)
		combatStates[player] = nil
	end)
	for _, player in ipairs(Players:GetPlayers()) do
		task.spawn(setupPlayer, player)
	end
end

function RelicService.GetShopInventory(player)
	local data = PlayerDataService.Get(player) or PlayerDataService.Load(player)
	local inventory = {}
	for _, definition in ipairs(RelicCatalog.GetAll()) do
		table.insert(inventory, {
			RelicId = definition.RelicId,
			ItemId = definition.RelicId,
			ItemType = "Relic",
			DisplayName = definition.DisplayName,
			Description = definition.Description,
			Price = definition.Price,
			Color = definition.Color,
			Icon = definition.Icon,
			ImageId = definition.ImageId,
			Owned = data.OwnedRelics[definition.RelicId] == true,
			Equipped = data.EquippedRelic == definition.RelicId,
			StatsText = "Passiva para todas as espadas",
		})
	end
	return inventory
end

function RelicService.Purchase(player, relicId)
	local definition = RelicCatalog.Get(relicId)
	if not definition then
		return false, "Relíquia inválida."
	end
	PlayerDataService.Load(player)
	if PlayerDataService.HasRelic(player, relicId) then
		return false, "Você já possui esta relíquia."
	end
	local paid = ScoreService.TrySpendCoins(player, definition.Price)
	if not paid then
		return false, "Moedas insuficientes."
	end
	PlayerDataService.GrantRelic(player, relicId)
	player:SetAttribute("OwnedRelicCount", (player:GetAttribute("OwnedRelicCount") or 0) + 1)
	task.spawn(PlayerDataService.Save, player, false)
	return true, "Relíquia comprada!"
end

function RelicService.Equip(player, relicId)
	local definition = RelicCatalog.Get(relicId)
	if not definition or not PlayerDataService.HasRelic(player, relicId) then
		return false, "Compre esta relíquia primeiro."
	end
	if not PlayerDataService.SetEquippedRelic(player, relicId) then
		return false, "Não foi possível equipar."
	end
	replicateEquippedRelic(player, relicId)
	task.spawn(PlayerDataService.Save, player, false)
	return true, "Relíquia equipada!"
end

function RelicService.PrepareAttack(player, target, attack)
	local definition = equippedDefinition(player)
	if not definition or definition.Effect ~= "Stone" then
		return attack
	end
	local state = getTargetState(player, target.Model)
	if not state.StoneCharged then
		return attack
	end
	state.StoneCharged = false
	state.StoneHits = 0
	target.Model:SetAttribute("StoneRelicChargedBy", nil)
	local modified = table.clone(attack)
	modified.Knockback *= definition.KnockbackMultiplier
	modified.UpwardKnockback *= definition.KnockbackMultiplier
	modified.StoneChargedAttack = true
	return modified
end

local function findLightningTarget(player, primaryModel, position, radius)
	local nearest
	local nearestDistance = radius
	for _, model in ipairs(CollectionService:GetTagged("CombatTarget")) do
		if model ~= primaryModel and model:IsA("Model") and model.Parent then
			local tutorialOwner = model:GetAttribute("TutorialTargetUserId")
			if typeof(tutorialOwner) == "number" and tutorialOwner ~= player.UserId then
				continue
			end
			local humanoid = model:FindFirstChildWhichIsA("Humanoid", true)
			local root = model:FindFirstChild("HumanoidRootPart", true)
				or model.PrimaryPart
				or model:FindFirstChildWhichIsA("BasePart", true)
			if humanoid and humanoid.Health > 0 and root and root:IsA("BasePart") then
				local distance = (root.Position - position).Magnitude
				if distance <= nearestDistance then
					nearestDistance = distance
					nearest = {
						Model = model,
						Humanoid = humanoid,
						Root = root,
					}
				end
			end
		end
	end
	return nearest
end

local function applyFire(player, target, attack, definition)
	local model = target.Model
	if not model or not model.Parent or not target.Humanoid or target.Humanoid.Health <= 0 then
		return false
	end
	local state = burnStates[model]
	if not state then
		state = {}
		burnStates[model] = state
	end
	local serial = (state.Serial or 0) + 1
	state.Serial = serial
	state.Player = player
	state.Damage = math.max(state.Damage or 0, attack.Damage * definition.DamagePerSecondRatio)
	model:SetAttribute("RelicBurning", true)
	task.spawn(function()
		for _ = 1, definition.Duration do
			task.wait(1)
			if
				not model.Parent
				or state.Serial ~= serial
				or not target.Humanoid.Parent
				or target.Humanoid.Health <= 0
			then
				return
			end
			DamageService.ApplyEffectDamage(player, target, state.Damage, "FireRelic")
		end
		if state.Serial == serial and model.Parent then
			model:SetAttribute("RelicBurning", nil)
			state.Damage = nil
		end
	end)
	return true
end

local function applyFreeze(target, definition)
	local model = target.Model
	if model:GetAttribute("RelicFrozen") == true then
		return false
	end
	local elite = model:GetAttribute("IsElite") == true or model:GetAttribute("IsBoss") == true
	local duration = elite and definition.EliteFreezeDuration or definition.FreezeDuration
	local untilTime = workspace:GetServerTimeNow() + duration
	local humanoid = target.Humanoid
	local originalSpeed = model:GetAttribute("CombatOriginalWalkSpeed")
	if typeof(originalSpeed) ~= "number" then
		originalSpeed = humanoid.WalkSpeed
	end
	local originalAutoRotate = model:GetAttribute("CombatOriginalAutoRotate")
	if typeof(originalAutoRotate) ~= "boolean" then
		originalAutoRotate = humanoid.AutoRotate
	end
	model:SetAttribute("RelicFrozen", true)
	model:SetAttribute("RelicFrozenUntil", untilTime)
	model:SetAttribute("RelicOriginalWalkSpeed", originalSpeed)
	model:SetAttribute("RelicOriginalAutoRotate", originalAutoRotate)
	model:SetAttribute("CombatStunned", true)
	humanoid.WalkSpeed = 0
	humanoid.AutoRotate = false
	humanoid:Move(Vector3.zero)
	task.delay(duration, function()
		if
			not model.Parent
			or (tonumber(model:GetAttribute("RelicFrozenUntil")) or 0) > workspace:GetServerTimeNow()
		then
			return
		end
		model:SetAttribute("RelicFrozen", nil)
		model:SetAttribute("RelicFrozenUntil", nil)
		local combatUntil = tonumber(model:GetAttribute("CombatStunnedUntil")) or 0
		if combatUntil <= workspace:GetServerTimeNow() then
			model:SetAttribute("CombatStunned", nil)
			model:SetAttribute("CombatStunTokenId", nil)
			model:SetAttribute("CombatStunnedUntil", nil)
			if humanoid.Parent and humanoid.Health > 0 then
				humanoid.WalkSpeed = tonumber(model:GetAttribute("RelicOriginalWalkSpeed")) or humanoid.WalkSpeed
				local restoreAutoRotate = model:GetAttribute("RelicOriginalAutoRotate")
				if typeof(restoreAutoRotate) == "boolean" then
					humanoid.AutoRotate = restoreAutoRotate
				end
			end
		end
		model:SetAttribute("RelicOriginalWalkSpeed", nil)
		model:SetAttribute("RelicOriginalAutoRotate", nil)
		model:SetAttribute("CombatOriginalWalkSpeed", nil)
		model:SetAttribute("CombatOriginalAutoRotate", nil)
	end)
	return true
end

function RelicService.ApplyAfterHit(player, attackerRoot, target, attack)
	local definition = equippedDefinition(player)
	if not definition then
		return
	end
	if definition.Effect == "Lightning" then
		local chained = findLightningTarget(player, target.Model, target.Root.Position, definition.ChainRadius)
		if chained then
			local applied = DamageService.ApplyEffectDamage(player, chained, attack.Damage, "LightningRelic")
			if applied then
				markRelicProc(player, definition, chained.Model)
			end
		end
	elseif definition.Effect == "Fire" then
		if applyFire(player, target, attack, definition) then
			markRelicProc(player, definition, target.Model)
		end
	elseif definition.Effect == "Ice" then
		local state = getTargetState(player, target.Model)
		local now = os.clock()
		state.IceHits = now - state.IceLastHitAt <= definition.ComboWindowSeconds and state.IceHits + 1 or 1
		state.IceLastHitAt = now
		if state.IceHits >= definition.HitsRequired and target.Model:GetAttribute("RelicFrozen") ~= true then
			state.IceHits = 0
			if applyFreeze(target, definition) then
				markRelicProc(player, definition, target.Model)
			end
		end
	elseif definition.Effect == "Stone" and attack.StoneChargedAttack then
		markRelicProc(player, definition, target.Model)
	elseif definition.Effect == "Stone" then
		local state = getTargetState(player, target.Model)
		local now = os.clock()
		state.StoneHits = now - state.StoneLastHitAt <= definition.ComboWindowSeconds and state.StoneHits + 1 or 1
		state.StoneLastHitAt = now
		if state.StoneHits >= definition.HitsToCharge then
			state.StoneCharged = true
			target.Model:SetAttribute("StoneRelicChargedBy", player.UserId)
		end
	end
end

return RelicService