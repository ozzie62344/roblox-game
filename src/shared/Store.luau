-- The ROBUX store (the shop's ROBUX tab: client Match/ShopMenu; purchases: server StoreService).
--
-- ┌─ SETTING IT UP (the game's owner, once) ─────────────────────────────────────────────────┐
-- │ Everything here ships with Id 0: its button says COMING SOON and nothing can be bought    │
-- │ until you paste in a real Id. To make them real:                                          │
-- │                                                                                           │
-- │ 1. Publish the game, then open create.roblox.com → Creations → this experience.           │
-- │ 2. Credit packs and the Starter Pack are DEVELOPER PRODUCTS (can be bought again and      │
-- │    again; the Starter Pack is limited to once by the game itself):                        │
-- │      Monetization → Developer Products → Create a Developer Product. Name it like the     │
-- │      Name below, set the price (Robux below), save, then copy its Product ID (the number  │
-- │      in the list, or "Copy Asset ID" in its ⋯ menu) into that entry's ProductId.          │
-- │ 3. VIP and Double XP are GAME PASSES (bought once, kept forever):                         │
-- │      Monetization → Passes → Create a Pass. Name + icon, create it, then open it → Sales  │
-- │      → "Item for Sale" on, price (Robux below), save. Copy its ID (the number in the      │
-- │      pass's URL, or "Copy Asset ID") into that entry's GamePassId.                        │
-- │ 4. Publish again. In Studio the BUY buttons open Roblox's test-purchase dialog: nothing    │
-- │    is charged, and the purchase is granted like a real one (with "Enable Studio Access    │
-- │    to API Services" on, so it saves).                                                     │
-- │                                                                                           │
-- │ Robux below is only what the shop SHOWS: the price you set on the dashboard is what       │
-- │ players actually pay, so keep the two the same. Never reuse or change the Key of an item  │
-- │ people have bought (saved data refers to it).                                             │
-- └───────────────────────────────────────────────────────────────────────────────────────────┘
--
-- Perks (StoreService applies them; clients read player attributes the server sets):
--   VIP         credits from matches x1.5 (kills, rounds, wins... not challenges, daily rewards
--               or level rewards), a gold [VIP] chat tag, and the VIP-only skin (Skins PassOnly)
--   Double XP   XP from matches x2 (same rule: not the XP for finishing a challenge)
--   Starter Pack (one time) 1,000 credits and its own skin (Skins PassOnly)

export type Product = {
	Key: string, -- never change: saved in player data / used by Skins PassOnly
	Name: string,
	ProductId: number, -- the Developer Product's ID (0 = not set up yet: COMING SOON)
	Robux: number, -- shown on the BUY button (match the dashboard price)
	Credits: number,
	Bonus: number?, -- about how many percent extra over the smallest pack's rate, for the badge ("+20%")
	OneTime: boolean?, -- can only be bought once (the Starter Pack)
	Skin: string?, -- a skin id (shared/Skins) that comes with it
	Description: string?,
}

export type Pass = {
	Key: string, -- also the player attribute the server sets to true when they own it
	Name: string,
	GamePassId: number, -- the Game Pass's ID (0 = not set up yet: COMING SOON)
	Robux: number,
	CreditMultiplier: number?, -- on credits from matches
	XpMultiplier: number?, -- on XP from matches
	Skin: string?, -- a skin id (shared/Skins) that comes with it
	Perks: { string }, -- lines on its card
}

local Store = {}

-- Credit packs, smallest first (the bigger the pack, the more credits per Robux)
Store.CreditPacks = {
	{ Key = "Credits500", Name = "500 Credits", ProductId = 0, Robux = 49, Credits = 500 },
	{ Key = "Credits1200", Name = "1,200 Credits", ProductId = 0, Robux = 99, Credits = 1200, Bonus = 20 },
	{ Key = "Credits2800", Name = "2,800 Credits", ProductId = 0, Robux = 199, Credits = 2800, Bonus = 40 },
	{ Key = "Credits6500", Name = "6,500 Credits", ProductId = 0, Robux = 399, Credits = 6500, Bonus = 60 },
} :: { Product }

-- One per player, ever
Store.StarterPack = {
	Key = "StarterPack",
	Name = "Starter Pack",
	ProductId = 0,
	Robux = 99,
	Credits = 1000,
	Skin = "Vanguard",
	OneTime = true,
	Description = "1,000 credits + the Vanguard skin. One per player!",
} :: Product

Store.Passes = {
	{
		Key = "VIP",
		Name = "VIP",
		GamePassId = 0,
		Robux = 299,
		CreditMultiplier = 1.5,
		Skin = "Royal",
		Perks = { "x1.5 credits from matches", "Royal Guard skin", "Gold [VIP] chat tag" },
	},
	{
		Key = "DoubleXp",
		Name = "Double XP",
		GamePassId = 0,
		Robux = 199,
		XpMultiplier = 2,
		Perks = { "x2 XP from matches", "Level up twice as fast", "More track rewards, sooner" },
	},
} :: { Pass }

-- Lookups (only items that are set up: Id 0 is skipped)
Store.Products = {} :: { Product }
Store.ProductById = {} :: { [number]: Product }
Store.PassById = {} :: { [number]: Pass }
Store.ByKey = {} :: { [string]: Product | Pass }

for _, product in Store.CreditPacks do
	table.insert(Store.Products, product)
end
table.insert(Store.Products, Store.StarterPack)
for _, product in Store.Products do
	Store.ByKey[product.Key] = product
	if product.ProductId ~= 0 then
		Store.ProductById[product.ProductId] = product
	end
end
for _, pass in Store.Passes do
	Store.ByKey[pass.Key] = pass
	if pass.GamePassId ~= 0 then
		Store.PassById[pass.GamePassId] = pass
	end
end

-- Owns the pass (or the one-time product): the server sets these attributes, clients read them
function Store.Owns(player: Player, key: string): boolean
	return player:GetAttribute(key) == true
end

return Store
