-- The skin shop (client Match/ShopMenu) and credits.
--   Shop:FireServer("Buy", skinId, item?)       buy a skin with credits (works on everything),
--                                               and wear it on `item` right away (not level
--                                               rewards: Skins TrackOnly)
--   Shop:FireServer("Equip", item, skinId?)     wear an owned skin on "Rifle", "Knife"... (nil =
--                                               the factory look)
--   Shop:FireServer("EquipAll", skinId?)        the same on every gun and the knife
--   Shop:FireServer("BuyAttachment", id, gun?)  buy an attachment with credits (works on every
--                                               gun it fits), and put it on `gun` right away
--   Shop:FireServer("Attach", gun, slot, id?)   put an owned attachment on a gun ("Rifle", "Optic",
--                                               "Scope"; nil id = take it off)
--   Shop:FireClient(player, "Reward", amount, reason)   credits earned (toast on screen)
--   Shop:FireClient(player, "Bought", id)               a purchase went through (skin or attachment)
--   Shop:FireClient(player, "Store", key)               a Robux purchase was granted (StoreService)
-- Credits are earned in matches (RoundService, ObjectiveService call Award; amounts in
-- MatchConfig.Credits). Ownership is checked here, never trusted from the client.
-- Credits for match reasons (MATCH_REASONS) are multiplied for VIPs (StoreService sets the hook);
-- challenges, daily / level rewards and dev gifts aren't.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Attachments = require(ReplicatedStorage.Shared.Attachments)
local Skins = require(ReplicatedStorage.Shared.Skins)
local PlayerData = require(script.Parent.PlayerData)

local Shop = ReplicatedStorage.Remotes.Shop :: RemoteEvent

local ShopService = {}

local lastRequest: { [Player]: number } = {}

-- The reasons RoundService / ObjectiveService give for credits earned playing a match
local MATCH_REASONS = {
	["KILL"] = true,
	["HEADSHOT"] = true,
	["DEFUSER PLANTED"] = true,
	["DEFUSER DISABLED"] = true,
	["ROUND WON"] = true,
	["MATCH WON"] = true,
	["MATCH COMPLETE"] = true,
}
local matchMultiplier = function(_player: Player): number
	return 1
end

-- StoreService: how much a player's match credits are multiplied by (the VIP pass)
function ShopService.SetMatchMultiplier(multiplier: (Player) -> number)
	matchMultiplier = multiplier
end

-- Gives a player credits and tells them why ("KILL", "ROUND WON"...)
function ShopService.Award(player: Player, amount: number, reason: string)
	if MATCH_REASONS[reason] then
		amount = math.floor(amount * matchMultiplier(player) + 0.5)
	end
	if amount <= 0 then
		return
	end
	local given = PlayerData.Update(player, function(data)
		data.Credits += amount
	end)
	if given then
		Shop:FireClient(player, "Reward", amount, reason)
	end
end

-- Adds (or with a negative amount, takes away, never below 0) credits: the dev panel's gifts
function ShopService.Adjust(player: Player, amount: number, reason: string)
	if amount > 0 then
		ShopService.Award(player, amount, reason)
	elseif amount < 0 then
		PlayerData.Update(player, function(data)
			data.Credits = math.max(0, data.Credits + amount)
		end)
	end
end

-- Takes `amount` credits if they have that many (founding a clan: ClanService). True if it did.
function ShopService.Spend(player: Player, amount: number): boolean
	local data = PlayerData.Get(player)
	if not data or amount < 0 or data.Credits < amount then
		return false
	end
	return PlayerData.Update(player, function(d)
		d.Credits -= amount
	end, true)
end

local function buy(player: Player, id: any, item: any)
	local skin = typeof(id) == "string" and Skins.ById[id]
	local data = PlayerData.Get(player)
	-- (level-reward skins only come from the reward track: ProgressService; Robux-store ones from
	-- StoreService)
	if not skin or skin.DevOnly or skin.OnlyFor or skin.TrackOnly or skin.DailyOnly or skin.PassOnly or not data or data.Skins[skin.Id] or data.Credits < skin.Price then
		return
	end
	PlayerData.Update(player, function(d)
		d.Credits -= skin.Price
		d.Skins[skin.Id] = true
		if typeof(item) == "string" and table.find(Skins.Items, item) then
			d.Equipped[item] = skin.Id
		end
	end, true)
	Shop:FireClient(player, "Bought", skin.Id)
end

-- Owned, or a dev / exclusive skin that's theirs
local function canWear(player: Player, data: PlayerData.Data, id: string): boolean
	local skin = Skins.ById[id]
	return data.Skins[id] == true or (skin ~= nil and Skins.Granted(player, skin))
end

-- `id` nil = back to the factory look
local function equip(player: Player, items: { string }, id: any)
	local data = PlayerData.Get(player)
	if not data or (id ~= nil and (typeof(id) ~= "string" or not canWear(player, data, id))) then
		return
	end
	PlayerData.Update(player, function(d)
		for _, item in items do
			d.Equipped[item] = id
		end
	end, true)
end

-- Attachments: any owned one that fits; nil takes the slot's one off
local function attach(player: Player, weaponName: any, slot: any, id: any)
	local slots = typeof(weaponName) == "string" and Attachments.SlotsFor[weaponName]
	local data = PlayerData.Get(player)
	if not data or not slots or typeof(slot) ~= "string" or not slots[slot] then
		return
	end
	if id ~= nil and (typeof(id) ~= "string" or not data.OwnedAttachments[id] or not Attachments.Fits(weaponName, id) or Attachments.ById[id].Slot ~= slot) then
		return
	end
	PlayerData.Update(player, function(d)
		local onGun = d.Attachments[weaponName] or {}
		onGun[slot] = id
		d.Attachments[weaponName] = if next(onGun) then onGun else nil
	end, true)
end

local function buyAttachment(player: Player, id: any, weaponName: any)
	local attachment = typeof(id) == "string" and Attachments.ById[id]
	local data = PlayerData.Get(player)
	if not attachment or not data or data.OwnedAttachments[attachment.Id] or data.Credits < attachment.Price then
		return
	end
	PlayerData.Update(player, function(d)
		d.Credits -= attachment.Price
		d.OwnedAttachments[attachment.Id] = true
		if typeof(weaponName) == "string" and Attachments.Fits(weaponName, attachment.Id) then
			local onGun = d.Attachments[weaponName] or {}
			onGun[attachment.Slot] = attachment.Id
			d.Attachments[weaponName] = onGun
		end
	end, true)
	Shop:FireClient(player, "Bought", attachment.Id)
end

function ShopService.Start()
	Shop.OnServerEvent:Connect(function(player, action, a, b, c)
		-- (a few requests a second is plenty for clicking around a menu)
		local now = os.clock()
		if now - (lastRequest[player] or 0) < 0.1 then
			return
		end
		lastRequest[player] = now
		if action == "Buy" then
			buy(player, a, b)
		elseif action == "Equip" and typeof(a) == "string" and table.find(Skins.Items, a) then
			equip(player, { a }, b)
		elseif action == "EquipAll" then
			equip(player, Skins.Items, a)
		elseif action == "Attach" then
			attach(player, a, b, c)
		elseif action == "BuyAttachment" then
			buyAttachment(player, a, b)
		end
	end)
	Players.PlayerRemoving:Connect(function(player)
		lastRequest[player] = nil
	end)
end

return ShopService
