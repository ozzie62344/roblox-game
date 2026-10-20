-- Tiny assertion helpers for the Lune tests: each check prints ok / FAIL, finish() errors (non-zero
-- exit) if any failed.

local check = {}

local failures = 0

local function report(name: string, passed: boolean, detail: string?)
	if passed then
		print("ok   " .. name)
	else
		failures += 1
		print("FAIL " .. name .. (if detail then " (" .. detail .. ")" else ""))
	end
end

function check.ok(name: string, passed: boolean, detail: string?)
	report(name, passed, detail)
end

function check.equal(name: string, actual: any, expected: any)
	report(name, actual == expected, `got {tostring(actual)}, expected {tostring(expected)}`)
end

function check.near(name: string, actual: number, expected: number, tolerance: number)
	report(name, math.abs(actual - expected) <= tolerance, `got {actual}, expected {expected}`)
end

function check.finish()
	if failures > 0 then
		error(`{failures} check(s) failed`)
	end
	print("all passed")
end

return check
