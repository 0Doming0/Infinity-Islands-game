-- Equipamento visual dos beneficios premium.
--
-- Coloque os assets em:
-- ServerStorage/MVPAssets/Monetization
--
-- Tipos aceitos: Accessory, Model ou BasePart. Scripts e interacoes presentes
-- nos modelos importados sao removidos da copia antes de equipa-la.

local ServerStorage = game:GetService("ServerStorage")

local MonetizationAssetService = {}

local ROOT_FOLDER_NAME = "MVPAssets"
local ASSET_FOLDER_NAME = "Monetization"
local EQUIPMENT_SLOT_ATTRIBUTE = "MonetizationEquipmentSlot"
local PRODUCT_ATTRIBUTE = "MonetizationProductId"
local FALLBACK_ATTRIBUTE = "MonetizationAssetFallback"
local WING_ANIMATION_NAME = "PlayWings"
local WING_ANIMATION_READY_ATTRIBUTE = "PlayWingsAnimationReady"
local WING_ANIMATION_PLAYING_ATTRIBUTE = "PlayWingsAnimationPlaying"
local WING_ANIMATION_TRACK_NAME_ATTRIBUTE = "WingFlightAnimationName"
local warned = {}
local wingAnimationTracks = setmetatable({}, { __mode = "k" })
local stopTrack

local function warnOnce(key, message)
	if warned[key] then
		return
	end
	warned[key] = true
	warn("[MonetizationAssetService] " .. message)
end

local function ensureFolder(parent, name)
	local existing = parent:FindFirstChild(name)
	if existing then
		if existing:IsA("Folder") then
			return existing
		end
		warnOnce(
			"InvalidFolder:" .. existing:GetFullName(),
			existing:GetFullName() .. " precisa ser uma Folder."
		)
		return nil
	end
	local folder = Instance.new("Folder")
	folder.Name = name
	folder.Parent = parent
	return folder
end

function MonetizationAssetService.EnsureAssetFolder()
	local root = ensureFolder(ServerStorage, ROOT_FOLDER_NAME)
	return root and ensureFolder(root, ASSET_FOLDER_NAME) or nil
end

local function acceptedTemplate(template)
	return template
		and (
			template:IsA("Accessory")
			or template:IsA("Model")
			or template:IsA("BasePart")
		)
end

local function assetNames(definition)
	local config = definition and definition.Asset
	local names = {}
	if type(config) ~= "table" then
		return names
	end
	if type(config.ModelName) == "string" and config.ModelName ~= "" then
		table.insert(names, config.ModelName)
	end
	for _, alias in ipairs(config.Aliases or {}) do
		if type(alias) == "string" and alias ~= "" and not table.find(names, alias) then
			table.insert(names, alias)
		end
	end
	return names
end

function MonetizationAssetService.FindTemplate(definition)
	local folder = MonetizationAssetService.EnsureAssetFolder()
	if not folder then
		return nil
	end
	for _, name in ipairs(assetNames(definition)) do
		local direct = folder:FindFirstChild(name)
		if acceptedTemplate(direct) then
			return direct
		end
	end
	-- Permite organizar os modelos em subpastas sem perder a descoberta
	-- automatica, mas nunca procura fora de MVPAssets/Monetization.
	for _, descendant in ipairs(folder:GetDescendants()) do
		if acceptedTemplate(descendant) then
			for _, name in ipairs(assetNames(definition)) do
				if descendant.Name == name then
					return descendant
				end
			end
		end
	end
	return nil
end

local function sanitizeClone(clone)
	for _, descendant in ipairs(clone:GetDescendants()) do
		if descendant:IsA("BaseScript")
			or descendant:IsA("ProximityPrompt")
			or descendant:IsA("ClickDetector")
			or descendant:IsA("Humanoid")
		then
			descendant:Destroy()
		elseif descendant:IsA("BasePart") then
			descendant.Anchored = false
			descendant.CanCollide = false
			descendant.CanTouch = false
			descendant.CanQuery = false
			descendant.Massless = true
		end
	end
	if clone:IsA("BasePart") then
		clone.Anchored = false
		clone.CanCollide = false
		clone.CanTouch = false
		clone.CanQuery = false
		clone.Massless = true
	end
end

local function equipmentRoots(character, slot)
	local result = {}
	for _, child in ipairs(character:GetChildren()) do
		if child:GetAttribute(EQUIPMENT_SLOT_ATTRIBUTE) == slot then
			table.insert(result, child)
		end
	end
	return result
end

function MonetizationAssetService.ClearSlot(character, slot)
	if not character then
		return
	end
	for _, instance in ipairs(equipmentRoots(character, slot)) do
		if slot == "Wings" then
			stopTrack(instance, 0)
		end
		instance:Destroy()
	end
	if slot == "Wings" then
		local legacy = character:FindFirstChild("MonetizationWings")
		if legacy then
			legacy:Destroy()
		end
	elseif slot == "Cape" then
		local legacy = character:FindFirstChild("MonetizationCape")
		if legacy then
			legacy:Destroy()
		end
	end
end

local function currentEquipment(character, definition, slot)
	for _, instance in ipairs(equipmentRoots(character, slot)) do
		if instance:GetAttribute(PRODUCT_ATTRIBUTE) == definition.Id
			and instance:GetAttribute(FALLBACK_ATTRIBUTE) ~= true
		then
			return instance
		end
	end
	return nil
end

function MonetizationAssetService.GetEquipped(character, definition, slot)
	if not character or not definition then
		return nil
	end
	for _, instance in ipairs(equipmentRoots(character, slot)) do
		if instance:GetAttribute(PRODUCT_ATTRIBUTE) == definition.Id then
			return instance
		end
	end
	return nil
end

local function torsoOf(character)
	local torso = character:FindFirstChild("UpperTorso")
		or character:FindFirstChild("Torso")
	return torso and torso:IsA("BasePart") and torso or nil
end

local function findAttachmentOutside(root, name, excluded)
	for _, descendant in ipairs(root:GetDescendants()) do
		if descendant:IsA("Attachment")
			and descendant.Name == name
			and not descendant:IsDescendantOf(excluded)
		then
			return descendant
		end
	end
	return nil
end

local function clonePivot(clone)
	if clone:IsA("Model") then
		return clone:GetPivot()
	end
	if clone:IsA("BasePart") then
		return clone.CFrame
	end
	return nil
end

local function pivotClone(clone, pivot)
	if clone:IsA("Model") then
		clone:PivotTo(pivot)
	else
		clone.CFrame = pivot
	end
end

local function partsOf(clone)
	local parts = {}
	if clone:IsA("BasePart") then
		table.insert(parts, clone)
	end
	for _, descendant in ipairs(clone:GetDescendants()) do
		if descendant:IsA("BasePart") then
			table.insert(parts, descendant)
		end
	end
	return parts
end

local function animationName(definition)
	local config = definition and definition.Asset
	if type(config) == "table"
		and type(config.FlightAnimationName) == "string"
		and config.FlightAnimationName ~= ""
	then
		return config.FlightAnimationName
	end
	return WING_ANIMATION_NAME
end

local function prepareWingAnimator(clone, definition, slot)
	if slot ~= "Wings" then
		return
	end

	local name = animationName(definition)
	local animation = clone:FindFirstChild(name, true)
	if not animation or not animation:IsA("Animation") then
		clone:SetAttribute(WING_ANIMATION_READY_ATTRIBUTE, false)
		warnOnce(
			"MissingWingAnimation:" .. tostring(definition.Id),
			string.format(
				"%s precisa conter um objeto Animation chamado %s.",
				tostring(definition.DisplayName or definition.Id),
				name
			)
		)
		return
	end
	clone:SetAttribute(WING_ANIMATION_TRACK_NAME_ATTRIBUTE, name)

	-- O Animator precisa nascer no servidor para a animacao das asas ser
	-- replicada e ficar visivel para todos os jogadores.
	local controller = clone:FindFirstChildWhichIsA("AnimationController", true)
	if not controller then
		controller = Instance.new("AnimationController")
		controller.Name = "WingsAnimationController"
		controller.Parent = clone
	end
	local animator = controller:FindFirstChildOfClass("Animator")
	if not animator then
		animator = Instance.new("Animator")
		animator.Name = "WingsAnimator"
		animator.Parent = controller
	end
	clone:SetAttribute(WING_ANIMATION_READY_ATTRIBUTE, true)
end

local function animationRoots(character)
	return equipmentRoots(character, "Wings")
end

stopTrack = function(root, fadeTime)
	local cachedTrack = wingAnimationTracks[root]
	local expectedName = root:GetAttribute(WING_ANIMATION_TRACK_NAME_ATTRIBUTE)
	if type(expectedName) ~= "string" or expectedName == "" then
		expectedName = WING_ANIMATION_NAME
	end

	-- Nao dependa apenas do cache: uma faixa pode continuar viva no Animator
	-- depois de uma troca rapida de modelo, recarregamento ou interrupcao do voo.
	for _, descendant in ipairs(root:GetDescendants()) do
		if descendant:IsA("Animator") then
			local ok, playingTracks = pcall(
				descendant.GetPlayingAnimationTracks,
				descendant
			)
			if ok then
				for _, track in ipairs(playingTracks) do
					local source = track.Animation
					local isWingFlightTrack = track == cachedTrack
						or track.Name == expectedName
						or (
							source
							and source:IsDescendantOf(root)
							and source.Name == expectedName
						)
					if isWingFlightTrack then
						pcall(track.Stop, track, fadeTime or 0.08)
					end
				end
			end
		end
	end

	if cachedTrack and cachedTrack.IsPlaying then
		pcall(cachedTrack.Stop, cachedTrack, fadeTime or 0.08)
	end
	wingAnimationTracks[root] = nil
	root:SetAttribute(WING_ANIMATION_PLAYING_ATTRIBUTE, false)
end

function MonetizationAssetService.StopWingAnimations(character, fadeTime)
	if not character then
		return false
	end
	local changed = false
	for _, root in ipairs(animationRoots(character)) do
		stopTrack(root, fadeTime)
		changed = true
	end
	return changed
end

function MonetizationAssetService.SetWingAnimationPlaying(character, definition, playing)
	if not character then
		return false
	end

	local changed = false
	for _, root in ipairs(animationRoots(character)) do
		if not playing then
			stopTrack(root, 0.08)
			changed = true
			continue
		end

		local name = animationName(definition)
		local animation = root:FindFirstChild(name, true)
		local animator = root:FindFirstChildWhichIsA("Animator", true)
		if not animation or not animation:IsA("Animation") or not animator then
			root:SetAttribute(WING_ANIMATION_READY_ATTRIBUTE, false)
			continue
		end

		local track = wingAnimationTracks[root]
		if not track then
			local loaded, result = pcall(animator.LoadAnimation, animator, animation)
			if not loaded then
				warnOnce(
					"LoadWingAnimation:" .. tostring(definition and definition.Id),
					"Nao foi possivel carregar " .. name .. ": " .. tostring(result)
				)
				continue
			end
			track = result
			track.Looped = true
			track.Priority = Enum.AnimationPriority.Movement
			wingAnimationTracks[root] = track
			track.Stopped:Connect(function()
				if wingAnimationTracks[root] == track then
					root:SetAttribute(WING_ANIMATION_PLAYING_ATTRIBUTE, false)
				end
			end)
		end
		if not track.IsPlaying then
			track:Play(0.12, 1, 1)
		end
		root:SetAttribute(WING_ANIMATION_READY_ATTRIBUTE, true)
		root:SetAttribute(WING_ANIMATION_PLAYING_ATTRIBUTE, true)
		changed = true
	end
	return changed
end

local function equipAccessory(character, humanoid, torso, clone, definition, slot)
	local handle = clone:FindFirstChild("Handle")
	if not handle or not handle:IsA("BasePart") then
		clone:Destroy()
		return false, "o Accessory nao possui uma BasePart chamada Handle"
	end
	clone:SetAttribute(EQUIPMENT_SLOT_ATTRIBUTE, slot)
	clone:SetAttribute(PRODUCT_ATTRIBUTE, definition.Id)
	clone:SetAttribute(FALLBACK_ATTRIBUTE, false)
	local success, errorMessage = pcall(humanoid.AddAccessory, humanoid, clone)
	if not success then
		clone:Destroy()
		return false, tostring(errorMessage)
	end
	local connected = false
	for _, joint in ipairs(handle:GetChildren()) do
		if joint:IsA("JointInstance") or joint:IsA("WeldConstraint") then
			connected = true
			break
		end
	end
	if not connected then
		local config = definition.Asset or {}
		local attachmentName = type(config.AttachmentName) == "string"
			and config.AttachmentName or "BodyBackAttachment"
		local sourceAttachment = clone:FindFirstChild(attachmentName, true)
		local targetAttachment = findAttachmentOutside(character, attachmentName, clone)
		if sourceAttachment and sourceAttachment:IsA("Attachment") and targetAttachment then
			local delta = targetAttachment.WorldCFrame * sourceAttachment.WorldCFrame:Inverse()
			handle.CFrame = delta * handle.CFrame
		else
			local offset = typeof(config.FallbackOffset) == "CFrame"
				and config.FallbackOffset or CFrame.new(0, 0, 0.65)
			handle.CFrame = torso.CFrame * offset
		end
		local weld = Instance.new("WeldConstraint")
		weld.Name = "MonetizationAutoWeld"
		weld.Part0 = torso
		weld.Part1 = handle
		weld.Parent = handle
	end
	return true, clone
end

local function equipModel(character, torso, clone, definition, slot)
	local parts = partsOf(clone)
	if #parts == 0 then
		clone:Destroy()
		return false, "o modelo nao possui nenhuma BasePart"
	end
	clone:SetAttribute(EQUIPMENT_SLOT_ATTRIBUTE, slot)
	clone:SetAttribute(PRODUCT_ATTRIBUTE, definition.Id)
	clone:SetAttribute(FALLBACK_ATTRIBUTE, false)
	clone.Parent = character

	local config = definition.Asset or {}
	local orientationOffset = typeof(config.ModelOrientationOffset) == "CFrame"
		and config.ModelOrientationOffset or CFrame.new()
	local attachmentName = type(config.AttachmentName) == "string"
		and config.AttachmentName or "BodyBackAttachment"
	local sourceAttachment = clone:FindFirstChild(attachmentName, true)
	local targetAttachment = findAttachmentOutside(character, attachmentName, clone)
	local pivot = clonePivot(clone)
	if sourceAttachment and sourceAttachment:IsA("Attachment") and targetAttachment and pivot then
		-- A orientacao extra e aplicada no espaco local do attachment do
		-- personagem. Assim modelos que vieram girados do editor podem ser
		-- corrigidos sem alterar o asset original no ServerStorage.
		local targetCFrame = targetAttachment.WorldCFrame * orientationOffset
		local delta = targetCFrame * sourceAttachment.WorldCFrame:Inverse()
		pivotClone(clone, delta * pivot)
	else
		local offset = typeof(config.FallbackOffset) == "CFrame"
			and config.FallbackOffset or CFrame.new(0, 0, 0.65)
		pivotClone(clone, torso.CFrame * offset * orientationOffset)
	end

	-- Em rigs animados, as partes Part1 de Motor6D precisam permanecer livres
	-- para o Animator movimenta-las. Somente as raizes do rig sao presas ao
	-- torso. Modelos sem Motor6D mantem o encaixe rigido anterior.
	local animatedParts = {}
	local hasMotor = false
	for _, descendant in ipairs(clone:GetDescendants()) do
		if descendant:IsA("Motor6D")
			and descendant.Part0
			and descendant.Part1
			and descendant.Part0:IsDescendantOf(clone)
			and descendant.Part1:IsDescendantOf(clone)
		then
			hasMotor = true
			animatedParts[descendant.Part1] = true
		end
	end
	local weldedRoots = 0
	for _, part in ipairs(parts) do
		if hasMotor and animatedParts[part] then
			continue
		end
		local weld = Instance.new("WeldConstraint")
		weld.Name = "MonetizationAutoWeld"
		weld.Part0 = torso
		weld.Part1 = part
		weld.Parent = part
		weldedRoots += 1
	end
	if weldedRoots == 0 then
		local rootPart = clone:IsA("Model") and clone.PrimaryPart or parts[1]
		local weld = Instance.new("WeldConstraint")
		weld.Name = "MonetizationAutoWeld"
		weld.Part0 = torso
		weld.Part1 = rootPart
		weld.Parent = rootPart
	end
	prepareWingAnimator(clone, definition, slot)
	return true, clone
end

function MonetizationAssetService.Equip(character, definition, slot)
	if not character or not definition or type(slot) ~= "string" then
		return false, "parametros invalidos"
	end
	local existing = currentEquipment(character, definition, slot)
	if existing then
		return true, existing
	end
	local template = MonetizationAssetService.FindTemplate(definition)
	if not template then
		local expected = table.concat(assetNames(definition), " ou ")
		warnOnce(
			"Missing:" .. tostring(definition.Id),
			string.format(
				"%s ausente em ServerStorage/MVPAssets/Monetization (%s). Usando fallback.",
				tostring(definition.DisplayName or definition.Id),
				expected ~= "" and expected or "nome nao configurado"
			)
		)
		return false, "asset ausente"
	end
	local torso = torsoOf(character)
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not torso or not humanoid then
		return false, "personagem sem torso ou Humanoid"
	end
	local originalArchivable = template.Archivable
	template.Archivable = true
	local cloned, clone = pcall(template.Clone, template)
	template.Archivable = originalArchivable
	if not cloned or not clone then
		warnOnce(
			"Clone:" .. template:GetFullName(),
			"Nao foi possivel clonar " .. template:GetFullName() .. "."
		)
		return false, "falha ao clonar"
	end
	sanitizeClone(clone)
	MonetizationAssetService.ClearSlot(character, slot)
	if clone:IsA("Accessory") then
		return equipAccessory(character, humanoid, torso, clone, definition, slot)
	end
	local success, result = equipModel(character, torso, clone, definition, slot)
	if not success then
		warnOnce(
			"Invalid:" .. template:GetFullName(),
			template:GetFullName() .. " e invalido: " .. tostring(result) .. "."
		)
	end
	return success, result
end

function MonetizationAssetService.MarkFallback(instance, definition, slot)
	instance:SetAttribute(EQUIPMENT_SLOT_ATTRIBUTE, slot)
	instance:SetAttribute(PRODUCT_ATTRIBUTE, definition.Id)
	instance:SetAttribute(FALLBACK_ATTRIBUTE, true)
end

return table.freeze(MonetizationAssetService)
