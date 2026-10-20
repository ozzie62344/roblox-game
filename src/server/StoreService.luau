-- The ROBUX store: credit packs and game passes (the Starter Pack, VIP, Double XP). What's for
-- sale and the IDs: shared/Store; the shop's ROBUX tab: client Match/ShopMenu. The client only
-- opens Roblox's own purchase prompt: everything is granted here, after Roblox says it was paid for.
--
-- Developer products (credit packs): Roblox calls ProcessReceipt, again and again (now, when the
-- player next joins any server...) until we answer PurchaseGranted. So:
--   - each receipt's PurchaseId is kept in the player's data (PlayerData Purchases, the last 200):
--     a receipt we've already granted is only confirmed, never granted twice
--   - the grant and its PurchaseId go in together (one PlayerData.Update), and PurchaseGranted is
--     only answered once that's saved (PlayerData.SaveNow). Player not here, data not loaded, the
--     DataStore down or the save failing → NotProcessedYet, and Roblox asks again later.
--   - Studio without a DataStore: granted for the session only (test purchases are free anyway)
--
-- Game passes (the Starter Pack, VIP, Double XP): checked when a player joins
-- (UserOwnsGamePassAsync, kept for the session) and the moment they buy one in-game
-- (PromptGamePassPurchaseFinished). Owning one sets the player attribute named after its Key
-- ("StarterPack", "VIP", "DoubleXp") for clients, and gives its skin.
-- The Starter Pack's 1,000 credits and skin are granted once ever (grantStarterPack), whenever we
-- see they own it (bought in-game, or on joining) and their saved StarterPackGranted flag isn't
-- set. That covers a purchase made outside the game, and one whose grant didn't get saved.
--   StoreService.HasPass(player, key)        owns the pass ("VIP", "DoubleXp")
--   StoreService.CreditMultiplier(player)    x match credits (ShopService: match reasons only)
--   StoreService.XpMultiplier(player)        x match XP (ProgressService.Record: the event's XP,
--                                            not the XP for finishing a challenge)
--   Shop:FireClient(player, "Store", key)    a purchase was granted (the shop's banner)
-- Items whose ProductId / GamePassId is still 0 are skipped (the shop shows COMING SOON).

local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Store = require(ReplicatedStorage.Shared.Store)
local PlayerData = require(script.Parent.PlayerData)
local ShopService = require(script.Parent.ShopService)

local Shop = ReplicatedStorage.Remotes.Shop :: RemoteEvent

local StoreService = {}

local RECEIPT_WAIT = 20 -- seconds a receipt waits for the player's data to load (then: ask again later)
local LOAD_WAIT = 120 -- seconds to wait for someone's data on joining before giving up on them
local PASS_TRIES = 3 -- UserOwnsGamePassAsync tries (it's a web call: it can fail)
local IS_STUDIO = RunService:IsStudio()

local passes: { [Player]: { [string]: boolean } } = {} -- owned passes by Key, checked once per session
local handling: { [string]: boolean } = {} -- PurchaseIds whose receipt is being handled right now

function StoreService.HasPass(player: Player, key: string): boolean
	local owned = passes[player]
	return owned ~= nil and owned[key] == true
end

-- Every owned pass's multiplier for `field` ("CreditMultiplier", "XpMultiplier"), multiplied together
local function multiplier(player: Player, field: string): number
	local result = 1
	for _, pass in Store.Passes do
		local value = (pass :: any)[field]
		if typeof(value) == "number" and StoreService.HasPass(player, pass.Key) then
			result *= value
		end
	end
	return result
end

function StoreService.CreditMultiplier(player: Player): number
	return multiplier(player, "CreditMultiplier")
end

function StoreService.XpMultiplier(player: Player): number
	return multiplier(player, "XpMultiplier")
end

local function waitForData(player: Player, timeout: number): PlayerData.Data?
	local waited = 0
	while player.Parent and not PlayerData.Get(player) and waited < timeout do
		waited += task.wait(0.5)
	end
	return if player.Parent then PlayerData.Get(player) else nil
end

-- ─── Game passes ───────────────────────────────────────────────────────────────

-- The pass's skin into their skins (once their data is in; joining checks again)
local function givePassSkin(player: Player, pass: Store.Pass)
	local skinId = pass.Skin
	local data = PlayerData.Get(player)
	if skinId and data and not data.Skins[skinId] then
		PlayerData.Update(player, function(d)
			d.Skins[skinId] = true
		end, true)
	end
end

-- The Starter Pack's credits and skin, once ever. Safe to run any number of times, even at the
-- same time: the saved StarterPackGranted flag is checked and set in the same Update as the grant.
local function grantStarterPack(player: Player)
	if not waitForData(player, LOAD_WAIT) then
		return -- (left, or no data: the next join tries again)
	end
	local pack = Store.StarterPack
	local granted = false
	PlayerData.Update(player, function(d)
		if d.StarterPackGranted then
			return
		end
		d.StarterPackGranted = true
		d.Credits += pack.Credits or 0
		if pack.Skin then
			d.Skins[pack.Skin] = true
		end
		granted = true
	end, true) -- (saved straight away)
	if granted then
		Shop:FireClient(player, "Reward", pack.Credits or 0, string.upper(pack.Name))
	end
end

local function setOwned(player: Player, pass: Store.Pass)
	local owned = passes[player]
	if not owned or not player.Parent then
		return -- (left)
	end
	owned[pass.Key] = true
	player:SetAttribute(pass.Key, true)
	givePassSkin(player, pass)
	if pass == Store.StarterPack then
		task.spawn(grantStarterPack, player) -- (bought just now, or owned when they joined)
	end
end

local function checkPass(player: Player, pass: Store.Pass)
	for attempt = 1, PASS_TRIES do
		local ok, result = pcall(MarketplaceService.UserOwnsGamePassAsync, MarketplaceService, player.UserId, pass.GamePassId)
		if ok then
			if result then
				setOwned(player, pass)
			end
			return
		end
		warn(`StoreService: couldn't check {player.Name}'s {pass.Name} pass: {result}`)
		if attempt < PASS_TRIES then
			task.wait(2 * attempt)
		end
		if not player.Parent then
			return
		end
	end
end

-- ─── Developer products ────────────────────────────────────────────────────────

-- (inside a PlayerData.Update) What the product gives, and the receipt noted as granted
local function grant(d: PlayerData.Data, product: Store.Product, purchaseId: string)
	d.Credits += product.Credits
	table.insert(d.Purchases, purchaseId)
	while #d.Purchases > PlayerData.PurchaseHistory do
		table.remove(d.Purchases, 1)
	end
end

local function handleReceipt(player: Player, product: Store.Product, purchaseId: string): Enum.ProductPurchaseDecision
	local data = waitForData(player, RECEIPT_WAIT)
	if not data then
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	-- No DataStore: on a live server that's an outage, so wait it out (Roblox asks again later).
	-- In Studio it usually means API access is off: grant it for this session.
	local saving = PlayerData.IsSaving(player)
	if not saving and not IS_STUDIO then
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	if table.find(data.Purchases, purchaseId) then
		-- Granted before (Roblox asking again): confirm once that's saved
		if saving and not PlayerData.SaveNow(player) then
			return Enum.ProductPurchaseDecision.NotProcessedYet
		end
		return Enum.ProductPurchaseDecision.PurchaseGranted
	end

	PlayerData.Update(player, function(d)
		grant(d, product, purchaseId)
	end)
	Shop:FireClient(player, "Reward", product.Credits, "PURCHASE")
	Shop:FireClient(player, "Store", product.Key)

	-- Only confirmed once it's saved. If the save fails, Roblox asks again later, and the
	-- PurchaseId now in their data (saved with the next save) stops a second grant.
	if saving and not PlayerData.SaveNow(player) then
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	return Enum.ProductPurchaseDecision.PurchaseGranted
end

local function processReceipt(receipt: { [string]: any }): Enum.ProductPurchaseDecision
	local player = Players:GetPlayerByUserId(receipt.PlayerId)
	local product = Store.ProductById[receipt.ProductId]
	if not player then
		return Enum.ProductPurchaseDecision.NotProcessedYet -- (granted when they're next in a server)
	end
	if not product then
		warn(`StoreService: a receipt for product {receipt.ProductId}, which isn't in shared/Store`)
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	local purchaseId = tostring(receipt.PurchaseId)
	if handling[purchaseId] then
		return Enum.ProductPurchaseDecision.NotProcessedYet -- (already on it)
	end
	handling[purchaseId] = true
	local ok, result = pcall(handleReceipt, player, product, purchaseId)
	handling[purchaseId] = nil
	if not ok then
		warn(`StoreService: receipt {purchaseId} for {player.Name} failed: {result}`)
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	return result
end

-- ─── Joining ───────────────────────────────────────────────────────────────────

local function onPlayerAdded(player: Player)
	passes[player] = {}
	for _, pass in Store.Passes do
		if pass.GamePassId ~= 0 then
			task.spawn(checkPass, player, pass)
		end
	end
	local data = waitForData(player, LOAD_WAIT)
	if not data then
		return
	end
	-- Passes checked before their data was in: their skins now
	for _, pass in Store.Passes do
		if StoreService.HasPass(player, pass.Key) then
			givePassSkin(player, pass)
		end
	end
end

function StoreService.Start()
	MarketplaceService.ProcessReceipt = processReceipt
	ShopService.SetMatchMultiplier(StoreService.CreditMultiplier)

	-- (fires on the server too, from Roblox: a client can't fake it)
	MarketplaceService.PromptGamePassPurchaseFinished:Connect(function(player, gamePassId, purchased)
		local pass = Store.PassById[gamePassId]
		if purchased and pass and not StoreService.HasPass(player, pass.Key) then
			setOwned(player, pass)
			Shop:FireClient(player, "Store", pass.Key)
		end
	end)

	for _, player in Players:GetPlayers() do
		task.spawn(onPlayerAdded, player)
	end
	Players.PlayerAdded:Connect(onPlayerAdded)
	Players.PlayerRemoving:Connect(function(player)
		passes[player] = nil
	end)
end

return StoreService
