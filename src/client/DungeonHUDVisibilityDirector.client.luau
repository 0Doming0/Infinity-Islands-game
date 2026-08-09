--[[
    Infinity Islands — Rebuild Part 25
    Context-aware HUD visibility director.

    Principle:
    "Show information when it changes the player's next decision."

    Managed Unified HUD panels:
    - Currencies: rewards / recent currency changes only;
    - Party: only when party information matters;
    - Vitals: damage, stamina use, boss or downed;
    - Hotbar: only when extra usable slots/inventory matter.

    Objective presentation, state banners, notifications and modals retain
    their own contextual logic.

    Show/hide uses transparency animation and never changes gameplay state.
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local VERSION = "ContextVisibilityV8"
local FADE_IN = 0.18
local FADE_OUT = 0.16
local CURRENCY_HOLD = 3.5
local VITALS_HOLD = 3.0

local records = setmetatable({}, { __mode = "k" })
local currencyUntil = 0
local vitalsUntil = 0
local previousCoins = tonumber(player:GetAttribute("Coins")) or 0
local previousPending = tonumber(player:GetAttribute("PendingRoundCoins")) or 0

local function transparencyProperties(instance)
    local props = {}

    if instance:IsA("GuiObject") then
        props.BackgroundTransparency = instance.BackgroundTransparency
    end
    if instance:IsA("TextLabel") or instance:IsA("TextButton") or instance:IsA("TextBox") then
        props.TextTransparency = instance.TextTransparency
        props.TextStrokeTransparency = instance.TextStrokeTransparency
    end
    if instance:IsA("ImageLabel") or instance:IsA("ImageButton") then
        props.ImageTransparency = instance.ImageTransparency
    end
    if instance:IsA("UIStroke") then
        props.Transparency = instance.Transparency
    end

    return props
end

local function ensureSnapshot(panel)
    local record = records[panel]
    if not record then
        record = {
            Desired = panel.Visible,
            Serial = 0,
            Original = setmetatable({}, { __mode = "k" }),
        }
        records[panel] = record
    end

    local function capture(instance)
        if not record.Original[instance] then
            local props = transparencyProperties(instance)
            if next(props) then
                record.Original[instance] = props
            end
        end
    end

    capture(panel)
    for _, descendant in ipairs(panel:GetDescendants()) do
        capture(descendant)
    end

    return record
end

local function tweenProperties(instance, properties, duration)
    if not instance.Parent or not next(properties) then
        return
    end
    pcall(function()
        TweenService:Create(
            instance,
            TweenInfo.new(
                duration,
                Enum.EasingStyle.Quad,
                duration == FADE_IN
                    and Enum.EasingDirection.Out
                    or Enum.EasingDirection.In
            ),
            properties
        ):Play()
    end)
end

local function hiddenProperties(original)
    local result = {}
    for property in pairs(original) do
        result[property] = 1
    end
    return result
end

local function setPanel(panel, shouldShow)
    if not panel or not panel:IsA("GuiObject") then
        return
    end

    local record = ensureSnapshot(panel)
    if record.Desired == shouldShow
        and panel.Visible == shouldShow
    then
        return
    end

    record.Desired = shouldShow
    record.Serial += 1
    local serial = record.Serial
    panel:SetAttribute("HUDDirectorDesiredVisible", shouldShow)

    if shouldShow then
        panel.Visible = true
        for instance, original in pairs(record.Original) do
            if instance.Parent then
                tweenProperties(instance, original, FADE_IN)
            end
        end
    else
        for instance, original in pairs(record.Original) do
            if instance.Parent then
                tweenProperties(instance, hiddenProperties(original), FADE_OUT)
            end
        end
        task.delay(FADE_OUT + 0.03, function()
            if record.Serial == serial and not record.Desired and panel.Parent then
                panel.Visible = false
            end
        end)
    end
end

local function characterVitals()
    local character = player.Character
    local humanoid = character and character:FindFirstChildOfClass("Humanoid")
    if not character or not humanoid then
        return 1, 1, false
    end

    local healthRatio = humanoid.MaxHealth > 0
        and math.clamp(humanoid.Health / humanoid.MaxHealth, 0, 1)
        or 1

    local stamina = tonumber(character:GetAttribute("SprintStamina")) or 100
    local staminaMax = math.max(
        1,
        tonumber(character:GetAttribute("SprintStaminaMax")) or 100
    )
    local staminaRatio = math.clamp(stamina / staminaMax, 0, 1)
    local sprinting = character:GetAttribute("Sprinting") == true

    return healthRatio, staminaRatio, sprinting
end

local function hotbarHasExtraUtility(hotbar)
    if not hotbar then
        return false
    end
    local slots = hotbar:FindFirstChild("Slots")
    if not slots then
        return false
    end

    for index = 2, 5 do
        local slot = slots:FindFirstChild("Slot" .. tostring(index))
        if slot then
            local glyph = slot:FindFirstChild("Glyph")
            local amount = slot:FindFirstChild("Amount")
            local glyphText = glyph and glyph:IsA("TextLabel") and glyph.Text or ""
            local amountText = amount and amount:IsA("TextLabel") and amount.Text or ""

            -- Slot 5 is the Inventory button. It becomes relevant when inventory
            -- actually contains something, not merely because the button exists.
            if index <= 4 and (glyphText ~= "" or amountText ~= "") then
                return true
            end
        end
    end

    local drawer = hotbar.Parent and hotbar.Parent:FindFirstChild("InventoryDrawer")
    return drawer and drawer.Visible == true or false
end

local function update()
    local unified = playerGui:FindFirstChild("DungeonUnifiedHUD")
    local root = unified and unified:FindFirstChild("Root")
    if not root then
        return
    end

    local presentation = tostring(
        player:GetAttribute("DungeonEntryPresentationState") or "Loading"
    )
    local gameplayVisible = presentation == "Playing"

    local state = tostring(
        Workspace:GetAttribute("DungeonProgressionState") or ""
    )
    local phaseState = tostring(
        Workspace:GetAttribute("DungeonPhaseState") or ""
    )
    local reward =
        state == "RewardPending"
        or state == "RewardCommitted"
        or Workspace:GetAttribute("DungeonRewardIslandActive") == true

    local partySize = math.max(
        1,
        math.floor(tonumber(Workspace:GetAttribute("DungeonPartySize")) or 1)
    )
    local lifeState = tostring(player:GetAttribute("DungeonLifeState") or "Active")
    local healthRatio, staminaRatio, sprinting = characterVitals()

    if healthRatio < 0.995 or staminaRatio < 0.92 or sprinting then
        vitalsUntil = os.clock() + VITALS_HOLD
    end

    local guideStage = tostring(
        player:GetAttribute("GuidedIntroPresentationStage") or ""
    )
    local beginnerHealthPresentation =
        player:GetAttribute("GuidedIntroActive") == true
        and guideStage ~= "Complete"

    -- During the beginner presentation, health has its own dedicated card.
    -- Keeping the legacy Vitals panel hidden avoids revealing STAMINA and BUFFS
    -- before those systems have earned their own introduction.
    local showVitals = gameplayVisible
        and not beginnerHealthPresentation
        and (
            healthRatio < 0.995
            or staminaRatio < 0.92
            or sprinting
            or os.clock() < vitalsUntil
            or lifeState == "Downed"
            or phaseState == "BossActive"
            or tostring(Workspace:GetAttribute("DungeonBossState") or "") == "Active"
        )

    local showParty = gameplayVisible and (
        partySize > 1
        or lifeState == "Downed"
        or Workspace:GetAttribute("DungeonWipePending") == true
    )

    local beginnerGuideActive =
        player:GetAttribute("GuidedIntroActive") == true
        and guideStage ~= "Complete"

    -- The beginner flow owns a tiny single-concept currency chip. The full
    -- Confirmed/Pending panel would introduce two economic states at once, so
    -- it stays hidden for the entire Guide even after "MOEDAS" is learned.
    local beginnerCurrencyPending =
        beginnerGuideActive
        and player:GetAttribute("GuidedIntroCurrencyIntroduced") ~= true

    local showCurrencies = gameplayVisible
        and not beginnerGuideActive
        and (
            reward
            or os.clock() < currencyUntil
        )

    local hotbar = root:FindFirstChild("Hotbar")
    local showHotbar = gameplayVisible
        and hotbarHasExtraUtility(hotbar)

    setPanel(root:FindFirstChild("Currencies"), showCurrencies)
    setPanel(root:FindFirstChild("Party"), showParty)
    setPanel(root:FindFirstChild("Vitals"), showVitals)
    setPanel(hotbar, showHotbar)

    -- Legacy reward/currency toasts would compete with the staged tutorial
    -- ("ILHA DE RECOMPENSA", "MOEDAS CONFIRMADAS", "ESSÊNCIA COLETADA").
    -- During the Guide the dedicated presentation components own those moments.
    if beginnerGuideActive then
        setPanel(root:FindFirstChild("Notification"), false)
    end

    player:SetAttribute("DungeonHUDDirectorReady", true)
    player:SetAttribute("DungeonHUDDirectorVersion", VERSION)
    player:SetAttribute("DungeonHUDCurrenciesVisible", showCurrencies)
    player:SetAttribute("DungeonHUDBeginnerCurrencyPending", beginnerCurrencyPending)
    player:SetAttribute("DungeonHUDBeginnerGuideActive", beginnerGuideActive)
    player:SetAttribute("DungeonHUDLegacyNotificationsSuppressed", beginnerGuideActive)

    local tutorialFocusOwner = "None"
    if player:GetAttribute("DungeonFirstRewardPresentationActive") == true then
        tutorialFocusOwner = "RewardReveal"
    elseif player:GetAttribute("DungeonBeginnerCurrencyPresentationActive") == true then
        tutorialFocusOwner = "Currency"
    elseif player:GetAttribute("DungeonBeginnerCompanionPresentationActive") == true then
        tutorialFocusOwner = "Companion"
    elseif player:GetAttribute("DungeonBeginnerUpgradePresentationActive") == true then
        tutorialFocusOwner = "Upgrade"
    elseif player:GetAttribute("DungeonSkyAmbushPresentationActive") == true then
        tutorialFocusOwner = "SkyAmbush"
    elseif player:GetAttribute("DungeonRangedThreatPresentationActive") == true then
        tutorialFocusOwner = "RangedThreat"
    end
    player:SetAttribute("DungeonHUDTutorialFocusOwner", tutorialFocusOwner)
    player:SetAttribute("DungeonHUDPartyVisible", showParty)
    player:SetAttribute("DungeonHUDVitalsVisible", showVitals)
    player:SetAttribute("DungeonHUDBeginnerHealthMode", beginnerHealthPresentation)
    player:SetAttribute("DungeonHUDHotbarVisible", showHotbar)
end

local function currencyChanged()
    local coins = tonumber(player:GetAttribute("Coins")) or 0
    local pending = tonumber(player:GetAttribute("PendingRoundCoins")) or 0

    if coins ~= previousCoins or pending ~= previousPending then
        previousCoins = coins
        previousPending = pending
        currencyUntil = os.clock() + CURRENCY_HOLD
    end
end

player:GetAttributeChangedSignal("Coins"):Connect(currencyChanged)
player:GetAttributeChangedSignal("PendingRoundCoins"):Connect(currencyChanged)

player.CharacterAdded:Connect(function(character)
    local humanoid = character:WaitForChild("Humanoid", 8)
    if humanoid then
        humanoid.HealthChanged:Connect(function()
            vitalsUntil = os.clock() + VITALS_HOLD
        end)
    end
end)

if player.Character then
    local humanoid = player.Character:FindFirstChildOfClass("Humanoid")
    if humanoid then
        humanoid.HealthChanged:Connect(function()
            vitalsUntil = os.clock() + VITALS_HOLD
        end)
    end
end

local elapsed = 0
RunService.Heartbeat:Connect(function(dt)
    elapsed += dt
    if elapsed >= 0.10 then
        elapsed = 0
        currencyChanged()
        update()
    end
end)

update()
