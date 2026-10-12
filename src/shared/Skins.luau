-- Weapon skins, sold in the lobby SHOP for credits (credits are earned in matches: MatchConfig
-- Credits). A skin is bought once and then works on every gun and on the knife; in the shop you
-- pick which of your skins each one wears.
--
-- How a skin paints a gun (client/Combat/SkinPainter): the gun's big pieces (receiver, stock,
-- handguard, barrel, magazine) get the skin's Colors, its small pieces (pins, rails, sights,
-- screws) get Trim. A Neon trim lights up a few lines instead (long thin strips like rails and
-- spines); everything else matches the body. Bores, lenses, brass and sights / scopes keep their
-- factory look (a skin never gets in the way of aiming).
--   Pattern  Solid    every big piece in Colors[1]
--            Camo     each big piece one of Colors, picked at random (same every time)
--            Stripes  bands of Colors along the gun, front to back
-- On the knife: blade in Colors[1] and Material, guard in Trim, handle in Colors[2] (or Trim).
-- Neon trims are kept dim on purpose: right in front of the camera, bright neon blooms into a blob.
--
-- Dev-only skins (DevOnly) can't be bought: anyone with the server's "IsDev" attribute (the
-- game's owner, everyone in a Studio test) has them, nobody else can see or wear them. Exclusive
-- skins (OnlyFor) work the same way for the players on their list (and devs). A Rainbow skin's
-- glowing trim slowly cycles through the colors (SkinPainter); a Stickers skin is covered in
-- little pictures on top of its paint (Stickers = "Cat": Combat/CatStickers).
--
-- The server keeps what you own and wear in player attributes:
--   Credits        number
--   OwnedSkins     "Gold,Tiger,..."
--   EquippedSkins  JSON {"Rifle":"Gold","Knife":"Tiger"} (items without one wear the factory look)

local HttpService = game:GetService("HttpService")

export type Rarity = "Common" | "Rare" | "Epic" | "Legendary" | "Exclusive" | "Dev"

export type Skin = {
	Id: string,
	Name: string,
	Rarity: Rarity,
	Price: number,
	Pattern: "Solid" | "Camo" | "Stripes",
	Colors: { Color3 },
	Material: Enum.Material,
	Reflectance: number?,
	Trim: Color3,
	TrimMaterial: Enum.Material,
	DevOnly: boolean?,
	OnlyFor: { number }?, -- UserIds of the only players (besides devs) who get it
	Note: string?, -- shown in the shop under a dev / exclusive skin
	Rainbow: boolean?, -- glowing trim cycles through the rainbow
	Stickers: "Cat"?,
}

local Skins = {}

-- Rarity decides the price and the color of its tag in the shop
Skins.Rarities = {
	Common = { Order = 1, Price = 400, Color = Color3.fromRGB(165, 170, 180) },
	Rare = { Order = 2, Price = 900, Color = Color3.fromRGB(60, 145, 255) },
	Epic = { Order = 3, Price = 1800, Color = Color3.fromRGB(175, 85, 255) },
	Legendary = { Order = 4, Price = 3500, Color = Color3.fromRGB(255, 190, 60) },
	Exclusive = { Order = 5, Price = 0, Color = Color3.fromRGB(255, 120, 190) },
	Dev = { Order = 6, Price = 0, Color = Color3.fromRGB(255, 70, 90) },
}

-- What can wear a skin, in the order the shop lists them
Skins.Items = { "Rifle", "SMG", "LMG", "Marksman", "Sniper", "Shotgun", "Revolver", "Autopistol", "Knife" }

local function rgb(r: number, g: number, b: number): Color3
	return Color3.fromRGB(r, g, b)
end

local function skin(id: string, name: string, rarity: Rarity, pattern: string, colors: { Color3 }, material: Enum.Material, trim: Color3, trimMaterial: Enum.Material, reflectance: number?): Skin
	return {
		Id = id,
		Name = name,
		Rarity = rarity,
		Price = Skins.Rarities[rarity].Price,
		Pattern = pattern :: any,
		Colors = colors,
		Material = material,
		Reflectance = reflectance,
		Trim = trim,
		TrimMaterial = trimMaterial,
	}
end

local M = Enum.Material

-- Shop order: cheapest first
Skins.List = {
	skin("Desert", "Desert Tan", "Common", "Solid", { rgb(196, 170, 128) }, M.Plastic, rgb(58, 54, 48), M.Metal),
	skin("Arctic", "Arctic White", "Common", "Solid", { rgb(226, 229, 233) }, M.Plastic, rgb(70, 74, 80), M.Metal),
	skin("Olive", "Olive Drab", "Common", "Solid", { rgb(88, 98, 62) }, M.Plastic, rgb(40, 42, 36), M.Metal),
	skin("Cobalt", "Cobalt", "Common", "Solid", { rgb(40, 82, 175) }, M.Metal, rgb(26, 27, 31), M.Metal, 0.05),

	skin("Woodland", "Woodland Camo", "Rare", "Camo", { rgb(74, 92, 52), rgb(52, 62, 38), rgb(112, 96, 64), rgb(32, 34, 28) }, M.Plastic, rgb(30, 32, 28), M.Metal),
	skin("Urban", "Urban Camo", "Rare", "Camo", { rgb(152, 154, 158), rgb(96, 99, 105), rgb(60, 62, 68), rgb(205, 205, 202) }, M.Plastic, rgb(34, 35, 38), M.Metal),
	skin("Crimson", "Crimson", "Rare", "Solid", { rgb(150, 22, 30) }, M.Metal, rgb(22, 22, 24), M.Metal, 0.08),
	skin("Carbon", "Carbon Fiber", "Rare", "Stripes", { rgb(30, 30, 33), rgb(44, 45, 50) }, M.Fabric, rgb(120, 124, 132), M.Metal),

	skin("Tiger", "Tiger", "Epic", "Stripes", { rgb(235, 120, 20), rgb(22, 20, 18), rgb(235, 120, 20), rgb(250, 190, 90) }, M.Plastic, rgb(22, 20, 18), M.Metal),
	skin("Frost", "Frost", "Epic", "Camo", { rgb(170, 215, 240), rgb(225, 242, 255), rgb(120, 170, 215) }, M.Glacier, rgb(235, 245, 255), M.SmoothPlastic),
	skin("Toxic", "Toxic", "Epic", "Solid", { rgb(36, 40, 35) }, M.Metal, rgb(55, 140, 30), M.Neon),
	skin("Magma", "Magma", "Epic", "Solid", { rgb(215, 80, 30) }, M.CrackedLava, rgb(28, 22, 20), M.Basalt),

	skin("Gold", "Solid Gold", "Legendary", "Solid", { rgb(255, 196, 64) }, M.Metal, rgb(32, 30, 26), M.Metal, 0.25),
	skin("Phantom", "Phantom", "Legendary", "Solid", { rgb(150, 100, 255) }, M.ForceField, rgb(105, 80, 160), M.Neon),
	skin("Cyber", "Neon Cyber", "Legendary", "Solid", { rgb(18, 18, 26) }, M.SmoothPlastic, rgb(0, 120, 145), M.Neon),
	skin("Dragon", "Dragon Scale", "Legendary", "Camo", { rgb(140, 20, 22), rgb(95, 12, 16), rgb(175, 40, 30) }, M.Slate, rgb(225, 175, 65), M.Metal, 0.15),
}

-- Black chrome with rainbow lines, for devs only
local developer = skin("Developer", "Developer", "Dev", "Solid", { rgb(16, 16, 20) }, M.Metal, rgb(160, 40, 60), M.Neon, 0.3)
developer.DevOnly = true
developer.Rainbow = true
table.insert(Skins.List, developer)

-- Bubblegum pink covered in little cat heads, just for @kittenloveeeeeeeeeee (and devs)
local kitty = skin("Kitty", "Kitty", "Exclusive", "Solid", { rgb(255, 140, 192), rgb(255, 212, 232) }, M.SmoothPlastic, rgb(255, 222, 236), M.SmoothPlastic)
kitty.OnlyFor = { 406566030 } -- kittenloveeeeeeeeeee
kitty.Note = "Made just for @kittenloveeeeeeeeeee"
kitty.Stickers = "Cat"
table.insert(Skins.List, kitty)

Skins.ById = {} :: { [string]: Skin }
for _, s in Skins.List do
	Skins.ById[s.Id] = s
end

-- A dev / exclusive skin this player gets for free (false for skins everyone can buy)
function Skins.Granted(player: Player, skin: Skin): boolean
	if skin.DevOnly then
		return player:GetAttribute("IsDev") == true
	elseif skin.OnlyFor then
		return player:GetAttribute("IsDev") == true or table.find(skin.OnlyFor, player.UserId) ~= nil
	end
	return false
end

-- Shows up in the shop for this player (everything but other people's dev / exclusive skins)
function Skins.Listed(player: Player, skin: Skin): boolean
	return not (skin.DevOnly or skin.OnlyFor) or Skins.Granted(player, skin)
end

-- Decoded EquippedSkins, cached per attribute string (BodyAnimator asks every frame)
local decoded: { [string]: { [string]: string } } = {}

-- The skin a player has on an item ("Rifle", "Knife"...), or nil for the factory look
function Skins.EquippedFor(player: Player, item: string): Skin?
	local json = player:GetAttribute("EquippedSkins")
	if typeof(json) ~= "string" or json == "" then
		return nil
	end
	local equipped = decoded[json]
	if not equipped then
		local ok, value = pcall(HttpService.JSONDecode, HttpService, json)
		equipped = if ok and typeof(value) == "table" then value else {}
		decoded[json] = equipped
	end
	local found = equipped[item] and Skins.ById[equipped[item]]
	if not found or not Skins.Listed(player, found) then
		return nil
	end
	return found
end

function Skins.Owns(player: Player, id: string): boolean
	local found = Skins.ById[id]
	if found and (found.DevOnly or found.OnlyFor) then
		return Skins.Granted(player, found)
	end
	local owned = player:GetAttribute("OwnedSkins")
	return typeof(owned) == "string" and table.find(string.split(owned, ","), id) ~= nil
end

return Skins
