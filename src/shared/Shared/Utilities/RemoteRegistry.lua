local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local RemoteRegistry = {}

local function getShared()
	return ReplicatedStorage:WaitForChild("Shared")
end

function RemoteRegistry.GetFolder(category)
	local shared = getShared()
	local remotes = shared:FindFirstChild("Remotes")
	if not remotes then
		if not RunService:IsServer() then
			return shared:WaitForChild("Remotes")
		end
		remotes = Instance.new("Folder")
		remotes.Name = "Remotes"
		remotes.Parent = shared
	end
	local folder = remotes:FindFirstChild(category)
	if not folder then
		if not RunService:IsServer() then
			return remotes:WaitForChild(category)
		end
		folder = Instance.new("Folder")
		folder.Name = category
		folder.Parent = remotes
	end
	return folder
end

function RemoteRegistry.Get(category, name, className)
	local folder = RemoteRegistry.GetFolder(category)
	local remote = folder:FindFirstChild(name)
	if remote and remote.ClassName ~= className then
		if not RunService:IsServer() then
			error(string.format("Remote %s/%s possui classe incorreta", category, name))
		end
		remote:Destroy()
		remote = nil
	end
	if not remote then
		if not RunService:IsServer() then
			return folder:WaitForChild(name)
		end
		remote = Instance.new(className)
		remote.Name = name
		remote.Parent = folder
	end
	return remote
end

return RemoteRegistry
