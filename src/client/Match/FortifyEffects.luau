-- Barricades and reinforcements going up, seen by everyone: while a defender holds G, the steel
-- plate rises up the wall (reinforce) or the boards unroll down the doorway (barricade), in step
-- with their progress. Let go early and it drops away; finish and it locks in with a clank as the
-- real one appears. The server marks the slot being worked on with Build* attributes
-- (FortifyService); this only draws.

local Debris = game:GetService("Debris")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Sounds = require(ReplicatedStorage.Shared.Sounds)
local Effects = require(script.Parent.Parent.Combat.Effects)
local Sound3D = require(script.Parent.Parent.Audio.Sound3D)

local FortifyEffects = {}

local LOOKS = {
	Reinforce = { color = Color3.fromRGB(92, 97, 104), material = Enum.Material.DiamondPlate, fromTop = false },
	Barricade = { color = Color3.fromRGB(176, 136, 92), material = Enum.Material.WoodPlanks, fromTop = true },
}
local FOLDERS = { "ReinforceSlots", "BarricadeSlots" }

local ghosts: { [BasePart]: { part: Part, endsAt: number } } = {}

-- Sizes and places the piece `t` (0..1) of the way up the wall / down the doorway
local function pose(ghost: Part, slot: BasePart, t: number)
	local cframe = slot:GetAttribute("BuildCFrame")
	local size = slot:GetAttribute("BuildSize")
	local look = LOOKS[slot:GetAttribute("BuildKind")]
	if typeof(cframe) ~= "CFrame" or typeof(size) ~= "Vector3" or not look then
		return
	end
	local height = math.max(size.Y * t, 0.05)
	local offset = (size.Y - height) / 2 * (if look.fromTop then 1 else -1)
	ghost.Size = Vector3.new(size.X, height, size.Z)
	ghost.CFrame = cframe * CFrame.new(0, offset, 0)
end

local function newGhost(slot: BasePart): Part
	local look = LOOKS[slot:GetAttribute("BuildKind")] or LOOKS.Reinforce
	local ghost = Instance.new("Part")
	ghost.Anchored = true
	ghost.CanCollide = false
	ghost.CanQuery = false
	ghost.CanTouch = false
	ghost.Color = look.color
	ghost.Material = look.material
	ghost.Parent = Effects.GetFolder()
	Sound3D.Play(Sounds.CoverStart.Id, slot.Position, { volume = Sounds.CoverStart.Volume, range = Sounds.CoverStart.Range, pitch = Sounds.CoverStart.Pitch })
	return ghost
end

local function update()
	local map = Workspace:FindFirstChild("Map")
	local now = Workspace:GetServerTimeNow()
	for _, folderName in FOLDERS do
		local folder = map and map:FindFirstChild(folderName)
		for _, slot in if folder then folder:GetChildren() else {} do
			local endsAt = slot:GetAttribute("BuildEndsAt")
			if slot:IsA("BasePart") and typeof(endsAt) == "number" then
				local entry = ghosts[slot]
				if not entry then
					entry = { part = newGhost(slot), endsAt = endsAt }
					ghosts[slot] = entry
				end
				local duration = slot:GetAttribute("BuildTime") or 1
				local t = math.clamp(1 - (endsAt - now) / duration, 0, 1)
				pose(entry.part, slot, 1 - (1 - t) ^ 2) -- fast at first, settling into place
			end
		end
	end

	-- Done (the real plate / boards are there now) or let go early
	for slot, entry in ghosts do
		if not slot.Parent or not slot:GetAttribute("BuildEndsAt") then
			ghosts[slot] = nil
			local finished = slot.Parent ~= nil and now >= entry.endsAt - 0.15
			if finished then
				local deploy = Sounds.CoverDeploy
				Sound3D.Play(deploy.Id, entry.part.Position, { volume = deploy.Volume, range = deploy.Range, pitch = deploy.Pitch })
				entry.part:Destroy()
			else
				TweenService:Create(entry.part, TweenInfo.new(0.25), { Transparency = 1 }):Play()
				Debris:AddItem(entry.part, 0.3)
			end
		end
	end
end

function FortifyEffects.Start()
	RunService.RenderStepped:Connect(update)
end

return FortifyEffects
