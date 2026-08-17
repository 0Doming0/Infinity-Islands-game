-- CompanionInventoryTypography.client.luau
-- Aplica a tipografia do inventario sem alterar tamanho, posicao, cor ou imagens do GUI.

local Players = game:GetService("Players")

local player = Players.LocalPlayer

local FONTS = {
	Title = Enum.Font.FredokaOne,
	Name = Enum.Font.GothamBlack,
	Level = Enum.Font.GothamBold,
	Progress = Enum.Font.GothamBold,
	StatLabel = Enum.Font.GothamBold,
	StatValue = Enum.Font.GothamBlack,
	Button = Enum.Font.GothamBlack,
	Empty = Enum.Font.GothamBold,
}

local function isTextObject(instance: Instance): boolean
	return instance:IsA("TextLabel") or instance:IsA("TextButton") or instance:IsA("TextBox")
end

local function hasAncestorNamed(instance: Instance, targetName: string): boolean
	local current = instance.Parent
	while current do
		if current.Name == targetName then
			return true
		end
		current = current.Parent
	end
	return false
end

local function getFontFor(instance: Instance): Enum.Font?
	local name = string.lower(instance.Name)

	-- Titulo principal: "COMPANHEIROS".
	if name == "title"
		or name == "titletext"
		or name == "inventorytitle"
		or name == "companioninventorytitle"
		or (name == "textlabel" and (hasAncestorNamed(instance, "TitleBanner") or instance.Parent and instance.Parent.Name == "MainFrame"))
	then
		return FONTS.Title
	end

	-- Nome do companheiro selecionado e nomes nos cards da lista.
	if name == "companionname" or name == "cardcompanionname" or name == "selectedcompanionname" then
		return FONTS.Name
	end

	-- Nivel do card e nivel do companheiro selecionado.
	if name == "leveltext"
		or name == "cardleveltext"
		or name == "selectedleveltext"
		or hasAncestorNamed(instance, "CardLevelPanel")
	then
		return FONTS.Level
	end

	-- Textos de XP/progresso.
	if name == "xp"
		or name == "levelxp"
		or name == "xptext"
		or name == "xpvalue"
		or name == "xpamount"
		or name == "progressvalue"
	then
		return FONTS.Progress
	end

	-- Textos da faixa de atributos (Vida, Ataque, Defesa e Velocidade).
	if name == "statlabel" or name == "attributelabel" then
		return FONTS.StatLabel
	end
	if name == "statvalue" or name == "attributevalue" then
		return FONTS.StatValue
	end

	-- Texto que voce vai colocar por cima dos botoes sem texto gerados.
	if name == "equiptext"
		or name == "unequiptext"
		or name == "equipbuttontext"
		or name == "unequipbuttontext"
		or name == "equipbutton"
		or name == "unequipbutton"
	then
		return FONTS.Button
	end

	if name == "emptytext" then
		return FONTS.Empty
	end

	return nil
end

local function applyFont(instance: Instance)
	if not isTextObject(instance) then
		return
	end

	local font = getFontFor(instance)
	if font then
		(instance :: TextLabel | TextButton | TextBox).Font = font
	end
end

local function bindInventoryGui(inventoryGui: Instance)
	for _, descendant in inventoryGui:GetDescendants() do
		applyFont(descendant)
	end

	inventoryGui.DescendantAdded:Connect(applyFont)
end

local function tryBind(instance: Instance)
	if instance.Name == "CompanionInventoryGui" and instance:IsA("ScreenGui") then
		bindInventoryGui(instance)
	end
end

local playerGui = player:WaitForChild("PlayerGui")

for _, child in playerGui:GetChildren() do
	tryBind(child)
end

playerGui.ChildAdded:Connect(tryBind)
