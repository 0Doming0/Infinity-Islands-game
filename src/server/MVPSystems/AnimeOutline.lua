-- ServerScriptService/MVPSystems/AnimeOutline.lua

local AnimeOutline = {}

export type OutlineOptions = {
	OutlineColor: Color3?,
	OutlineTransparency: number?,
	FillColor: Color3?,
	FillTransparency: number?,
	DepthMode: Enum.HighlightDepthMode?,
}

local HIGHLIGHT_NAME = "AnimeOutline"

function AnimeOutline.Apply(
	model: Model?,
	options: OutlineOptions?
): Highlight?
	if model == nil then
		warn("[AnimeOutline] Apply chamado com model nil.")
		return nil
	end

	if not model:IsA("Model") then
		warn(
			"[AnimeOutline] O objeto recebido não é um Model:",
			model:GetFullName(),
			"Classe:",
			model.ClassName
		)
		return nil
	end

	options = options or {}

	local existing = model:FindFirstChild(HIGHLIGHT_NAME)

	if existing and existing:IsA("Highlight") then
		existing.Adornee = model

		existing.FillColor =
			options.FillColor
			or existing.FillColor

		existing.FillTransparency =
			options.FillTransparency
			or existing.FillTransparency

		existing.OutlineColor =
			options.OutlineColor
			or existing.OutlineColor

		existing.OutlineTransparency =
			options.OutlineTransparency
			or existing.OutlineTransparency

		existing.DepthMode =
			options.DepthMode
			or existing.DepthMode

		return existing
	end

	if existing then
		existing:Destroy()
	end

	local highlight = Instance.new("Highlight")
	highlight.Name = HIGHLIGHT_NAME
	highlight.Adornee = model

	highlight.FillColor =
		options.FillColor
		or Color3.fromRGB(255, 255, 255)

	highlight.FillTransparency =
		options.FillTransparency ~= nil
			and options.FillTransparency
			or 1

	highlight.OutlineColor =
		options.OutlineColor
		or Color3.fromRGB(30, 27, 40)

	highlight.OutlineTransparency =
		options.OutlineTransparency ~= nil
			and options.OutlineTransparency
			or 0.15

	highlight.DepthMode =
		options.DepthMode
		or Enum.HighlightDepthMode.Occluded

	highlight.Parent = model

	return highlight
end

function AnimeOutline.Remove(model: Model?): boolean
	if model == nil then
		return false
	end

	if not model:IsA("Model") then
		return false
	end

	local highlight = model:FindFirstChild(HIGHLIGHT_NAME)

	if highlight then
		highlight:Destroy()
		return true
	end

	return false
end

return AnimeOutline