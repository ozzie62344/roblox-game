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
-- little pictures on top of its paint (Combat/Stickers: "Cat", "Cheeto", "Holds").
-- Level-reward skins (TrackOnly) can't be bought either: reaching their level on the reward track
-- unlocks them (shared/Progression, server ProgressService).
-- Robux-store skins (PassOnly = a Key in shared/Store: the "VIP" game pass, the "StarterPack")
-- can't be bought with credits: buying that pass / pack adds them to your skins (StoreService).
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
	Stickers: ("Cat" | "Cheeto" | "Holds")?,
	TrackOnly: number?, -- a level reward (shared/Progression): can't be bought, unlocked at this level
	DailyOnly: number?, -- a daily-reward streak skin: can't be bought, yours after claiming this many days in a row
	PassOnly: string?, -- comes with a Robux-store item (its Key in shared/Store): can't be bought with credits
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
Skins.Items = { "Rifle", "SMG", "LMG", "Gatling", "Marksman", "Sniper", "Shotgun", "Revolver", "Autopistol", "Knife" }

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
	skin("Midnight", "Midnight", "Common", "Solid", { rgb(28, 34, 58) }, M.Plastic, rgb(150, 156, 170), M.Metal),
	skin("Mint", "Mint", "Common", "Solid", { rgb(150, 220, 190) }, M.SmoothPlastic, rgb(245, 245, 240), M.SmoothPlastic),

	skin("Woodland", "Woodland Camo", "Rare", "Camo", { rgb(74, 92, 52), rgb(52, 62, 38), rgb(112, 96, 64), rgb(32, 34, 28) }, M.Plastic, rgb(30, 32, 28), M.Metal),
	skin("Urban", "Urban Camo", "Rare", "Camo", { rgb(152, 154, 158), rgb(96, 99, 105), rgb(60, 62, 68), rgb(205, 205, 202) }, M.Plastic, rgb(34, 35, 38), M.Metal),
	skin("Crimson", "Crimson", "Rare", "Solid", { rgb(150, 22, 30) }, M.Metal, rgb(22, 22, 24), M.Metal, 0.08),
	skin("Carbon", "Carbon Fiber", "Rare", "Stripes", { rgb(30, 30, 33), rgb(44, 45, 50) }, M.Fabric, rgb(120, 124, 132), M.Metal),
	skin("Zebra", "Zebra", "Rare", "Stripes", { rgb(235, 235, 232), rgb(24, 24, 26) }, M.Plastic, rgb(24, 24, 26), M.Metal),
	skin("CandyCane", "Candy Cane", "Rare", "Stripes", { rgb(215, 30, 45), rgb(245, 242, 238) }, M.SmoothPlastic, rgb(40, 140, 70), M.SmoothPlastic),
	skin("Ocean", "Ocean Camo", "Rare", "Camo", { rgb(30, 80, 140), rgb(50, 130, 180), rgb(20, 50, 90), rgb(110, 180, 210) }, M.Plastic, rgb(20, 30, 45), M.Metal),

	skin("Tiger", "Tiger", "Epic", "Stripes", { rgb(235, 120, 20), rgb(22, 20, 18), rgb(235, 120, 20), rgb(250, 190, 90) }, M.Plastic, rgb(22, 20, 18), M.Metal),
	skin("Frost", "Frost", "Epic", "Camo", { rgb(170, 215, 240), rgb(225, 242, 255), rgb(120, 170, 215) }, M.Glacier, rgb(235, 245, 255), M.SmoothPlastic),
	skin("Toxic", "Toxic", "Epic", "Solid", { rgb(36, 40, 35) }, M.Metal, rgb(55, 140, 30), M.Neon),
	skin("Magma", "Magma", "Epic", "Solid", { rgb(215, 80, 30) }, M.CrackedLava, rgb(28, 22, 20), M.Basalt),
	skin("Jungle", "Jungle", "Epic", "Camo", { rgb(40, 95, 45), rgb(70, 130, 50), rgb(25, 60, 30), rgb(120, 150, 60) }, M.Fabric, rgb(90, 60, 35), M.Wood),
	skin("Galaxy", "Galaxy", "Epic", "Camo", { rgb(40, 20, 70), rgb(70, 30, 110), rgb(20, 15, 45), rgb(100, 50, 140) }, M.SmoothPlastic, rgb(110, 60, 170), M.Neon),

	skin("Gold", "Solid Gold", "Legendary", "Solid", { rgb(255, 196, 64) }, M.Metal, rgb(32, 30, 26), M.Metal, 0.25),
	skin("Phantom", "Phantom", "Legendary", "Solid", { rgb(150, 100, 255) }, M.ForceField, rgb(105, 80, 160), M.Neon),
	skin("Cyber", "Neon Cyber", "Legendary", "Solid", { rgb(18, 18, 26) }, M.SmoothPlastic, rgb(0, 120, 145), M.Neon),
	skin("Dragon", "Dragon Scale", "Legendary", "Camo", { rgb(140, 20, 22), rgb(95, 12, 16), rgb(175, 40, 30) }, M.Slate, rgb(225, 175, 65), M.Metal, 0.15),
	skin("Chrome", "Chrome", "Legendary", "Solid", { rgb(215, 218, 224) }, M.Metal, rgb(40, 42, 46), M.Metal, 0.4),
	skin("Diamond", "Diamond", "Legendary", "Camo", { rgb(185, 230, 245), rgb(150, 210, 235), rgb(225, 245, 252) }, M.Ice, rgb(240, 250, 255), M.Glass, 0.2),
}

-- Level rewards (shared/Progression): in the shop for everyone to see, locked until you reach
-- the level ("LEVEL 10" instead of a price), then yours for free
local function trackSkin(level: number, s: Skin)
	s.TrackOnly = level
	table.insert(Skins.List, s)
end
trackSkin(5, skin("Recruit", "Recruit", "Rare", "Stripes", { rgb(120, 112, 80), rgb(84, 90, 60) }, M.Fabric, rgb(36, 38, 32), M.Metal))
trackSkin(10, skin("Veteran", "Veteran", "Rare", "Camo", { rgb(150, 120, 80), rgb(110, 88, 60), rgb(70, 60, 45), rgb(180, 160, 120) }, M.Plastic, rgb(170, 130, 60), M.Metal, 0.1))
trackSkin(15, skin("Hazard", "Hazard", "Epic", "Stripes", { rgb(245, 200, 30), rgb(26, 26, 28) }, M.SmoothPlastic, rgb(26, 26, 28), M.Metal))
trackSkin(20, skin("Elite", "Elite", "Epic", "Solid", { rgb(22, 22, 25) }, M.SmoothPlastic, rgb(170, 125, 30), M.Neon))
trackSkin(30, skin("Breacher", "Breacher", "Legendary", "Camo", { rgb(90, 20, 20), rgb(30, 28, 30), rgb(60, 58, 62) }, M.Metal, rgb(170, 70, 20), M.Neon, 0.1))
trackSkin(40, skin("Warlord", "Warlord", "Legendary", "Solid", { rgb(70, 74, 82) }, M.Metal, rgb(150, 25, 30), M.Neon, 0.3))
local apex = skin("Apex", "Apex", "Legendary", "Solid", { rgb(240, 238, 232) }, M.SmoothPlastic, rgb(200, 200, 200), M.Neon, 0.2)
apex.Rainbow = true
trackSkin(50, apex)

-- Daily reward: claim the login reward this many days in a row (ProgressService) and it's yours.
-- Sunrise stripes with gold trim.
Skins.DailyStreakDays = 7
local daybreak = skin("Daybreak", "Daybreak", "Legendary", "Stripes", { rgb(250, 84, 40), rgb(255, 140, 20), rgb(255, 196, 40), rgb(220, 60, 110) }, M.SmoothPlastic, rgb(255, 200, 60), M.Metal, 0.2)
daybreak.DailyOnly = Skins.DailyStreakDays
table.insert(Skins.List, daybreak)

-- Robux store (shared/Store, server StoreService): in the shop for everyone to see, "VIP PASS" /
-- "STARTER PACK" instead of a price. Royal Guard: deep purple with gleaming gold stripes, for VIPs.
local royal = skin("Royal", "Royal Guard", "Legendary", "Stripes", { rgb(58, 26, 96), rgb(40, 18, 70), rgb(255, 196, 64) }, M.Metal, rgb(255, 205, 80), M.Neon, 0.2)
royal.PassOnly = "VIP"
table.insert(Skins.List, royal)
-- Vanguard: navy and steel camo with a blaze-orange trim, in the Starter Pack
local vanguard = skin("Vanguard", "Vanguard", "Epic", "Camo", { rgb(34, 46, 74), rgb(70, 82, 100), rgb(24, 30, 44), rgb(110, 120, 135) }, M.Plastic, rgb(255, 120, 30), M.Metal, 0.05)
vanguard.PassOnly = "StarterPack"
table.insert(Skins.List, vanguard)

-- Black chrome with rainbow lines, for devs only
local developer = skin("Developer", "Developer", "Dev", "Solid", { rgb(16, 16, 20) }, M.Metal, rgb(160, 40, 60), M.Neon, 0.3)
developer.DevOnly = true
developer.Rainbow = true
table.insert(Skins.List, developer)

-- Bubblegum pink covered in little cat heads, just for @kittenloveeeeeeeeeee (and devs)
local kitty = skin("Kitty", "Kitty", "Exclusive", "Solid", { rgb(255, 118, 172), rgb(255, 205, 226) }, M.SmoothPlastic, rgb(255, 222, 236), M.SmoothPlastic)
kitty.OnlyFor = { 406566030 } -- kittenloveeeeeeeeeee
kitty.Note = "Made just for @kittenloveeeeeeeeeee"
kitty.Stickers = "Cat"
table.insert(Skins.List, kitty)

-- Ginger orange covered in Cheetos, just for @raycerTy (and devs)
local bigRed = skin("BigRed", "Big Red", "Exclusive", "Solid", { rgb(196, 78, 26), rgb(235, 140, 60) }, M.SmoothPlastic, rgb(255, 165, 45), M.SmoothPlastic)
bigRed.OnlyFor = { 1341360115 } -- raycerTy
bigRed.Note = "Made just for @raycerTy"
bigRed.Stickers = "Cheeto"
table.insert(Skins.List, bigRed)

-- Rock climbing: grey crag covered in colourful holds, rope-blue trim, just for @trashcan648 (and devs)
local crag = skin("Crag", "Crag", "Exclusive", "Camo", { rgb(128, 124, 118), rgb(104, 101, 96), rgb(146, 141, 133), rgb(90, 88, 84) }, M.Slate, rgb(40, 170, 210), M.Fabric)
crag.OnlyFor = { 2630899223 } -- trashcan648
crag.Note = "Made just for @trashcan648"
crag.Stickers = "Holds"
table.insert(Skins.List, crag)

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
