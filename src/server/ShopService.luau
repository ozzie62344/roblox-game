-- The skin shop (client Match/ShopMenu) and credits.
--   Shop:FireServer("Buy", skinId, item?)       buy a skin with credits (works on everything),
--                                               and wear it on `item` right away
--   Shop:FireServer("Equip", item, skinId?)     wear an owned skin on "Rifle", "Knife"... (nil =
--                                               the factory look)
--   Shop:FireServer("EquipAll", skinId?)        the same on every gun and the knife
--   Shop:FireClient(player, "Reward", amount, reason)   credits earned (toast on screen)
--   Shop:FireClient(player, "Bought", skinId)           a purchase went through
-- Credits are earned in matches (RoundService, ObjectiveService call Award; amounts in
-- MatchConfig.Credits). Ownership is checked here, never trusted from the client.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Skins = require(ReplicatedStorage.Shared.Skins)
local PlayerData = require(script.Parent.PlayerData)

local Shop = ReplicatedStorage.Remotes.Shop :: RemoteEvent

local ShopService = {}

local lastRequest: { [Player]: number } = {}

-- Gives a player credits and tells them why ("KILL", "ROUND WON"...)
function ShopService.Award(player: Player, amount: number, reason: string)
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

local function buy(player: Player, id: any, item: any)
	local skin = typeof(id) == "string" and Skins.ById[id]
	local data = PlayerData.Get(player)
	if not skin or skin.DevOnly or skin.OnlyFor or not data or data.Skins[skin.Id] or data.Credits < skin.Price then
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

function ShopService.Start()
	Shop.OnServerEvent:Connect(function(player, action, a, b)
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
		end
	end)
	Players.PlayerRemoving:Connect(function(player)
		lastRequest[player] = nil
	end)
end

return ShopService
