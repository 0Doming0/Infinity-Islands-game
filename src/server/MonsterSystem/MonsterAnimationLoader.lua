-- Carrega Animations/<Estado> ou <Estado>AnimationId sem depender do rig do mob.

local MonsterAnimationLoader = {}
local caches = setmetatable({}, { __mode = "k" })

local function normalizeId(value)
	if typeof(value) == "number" and value > 0 then
		return "rbxassetid://" .. tostring(math.floor(value))
	end
	if typeof(value) ~= "string" or value == "" then
		return nil
	end
	return string.match(value, "^%d+$") and ("rbxassetid://" .. value) or value
end

local function animationId(model, name)
	local folder = model:FindFirstChild("Animations")
	local object = folder and folder:FindFirstChild(name)
	if object and object:IsA("Animation") and object.AnimationId ~= "" then
		return normalizeId(object.AnimationId)
	end
	return normalizeId(model:GetAttribute(name .. "AnimationId"))
end

function MonsterAnimationLoader.Bind(model, humanoid)
	local animator = humanoid:FindFirstChildOfClass("Animator")
	if not animator then
		animator = Instance.new("Animator")
		animator.Parent = humanoid
	end
	local cache = { Animator = animator, Tracks = {}, Current = nil }
	caches[model] = cache
	return cache
end

function MonsterAnimationLoader.Get(model, humanoid, name)
	local cache = caches[model]
	if not cache or cache.Animator.Parent ~= humanoid then
		cache = MonsterAnimationLoader.Bind(model, humanoid)
	end
	if cache.Tracks[name] ~= nil then
		return cache.Tracks[name] or nil
	end
	local id = animationId(model, name)
	if not id then
		cache.Tracks[name] = false
		return nil
	end
	local animation = Instance.new("Animation")
	animation.AnimationId = id
	local ok, track = pcall(cache.Animator.LoadAnimation, cache.Animator, animation)
	animation:Destroy()
	if not ok then
		warn(string.format("[MonsterAnimation] %s/%s falhou: %s", model.Name, name, tostring(track)))
		cache.Tracks[name] = false
		return nil
	end
	track.Priority = (name == "Attack" or name == "GroundSlam") and Enum.AnimationPriority.Action
		or Enum.AnimationPriority.Movement
	track.Looped = name == "Idle" or name == "Walk"
	cache.Tracks[name] = track
	return track
end

function MonsterAnimationLoader.Play(model, humanoid, name, fade, speed)
	local cache = caches[model] or MonsterAnimationLoader.Bind(model, humanoid)
	if cache.Current == name then
		return cache.Tracks[name] or nil
	end
	if cache.Current then
		local previous = cache.Tracks[cache.Current]
		if previous then
			previous:Stop(fade or 0.12)
		end
	end
	local track = MonsterAnimationLoader.Get(model, humanoid, name)
	cache.Current = name
	if track then
		track:Play(fade or 0.12, 1, speed or 1)
	end
	return track
end

function MonsterAnimationLoader.Stop(model)
	local cache = caches[model]
	if not cache then
		return
	end
	for _, track in pairs(cache.Tracks) do
		if track then
			track:Stop(0.1)
		end
	end
	caches[model] = nil
end

return MonsterAnimationLoader
