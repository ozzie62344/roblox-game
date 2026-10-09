-- Target dummies for testing guns. They stand still; permanent ones respawn after dying.

local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")

local Dummies = {}

local RESPAWN_DELAY = 3

-- Bumped by ClearAll so dummies from a previous map don't respawn
local generation = 0

local function getFolder(): Folder
	local folder = Workspace:FindFirstChild("Dummies")
	if not folder then
		folder = Instance.new("Folder")
		folder.Name = "Dummies"
		folder.Parent = Workspace
	end
	return folder :: Folder
end

-- cframe = where the dummy's root stands (y ≈ 3 for a dummy standing on the ground at y = 0).
-- Permanent dummies respawn when killed and aren't removed by ClearSpawned.
function Dummies.Spawn(cframe: CFrame, permanent: boolean?)
	local description = Instance.new("HumanoidDescription")
	local dummy = Players:CreateHumanoidModelFromDescription(description, Enum.HumanoidRigType.R15)
	dummy.Name = "Target Dummy"
	dummy:SetAttribute("Permanent", permanent == true)

	local root = dummy:FindFirstChild("HumanoidRootPart") :: BasePart
	root.Anchored = true
	dummy:PivotTo(cframe)

	local humanoid = dummy:FindFirstChildOfClass("Humanoid") :: Humanoid
	humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.Viewer
	humanoid.HealthDisplayDistance = 100
	humanoid.HealthDisplayType = Enum.HumanoidHealthDisplayType.AlwaysOn

	local spawnedIn = generation
	humanoid.Died:Connect(function()
		task.delay(RESPAWN_DELAY, function()
			dummy:Destroy()
			if permanent and spawnedIn == generation then
				Dummies.Spawn(cframe, true)
			end
		end)
	end)

	dummy.Parent = getFolder()
	return dummy
end

-- Removes dummies spawned from the dev panel (keeps the arena's permanent ones)
function Dummies.ClearSpawned()
	for _, dummy in getFolder():GetChildren() do
		if not dummy:GetAttribute("Permanent") then
			dummy:Destroy()
		end
	end
end

-- Removes every dummy, including permanent ones (used when switching maps)
function Dummies.ClearAll()
	generation += 1
	getFolder():ClearAllChildren()
end

return Dummies
