-- SkyDungeon - coordenador responsivo do HUD para toque.
--
-- Este controlador nao substitui as interfaces existentes. Ele reserva zonas
-- reais da tela, mede os controles nativos do Roblox e reposiciona os elementos
-- ja criados pelos outros LocalScripts. Assim ataque, pulo, agachamento,
-- corrida, inventario e navegacao nunca disputam o mesmo espaco em celulares.

local ContextActionService = game:GetService("ContextActionService")
local GuiService = game:GetService("GuiService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local MVPConfig = require(ReplicatedStorage:WaitForChild("MVPConfig"))
local CombatConfig = require(ReplicatedStorage:WaitForChild("SwordCombat"):WaitForChild("CombatConfig"))

local VERSION = "ResponsiveTouchHUDV1"
local LAYOUT_INTERVAL = 0.25
local BASE_MARGIN = 8
local NAV_GAP = 5
local ACTION_GAP_RATIO = 0.025

local ACTION_ATTACK = "SkyDungeonAttack"
local ACTION_SPRINT = "SkyDungeonSprint"
local ACTION_SNEAK = "SkyDungeonSneak"

local currentCameraConnection
local layoutQueued = false
local elapsed = 0
local mobileProgressGui
local progressPill
local progressLabel
local progressRemaining
local progressTrack
local progressFill
local layoutSprintStamina

local function round(value)
	return math.floor(value + 0.5)
end

local function getViewport()
	local camera = workspace.CurrentCamera
	return camera and camera.ViewportSize or Vector2.new(1280, 720)
end

local function getInsets()
	local topLeft = Vector2.zero
	local bottomRight = Vector2.zero
	local success, first, second = pcall(function()
		return GuiService:GetGuiInset()
	end)
	if success then
		topLeft = typeof(first) == "Vector2" and first or Vector2.zero
		bottomRight = typeof(second) == "Vector2" and second or Vector2.zero
	end
	return topLeft, bottomRight
end

local function isPhoneViewport(viewport)
	return math.min(viewport.X, viewport.Y) < 600
end

local function getScale(viewport)
	local shortest = math.min(viewport.X, viewport.Y)
	if shortest < 390 then
		return 0.70
	elseif shortest < 480 then
		return 0.76
	elseif shortest < 600 then
		return 0.84
	elseif shortest < 760 then
		return 0.92
	end
	return 1
end


local function containingScreenGui(guiObject)
	local current = guiObject
	while current do
		if current:IsA("ScreenGui") then
			return current
		end
		current = current.Parent
	end
	return nil
end

local function screenPointForGui(guiObject, screenPoint, topLeftInset)
	local screenGui = containingScreenGui(guiObject)
	if screenGui and screenGui.IgnoreGuiInset ~= true then
		return screenPoint - topLeftInset
	end
	return screenPoint
end

local function setScreenPosition(guiObject, screenPoint, topLeftInset)
	local point = screenPointForGui(guiObject, screenPoint, topLeftInset)
	guiObject.Position = UDim2.fromOffset(round(point.X), round(point.Y))
end

local function getOrCreateScale(guiObject, name)
	local scale = guiObject:FindFirstChild(name)
	if scale and not scale:IsA("UIScale") then
		scale:Destroy()
		scale = nil
	end
	if not scale then
		scale = Instance.new("UIScale")
		scale.Name = name
		scale.Parent = guiObject
	end
	return scale
end

local function getGuiObject(guiName, objectName)
	local gui = playerGui:FindFirstChild(guiName)
	if not gui then
		return nil
	end
	local object = gui:FindFirstChild(objectName, true)
	return object and object:IsA("GuiObject") and object or nil
end

local function firstVisibleGuiButtonByName(name)
	for _, descendant in ipairs(playerGui:GetDescendants()) do
		if descendant:IsA("GuiButton")
			and descendant.Name == name
			and descendant.Visible
			and descendant.AbsoluteSize.X > 2
			and descendant.AbsoluteSize.Y > 2
		then
			return descendant
		end
	end
	return nil
end

local function rectOf(guiObject)
	if not guiObject or not guiObject:IsA("GuiObject") then
		return nil
	end
	local position = guiObject.AbsolutePosition
	local size = guiObject.AbsoluteSize
	if size.X <= 1 or size.Y <= 1 then
		return nil
	end
	return {
		Left = position.X,
		Top = position.Y,
		Right = position.X + size.X,
		Bottom = position.Y + size.Y,
		Width = size.X,
		Height = size.Y,
		Center = position + size / 2,
	}
end

local function expandedRect(rect, amount)
	return {
		Left = rect.Left - amount,
		Top = rect.Top - amount,
		Right = rect.Right + amount,
		Bottom = rect.Bottom + amount,
		Width = rect.Width + amount * 2,
		Height = rect.Height + amount * 2,
		Center = rect.Center,
	}
end

local function rectanglesOverlap(left, right)
	return left.Left < right.Right
		and left.Right > right.Left
		and left.Top < right.Bottom
		and left.Bottom > right.Top
end

local function estimatedJumpRect(viewport, topLeft, bottomRight, actionSize)
	local size = math.clamp(actionSize * 1.12, 62, 92)
	local center = Vector2.new(
		viewport.X - bottomRight.X - math.max(size * 0.62, 42),
		viewport.Y - bottomRight.Y - math.max(size * 0.62, 46)
	)
	return {
		Left = center.X - size / 2,
		Top = center.Y - size / 2,
		Right = center.X + size / 2,
		Bottom = center.Y + size / 2,
		Width = size,
		Height = size,
		Center = center,
	}
end

local function findThumbstickRect(viewport)
	local best
	local bestArea = 0
	for _, descendant in ipairs(playerGui:GetDescendants()) do
		if descendant:IsA("GuiObject") and descendant.Visible then
			local lowerName = string.lower(descendant.Name)
			if string.find(lowerName, "thumbstick", 1, true)
				or string.find(lowerName, "joystick", 1, true)
			then
				local rect = rectOf(descendant)
				if rect
					and rect.Center.X < viewport.X * 0.5
					and rect.Center.Y > viewport.Y * 0.45
				then
					local area = rect.Width * rect.Height
					if area > bestArea then
						best = rect
						bestArea = area
					end
				end
			end
		end
	end
	return best
end

local function estimatedThumbstickRect(viewport, topLeft, bottomRight, secondarySize)
	local size = math.clamp(math.min(viewport.X, viewport.Y) * 0.29, 96, 150)
	local center = Vector2.new(
		topLeft.X + math.max(size * 0.58, 58),
		viewport.Y - bottomRight.Y - math.max(size * 0.52, 54)
	)
	return {
		Left = center.X - size / 2,
		Top = center.Y - size / 2,
		Right = center.X + size / 2,
		Bottom = center.Y + size / 2,
		Width = size,
		Height = size,
		Center = center,
	}
end

local function getActionButton(actionName)
	local button = ContextActionService:GetButton(actionName)
	return button and button:IsA("GuiButton") and button or nil
end

local function setButtonTextSizes(button, primarySize, captionSize)
	for _, descendant in ipairs(button:GetDescendants()) do
		if descendant:IsA("TextLabel") then
			if descendant.Name == "CompactCaption" then
				descendant.TextSize = captionSize
			else
				descendant.TextSize = primarySize
			end
		end
	end
end

local function placeActionButton(actionName, center, size, viewport, topLeft, bottomRight)
	local button = getActionButton(actionName)
	if not button then
		return nil
	end

	local half = size / 2
	local clampedCenter = Vector2.new(
		math.clamp(center.X, topLeft.X + half + 2, viewport.X - bottomRight.X - half - 2),
		math.clamp(center.Y, topLeft.Y + half + 2, viewport.Y - bottomRight.Y - half - 2)
	)
	local parentPosition = button.Parent and button.Parent.AbsolutePosition or Vector2.zero
	button.AnchorPoint = Vector2.new(0.5, 0.5)
	button.Size = UDim2.fromOffset(size, size)
	button.Position = UDim2.fromOffset(
		round(clampedCenter.X - parentPosition.X),
		round(clampedCenter.Y - parentPosition.Y)
	)
	button.ZIndex = 20
	setButtonTextSizes(button, math.max(15, round(size * 0.30)), math.max(8, round(size * 0.13)))
	return button
end

local function actionRect(center, size)
	return {
		Left = center.X - size / 2,
		Top = center.Y - size / 2,
		Right = center.X + size / 2,
		Bottom = center.Y + size / 2,
		Width = size,
		Height = size,
		Center = center,
	}
end

local function anyBlockingPanelOpen()
	local candidates = {
		{ "SettingsUI", "Panel" },
		{ "PartyUI", "Panel" },
		{ "TradeUI", "Panel" },
		{ "GlobalLeaderboardUI", "Panel" },
		{ "GlobalStoreUI", "StorePanel" },
		{ "InventoryUI", "Drawer" },
	}
	for _, candidate in ipairs(candidates) do
		local object = getGuiObject(candidate[1], candidate[2])
		if object and object.Visible then
			return true
		end
	end
	local companionGui = playerGui:FindFirstChild("CompanionUI")
	if companionGui and companionGui.Enabled then
		for _, descendant in ipairs(companionGui:GetDescendants()) do
			if descendant:IsA("GuiObject") and descendant.Visible and descendant.Active then
				local rect = rectOf(descendant)
				if rect and rect.Width > getViewport().X * 0.45 and rect.Height > getViewport().Y * 0.45 then
					return true
				end
			end
		end
	end
	return false
end

local function playerHasEquippedSword()
	local character = player.Character
	if not character then
		return false
	end
	for _, child in ipairs(character:GetChildren()) do
		if CombatConfig.IsSword(child) then
			return true
		end
	end
	return false
end

local function updateActionVisibility()
	local blocked = anyBlockingPanelOpen()
		or player:GetAttribute("IsDowned") == true
		or (player.Character and player.Character:GetAttribute("MovementLocked") == true)

	local attack = getActionButton(ACTION_ATTACK)
	if attack then
		attack.Visible = not blocked and playerHasEquippedSword()
	end
	local sprint = getActionButton(ACTION_SPRINT)
	if sprint then
		sprint.Visible = not blocked
	end
	local sneak = getActionButton(ACTION_SNEAK)
	if sneak then
		sneak.Visible = not blocked
	end
end

local function layoutActions(viewport, topLeft, bottomRight)
	local shortest = math.min(viewport.X, viewport.Y)
	local attackSize = math.clamp(round(shortest * 0.17), 58, 74)
	local secondarySize = math.clamp(round(attackSize * 0.78), 46, 58)
	local gap = math.clamp(round(shortest * ACTION_GAP_RATIO), 8, 14)

	local jumpButton = firstVisibleGuiButtonByName("JumpButton")
	local jumpRect = rectOf(jumpButton) or estimatedJumpRect(viewport, topLeft, bottomRight, attackSize)
	jumpRect = expandedRect(jumpRect, 2)

	local attackCenter = Vector2.new(
		jumpRect.Left - gap - attackSize / 2,
		jumpRect.Center.Y - math.min(8, shortest * 0.015)
	)
	local attack = actionRect(attackCenter, attackSize)
	if attack.Left < viewport.X * 0.54 then
		local shift = viewport.X * 0.54 - attack.Left
		attackCenter += Vector2.new(shift, 0)
		attack = actionRect(attackCenter, attackSize)
	end
	if rectanglesOverlap(expandedRect(attack, gap * 0.35), jumpRect) then
		attackCenter = Vector2.new(jumpRect.Left - gap - attackSize / 2, jumpRect.Center.Y)
		attack = actionRect(attackCenter, attackSize)
	end

	local sneakCenter = Vector2.new(
		attackCenter.X,
		attack.Top - gap - secondarySize / 2
	)
	local sneak = actionRect(sneakCenter, secondarySize)
	if sneak.Top < topLeft.Y + 92 then
		sneakCenter = Vector2.new(
			attack.Left - gap - secondarySize / 2,
			attackCenter.Y - (attackSize - secondarySize) * 0.2
		)
		sneak = actionRect(sneakCenter, secondarySize)
	end

	local thumbstickRect = findThumbstickRect(viewport)
		or estimatedThumbstickRect(viewport, topLeft, bottomRight, secondarySize)
	local sprintCenter = Vector2.new(
		thumbstickRect.Center.X,
		thumbstickRect.Top - gap - secondarySize / 2
	)
	local sprint = actionRect(sprintCenter, secondarySize)
	if sprint.Top < topLeft.Y + 110 then
		sprintCenter = Vector2.new(
			thumbstickRect.Right + gap + secondarySize / 2,
			thumbstickRect.Center.Y - secondarySize * 0.35
		)
		sprint = actionRect(sprintCenter, secondarySize)
	end

	placeActionButton(ACTION_ATTACK, attackCenter, attackSize, viewport, topLeft, bottomRight)
	placeActionButton(ACTION_SNEAK, sneakCenter, secondarySize, viewport, topLeft, bottomRight)
	placeActionButton(ACTION_SPRINT, sprintCenter, secondarySize, viewport, topLeft, bottomRight)
	layoutSprintStamina(viewport, topLeft, bottomRight, sneak)

	local overlapCount = 0
	local rects = { Attack = attack, Sneak = sneak, Sprint = sprint, Jump = jumpRect, Thumbstick = thumbstickRect }
	local pairsToCheck = {
		{ "Attack", "Jump" },
		{ "Sneak", "Jump" },
		{ "Sneak", "Attack" },
		{ "Sprint", "Thumbstick" },
	}
	for _, pair in ipairs(pairsToCheck) do
		if rectanglesOverlap(expandedRect(rects[pair[1]], 2), expandedRect(rects[pair[2]], 2)) then
			overlapCount += 1
		end
	end
	playerGui:SetAttribute("MobileHUDControlOverlapCount", overlapCount)
	playerGui:SetAttribute("MobileHUDAttackCenter", Vector2.new(round(attackCenter.X), round(attackCenter.Y)))
	playerGui:SetAttribute("MobileHUDSneakCenter", Vector2.new(round(sneakCenter.X), round(sneakCenter.Y)))
	playerGui:SetAttribute("MobileHUDSprintCenter", Vector2.new(round(sprintCenter.X), round(sprintCenter.Y)))
	updateActionVisibility()
end

local function layoutTopNavigation(viewport, topLeft, bottomRight)
	local phone = isPhoneViewport(viewport)
	local buttonWidth = viewport.X < 500 and 36 or (phone and 40 or 44)
	local buttonHeight = phone and 36 or 40
	local right = viewport.X - bottomRight.X - BASE_MARGIN
	local top = topLeft.Y + BASE_MARGIN

	local definitions = {
		{ "GlobalLeaderboardUI", "RankingButton" },
		{ "SettingsUI", "SettingsButton" },
		{ "TradeUI", "TradeButton" },
		{ "PartyUI", "PartyButton" },
		{ "CompanionLauncherUI", "OpenCompanions" },
	}

	local placed = 0
	for _, definition in ipairs(definitions) do
		local button = getGuiObject(definition[1], definition[2])
		if button then
			button.AnchorPoint = Vector2.new(1, 0)
			setScreenPosition(
				button,
				Vector2.new(right - placed * (buttonWidth + NAV_GAP), top),
				topLeft
			)
			button.Size = UDim2.fromOffset(buttonWidth, buttonHeight)
			button.ZIndex = math.max(button.ZIndex, 20)
			placed += 1
		end
	end

	local store = getGuiObject("GlobalStoreUI", "OpenStore")
	if store then
		store.AnchorPoint = Vector2.new(1, 0)
		setScreenPosition(store, Vector2.new(right, top + buttonHeight + 6), topLeft)
		store.Size = UDim2.fromOffset(phone and 96 or 112, phone and 38 or 42)
		if store:IsA("TextButton") then
			store.TextSize = phone and 14 or 16
		end
	end
end

local function fitPanel(guiName, panelName, preferredWidth, preferredHeight, viewport, topLeft, bottomRight)
	local panel = getGuiObject(guiName, panelName)
	if not panel then
		return
	end
	local availableWidth = math.max(220, viewport.X - topLeft.X - bottomRight.X - 16)
	local availableHeight = math.max(180, viewport.Y - topLeft.Y - bottomRight.Y - 16)
	panel.AnchorPoint = Vector2.new(0.5, 0.5)
	setScreenPosition(
		panel,
		Vector2.new(topLeft.X + availableWidth / 2 + 8, topLeft.Y + availableHeight / 2 + 8),
		topLeft
	)
	panel.Size = UDim2.fromOffset(
		round(math.min(preferredWidth, availableWidth)),
		round(math.min(preferredHeight, availableHeight))
	)
end

local function layoutPanels(viewport, topLeft, bottomRight)
	fitPanel("SettingsUI", "Panel", 286, 194, viewport, topLeft, bottomRight)
	fitPanel("PartyUI", "Panel", 350, 470, viewport, topLeft, bottomRight)
	fitPanel("TradeUI", "Panel", 440, 550, viewport, topLeft, bottomRight)
	fitPanel("GlobalLeaderboardUI", "Panel", 300, 420, viewport, topLeft, bottomRight)

	local partyToast = getGuiObject("PartyUI", "PartyToast")
	if partyToast then
		partyToast.AnchorPoint = Vector2.new(0.5, 0)
		setScreenPosition(
			partyToast,
			Vector2.new(viewport.X / 2, topLeft.Y + (viewport.X < 500 and 230 or 170)),
			topLeft
		)
		partyToast.Size = UDim2.fromOffset(round(math.min(350, viewport.X - 20)), 78)
	end
end

local function layoutSurvival(viewport, topLeft, bottomRight)
	local scaleValue = getScale(viewport)
	if viewport.X < 500 then
		scaleValue = math.min(scaleValue, 0.64)
	end
	local hud = getGuiObject("SurvivalUI", "HUD")
	if hud then
		local hudScale = getOrCreateScale(hud, "MobileHUDScale")
		hudScale.Scale = scaleValue
		setScreenPosition(hud, Vector2.new(topLeft.X + BASE_MARGIN, topLeft.Y + BASE_MARGIN), topLeft)
	end

	local hudHeight = 72 * scaleValue
	local hudWidth = 230 * scaleValue
	local warning = getGuiObject("SurvivalUI", "Warning")
	if warning then
		getOrCreateScale(warning, "MobileHUDScale").Scale = scaleValue
		setScreenPosition(
			warning,
			Vector2.new(topLeft.X + BASE_MARGIN, topLeft.Y + BASE_MARGIN + hudHeight + 5),
			topLeft
		)
	end
	local resultCard = getGuiObject("SurvivalUI", "ResultCard")
	if resultCard then
		getOrCreateScale(resultCard, "MobileHUDScale").Scale = scaleValue
		setScreenPosition(
			resultCard,
			Vector2.new(topLeft.X + BASE_MARGIN, topLeft.Y + BASE_MARGIN + hudHeight + 43 * scaleValue),
			topLeft
		)
	end

	local levelNotice = getGuiObject("SurvivalUI", "LevelUpNotice")
	if levelNotice then
		levelNotice.AnchorPoint = Vector2.new(0.5, 0)
		setScreenPosition(
			levelNotice,
			Vector2.new(viewport.X / 2, topLeft.Y + (viewport.X < 500 and 230 or 170)),
			topLeft
		)
		levelNotice.Size = UDim2.fromOffset(round(math.min(330, viewport.X - 24)), 50)
		if levelNotice:IsA("TextLabel") then
			levelNotice.TextSize = isPhoneViewport(viewport) and 13 or 15
		end
	end

	local race = getGuiObject("SurvivalUI", "RunLevelRace")
	if race then
		if isPhoneViewport(viewport) then
			race.Visible = false
		else
			race.Visible = true
			race.AnchorPoint = Vector2.new(1, 0.5)
			setScreenPosition(
				race,
				Vector2.new(viewport.X - bottomRight.X - 4, viewport.Y * 0.43),
				topLeft
			)
			local raceScale = getOrCreateScale(race, "MobileCoordinatorScale")
			raceScale.Scale = math.min(0.78, scaleValue)
		end
	end

	playerGui:SetAttribute("MobileHUDLeftStackWidth", round(hudWidth))
	playerGui:SetAttribute("MobileHUDLeftStackTop", round(topLeft.Y + BASE_MARGIN + hudHeight + 8))
end

local function layoutInventoryAndRelic(viewport, topLeft, bottomRight)
	local scaleValue = getScale(viewport)
	local hudHeight = 72 * (viewport.X < 500 and math.min(scaleValue, 0.64) or scaleValue)
	local stackTop = topLeft.Y + BASE_MARGIN + hudHeight + 8
	local compactSize = viewport.X < 500 and 42 or 48

	local inventoryGui = playerGui:FindFirstChild("InventoryUI")
	local quickInventory = getGuiObject("InventoryUI", "QuickInventory")
	if quickInventory then
		quickInventory.AnchorPoint = Vector2.new(0, 0)
		setScreenPosition(quickInventory, Vector2.new(topLeft.X + BASE_MARGIN, stackTop), topLeft)
		quickInventory.Size = UDim2.fromOffset(compactSize, compactSize)
		quickInventory.ClipsDescendants = true
		local toggle = quickInventory:FindFirstChildWhichIsA("TextButton")
		if toggle then
			toggle.Name = "Toggle"
			toggle.Position = UDim2.fromOffset(3, 3)
			toggle.Size = UDim2.new(1, -6, 1, -6)
			toggle.Text = "ITENS"
			toggle.TextSize = viewport.X < 500 and 8 or 9
		end
		for _, child in ipairs(quickInventory:GetChildren()) do
			if child:IsA("TextLabel") then
				child.Name = "Summary"
				child.Visible = false
			end
		end
	end

	if inventoryGui then
		local drawer = inventoryGui:FindFirstChild("Drawer")
		if not drawer then
			for _, child in ipairs(inventoryGui:GetChildren()) do
				if child:IsA("Frame") and child ~= quickInventory then
					drawer = child
					drawer.Name = "Drawer"
					break
				end
			end
		end
		if drawer and drawer:IsA("GuiObject") then
			local drawerTop = stackTop + compactSize + 6
			drawer.AnchorPoint = Vector2.new(0, 0)
			setScreenPosition(drawer, Vector2.new(topLeft.X + BASE_MARGIN, drawerTop), topLeft)
			drawer.Size = UDim2.fromOffset(
				round(math.min(320, viewport.X - topLeft.X - bottomRight.X - 16)),
				round(math.max(170, math.min(260, viewport.Y - bottomRight.Y - drawerTop - 8)))
			)
		end
	end

	local relic = getGuiObject("SurvivalUI", "EquippedRelic")
	if relic then
		relic.AnchorPoint = Vector2.new(0, 0)
		setScreenPosition(relic, Vector2.new(topLeft.X + BASE_MARGIN + compactSize + 7, stackTop), topLeft)
		relic.Size = UDim2.fromOffset(compactSize, compactSize)
		relic.ClipsDescendants = true
		local imageSlot = relic:FindFirstChild("ImageSlot")
		if imageSlot and imageSlot:IsA("GuiObject") then
			imageSlot.Position = UDim2.fromOffset(2, 2)
			imageSlot.Size = UDim2.new(1, -4, 1, -4)
		end
		local status = relic:FindFirstChild("Status")
		if status and status:IsA("GuiObject") then
			status.Visible = false
		end
		local name = relic:FindFirstChild("Name")
		if name and name:IsA("GuiObject") then
			name.Visible = false
		end
	end
end

local function layoutMobility(viewport, topLeft, bottomRight)
	local holder = getGuiObject("MobilityPerksUI", "CharacterSideCommands")
	if not holder then
		return
	end
	local scale = getOrCreateScale(holder, "MobileHUDScale")
	scale.Scale = viewport.X < 500 and 0.68 or (isPhoneViewport(viewport) and 0.76 or 0.86)
	holder.AnchorPoint = Vector2.new(1, 0)
	setScreenPosition(
		holder,
		Vector2.new(
			viewport.X - bottomRight.X - BASE_MARGIN,
			topLeft.Y + (viewport.X < 500 and 170 or (isPhoneViewport(viewport) and 96 or 104))
		),
		topLeft
	)
end

local function layoutSessionAndStatus(viewport, topLeft)
	local sessionTimer = getGuiObject("SessionFloodHUD", "SessionTimer")
	if sessionTimer then
		sessionTimer.AnchorPoint = Vector2.new(0.5, 0)
		setScreenPosition(sessionTimer, Vector2.new(viewport.X / 2, topLeft.Y + 100), topLeft)
		local timerScale = getOrCreateScale(sessionTimer, "MobileHUDScale")
		timerScale.Scale = viewport.X < 500 and 0.86 or 0.94
	end

	local effects = getGuiObject("StatusEffectsUI", "TemporaryEffects")
	if effects then
		effects.AnchorPoint = Vector2.new(0.5, 0)
		setScreenPosition(effects, Vector2.new(viewport.X / 2, topLeft.Y + 130), topLeft)
		local effectsScale = effects:FindFirstChildOfClass("UIScale")
		if not effectsScale then
			effectsScale = getOrCreateScale(effects, "MobileHUDScale")
		end
		effectsScale.Scale = viewport.X < 500 and 0.64 or (isPhoneViewport(viewport) and 0.72 or 0.82)
	end
end

layoutSprintStamina = function(viewport, topLeft, bottomRight, sneakRect)
	local stamina = getGuiObject("SprintStaminaGui", "Background")
	if not stamina then
		return
	end
	local width = math.clamp(viewport.X * 0.22, 120, 170)
	local desiredBottom = math.max(topLeft.Y + 184, sneakRect.Top - 10)
	stamina.AnchorPoint = Vector2.new(1, 1)
	setScreenPosition(
		stamina,
		Vector2.new(viewport.X - bottomRight.X - BASE_MARGIN, desiredBottom),
		topLeft
	)
	stamina.Size = UDim2.fromOffset(round(width), 7)
	local limit = stamina:FindFirstChild("CurrentLimit")
	if limit and limit:IsA("TextLabel") then
		limit.Size = UDim2.fromOffset(round(width), 18)
		limit.TextSize = isPhoneViewport(viewport) and 12 or 14
	end
end

local function ensureProgressPill()
	if mobileProgressGui and mobileProgressGui.Parent then
		return
	end
	mobileProgressGui = Instance.new("ScreenGui")
	mobileProgressGui.Name = "MobileHUDCoordinatorUI"
	mobileProgressGui.ResetOnSpawn = false
	mobileProgressGui.IgnoreGuiInset = true
	mobileProgressGui.DisplayOrder = 7
	mobileProgressGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	mobileProgressGui.Parent = playerGui

	progressPill = Instance.new("Frame")
	progressPill.Name = "RunProgressPill"
	progressPill.AnchorPoint = Vector2.new(0.5, 0)
	progressPill.Size = UDim2.fromOffset(184, 42)
	progressPill.BackgroundColor3 = Color3.fromRGB(17, 20, 34)
	progressPill.BackgroundTransparency = 0.10
	progressPill.BorderSizePixel = 0
	progressPill.Parent = mobileProgressGui
	Instance.new("UICorner", progressPill).CornerRadius = UDim.new(0, 11)
	local stroke = Instance.new("UIStroke")
	stroke.Color = Color3.fromRGB(163, 112, 239)
	stroke.Transparency = 0.35
	stroke.Thickness = 1.2
	stroke.Parent = progressPill

	progressLabel = Instance.new("TextLabel")
	progressLabel.Name = "Level"
	progressLabel.Position = UDim2.fromOffset(9, 4)
	progressLabel.Size = UDim2.new(1, -18, 0, 17)
	progressLabel.BackgroundTransparency = 1
	progressLabel.Text = "NÍVEL 1"
	progressLabel.TextColor3 = Color3.fromRGB(236, 219, 255)
	progressLabel.Font = Enum.Font.GothamBold
	progressLabel.TextSize = 11
	progressLabel.TextXAlignment = Enum.TextXAlignment.Left
	progressLabel.Parent = progressPill

	progressRemaining = Instance.new("TextLabel")
	progressRemaining.Name = "Remaining"
	progressRemaining.AnchorPoint = Vector2.new(1, 0)
	progressRemaining.Position = UDim2.new(1, -9, 0, 4)
	progressRemaining.Size = UDim2.fromOffset(96, 17)
	progressRemaining.BackgroundTransparency = 1
	progressRemaining.Text = "FALTAM 150m"
	progressRemaining.TextColor3 = Color3.fromRGB(194, 177, 220)
	progressRemaining.Font = Enum.Font.GothamMedium
	progressRemaining.TextSize = 9
	progressRemaining.TextXAlignment = Enum.TextXAlignment.Right
	progressRemaining.Parent = progressPill

	progressTrack = Instance.new("Frame")
	progressTrack.Name = "Track"
	progressTrack.Position = UDim2.fromOffset(9, 27)
	progressTrack.Size = UDim2.new(1, -18, 0, 6)
	progressTrack.BackgroundColor3 = Color3.fromRGB(57, 51, 73)
	progressTrack.BorderSizePixel = 0
	progressTrack.ClipsDescendants = true
	progressTrack.Parent = progressPill
	Instance.new("UICorner", progressTrack).CornerRadius = UDim.new(1, 0)

	progressFill = Instance.new("Frame")
	progressFill.Name = "Fill"
	progressFill.Size = UDim2.fromScale(0, 1)
	progressFill.BackgroundColor3 = Color3.fromRGB(176, 97, 255)
	progressFill.BorderSizePixel = 0
	progressFill.Parent = progressTrack
	Instance.new("UICorner", progressFill).CornerRadius = UDim.new(1, 0)
end

local function updateProgressPill(viewport, topLeft)
	ensureProgressPill()
	local phone = isPhoneViewport(viewport)
	progressPill.Visible = phone
	if not phone then
		return
	end
	local width = math.clamp(viewport.X * 0.27, 150, 184)
	local progressTop = topLeft.Y + 54
	progressPill.Position = UDim2.fromOffset(round(viewport.X / 2), round(progressTop))
	progressPill.Size = UDim2.fromOffset(round(width), 42)

	local level = math.max(1, math.floor(tonumber(player:GetAttribute("RunLevel")) or 1))
	local distance = math.max(0, tonumber(player:GetAttribute("RunDistance")) or 0)
	local rangeStart, rangeEnd = MVPConfig.Progression.RunLevel.GetLevelBounds(level)
	local length = math.max(1, rangeEnd - rangeStart)
	local ratio = math.clamp((distance - rangeStart) / length, 0, 1)
	local remaining = math.max(0, rangeEnd - distance)
	progressLabel.Text = string.format("NÍVEL %d", level)
	progressRemaining.Text = string.format("FALTAM %dm", math.ceil(remaining))
	progressFill.Size = UDim2.fromScale(ratio, 1)
end

local function layoutAll()
	layoutQueued = false
	if not UserInputService.TouchEnabled then
		if mobileProgressGui then
			mobileProgressGui.Enabled = false
		end
		return
	end
	if mobileProgressGui then
		mobileProgressGui.Enabled = true
	end

	local viewport = getViewport()
	local topLeft, bottomRight = getInsets()
	layoutTopNavigation(viewport, topLeft, bottomRight)
	layoutPanels(viewport, topLeft, bottomRight)
	layoutSurvival(viewport, topLeft, bottomRight)
	layoutInventoryAndRelic(viewport, topLeft, bottomRight)
	layoutMobility(viewport, topLeft, bottomRight)
	layoutSessionAndStatus(viewport, topLeft)
	updateProgressPill(viewport, topLeft)
	layoutActions(viewport, topLeft, bottomRight)

	playerGui:SetAttribute("MobileHUDLayoutVersion", VERSION)
	playerGui:SetAttribute("MobileHUDViewport", string.format("%dx%d", round(viewport.X), round(viewport.Y)))
	playerGui:SetAttribute("MobileHUDPhoneLayout", isPhoneViewport(viewport))
end

local function queueLayout()
	if layoutQueued then
		return
	end
	layoutQueued = true
	task.defer(layoutAll)
end

local function bindCamera()
	if currentCameraConnection then
		currentCameraConnection:Disconnect()
		currentCameraConnection = nil
	end
	local camera = workspace.CurrentCamera
	if camera then
		currentCameraConnection = camera:GetPropertyChangedSignal("ViewportSize"):Connect(queueLayout)
	end
	queueLayout()
end

workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(bindCamera)
playerGui.DescendantAdded:Connect(function()
	queueLayout()
end)
playerGui.DescendantRemoving:Connect(function()
	queueLayout()
end)
player:GetAttributeChangedSignal("IsDowned"):Connect(queueLayout)
player:GetAttributeChangedSignal("RunLevel"):Connect(queueLayout)
player:GetAttributeChangedSignal("RunDistance"):Connect(queueLayout)
player.CharacterAdded:Connect(function()
	task.delay(0.2, queueLayout)
end)

RunService.RenderStepped:Connect(function(deltaTime)
	elapsed += deltaTime
	if elapsed >= LAYOUT_INTERVAL then
		elapsed = 0
		layoutAll()
	end
end)

bindCamera()
