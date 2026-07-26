local Debris = game:GetService("Debris")
local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")

local PlayerDamageService = require(
	script.Parent.Parent.Parent.MVPSystems:WaitForChild("PlayerDamageService")
)
local MonsterAnimationLoader = require(script.Parent.Parent.MonsterAnimationLoader)

local GroundSlam = {}

function GroundSlam.CanUse(context)
	local radius = math.max(1, tonumber(context.Model:GetAttribute("GroundSlamRadius")) or 12)
	return context.Distance <= radius
end

function GroundSlam.Use(context)
	local model = context.Model
	local root = context.Root
	local humanoid = context.Humanoid
	local radius = math.max(1, tonumber(model:GetAttribute("GroundSlamRadius")) or 12)
	local windup = math.max(0.2, tonumber(model:GetAttribute("GroundSlamWindup")) or 1)
	local damage = math.max(0, tonumber(model:GetAttribute("GroundSlamDamage")) or context.Config.AttackDamage * 1.5)
	local interruptSerial = model:GetAttribute("CombatInterruptSerial") or 0

	humanoid:MoveTo(root.Position)
	MonsterAnimationLoader.Play(model, humanoid, "GroundSlam", 0.08)
	model:SetAttribute("MonsterState", "Ability")
	model:SetAttribute("ActiveAbility", "GroundSlam")

	local warning = Instance.new("Part")
	warning.Name = "GroundSlamWarning"
	warning.Shape = Enum.PartType.Cylinder
	warning.Size = Vector3.new(0.12, 1, 1)
	warning.CFrame = CFrame.new(root.Position - Vector3.new(0, math.max(1, root.Size.Y / 2), 0))
		* CFrame.Angles(0, 0, math.rad(90))
	warning.Anchored = true
	warning.CanCollide = false
	warning.CanTouch = false
	warning.CanQuery = false
	warning.Material = Enum.Material.Neon
	warning.Color = Color3.fromRGB(255, 93, 43)
	warning.Transparency = 0.52
	warning.Parent = workspace
	TweenService:Create(
		warning,
		TweenInfo.new(windup, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{ Size = Vector3.new(0.12, radius * 2, radius * 2), Transparency = 0.18 }
	):Play()
	Debris:AddItem(warning, windup + 0.25)

	task.delay(windup, function()
		if
			not model.Parent
			or humanoid.Health <= 0
			or model:GetAttribute("CombatStunned") == true
			or (model:GetAttribute("CombatInterruptSerial") or 0) ~= interruptSerial
		then
			model:SetAttribute("ActiveAbility", nil)
			return
		end
		local impactPosition = root.Position
		for _, player in ipairs(Players:GetPlayers()) do
			local character = player.Character
			local targetHumanoid = character and character:FindFirstChildOfClass("Humanoid")
			local targetRoot = character and character:FindFirstChild("HumanoidRootPart")
			if
				targetHumanoid
				and targetHumanoid.Health > 0
				and targetRoot
				and (targetRoot.Position - impactPosition).Magnitude <= radius
			then
				PlayerDamageService.ApplyToHumanoid(targetHumanoid, damage, "GroundSlam")
			end
		end
		if warning.Parent then
			warning.Color = Color3.fromRGB(255, 214, 89)
			warning.Transparency = 0.05
		end
		model:SetAttribute("ActiveAbility", nil)
	end)
	return windup + math.max(0.1, tonumber(model:GetAttribute("GroundSlamRecovery")) or 0.8)
end

return table.freeze(GroundSlam)
