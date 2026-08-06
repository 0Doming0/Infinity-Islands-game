local RuntimeFolders = {}

local NAMES = {
	"GeneratedIslands",
	"ActiveEnemies",
	"ActiveBoss",
	"PlayerObjects",
	"Effects",
}

function RuntimeFolders.Ensure()
	local runtime = workspace:FindFirstChild("Runtime")
	if not runtime then
		runtime = Instance.new("Folder")
		runtime.Name = "Runtime"
		runtime.Parent = workspace
	end
	for _, name in ipairs(NAMES) do
		if not runtime:FindFirstChild(name) then
			local folder = Instance.new("Folder")
			folder.Name = name
			folder.Parent = runtime
		end
	end
	return runtime
end

function RuntimeFolders.Get(name)
	return RuntimeFolders.Ensure():WaitForChild(name)
end

return RuntimeFolders
