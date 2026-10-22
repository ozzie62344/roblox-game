-- Tests for the gift inbox list (src/server/GiftInbox.luau), loaded unchanged.
-- Run from the repo root: lune run tests/GiftInbox.test.luau

local load = require("./roblox")
local check = require("./check")
local GiftInbox = load("src/server/GiftInbox")

-- Adding is idempotent by purchase id (Roblox can ask about a receipt again)
local list = {}
check.ok("a new gift is added", GiftInbox.Add(list, { id = "p1", pass = "VIP", from = "Ann" }))
check.ok("the same purchase again is not", not GiftInbox.Add(list, { id = "p1", pass = "VIP", from = "Ann" }))
check.equal("one entry", #list, 1)

-- Claiming
GiftInbox.Add(list, { id = "p2", pass = "DoubleXp", from = "Bo" })
check.equal("two waiting", #GiftInbox.Unclaimed(list), 2)
GiftInbox.MarkClaimed(list, { "p1" })
local waiting = GiftInbox.Unclaimed(list)
check.ok("only p2 is left to give", #waiting == 1 and waiting[1].id == "p2")
check.ok("a claimed gift is still recognised", not GiftInbox.Add(list, { id = "p1", pass = "VIP", from = "Ann" }))

-- Trimming keeps every unclaimed gift and at most KeepClaimed claimed ones (the newest)
local big = {}
for i = 1, GiftInbox.KeepClaimed + 10 do
	GiftInbox.Add(big, { id = "c" .. i, pass = "VIP", from = "X" })
	GiftInbox.MarkClaimed(big, { "c" .. i })
end
GiftInbox.Add(big, { id = "new", pass = "VIP", from = "X" })
local claimed = 0
for _, e in big do
	claimed += if e.claimed then 1 else 0
end
check.equal("claimed entries capped", claimed, GiftInbox.KeepClaimed)
check.ok("the oldest claimed went first", not GiftInbox.Has(big, "c1") and GiftInbox.Has(big, "c" .. (GiftInbox.KeepClaimed + 10)))
check.ok("the unclaimed gift is kept", GiftInbox.Has(big, "new") and #GiftInbox.Unclaimed(big) == 1)

-- Cleaning stored data
local clean = GiftInbox.Clean({ { id = "a", pass = "VIP", from = "Z", claimed = true }, { id = 5 }, "junk", { id = "b", pass = "VIP" } })
check.equal("malformed entries dropped", #clean, 2)
check.equal("a missing name becomes Someone", clean[2].from, "Someone")
check.equal("not a table: empty", #GiftInbox.Clean(nil), 0)

check.finish()
