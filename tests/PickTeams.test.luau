-- Tests for the matchmaker's team picker (src/server/PickTeams.luau).
-- Run from the repo root: lune run tests/PickTeams.test.luau
-- Players are plain strings here; a unit (party or solo) is a list of them.

local PickTeams = require("../src/server/PickTeams")

local failures = 0
local function check(name: string, ok: boolean, detail: string?)
	if ok then
		print("ok   " .. name)
	else
		failures += 1
		print("FAIL " .. name .. (if detail then " (" .. detail .. ")" else ""))
	end
end

-- How many players a side has
local function count(side: { { string } }): number
	local total = 0
	for _, unit in side do
		total += #unit
	end
	return total
end

-- Each unit is the same table the queue had: a party is placed whole or not at all
local function wholeUnits(sides: { { { string } } }, list: { { string } }): boolean
	for _, side in sides do
		for _, unit in side do
			if not table.find(list, unit) then
				return false
			end
		end
	end
	return true
end

local function sizesText(sides: { { { string } } }?): string
	return if sides then `{count(sides[1])}v{count(sides[2])}` else "no match"
end

-- 1v1: two solos make a match
do
	local list = { { "a" }, { "b" } }
	local sides = PickTeams(list, 1)
	check("1v1 from two solos", sides ~= nil and count(sides[1]) == 1 and count(sides[2]) == 1, sizesText(sides))
end

-- Not enough players yet
do
	local sides = PickTeams({ { "a" }, { "b" }, { "c" } }, 2)
	check("2v2 needs four players", sides == nil, sizesText(sides))
end

-- A party of 3 can't fit a 2v2, and one solo isn't a team: no match
do
	local sides = PickTeams({ { "a", "b", "c" }, { "d" } }, 2)
	check("party of 3 never fits 2v2", sides == nil, sizesText(sides))
end

-- 4v4 from 2+2+1+1+1+1: full teams, nobody split
do
	local list = { { "a", "b" }, { "c", "d" }, { "e" }, { "f" }, { "g" }, { "h" } }
	local sides = PickTeams(list, 4)
	check("4v4 from 2+2+1+1+1+1", sides ~= nil and count(sides[1]) == 4 and count(sides[2]) == 4, sizesText(sides))
	check("4v4 keeps parties whole", sides ~= nil and wholeUnits(sides :: any, list))
end

-- A party further back fills the gap the ones in front couldn't: 3 + 3 + 1 + 1 for 4v4 needs
-- the two solos split across the teams (3+1 / 3+1)
do
	local list = { { "a", "b", "c" }, { "d", "e", "f" }, { "g" }, { "h" } }
	local sides = PickTeams(list, 4)
	check("4v4 from 3+3+1+1", sides ~= nil and count(sides[1]) == 4 and count(sides[2]) == 4, sizesText(sides))
end

-- 3v3 from a party of 2 behind two parties of 3 that can't both fit with it: takes the two 3s
do
	local list = { { "a", "b", "c" }, { "d", "e" }, { "f", "g", "h" } }
	local sides = PickTeams(list, 3)
	check("3v3 from 3+2+3 uses the two 3s", sides ~= nil and count(sides[1]) == 3 and count(sides[2]) == 3 and wholeUnits(sides :: any, list), sizesText(sides))
end

-- Nobody is placed twice
do
	local list = { { "a" }, { "b" }, { "c" }, { "d" }, { "e" } }
	local sides = PickTeams(list, 2)
	local seen, twice = {}, false
	for _, side in sides or {} do
		for _, unit in side do
			for _, name in unit do
				twice = twice or seen[name] == true
				seen[name] = true
			end
		end
	end
	check("2v2 from five solos places four, once each", sides ~= nil and not twice and count(sides[1]) == 2 and count(sides[2]) == 2, sizesText(sides))
end

if failures > 0 then
	error(`{failures} test(s) failed`)
end
print("all passed")
