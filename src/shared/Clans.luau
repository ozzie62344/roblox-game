-- CLANS: the rules and numbers both sides share. The server (ClanService) checks everything;
-- the clan menu (client Match/ClanMenu) uses this to show the same answers before you ask.
--
-- A clan has a name (3-20 letters, digits, spaces), a TAG (2-4 capital letters / digits, unique
-- across the game), a description (up to 100 characters), a badge (one of Badges) and a type:
--   Open     anyone who meets the requirements joins straight away
--   Request  they ask (with an optional short message); the owner or an officer accepts
--   Invite   members only come in by invite
-- Requirements (Open / Request clans): a minimum level, and optionally a minimum ranked tier
-- (Ranked.Tiers index, 0 = none; you need to be done with your placements to meet one).
-- Roles: Owner (one), Officer, Member.

local Ranked = require(script.Parent.Ranked)

local Clans = {}

Clans.MaxMembers = 20
Clans.CreateCost = 1000 -- credits
Clans.CreateLevel = 5 -- you need to be this level to found a clan
Clans.MaxLevelRequirement = 100
Clans.MaxDescription = 100
Clans.MaxMessage = 60 -- a join request's message
Clans.MaxRequests = 30 -- pending join requests kept per clan (the oldest are dropped)
Clans.MaxLog = 20 -- activity log entries kept per clan

export type ClanType = "Open" | "Request" | "Invite"
export type Role = "Owner" | "Officer" | "Member"

Clans.Types = { "Open", "Request", "Invite" } :: { ClanType }
Clans.TypeLabels = { Open = "OPEN", Request = "REQUEST", Invite = "INVITE ONLY" }
Clans.Roles = { Owner = 3, Officer = 2, Member = 1 } -- (higher outranks lower)

-- Badges: a shape in a colour, drawn from plain frames (client ClanMenu)
export type Badge = { Id: number, Color: Color3, Shape: "Circle" | "Square" | "Diamond" | "Shield" }
Clans.Badges = {
	{ Id = 1, Color = Color3.fromRGB(215, 60, 55), Shape = "Shield" },
	{ Id = 2, Color = Color3.fromRGB(45, 110, 230), Shape = "Shield" },
	{ Id = 3, Color = Color3.fromRGB(80, 190, 60), Shape = "Circle" },
	{ Id = 4, Color = Color3.fromRGB(255, 190, 60), Shape = "Diamond" },
	{ Id = 5, Color = Color3.fromRGB(150, 120, 255), Shape = "Diamond" },
	{ Id = 6, Color = Color3.fromRGB(70, 210, 190), Shape = "Square" },
	{ Id = 7, Color = Color3.fromRGB(255, 120, 40), Shape = "Circle" },
	{ Id = 8, Color = Color3.fromRGB(190, 198, 210), Shape = "Square" },
} :: { Badge }

-- "My Clan  Name " → "My Clan Name" (spaces trimmed and squeezed); nil if it isn't a valid name
function Clans.CleanName(text: any): string?
	if typeof(text) ~= "string" or #text > 60 then
		return nil
	end
	local name = string.gsub(string.gsub(text, "%s+", " "), "^ ", "")
	name = string.gsub(name, " $", "")
	if #name < 3 or #name > 20 or not string.match(name, "^[%w ]+$") then
		return nil
	end
	return name
end

-- "abc" → "ABC"; nil if it isn't 2-4 letters / digits
function Clans.CleanTag(text: any): string?
	if typeof(text) ~= "string" then
		return nil
	end
	local tag = string.upper(text)
	if #tag < 2 or #tag > 4 or not string.match(tag, "^[A-Z0-9]+$") then
		return nil
	end
	return tag
end

-- Free text (description, request message): one line, trimmed, at most `max` characters
function Clans.CleanText(text: any, max: number): string?
	if typeof(text) ~= "string" or #text > max * 4 then
		return nil
	end
	local clean = string.gsub(string.gsub(text, "[%c]", " "), "^%s+", "")
	clean = string.gsub(clean, "%s+$", "")
	if utf8.len(clean) == nil or (utf8.len(clean) :: number) > max then
		return nil
	end
	return clean
end

function Clans.IsType(value: any): boolean
	return typeof(value) == "string" and table.find(Clans.Types, value :: any) ~= nil
end

function Clans.BadgeById(id: any): Badge
	return Clans.Badges[if typeof(id) == "number" then id else 1] or Clans.Badges[1]
end

-- "COPPER", "GOLD"... for a minimum rank (Ranked.Tiers index; 0 = none)
function Clans.RankLabel(minRank: number): string
	local tier = Ranked.Tiers[minRank]
	return if tier then string.upper(tier.Name) else "NONE"
end

-- The ranked tier index a player counts as (0 until they're done with their placements)
function Clans.TierIndex(mmr: number, rankedMatches: number): number
	if not Ranked.IsPlaced(rankedMatches) then
		return 0
	end
	local _, index = Ranked.TierFor(mmr)
	return index
end

-- Whether someone of `level` and ranked tier `tier` (TierIndex) meets a clan's requirements
function Clans.Meets(level: number, tier: number, minLevel: number, minRank: number): (boolean, boolean)
	return level >= minLevel, minRank <= 0 or tier >= minRank
end

return Clans
