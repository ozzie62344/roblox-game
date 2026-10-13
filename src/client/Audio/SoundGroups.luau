-- The volume knobs (SETTINGS → AUDIO, ClientSettings): SoundGroups made on this client only, so
-- each player sets their own.
--   Master > Effects  everything SoundCache hands out (guns, footsteps, gadgets...) and any other
--                     sound that turns up in the workspace without a group (server-made ones)
--          > Music    nothing yet: a music system puts its sounds in here (and can read
--                     ClientSettings.Get("MusicVolume"))
--          > UI       menu blips (shop, rewards)
-- A group inside another is multiplied by it, so Master turns everything down.

local SoundService = game:GetService("SoundService")
local Workspace = game:GetService("Workspace")

local function group(name: string, parent: Instance): SoundGroup
	local existing = parent:FindFirstChild(name)
	if existing and existing:IsA("SoundGroup") then
		return existing
	end
	local new = Instance.new("SoundGroup")
	new.Name = name
	new.Volume = 1
	new.Parent = parent
	return new
end

local master = group("Master", SoundService)

local SoundGroups = {
	Master = master,
	Effects = group("Effects", master),
	Music = group("Music", master),
	UI = group("UI", master),
}

-- Sounds made elsewhere (the server's, or a script's own Instance.new("Sound")) go in Effects
function SoundGroups.Start()
	Workspace.DescendantAdded:Connect(function(descendant)
		if descendant:IsA("Sound") and not descendant.SoundGroup then
			descendant.SoundGroup = SoundGroups.Effects
		end
	end)
end

return SoundGroups
