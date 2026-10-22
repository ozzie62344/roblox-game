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

local DataStoreService = game:GetService("DataStoreService")
local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Store = require(ReplicatedStorage.Shared.Store)
local GiftInbox = require(script.Parent.GiftInbox)
local PlayerData = require(script.Parent.PlayerData)
local ShopService = require(script.Parent.ShopService)

local Shop = ReplicatedStorage.Remotes.Shop :: RemoteEvent

local StoreService = {}

local RECEIPT_WAIT = 20 -- seconds a receipt waits for the player's data to load (then: ask again later)
local LOAD_WAIT = 120 -- seconds to wait for someone's data on joining before giving up on them
local PASS_TRIES = 3 -- UserOwnsGamePassAsync tries (it's a web call: it can fail)
local IS_STUDIO = RunService:IsStudio()
local GIFT_STORE = "Gifts_v1" -- keys: Inbox_<recipient UserId>, Pending_<buyer UserId>_<gift Key>
local GIFT_CHECK_EVERY = 60 -- seconds between checks of everyone's inbox (gifts bought in another server)
local GIFT_REQUEST_GAP = 3 -- seconds between one player's gift requests

local passes: { [Player]: { [string]: boolean } } = {} -- owned passes by Key, checked once per session
local handling: { [string]: boolean } = {} -- PurchaseIds whose receipt is being handled right now
local lastGiftRequest: { [Player]: number } = {}
local claiming: { [Player]: boolean } = {} -- an inbox claim is running for them

local giftStore: DataStore? = nil
do
	local ok, result = pcall(DataStoreService.GetDataStore, DataStoreService, GIFT_STORE)
	if ok then
		giftStore = result
	end
end

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

-- ─── Gifted passes ─────────────────────────────────────────────────────────────
-- Owned through a gift or the dev panel rather than bought: saved in their data (GiftedPasses)
-- and treated exactly like the real pass (setOwned).

-- Gives `player` the pass `key` for good. False if their data isn't loaded.
function StoreService.GrantPass(player: Player, key: string): boolean
	local pass = Store.PassByKey[key]
	if not pass or not PlayerData.Update(player, function(d)
		d.GiftedPasses[key] = true
	end, true) then
		return false
	end
	setOwned(player, pass)
	return true
end

local function inboxKey(userId: number): string
	return "Inbox_" .. userId
end

local function pendingKey(buyerId: number, gift: Store.Gift): string
	return `Pending_{buyerId}_{gift.Key}`
end

-- Hands over every gift waiting for `player` (bought for them in any server). The pass goes into
-- their data and is saved BEFORE the gift is marked as given, so a failure part way only means it
-- is given again next time (harmless: a pass is owned or not).
local function claimInbox(player: Player)
	local store = giftStore
	if not store or claiming[player] or not PlayerData.Get(player) or not PlayerData.IsSaving(player) then
		return
	end
	claiming[player] = true
	local ok, stored = pcall(store.GetAsync, store, inboxKey(player.UserId))
	local waiting = if ok then GiftInbox.Unclaimed(GiftInbox.Clean(stored)) else {}
	local given: { string } = {}
	for _, entry in waiting do
		if StoreService.GrantPass(player, entry.pass) then
			table.insert(given, entry.id)
			Shop:FireClient(player, "Gifted", entry.from, entry.pass)
		end
	end
	if #given > 0 and PlayerData.SaveNow(player) then
		local marked, err = pcall(store.UpdateAsync, store, inboxKey(player.UserId), function(old)
			local list = GiftInbox.Clean(old)
			GiftInbox.MarkClaimed(list, given)
			return list
		end)
		if not marked then
			warn(`StoreService: couldn't mark {player.Name}'s gifts as given (they'll be given again, harmlessly): {err}`)
		end
	end
	claiming[player] = nil
end

-- Shop:FireServer("Gift", recipient, passKey): check it, remember who it's for (where a receipt
-- can find it even after a server restart), then show the buyer Roblox's purchase prompt
local function requestGift(player: Player, recipient: any, key: any)
	local now = os.clock()
	if now - (lastGiftRequest[player] or 0) < GIFT_REQUEST_GAP then
		return
	end
	lastGiftRequest[player] = now
	local gift = if typeof(key) == "string" then Store.GiftByPass[key] else nil
	local store = giftStore
	if not gift or gift.ProductId == 0 or not store then
		return
	end
	if typeof(recipient) ~= "Instance" or not recipient:IsA("Player") or recipient.Parent ~= Players or recipient == player then
		return
	end
	local pass = Store.PassByKey[gift.Pass]
	if StoreService.HasPass(recipient, gift.Pass) then
		Shop:FireClient(player, "GiftRefused", `{string.upper(recipient.DisplayName)} ALREADY HAS {string.upper(pass.Name)}`)
		return
	end
	local ok, err = pcall(store.SetAsync, store, pendingKey(player.UserId, gift), { to = recipient.UserId, at = os.time() })
	if not ok then
		warn(`StoreService: couldn't save {player.Name}'s gift choice: {err}`)
		Shop:FireClient(player, "GiftRefused", "COULDN'T START THE GIFT · TRY AGAIN")
		return
	end
	MarketplaceService:PromptProductPurchase(player, gift.ProductId)
end

-- A gift product's receipt: into the recipient's inbox (idempotent by PurchaseId). Granted only
-- once that's written; the buyer doesn't need to be in this server.
local function handleGiftReceipt(buyerId: number, gift: Store.Gift, purchaseId: string): Enum.ProductPurchaseDecision
	local store = giftStore
	if not store then
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	local ok, pending = pcall(store.GetAsync, store, pendingKey(buyerId, gift))
	local to = if ok and typeof(pending) == "table" and typeof(pending.to) == "number" then pending.to else nil
	if not to then
		warn(`StoreService: gift receipt {purchaseId} from {buyerId}: no recipient saved`)
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	local buyer = Players:GetPlayerByUserId(buyerId)
	local from = if buyer then buyer.DisplayName else "Someone"
	local written, err = pcall(store.UpdateAsync, store, inboxKey(to), function(old)
		local list = GiftInbox.Clean(old)
		GiftInbox.Add(list, { id = purchaseId, pass = gift.Pass, from = from })
		return list
	end)
	if not written then
		warn(`StoreService: couldn't deliver gift receipt {purchaseId}: {err}`)
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	local recipient = Players:GetPlayerByUserId(to)
	if recipient then
		task.spawn(claimInbox, recipient) -- (they're here: give it now)
	end
	if buyer then
		Shop:FireClient(buyer, "GiftSent", if recipient then recipient.DisplayName else "", gift.Pass)
	end
	return Enum.ProductPurchaseDecision.PurchaseGranted
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
	local gift = Store.GiftById[receipt.ProductId]
	if gift then
		local giftId = tostring(receipt.PurchaseId)
		if handling[giftId] then
			return Enum.ProductPurchaseDecision.NotProcessedYet -- (already on it)
		end
		handling[giftId] = true
		local ok, result = pcall(handleGiftReceipt, receipt.PlayerId, gift, giftId)
		handling[giftId] = nil
		if not ok then
			warn(`StoreService: gift receipt {giftId} failed: {result}`)
			return Enum.ProductPurchaseDecision.NotProcessedYet
		end
		return result
	end
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
	-- Passes they were given (gifts, the dev panel) count as owned
	for key in data.GiftedPasses do
		local pass = Store.PassByKey[key]
		if pass then
			setOwned(player, pass)
		end
	end
	-- Passes checked before their data was in: their skins now
	for _, pass in Store.Passes do
		if StoreService.HasPass(player, pass.Key) then
			givePassSkin(player, pass)
		end
	end
	claimInbox(player) -- (gifts bought for them while they were away)
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
	Shop.OnServerEvent:Connect(function(player, action, a, b)
		if action == "Gift" then
			requestGift(player, a, b)
		end
	end)
	-- Gifts bought in another server turn up within a minute
	task.spawn(function()
		while true do
			task.wait(GIFT_CHECK_EVERY)
			for _, player in Players:GetPlayers() do
				task.spawn(claimInbox, player)
			end
		end
	end)

	Players.PlayerRemoving:Connect(function(player)
		passes[player] = nil
		lastGiftRequest[player] = nil
		claiming[player] = nil
	end)
end

return StoreService
