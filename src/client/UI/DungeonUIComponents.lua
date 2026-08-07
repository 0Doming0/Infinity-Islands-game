local Theme = require(script.Parent.DungeonUITheme)
local Colors = Theme.Colors

local DungeonUIComponents = {}

function DungeonUIComponents.Corner(parent, radius)
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, radius or Theme.Layout.PanelRadius)
	corner.Parent = parent
	return corner
end

function DungeonUIComponents.Stroke(parent, color, transparency, thickness)
	local stroke = Instance.new("UIStroke")
	stroke.Color = color or Colors.Gold
	stroke.Transparency = transparency == nil and 0.18 or transparency
	stroke.Thickness = thickness or Theme.Layout.GoldStrokeThickness
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	stroke.Parent = parent
	return stroke
end

function DungeonUIComponents.Gradient(parent, topColor, bottomColor, rotation)
	local gradient = Instance.new("UIGradient")
	gradient.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, topColor or Colors.GlassRaised),
		ColorSequenceKeypoint.new(1, bottomColor or Colors.GlassDeep),
	})
	gradient.Rotation = rotation or 100
	gradient.Parent = parent
	return gradient
end

local function cornerAccent(parent, name, xScale, yScale, xAnchor, yAnchor, xDirection, yDirection)
	local holder = Instance.new("Frame")
	holder.Name = name
	holder.AnchorPoint = Vector2.new(xAnchor, yAnchor)
	holder.Position = UDim2.fromScale(xScale, yScale)
	holder.Size = UDim2.fromOffset(22, 22)
	holder.BackgroundTransparency = 1
	holder.ZIndex = parent.ZIndex + 2
	holder.Parent = parent

	local horizontal = Instance.new("Frame")
	horizontal.AnchorPoint = Vector2.new(xAnchor, yAnchor)
	horizontal.Position = UDim2.fromScale(xAnchor, yAnchor)
	horizontal.Size = UDim2.fromOffset(18, 2)
	horizontal.BackgroundColor3 = Colors.GoldSoft
	horizontal.BorderSizePixel = 0
	horizontal.ZIndex = holder.ZIndex
	horizontal.Parent = holder

	local vertical = Instance.new("Frame")
	vertical.AnchorPoint = Vector2.new(xAnchor, yAnchor)
	vertical.Position = UDim2.fromScale(xAnchor, yAnchor)
	vertical.Size = UDim2.fromOffset(2, 18)
	vertical.BackgroundColor3 = Colors.GoldSoft
	vertical.BorderSizePixel = 0
	vertical.ZIndex = holder.ZIndex
	vertical.Parent = holder

	if xDirection < 0 then
		horizontal.Position = UDim2.new(1, 0, yAnchor, 0)
	end
	if yDirection < 0 then
		vertical.Position = UDim2.new(xAnchor, 0, 1, 0)
	end
	return holder
end

function DungeonUIComponents.AddCrystalCorners(parent)
	cornerAccent(parent, "CrystalCornerTopLeft", 0, 0, 0, 0, 1, 1)
	cornerAccent(parent, "CrystalCornerTopRight", 1, 0, 1, 0, -1, 1)
	cornerAccent(parent, "CrystalCornerBottomLeft", 0, 1, 0, 1, 1, -1)
	cornerAccent(parent, "CrystalCornerBottomRight", 1, 1, 1, 1, -1, -1)
end

function DungeonUIComponents.GlassPanel(parent, name, position, size, options)
	options = type(options) == "table" and options or {}
	local frame = Instance.new("Frame")
	frame.Name = name
	frame.Position = position or UDim2.new()
	frame.Size = size or UDim2.fromOffset(200, 100)
	frame.AnchorPoint = options.AnchorPoint or Vector2.zero
	frame.BackgroundColor3 = options.BackgroundColor or Colors.Glass
	frame.BackgroundTransparency = options.Transparency == nil and Theme.Layout.PanelTransparency or options.Transparency
	frame.BorderSizePixel = 0
	frame.ClipsDescendants = options.ClipsDescendants == true
	frame.ZIndex = options.ZIndex or 1
	frame.Visible = options.Visible ~= false
	frame.Parent = parent
	DungeonUIComponents.Corner(frame, options.Radius or Theme.Layout.PanelRadius)
	DungeonUIComponents.Stroke(frame, options.StrokeColor or Colors.Gold, options.StrokeTransparency, options.StrokeThickness)
	DungeonUIComponents.Gradient(frame, options.TopColor, options.BottomColor, options.GradientRotation)
	if options.CrystalCorners ~= false then
		DungeonUIComponents.AddCrystalCorners(frame)
	end
	return frame
end

function DungeonUIComponents.Label(parent, name, text, position, size, options)
	options = type(options) == "table" and options or {}
	local label = Instance.new("TextLabel")
	label.Name = name
	label.Position = position or UDim2.new()
	label.Size = size or UDim2.fromOffset(100, 30)
	label.AnchorPoint = options.AnchorPoint or Vector2.zero
	label.BackgroundTransparency = 1
	label.Text = tostring(text or "")
	label.TextColor3 = options.Color or Colors.Text
	label.TextTransparency = options.Transparency or 0
	label.Font = options.Font or Enum.Font.GothamMedium
	label.TextSize = options.TextSize or 14
	label.TextScaled = options.TextScaled == true
	label.TextWrapped = options.TextWrapped == true
	label.TextXAlignment = options.XAlignment or Enum.TextXAlignment.Left
	label.TextYAlignment = options.YAlignment or Enum.TextYAlignment.Center
	label.TextTruncate = options.Truncate or Enum.TextTruncate.AtEnd
	label.ZIndex = options.ZIndex or parent.ZIndex + 1
	label.Parent = parent
	if options.TextScaled then
		local constraint = Instance.new("UITextSizeConstraint")
		constraint.MinTextSize = options.MinTextSize or 9
		constraint.MaxTextSize = options.MaxTextSize or options.TextSize or 18
		constraint.Parent = label
	end
	return label
end

function DungeonUIComponents.Bar(parent, name, position, size, fillColor, options)
	options = type(options) == "table" and options or {}
	local back = Instance.new("Frame")
	back.Name = name
	back.Position = position
	back.Size = size
	back.BackgroundColor3 = options.BackColor or Colors.Black
	back.BackgroundTransparency = options.BackTransparency or 0.22
	back.BorderSizePixel = 0
	back.ClipsDescendants = true
	back.ZIndex = options.ZIndex or parent.ZIndex + 1
	back.Parent = parent
	DungeonUIComponents.Corner(back, options.Radius or 6)
	DungeonUIComponents.Stroke(back, options.StrokeColor or Colors.GoldDark, options.StrokeTransparency or 0.35, options.StrokeThickness or 1)

	local lag
	if options.LagColor then
		lag = Instance.new("Frame")
		lag.Name = "LagFill"
		lag.Size = UDim2.fromScale(1, 1)
		lag.BackgroundColor3 = options.LagColor
		lag.BorderSizePixel = 0
		lag.ZIndex = back.ZIndex + 1
		lag.Parent = back
		DungeonUIComponents.Corner(lag, options.Radius or 6)
	end

	local fill = Instance.new("Frame")
	fill.Name = "Fill"
	fill.Size = UDim2.fromScale(1, 1)
	fill.BackgroundColor3 = fillColor or Colors.Cyan
	fill.BorderSizePixel = 0
	fill.ZIndex = back.ZIndex + 2
	fill.Parent = back
	DungeonUIComponents.Corner(fill, options.Radius or 6)
	local fillGradient = Instance.new("UIGradient")
	fillGradient.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, (fillColor or Colors.Cyan):Lerp(Color3.new(1, 1, 1), 0.25)),
		ColorSequenceKeypoint.new(1, fillColor or Colors.Cyan),
	})
	fillGradient.Rotation = 90
	fillGradient.Parent = fill
	return {
		Back = back,
		Lag = lag,
		Fill = fill,
	}
end

function DungeonUIComponents.Diamond(parent, name, position, size, color, options)
	options = type(options) == "table" and options or {}
	local holder = Instance.new("Frame")
	holder.Name = name
	holder.Position = position
	holder.Size = size
	holder.AnchorPoint = options.AnchorPoint or Vector2.zero
	holder.BackgroundTransparency = 1
	holder.ZIndex = options.ZIndex or parent.ZIndex + 1
	holder.Parent = parent

	local outer = Instance.new("Frame")
	outer.AnchorPoint = Vector2.new(0.5, 0.5)
	outer.Position = UDim2.fromScale(0.5, 0.5)
	outer.Size = UDim2.fromScale(0.74, 0.74)
	outer.Rotation = 45
	outer.BackgroundColor3 = options.OuterColor or Colors.GlassDeep
	outer.BorderSizePixel = 0
	outer.ZIndex = holder.ZIndex
	outer.Parent = holder
	DungeonUIComponents.Corner(outer, options.Radius or 5)
	DungeonUIComponents.Stroke(outer, options.StrokeColor or Colors.GoldSoft, options.StrokeTransparency or 0.05, options.StrokeThickness or 2)

	local inner = Instance.new("Frame")
	inner.AnchorPoint = Vector2.new(0.5, 0.5)
	inner.Position = UDim2.fromScale(0.5, 0.5)
	inner.Size = UDim2.fromScale(0.48, 0.48)
	inner.BackgroundColor3 = color or Colors.Cyan
	inner.BorderSizePixel = 0
	inner.ZIndex = outer.ZIndex + 1
	inner.Parent = outer
	DungeonUIComponents.Corner(inner, 3)
	DungeonUIComponents.Gradient(inner, Colors.CyanSoft, color or Colors.Cyan, 135)
	return holder
end

function DungeonUIComponents.Scale(parent, name)
	local scale = Instance.new("UIScale")
	scale.Name = name or "ResponsiveScale"
	scale.Parent = parent
	return scale
end

return table.freeze(DungeonUIComponents)
