-- Cria somente a estrutura compartilhada. Nao substitui assets existentes.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Bootstrap = {}

local REMOTES = {
	OpenShop = "RemoteEvent",
	PurchaseItem = "RemoteFunction",
	EquipItem = "RemoteFunction",
	UnequipItem = "RemoteFunction",
	InventoryUpdated = "RemoteEvent",
}

local remotesFolder = nil

local function ensureFolder(parent, name)
	local existing = parent:FindFirstChild(name)
	if existing then
		assert(existing:IsA("Folder"), string.format("[MVP Bootstrap] %s deve ser Folder", existing:GetFullName()))
		return existing
	end
	local folder = Instance.new("Folder")
	folder.Name = name
	folder.Parent = parent
	return folder
end

function Bootstrap.Start()
	if remotesFolder then
		return
	end
	remotesFolder = ensureFolder(ReplicatedStorage, "MVPRemotes")
	for name, className in pairs(REMOTES) do
		local existing = remotesFolder:FindFirstChild(name)
		if existing then
			assert(
				existing.ClassName == className,
				string.format("[MVP Bootstrap] %s deve ser %s", existing:GetFullName(), className)
			)
		else
			local remote = Instance.new(className)
			remote.Name = name
			remote.Parent = remotesFolder
		end
	end
end

function Bootstrap.GetRemote(name)
	assert(remotesFolder, "[MVP Bootstrap] Start deve ser chamado primeiro")
	assert(REMOTES[name], "[MVP Bootstrap] Remote desconhecido: " .. tostring(name))
	return remotesFolder:WaitForChild(name)
end

return Bootstrap
