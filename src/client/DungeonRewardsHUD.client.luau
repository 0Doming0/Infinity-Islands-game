-- HUD-07 — coletáveis físicos, moedas pendentes, Reward Island e inventário/recompensas
-- Consome Task 24, Task 28 e RewardIslandService. Não concede recompensas no cliente.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local VERSION = "CrystalCelestialRewardsV1"
local HUD_NAME = "DungeonUnifiedHUD"
local UPDATE_INTERVAL = 0.10

local COLORS = {
	Text = Color3.fromRGB(239, 247, 252),
	Muted = Color3.fromRGB(147, 176, 199),
	Cyan = Color3.fromRGB(107, 225, 255),
	CyanSoft = Color3.fromRGB(181, 241, 255),
	Gold = Color3.fromRGB(232, 195, 104),
	GoldSoft = Color3.fromRGB(255, 225, 143),
	Green = Color3.fromRGB(100, 236, 162),
	Orange = Color3.fromRGB(255, 184, 91),
	Red = Color3.fromRGB(255, 106, 118),
	Purple = Color3.fromRGB(198, 142, 255),
	Glass = Color3.fromRGB(13, 27, 42),
	GlassRaised = Color3.fromRGB(24, 49, 65),
}

local gui = playerGui:WaitForChild(HUD_NAME, 20)
if not gui or not gui:IsA("ScreenGui") then
	warn("[HUD-07] HUD-01 não encontrado.")
	return
end

local root = gui:WaitForChild("Root")
local currencies = root:WaitForChild("Currencies")
local confirmedCard = currencies:WaitForChild("ConfirmedCoins")
local pendingCard = currencies:WaitForChild("PendingCoins")
local inventoryDrawer = root:WaitForChild("InventoryDrawer")

local function serverTime()
	return workspace:GetServerTimeNow()
end

local function addSubtitle(card, name, text)
	local existing = card:FindFirstChild(name)
	if existing then return existing end
	local label = Instance.new("TextLabel")
	label.Name = name
	label.AnchorPoint = Vector2.new(1, 1)
	label.Position = UDim2.new(1, -10, 1, -5)
	label.Size = UDim2.new(1, -86, 0, 16)
	label.BackgroundTransparency = 1
	label.Text = text
	label.TextColor3 = COLORS.Muted
	label.Font = Enum.Font.GothamMedium
	label.TextSize = 8
	label.TextXAlignment = Enum.TextXAlignment.Right
	label.TextTruncate = Enum.TextTruncate.AtEnd
	label.ZIndex = card.ZIndex + 5
	label.Parent = card
	return label
end

local confirmedSubtitle = addSubtitle(confirmedCard, "RewardStatus", "SALDO SALVO")
local pendingSubtitle = addSubtitle(pendingCard, "RewardStatus", "AGUARDANDO CHECKPOINT")

-- Indicador compacto dos coletáveis físicos.
local collectible = root:FindFirstChild("CollectibleTracker")
if collectible then collectible:Destroy() end
collectible = Instance.new("Frame")
collectible.Name = "CollectibleTracker"
collectible.Position = UDim2.fromOffset(22, 198)
collectible.Size = UDim2.fromOffset(310, 52)
collectible.BackgroundColor3 = COLORS.Glass
collectible.BackgroundTransparency = 0.10
collectible.BorderSizePixel = 0
collectible.Visible = false
collectible.ZIndex = 26
collectible.Parent = root
Instance.new("UICorner", collectible).CornerRadius = UDim.new(0, 13)

local collectibleStroke = Instance.new("UIStroke")
collectibleStroke.Color = COLORS.Cyan
collectibleStroke.Transparency = 0.30
collectibleStroke.Thickness = 1.1
collectibleStroke.Parent = collectible

local collectibleGlyph = Instance.new("TextLabel")
collectibleGlyph.Position = UDim2.fromOffset(8, 4)
collectibleGlyph.Size = UDim2.fromOffset(42, 42)
collectibleGlyph.BackgroundTransparency = 1
collectibleGlyph.Text = "✦"
collectibleGlyph.TextColor3 = COLORS.CyanSoft
collectibleGlyph.Font = Enum.Font.GothamBlack
collectibleGlyph.TextSize = 22
collectibleGlyph.ZIndex = 27
collectibleGlyph.Parent = collectible

local collectibleTitle = Instance.new("TextLabel")
collectibleTitle.Position = UDim2.fromOffset(50, 5)
collectibleTitle.Size = UDim2.new(1, -60, 0, 20)
collectibleTitle.BackgroundTransparency = 1
collectibleTitle.Text = "ESSÊNCIAS NO CHÃO"
collectibleTitle.TextColor3 = COLORS.Text
collectibleTitle.Font = Enum.Font.GothamBold
collectibleTitle.TextSize = 10
collectibleTitle.TextXAlignment = Enum.TextXAlignment.Left
collectibleTitle.ZIndex = 27
collectibleTitle.Parent = collectible

local collectibleDetail = Instance.new("TextLabel")
collectibleDetail.Position = UDim2.fromOffset(50, 25)
collectibleDetail.Size = UDim2.new(1, -60, 0, 18)
collectibleDetail.BackgroundTransparency = 1
collectibleDetail.Text = ""
collectibleDetail.TextColor3 = COLORS.Muted
collectibleDetail.Font = Enum.Font.GothamMedium
collectibleDetail.TextSize = 9
collectibleDetail.TextXAlignment = Enum.TextXAlignment.Left
collectibleDetail.TextTruncate = Enum.TextTruncate.AtEnd
collectibleDetail.ZIndex = 27
collectibleDetail.Parent = collectible

-- Reward Island.
local oldReward = root:FindFirstChild("RewardIslandPanel")
if oldReward then oldReward:Destroy() end

local rewardPanel = Instance.new("Frame")
rewardPanel.Name = "RewardIslandPanel"
rewardPanel.AnchorPoint = Vector2.new(0.5, 0.5)
rewardPanel.Position = UDim2.fromScale(0.5, 0.53)
rewardPanel.Size = UDim2.fromOffset(560, 252)
rewardPanel.BackgroundColor3 = COLORS.Glass
rewardPanel.BackgroundTransparency = 0.035
rewardPanel.BorderSizePixel = 0
rewardPanel.Visible = false
rewardPanel.ZIndex = 70
rewardPanel.Parent = root
Instance.new("UICorner", rewardPanel).CornerRadius = UDim.new(0, 18)

local rewardStroke = Instance.new("UIStroke")
rewardStroke.Color = COLORS.Gold
rewardStroke.Transparency = 0.12
rewardStroke.Thickness = 1.5
rewardStroke.Parent = rewardPanel

local rewardTitle = Instance.new("TextLabel")
rewardTitle.Position = UDim2.fromOffset(18, 10)
rewardTitle.Size = UDim2.new(1, -36, 0, 30)
rewardTitle.BackgroundTransparency = 1
rewardTitle.Text = "ILHA DE RECOMPENSA"
rewardTitle.TextColor3 = COLORS.GoldSoft
rewardTitle.Font = Enum.Font.GothamBlack
rewardTitle.TextSize = 17
rewardTitle.ZIndex = 71
rewardTitle.Parent = rewardPanel

local rewardTimer = Instance.new("TextLabel")
rewardTimer.Position = UDim2.fromOffset(18, 41)
rewardTimer.Size = UDim2.new(1, -36, 0, 20)
rewardTimer.BackgroundTransparency = 1
rewardTimer.Text = ""
rewardTimer.TextColor3 = COLORS.Muted
rewardTimer.Font = Enum.Font.GothamMedium
rewardTimer.TextSize = 9
rewardTimer.ZIndex = 71
rewardTimer.Parent = rewardPanel

local function chestCard(name, x, titleText, glyph, color)
	local card = Instance.new("Frame")
	card.Name = name
	card.Position = UDim2.fromOffset(x, 74)
	card.Size = UDim2.fromOffset(246, 102)
	card.BackgroundColor3 = COLORS.GlassRaised
	card.BackgroundTransparency = 0.07
	card.BorderSizePixel = 0
	card.ZIndex = 71
	card.Parent = rewardPanel
	Instance.new("UICorner", card).CornerRadius = UDim.new(0, 14)

	local s = Instance.new("UIStroke")
	s.Name = "Stroke"
	s.Color = color
	s.Transparency = 0.24
	s.Thickness = 1.2
	s.Parent = card

	local icon = Instance.new("TextLabel")
	icon.Position = UDim2.fromOffset(8, 11)
	icon.Size = UDim2.fromOffset(54, 54)
	icon.BackgroundTransparency = 1
	icon.Text = glyph
	icon.TextColor3 = color
	icon.Font = Enum.Font.GothamBlack
	icon.TextSize = 26
	icon.ZIndex = 72
	icon.Parent = card

	local title = Instance.new("TextLabel")
	title.Position = UDim2.fromOffset(63, 10)
	title.Size = UDim2.new(1, -73, 0, 23)
	title.BackgroundTransparency = 1
	title.Text = titleText
	title.TextColor3 = COLORS.Text
	title.Font = Enum.Font.GothamBold
	title.TextSize = 11
	title.TextXAlignment = Enum.TextXAlignment.Left
	title.ZIndex = 72
	title.Parent = card

	local state = Instance.new("TextLabel")
	state.Name = "State"
	state.Position = UDim2.fromOffset(63, 35)
	state.Size = UDim2.new(1, -73, 0, 22)
	state.BackgroundTransparency = 1
	state.Text = "DISPONÍVEL"
	state.TextColor3 = color
	state.Font = Enum.Font.GothamBold
	state.TextSize = 10
	state.TextXAlignment = Enum.TextXAlignment.Left
	state.ZIndex = 72
	state.Parent = card

	local detail = Instance.new("TextLabel")
	detail.Name = "Detail"
	detail.Position = UDim2.fromOffset(12, 69)
	detail.Size = UDim2.new(1, -24, 0, 23)
	detail.BackgroundTransparency = 1
	detail.Text = "Aproxime-se e abra o baú."
	detail.TextColor3 = COLORS.Muted
	detail.Font = Enum.Font.GothamMedium
	detail.TextSize = 8
	detail.TextWrapped = true
	detail.ZIndex = 72
	detail.Parent = card
	return { Card = card, Stroke = s, State = state, Detail = detail, Color = color }
end

local coreCard = chestCard("CoreChest", 22, "CORE CHEST", "◆", COLORS.Cyan)
local bonusCard = chestCard("BonusChest", 292, "BONUS CHEST", "✦", COLORS.Gold)

local coinsState = Instance.new("Frame")
coinsState.Name = "CoinsCommit"
coinsState.Position = UDim2.fromOffset(22, 187)
coinsState.Size = UDim2.new(1, -44, 0, 48)
coinsState.BackgroundColor3 = Color3.fromRGB(17, 38, 52)
coinsState.BackgroundTransparency = 0.09
coinsState.BorderSizePixel = 0
coinsState.ZIndex = 71
coinsState.Parent = rewardPanel
Instance.new("UICorner", coinsState).CornerRadius = UDim.new(0, 12)

local coinsStateStroke = Instance.new("UIStroke")
coinsStateStroke.Color = COLORS.Gold
coinsStateStroke.Transparency = 0.35
coinsStateStroke.Parent = coinsState

local coinsTitle = Instance.new("TextLabel")
coinsTitle.Position = UDim2.fromOffset(10, 5)
coinsTitle.Size = UDim2.new(0.58, 0, 0, 19)
coinsTitle.BackgroundTransparency = 1
coinsTitle.Text = "MOEDAS DO ROUND"
coinsTitle.TextColor3 = COLORS.Text
coinsTitle.Font = Enum.Font.GothamBold
coinsTitle.TextSize = 9
coinsTitle.TextXAlignment = Enum.TextXAlignment.Left
coinsTitle.ZIndex = 72
coinsTitle.Parent = coinsState

local coinsDetail = Instance.new("TextLabel")
coinsDetail.Position = UDim2.fromOffset(10, 23)
coinsDetail.Size = UDim2.new(0.7, 0, 0, 18)
coinsDetail.BackgroundTransparency = 1
coinsDetail.Text = "Abra os dois baús para confirmar."
coinsDetail.TextColor3 = COLORS.Muted
coinsDetail.Font = Enum.Font.GothamMedium
coinsDetail.TextSize = 8
coinsDetail.TextXAlignment = Enum.TextXAlignment.Left
coinsDetail.ZIndex = 72
coinsDetail.Parent = coinsState

local pendingValue = Instance.new("TextLabel")
pendingValue.AnchorPoint = Vector2.new(1, 0.5)
pendingValue.Position = UDim2.new(1, -11, 0.5, 0)
pendingValue.Size = UDim2.fromOffset(150, 30)
pendingValue.BackgroundTransparency = 1
pendingValue.Text = "0 PENDENTES"
pendingValue.TextColor3 = COLORS.GoldSoft
pendingValue.Font = Enum.Font.GothamBlack
pendingValue.TextSize = 11
pendingValue.TextXAlignment = Enum.TextXAlignment.Right
pendingValue.ZIndex = 72
pendingValue.Parent = coinsState

-- Inventário: status compacto.
local inventoryStatus = inventoryDrawer:FindFirstChild("InventoryStatusHUD07")
if inventoryStatus then inventoryStatus:Destroy() end
inventoryStatus = Instance.new("TextLabel")
inventoryStatus.Name = "InventoryStatusHUD07"
inventoryStatus.AnchorPoint = Vector2.new(1, 0)
inventoryStatus.Position = UDim2.new(1, -53, 0, 12)
inventoryStatus.Size = UDim2.fromOffset(180, 22)
inventoryStatus.BackgroundTransparency = 1
inventoryStatus.Text = "CONSUMÍVEIS DA RUN"
inventoryStatus.TextColor3 = COLORS.Muted
inventoryStatus.Font = Enum.Font.GothamBold
inventoryStatus.TextSize = 8
inventoryStatus.TextXAlignment = Enum.TextXAlignment.Right
inventoryStatus.ZIndex = 20
inventoryStatus.Parent = inventoryDrawer

local currentReward = { Active = false }
local lastMagnetAt = tonumber(workspace:GetAttribute("DungeonMobCollectibleMagnetAt")) or 0
local lastOptionalClaimAt = tonumber(player:GetAttribute("DungeonOptionalLastClaimAt")) or 0
local optionalToastSerial = 0

local function statePresentation(raw, role)
	raw = tostring(raw or "Available")
	if raw == "Available" then
		return "DISPONÍVEL", "Aproxime-se e abra o baú.", role == "Core" and COLORS.Cyan or COLORS.Gold
	elseif raw == "Granting" then
		return "ABRINDO...", "Recompensa sendo concedida.", COLORS.CyanSoft
	elseif raw == "Saving" then
		return "SALVANDO...", "Aguarde a confirmação do servidor.", COLORS.Orange
	elseif raw == "RetryPending" then
		return "TENTANDO NOVAMENTE", "Houve uma falha temporária de concessão.", COLORS.Orange
	elseif raw == "Claimed" then
		return "COLETADO", "Sua recompensa deste baú foi recebida.", COLORS.Green
	end
	return string.upper(raw), "Aguardando atualização da recompensa.", COLORS.Muted
end

local function applyChest(record, data, role)
	local state, detail, color = statePresentation(data and data.State, role)
	record.State.Text = state
	record.State.TextColor3 = color
	record.Stroke.Color = color
	record.Card.BackgroundTransparency = state == "COLETADO" and 0.20 or 0.07
	if data and data.Error then
		detail = "Erro: " .. tostring(data.Error)
	end
	record.Detail.Text = detail
end

local function refreshCurrencyStatus()
	local pending = math.max(0, math.floor(tonumber(player:GetAttribute("PendingRoundCoins")) or 0))
	local rewardActive = currentReward.Active == true or workspace:GetAttribute("DungeonRewardIslandActive") == true

	if pending > 0 then
		if rewardActive then
			pendingSubtitle.Text = "PRONTO PARA CONFIRMAR"
			pendingSubtitle.TextColor3 = COLORS.GoldSoft
		else
			pendingSubtitle.Text = "SERÁ SALVO NA ROUND EXIT"
			pendingSubtitle.TextColor3 = COLORS.Purple
		end
	else
		pendingSubtitle.Text = "NENHUMA MOEDA PENDENTE"
		pendingSubtitle.TextColor3 = COLORS.Muted
	end

	confirmedSubtitle.Text = "SALDO PERMANENTE DA RUN"
	confirmedSubtitle.TextColor3 = COLORS.Green
end

local function refreshCollectibles()
	local active = math.max(0, math.floor(tonumber(workspace:GetAttribute("DungeonMobCollectibleActiveCount")) or 0))
	local magnetAt = tonumber(workspace:GetAttribute("DungeonMobCollectibleMagnetAt")) or 0
	local magnetCount = math.max(0, math.floor(tonumber(workspace:GetAttribute("DungeonMobCollectibleMagnetCount")) or 0))
	local magnetReason = tostring(workspace:GetAttribute("DungeonMobCollectibleMagnetReason") or "")
	local magnetRecent = magnetAt > 0 and serverTime() - magnetAt <= 4

	collectible.Visible = active > 0 or magnetRecent
	if magnetRecent and magnetCount > 0 then
		collectibleGlyph.Text = "»"
		collectibleGlyph.TextColor3 = COLORS.GoldSoft
		collectibleStroke.Color = COLORS.Gold
		collectibleTitle.Text = "COLETA AUTOMÁTICA"
		collectibleDetail.Text = string.format("%d essência(s) atraídas ao concluir o round", magnetCount)
	elseif active > 0 then
		collectibleGlyph.Text = "✦"
		collectibleGlyph.TextColor3 = COLORS.CyanSoft
		collectibleStroke.Color = COLORS.Cyan
		collectibleTitle.Text = string.format("%d ESSÊNCIA(S) NO CHÃO", active)
		collectibleDetail.Text = "Aproxime-se para coletar • o round recolhe as restantes"
	else
		collectible.Visible = false
	end

	if magnetAt > lastMagnetAt then
		lastMagnetAt = magnetAt
		player:SetAttribute("DungeonHUDLastMagnetShownAt", magnetAt)
		player:SetAttribute("DungeonHUDLastMagnetReason", magnetReason)
	end
end

local function refreshRewardPanel()
	local active = currentReward.Active == true or workspace:GetAttribute("DungeonRewardIslandActive") == true
	rewardPanel.Visible = active
	if not active then return end

	local round = tonumber(currentReward.RoundIndex) or tonumber(workspace:GetAttribute("DungeonRewardIslandRound")) or 1
	local autoResolveAt = tonumber(currentReward.AutoResolveAt)
		or tonumber(workspace:GetAttribute("DungeonRewardIslandAutoResolveAt"))
		or 0
	local remaining = math.max(0, math.ceil(autoResolveAt - serverTime()))
	rewardTitle.Text = string.format("ILHA DE RECOMPENSA — ROUND %d", round)
	if remaining > 0 then
		rewardTimer.Text = string.format("Abra seus baús • resolução automática em %ds", remaining)
	else
		rewardTimer.Text = "Resolução automática em andamento..."
	end

	applyChest(coreCard, currentReward.Core, "Core")
	applyChest(bonusCard, currentReward.Bonus, "Bonus")

	local pending = math.max(0, math.floor(tonumber(player:GetAttribute("PendingRoundCoins")) or 0))
	pendingValue.Text = string.format("%d PENDENTES", pending)

	local coinState = tostring(currentReward.CoinsState or "Pending")
	if coinState == "Committed" then
		coinsTitle.Text = "MOEDAS CONFIRMADAS"
		coinsTitle.TextColor3 = COLORS.Green
		coinsDetail.Text = "O saldo deste round já foi salvo."
		pendingValue.TextColor3 = COLORS.Green
		coinsStateStroke.Color = COLORS.Green
	elseif coinState == "Committing" then
		coinsTitle.Text = "CONFIRMANDO MOEDAS..."
		coinsTitle.TextColor3 = COLORS.GoldSoft
		coinsDetail.Text = "Aguarde a gravação do saldo."
		pendingValue.TextColor3 = COLORS.GoldSoft
		coinsStateStroke.Color = COLORS.Gold
	elseif coinState == "SavePending" then
		coinsTitle.Text = "SALVAMENTO PENDENTE"
		coinsTitle.TextColor3 = COLORS.Orange
		coinsDetail.Text = "O servidor tentará confirmar novamente."
		pendingValue.TextColor3 = COLORS.Orange
		coinsStateStroke.Color = COLORS.Orange
	else
		coinsTitle.Text = "MOEDAS DO ROUND"
		coinsTitle.TextColor3 = COLORS.Text
		coinsDetail.Text = "Abra os dois baús para confirmar o saldo."
		pendingValue.TextColor3 = COLORS.GoldSoft
		coinsStateStroke.Color = COLORS.Gold
	end
end

local function flashOptionalReward()
	local at = tonumber(player:GetAttribute("DungeonOptionalLastClaimAt")) or 0
	if at <= lastOptionalClaimAt then return end
	lastOptionalClaimAt = at
	optionalToastSerial += 1

	local result = tostring(player:GetAttribute("DungeonOptionalLastClaimResult") or "")
	local item = tostring(player:GetAttribute("DungeonOptionalLastRewardItem") or "")
	local coins = math.max(0, math.floor(tonumber(player:GetAttribute("DungeonOptionalLastRewardCoins")) or 0))

	-- Usa apenas atributos de diagnóstico; o HUD-01 já recebe InventoryEvent para atualizar os slots.
	if string.find(result, "Fallback", 1, true) then
		inventoryStatus.Text = string.format("INVENTÁRIO CHEIO • +%d MOEDAS", coins)
		inventoryStatus.TextColor3 = COLORS.Orange
	elseif item ~= "" and item ~= "nil" then
		inventoryStatus.Text = "NOVO ITEM: " .. string.upper(item)
		inventoryStatus.TextColor3 = COLORS.Green
	elseif coins > 0 then
		inventoryStatus.Text = string.format("+%d MOEDAS DA ROTA", coins)
		inventoryStatus.TextColor3 = COLORS.GoldSoft
	end

	local serial = optionalToastSerial
	task.delay(4, function()
		if optionalToastSerial == serial then
			inventoryStatus.Text = "CONSUMÍVEIS DA RUN"
			inventoryStatus.TextColor3 = COLORS.Muted
		end
	end)
end

local shared = ReplicatedStorage:FindFirstChild("Shared")
local remotes = shared and shared:FindFirstChild("Remotes")
local dungeonRemotes = remotes and remotes:FindFirstChild("Dungeon")
local rewardEvent = dungeonRemotes and dungeonRemotes:FindFirstChild("RewardState")

if rewardEvent and rewardEvent:IsA("RemoteEvent") then
	rewardEvent.OnClientEvent:Connect(function(payload)
		if type(payload) ~= "table" then return end
		currentReward = payload
		if payload.Action == "RewardRoundCommitted" then
			currentReward.Active = false
		elseif payload.Active == false then
			currentReward.Active = false
		end
		refreshRewardPanel()
		refreshCurrencyStatus()
	end)
end

for _, attribute in ipairs({
	"PendingRoundCoins",
	"DungeonOptionalLastClaimAt",
	"DungeonOptionalLastClaimResult",
	"DungeonOptionalLastRewardItem",
	"DungeonOptionalLastRewardCoins",
}) do
	player:GetAttributeChangedSignal(attribute):Connect(function()
		refreshCurrencyStatus()
		flashOptionalReward()
	end)
end

for _, attribute in ipairs({
	"DungeonMobCollectibleActiveCount",
	"DungeonMobCollectibleMagnetAt",
	"DungeonMobCollectibleMagnetCount",
	"DungeonMobCollectibleMagnetReason",
	"DungeonRewardIslandActive",
	"DungeonRewardIslandRound",
	"DungeonRewardIslandAutoResolveAt",
	"DungeonRewardCommitError",
}) do
	workspace:GetAttributeChangedSignal(attribute):Connect(function()
		refreshCollectibles()
		refreshRewardPanel()
	end)
end

local nextUpdate = 0
RunService.RenderStepped:Connect(function()
	local clock = os.clock()
	if clock < nextUpdate then return end
	nextUpdate = clock + UPDATE_INTERVAL
	refreshCurrencyStatus()
	refreshCollectibles()
	refreshRewardPanel()
	flashOptionalReward()
end)

gui:SetAttribute("RewardsInventoryVersion", VERSION)
player:SetAttribute("DungeonHUDRewardsReady", true)
player:SetAttribute("DungeonHUDRewardsVersion", VERSION)
workspace:SetAttribute("DungeonHUDRewardsReady", true)
workspace:SetAttribute("DungeonHUDRewardsPolicy", "PhysicalCollectiblesRewardIslandInventoryV1")

refreshCurrencyStatus()
refreshCollectibles()
refreshRewardPanel()
flashOptionalReward()
