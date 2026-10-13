-- Gun attachments, bought with credits in the shop's MODS view: bought once, an attachment goes on
-- every gun it fits (you pick which ones wear it). Each gun has up to three slots:
--   Optic   Red Dot, Holo, 2.5x Scope: swaps the gun's own sight (GunModels); the scope zooms
--           in further and is slower to aim. Guns with a sight that can't come off (the
--           sniper's scope) or nowhere to put one (pistols) don't get this slot.
--   Muzzle  Suppressor (much quieter, no echo), Compensator (less sideways kick)
--   Under   Laser (tighter hip fire)
-- No attachment in a slot = the gun as it comes (its "Factory" look).
-- What a player owns and has on their guns is kept with their data (PlayerData) and shown as
-- player attributes: OwnedAttachments "RedDot,Scope" and Attachments (JSON
-- {"Rifle":{"Optic":"Scope","Muzzle":"Suppressor"}}, which everyone's client reads).

local HttpService = game:GetService("HttpService")

local Attachments = {}

export type Slot = "Optic" | "Muzzle" | "Under"
export type Attachment = {
	Id: string,
	Slot: Slot,
	Name: string,
	Description: string,
	Price: number,
}
export type Chosen = { [string]: string } -- slot → attachment id

Attachments.Slots = { "Optic", "Muzzle", "Under" } :: { Slot }
Attachments.SlotNames = { Optic = "OPTIC", Muzzle = "MUZZLE", Under = "UNDER BARREL" }

Attachments.List = {
	{ Id = "RedDot", Slot = "Optic", Name = "Red Dot", Description = "Small tube sight with a clear view. Quick to aim.", Price = 400 },
	{ Id = "Holo", Slot = "Optic", Name = "Holo", Description = "Big window, ring-and-dot reticle.", Price = 600 },
	{ Id = "Scope", Slot = "Optic", Name = "2.5x Scope", Description = "Zooms in further. Slower to aim.", Price = 1100 },
	{ Id = "Suppressor", Slot = "Muzzle", Name = "Suppressor", Description = "Much quieter shots, no echo.", Price = 800 },
	{ Id = "Compensator", Slot = "Muzzle", Name = "Compensator", Description = "Less sideways kick.", Price = 550 },
	{ Id = "Laser", Slot = "Under", Name = "Laser", Description = "Tighter hip fire.", Price = 450 },
} :: { Attachment }

Attachments.ById = {} :: { [string]: Attachment }
for _, attachment in Attachments.List do
	Attachments.ById[attachment.Id] = attachment
end

-- Which slots each gun has
Attachments.SlotsFor = {
	Rifle = { Optic = true, Muzzle = true, Under = true },
	SMG = { Optic = true, Muzzle = true, Under = true },
	LMG = { Optic = true, Muzzle = true, Under = true },
	Marksman = { Optic = true, Muzzle = true, Under = true },
	Shotgun = { Optic = true, Muzzle = true, Under = true },
	Gatling = { Optic = true, Under = true }, -- (nothing goes on six spinning muzzles)
	Sniper = { Muzzle = true, Under = true },
	Revolver = { Muzzle = true, Under = true },
	Autopistol = { Muzzle = true, Under = true },
} :: { [string]: { [string]: boolean } }

-- Can this go on that gun?
function Attachments.Fits(weaponName: string, id: string): boolean
	local attachment = Attachments.ById[id]
	local slots = Attachments.SlotsFor[weaponName]
	return attachment ~= nil and slots ~= nil and slots[attachment.Slot] == true
end

function Attachments.Owns(player: Player, id: string): boolean
	local owned = player:GetAttribute("OwnedAttachments")
	return typeof(owned) == "string" and table.find(string.split(owned, ","), id) ~= nil
end

-- Decoded "Attachments" attributes, cached per string (other players' guns ask every frame)
local decoded: { [string]: { [string]: Chosen } } = {}

-- What a player has on a gun (slot → id), only what fits
function Attachments.For(player: Player, weaponName: string): Chosen
	local json = player:GetAttribute("Attachments")
	if typeof(json) ~= "string" or json == "" then
		return {}
	end
	local all = decoded[json]
	if not all then
		local ok, value = pcall(HttpService.JSONDecode, HttpService, json)
		all = if ok and typeof(value) == "table" then value else {}
		decoded[json] = all
	end
	local chosen: Chosen = {}
	local onGun = all[weaponName]
	if typeof(onGun) == "table" then
		for slot, id in onGun do
			if typeof(id) == "string" and Attachments.Fits(weaponName, id) and Attachments.ById[id].Slot == slot then
				chosen[slot] = id
			end
		end
	end
	return chosen
end

-- A short key for what's on a gun ("Optic=Scope,Under=Laser"), to tell when a model needs rebuilding
function Attachments.Key(chosen: Chosen): string
	local parts = {}
	for _, slot in Attachments.Slots do
		if chosen[slot] then
			table.insert(parts, `{slot}={chosen[slot]}`)
		end
	end
	return table.concat(parts, ",")
end

-- The gun's stats with its attachments on (a copy; the shared table is never changed)
function Attachments.Apply<W>(weapon: W, chosen: Chosen): W
	if next(chosen) == nil then
		return weapon
	end
	local stats = table.clone(weapon :: any)
	if chosen.Optic == "RedDot" then
		stats.AdsTime *= 0.92
	elseif chosen.Optic == "Scope" then
		stats.AdsFovScale = math.min(stats.AdsFovScale, 0.5)
		stats.AdsTime += 0.08
		stats.AdsSensitivity *= 0.75
	end
	if chosen.Muzzle == "Suppressor" then
		stats.FireVolume *= 0.35
		stats.TailSound = nil
	elseif chosen.Muzzle == "Compensator" then
		stats.RecoilSide *= 0.6
		stats.RecoilDrift *= 0.5
		stats.FireVolume *= 1.1
	end
	if chosen.Under == "Laser" then
		stats.HipSpread *= 0.8
	end
	return stats :: W
end

return Attachments
