-- The list of gifts waiting for someone (StoreService keeps one per recipient in a DataStore), as
-- plain functions so they can be tested outside Roblox (tests/GiftInbox.test.luau).
-- An entry is { id = PurchaseId, pass = Store pass Key, from = buyer's name, claimed = true once
-- it's been given }. Claimed entries stay a while so a receipt Roblox asks about again is still
-- recognised and never delivered twice.

export type Entry = { id: string, pass: string, from: string, claimed: boolean? }

local GiftInbox = {}

GiftInbox.KeepClaimed = 50 -- claimed entries kept (the oldest go first); unclaimed ones are never dropped

-- Whatever came out of the DataStore, as a clean list (anything malformed dropped)
function GiftInbox.Clean(stored: any): { Entry }
	local list = {}
	if type(stored) ~= "table" then
		return list
	end
	for _, entry in stored do
		if type(entry) == "table" and type(entry.id) == "string" and type(entry.pass) == "string" then
			table.insert(list, {
				id = entry.id,
				pass = entry.pass,
				from = if type(entry.from) == "string" then entry.from else "Someone",
				claimed = if entry.claimed == true then true else nil,
			})
		end
	end
	return list
end

function GiftInbox.Has(list: { Entry }, id: string): boolean
	for _, entry in list do
		if entry.id == id then
			return true
		end
	end
	return false
end

-- Adds `entry` unless its id is already there (a receipt asked about again). True if added.
-- Then trims the oldest claimed entries past KeepClaimed.
function GiftInbox.Add(list: { Entry }, entry: Entry): boolean
	if GiftInbox.Has(list, entry.id) then
		return false
	end
	table.insert(list, { id = entry.id, pass = entry.pass, from = entry.from })
	local claimed = 0
	for _, e in list do
		if e.claimed then
			claimed += 1
		end
	end
	local i = 1
	while claimed > GiftInbox.KeepClaimed and i <= #list do
		if list[i].claimed then
			table.remove(list, i)
			claimed -= 1
		else
			i += 1
		end
	end
	return true
end

-- The entries still to be given, oldest first
function GiftInbox.Unclaimed(list: { Entry }): { Entry }
	local result = {}
	for _, entry in list do
		if not entry.claimed then
			table.insert(result, entry)
		end
	end
	return result
end

-- Marks the entries with these ids as given
function GiftInbox.MarkClaimed(list: { Entry }, ids: { string })
	for _, entry in list do
		if table.find(ids, entry.id) then
			entry.claimed = true
		end
	end
end

return GiftInbox
