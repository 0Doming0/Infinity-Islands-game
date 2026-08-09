local GuiService = game:GetService("GuiService")
local UserInputService = game:GetService("UserInputService")

local DungeonUITheme = {}

DungeonUITheme.Version = 2
DungeonUITheme.StyleId = "CrystalCelestial"
DungeonUITheme.StyleName = "Cristal Celestial"

DungeonUITheme.Colors = table.freeze({
    Glass = Color3.fromRGB(12, 35, 65),
    GlassRaised = Color3.fromRGB(20, 55, 91),
    GlassDeep = Color3.fromRGB(5, 18, 38),
    GlassHover = Color3.fromRGB(31, 78, 119),
    Gold = Color3.fromRGB(247, 209, 105),
    GoldSoft = Color3.fromRGB(255, 235, 167),
    GoldDark = Color3.fromRGB(135, 96, 34),
    Cyan = Color3.fromRGB(91, 222, 255),
    CyanSoft = Color3.fromRGB(184, 244, 255),
    Crystal = Color3.fromRGB(92, 171, 255),
    Purple = Color3.fromRGB(174, 111, 255),
    Text = Color3.fromRGB(245, 249, 255),
    Muted = Color3.fromRGB(183, 205, 229),
    Dim = Color3.fromRGB(118, 145, 177),
    Health = Color3.fromRGB(239, 58, 73),
    HealthLag = Color3.fromRGB(255, 148, 105),
    Stamina = Color3.fromRGB(33, 211, 247),
    Success = Color3.fromRGB(91, 226, 153),
    Warning = Color3.fromRGB(255, 193, 76),
    Danger = Color3.fromRGB(255, 92, 105),
    Disabled = Color3.fromRGB(75, 91, 113),
    Black = Color3.fromRGB(4, 9, 19),
})

DungeonUITheme.Layout = table.freeze({
    DesktopReference = Vector2.new(1920, 1080),
    DesktopMargin = 22,
    CompactMargin = 10,
    TopGap = 12,
    BottomGap = 14,
    PanelRadius = 16,
    SmallRadius = 10,
    GoldStrokeThickness = 1.35,
    PanelTransparency = 0.12,
})

function DungeonUITheme.GetResponsive(viewport)
    viewport = typeof(viewport) == "Vector2"
        and viewport
        or Vector2.new(1280, 720)

    local shortest = math.max(1, math.min(viewport.X, viewport.Y))
    local touch = UserInputService.TouchEnabled
    local portrait = viewport.Y > viewport.X * 1.08

    local rawScale
    if touch then
        rawScale = (shortest / 720) ^ 0.85
    else
        rawScale = (shortest / 900) ^ 0.90
    end

    local scale = touch
        and math.clamp(rawScale, 0.52, 0.92)
        or math.clamp(rawScale, 0.72, 1.20)

    if GuiService.ViewportDisplaySize == Enum.DisplaySize.Large then
        scale = math.min(1.28, scale * 1.05)
    end

    local phone = touch and shortest < 600
    local compact = portrait
        or viewport.X < 1100
        or viewport.Y < 680

    local margin = math.clamp(
        math.floor(shortest * 0.018 + 0.5),
        8,
        26
    )

    return {
        Viewport = viewport,
        Phone = phone,
        Compact = compact,
        Portrait = portrait,
        Touch = touch,
        Scale = scale,
        Margin = margin,
        ShortestSide = shortest,
        PreferredTextSize = GuiService.PreferredTextSize,
    }
end

return table.freeze(DungeonUITheme)
