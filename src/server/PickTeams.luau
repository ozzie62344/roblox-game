-- Matchmaker's team picker, on its own so it can be tested outside Roblox
-- (tests/PickTeams.test.luau, run with `lune run tests/PickTeams.test.luau`).
--
-- Two full teams of `size` from the front of `list` without splitting a party: the units on each
-- team, or nil if this queue can't make a match yet. A unit is a party (or one player on their
-- own): a list of players. Goes down the queue remembering one way to reach every pair of team
-- counts so far (at most (size + 1)² of them), so a party further back can still fill a gap that
-- the ones in front of it couldn't.

return function<Unit>(list: { { Unit } }, size: number): { { { Unit } } }?
	local stride = size + 1 -- key = (filled on team 1) × stride + (filled on team 2)
	local full = size * stride + size
	local ways: { [number]: { { { Unit } } } } = { [0] = { {}, {} } }
	for _, unit in list do
		local found = {}
		for key, sides in ways do
			local filled = { key // stride, key % stride }
			for side = 1, 2 do
				local newKey = key + #unit * (if side == 1 then stride else 1)
				if filled[side] + #unit <= size and not ways[newKey] and not found[newKey] then
					local copy = { table.clone(sides[1]), table.clone(sides[2]) }
					table.insert(copy[side], unit)
					found[newKey] = copy
				end
			end
		end
		for key, sides in found do
			ways[key] = sides
		end
		if ways[full] then
			return ways[full]
		end
	end
	return nil
end
