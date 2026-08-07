local DungeonUITheme = {}

DungeonUITheme.Version = 1
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
	viewport = typeof(viewport) == "Vector2" and viewport or Vector2.new(1280, 720)
	local shortest = math.min(viewport.X, viewport.Y)
	local phone = shortest < 600
	local compact = viewport.X < 1080 or shortest < 720
	local scale = math.clamp(math.min(viewport.X / 1920, viewport.Y / 1080), phone and 0.58 or 0.70, 1)
	return {
		Viewport = viewport,
		Phone = phone,
		Compact = compact,
		Scale = scale,
		Margin = compact and DungeonUITheme.Layout.CompactMargin or DungeonUITheme.Layout.DesktopMargin,
	}
end

return table.freeze(DungeonUITheme)
