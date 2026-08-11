local Players = game:GetService("Players")
local SoundService = game:GetService("SoundService")

local player = Players.LocalPlayer
local collectSound = Instance.new("Sound")
collectSound.Name = "XPCollectSatisfying"
collectSound.SoundId = "rbxasset://sounds/electronicpingshort.wav"
collectSound.Volume = 0.48
collectSound.PlaybackSpeed = 1.18
collectSound.Parent = SoundService

local lastSerial = player:GetAttribute("XPCollectibleCollectedSerial")

local function playCollectSound()
	local xpValue = tonumber(player:GetAttribute("LastXPCollectibleValue")) or 1
	collectSound.PlaybackSpeed = math.clamp(
		1.12 + math.min(xpValue, 40) * 0.004,
		1.12,
		1.28
	)
	SoundService:PlayLocalSound(collectSound)
end

player:GetAttributeChangedSignal("XPCollectibleCollectedSerial"):Connect(function()
	local serial = player:GetAttribute("XPCollectibleCollectedSerial")
	if serial == nil or serial == lastSerial then
		return
	end

	lastSerial = serial
	playCollectSound()
end)
