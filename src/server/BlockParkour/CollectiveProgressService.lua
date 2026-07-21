-- Calcula o ritmo coletivo sem permitir que um unico jogador controle a agua.

local Players = game:GetService("Players")

local Config = require(script.Parent.Config_SkyDungeon_V10)

local CollectiveProgressService = {}

local function eligibleHeight(player)
	if player:GetAttribute("TutorialActive") == true
		or player:GetAttribute("TutorialWaterProtection") == true
		or player:GetAttribute("ExcludeFromWaterPacing") == true
	then
		return nil
	end
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not humanoid or humanoid.Health <= 0 or not root then
		return nil
	end
	return root.Position.Y
end

local function percentile(sorted, fraction)
	if #sorted == 0 then
		return nil
	end
	local index = math.clamp(math.ceil(#sorted * fraction), 1, #sorted)
	return sorted[index]
end

function CollectiveProgressService.GetSnapshot()
	local heights = {}
	for _, player in ipairs(Players:GetPlayers()) do
		local height = eligibleHeight(player)
		if height then
			table.insert(heights, height)
		end
	end
	table.sort(heights)
	if #heights == 0 then
		return {
			Count = 0,
			MeanY = nil,
			MedianY = nil,
			LowerGroupY = nil,
			MinimumY = nil,
			MaximumY = nil,
			TrimmedCount = 0,
		}
	end

	local trim = #heights >= 10 and math.floor(#heights * Config.COLLECTIVE_TRIM_FRACTION) or 0
	local first = 1 + trim
	local last = #heights - trim
	if first > last then
		first, last = 1, #heights
	end
	local total = 0
	for index = first, last do
		total += heights[index]
	end

	return {
		Count = #heights,
		MeanY = total / (last - first + 1),
		MedianY = percentile(heights, 0.5),
		LowerGroupY = percentile(heights, Config.COLLECTIVE_LOWER_PERCENTILE),
		MinimumY = heights[1],
		MaximumY = heights[#heights],
		TrimmedCount = last - first + 1,
	}
end

return table.freeze(CollectiveProgressService)
