-- Laser sights (the Laser attachment, shared/Attachments): a red beam out of the gun's lens to
-- whatever it's pointing at, with a dot where it lands. Everyone sees everyone's, like Siege: the
-- price of the steadier hip fire is that it gives you away.
-- Yours comes out of your first-person gun and lands where your crosshair is; other players' come
-- out of the gun in their hands (BodyAnimator.HeldGun) along the barrel. Off while the gun is put
-- away (gadgets, planting, drones...) and for anyone who's dead.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Attachments = require(ReplicatedStorage.Shared.Attachments)
local Weapons = require(ReplicatedStorage.Shared.Weapons)
local BodyAnimator = require(script.Parent.Parent.Pose.BodyAnimator)
local Effects = require(script.Parent.Effects)
local state = require(script.Parent.Parent.PlayerState)

local player = Players.LocalPlayer

local LaserSights = {}

local RANGE = 150 -- studs a beam reaches when it hits nothing
local COLOR = Color3.fromRGB(255, 45, 40)

type Laser = { beam: Beam, from: Attachment, to: Attachment, dot: Part }
local lasers: { [Player]: Laser } = {}

local function newLaser(): Laser
	local folder = Effects.GetFolder()
	local dot = Instance.new("Part")
	dot.Name = "LaserDot"
	dot.Shape = Enum.PartType.Ball
	dot.Size = Vector3.one * 0.12
	dot.Color = COLOR
	dot.Material = Enum.Material.Neon
	dot.Anchored = true
	dot.CanCollide = false
	dot.CanQuery = false
	dot.CanTouch = false
	dot.CastShadow = false
	dot.Parent = folder
	local from = Instance.new("Attachment")
	from.Parent = Workspace.Terrain
	local to = Instance.new("Attachment")
	to.Parent = dot
	local beam = Instance.new("Beam")
	beam.Attachment0 = from
	beam.Attachment1 = to
	beam.Color = ColorSequence.new(COLOR)
	beam.LightEmission = 1
	beam.Transparency = NumberSequence.new(0.35, 0.75) -- (fades toward the far end)
	beam.Width0, beam.Width1 = 0.03, 0.02
	beam.FaceCamera = true
	beam.Segments = 1
	beam.Parent = dot
	return { beam = beam, from = from, to = to, dot = dot }
end

local function remove(owner: Player)
	local laser = lasers[owner]
	if laser then
		laser.dot:Destroy()
		laser.from:Destroy()
		lasers[owner] = nil
	end
end

-- The lens on `owner`'s gun right now, if they have a laser on it and the gun is out
local function lensOf(owner: Player): BasePart?
	local character = owner.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local weaponName = owner:GetAttribute("Weapon")
	if not character or not humanoid or humanoid.Health <= 0 or typeof(weaponName) ~= "string" or not Weapons[weaponName] then
		return nil
	end
	if Attachments.For(owner, weaponName).Under ~= "Laser" then
		return nil
	end
	local firstPerson = owner == player and not state.inLobby and not state.spectating
	if firstPerson and (state.gesturing or state.interacting or state.deploying or state.droning or state.downed) then
		return nil -- (gun put away)
	end
	local gun = if firstPerson then Workspace.CurrentCamera:FindFirstChild("Viewmodel") else BodyAnimator.HeldGun(character)
	local lens = gun and gun:FindFirstChild("LaserLens", true)
	if not lens or not lens:IsA("BasePart") or lens.Transparency >= 1 or lens.LocalTransparencyModifier >= 1 then
		return nil
	end
	return lens
end

local function update()
	local camera = Workspace.CurrentCamera
	for owner in lasers do
		if not owner.Parent then
			remove(owner)
		end
	end
	for _, owner in Players:GetPlayers() do
		local lens = lensOf(owner)
		if not lens then
			remove(owner)
			continue
		end
		local params = RaycastParams.new()
		params.FilterType = Enum.RaycastFilterType.Exclude
		params.FilterDescendantsInstances = { owner.Character :: Model, camera, Effects.GetFolder() }
		-- Yours lands where you aim (your crosshair); theirs follows their barrel
		local origin, direction
		if owner == player and not state.inLobby and not state.spectating then
			origin, direction = camera.CFrame.Position, camera.CFrame.LookVector
		else
			origin, direction = lens.Position, lens.CFrame.LookVector
		end
		local hit = Workspace:Raycast(origin, direction * RANGE, params)
		local finish = if hit then hit.Position else origin + direction * RANGE
		local laser = lasers[owner] or newLaser()
		lasers[owner] = laser
		laser.from.WorldPosition = lens.Position
		laser.dot.Position = finish
		laser.dot.Transparency = if hit then 0 else 1 -- (no dot in the sky)
	end
end

function LaserSights.Start()
	RunService.RenderStepped:Connect(update)
end

return LaserSights
