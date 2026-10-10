-- First-person animations (reloads per gun, plus the draw when you pull a gun out).
-- Viewmodel.luau plays these.
--
-- An animation is a list of keyframes over time (t = 0 → 1 of the reload time). Between two
-- keyframes everything blends smoothly. A keyframe can set:
--   gun    = CFrame   how the gun is moved/tilted from its normal spot (camera space)
--   left   = Hand     where the left hand is   (right = same for the right hand)
--   groups = { [name] = Part }   where a moving piece of the gun is (Magazine, Bolt, Pump, ...)
--   hide   = { name = true }     pieces that are invisible from this keyframe until the next one
--   events = { "MagOut", ... }   sounds to play when this keyframe is reached
--   ease   = "inOut" | "in" | "out" | "linear" | "back"   how it moves INTO this keyframe
-- Anything a keyframe leaves out stays as it was in the keyframe before.
--
-- Hands:
--   { "grip" }                    on its normal spot on the gun
--   { "gun", CFrame }             a spot on the gun (gun model space; same axes as a grip:
--                                 Y = along the handle toward the thumb)
--   { "camera", CFrame }          a spot relative to your eyes (e.g. a pouch down by your belt)
--   { "group", name, CFrame? }    holding a moving piece (CFrame relative to that piece; leave it
--                                 out to keep the hand where it normally is relative to the piece,
--                                 e.g. the left hand riding along with the shotgun pump)
-- Pieces:
--   { "rest" }                    in place
--   { "gun", CFrame }             moved from its normal place (in its own space, gun axes)
--   { "hand", "Left" | "Right", CFrame }   carried in a hand
--   { "on", otherPiece, CFrame }  placed relative to another piece (speedloader on the cylinder)
--
-- Gun model axes: -Z = toward the muzzle, +Y = up, +X = the gun's right side.

export type Hand = { any }
export type Piece = { any }
export type Keyframe = {
	t: number,
	ease: string?,
	gun: CFrame?,
	left: Hand?,
	right: Hand?,
	groups: { [string]: Piece }?,
	hide: { [string]: boolean }?,
	events: { string }?,
}
export type Info = {
	empty: boolean, -- the magazine was empty (bolt / slide needs working)
	rounds: number, -- how many rounds are missing (shotgun loads shells one at a time)
	grips: { Left: CFrame, Right: CFrame }, -- normal hand spots (gun space)
	groups: { [string]: { rest: CFrame, size: Vector3 } }, -- moving pieces and their size
	points: { [string]: Vector3 }, -- positions of named gun parts (gun space)
}

local ReloadAnimations = {}

local function deg(x: number, y: number, z: number): CFrame
	return CFrame.Angles(math.rad(x), math.rad(y), math.rad(z))
end

-- Off-screen spot by the belt where fresh mags / shells / speedloaders come from
local POUCH = CFrame.new(-0.55, -1.35, -0.55) * deg(-50, 20, 30)

-- A hand gripping a piece from its left side: same orientation as the left hand's normal grip
local function grabOn(info: Info, offset: Vector3): CFrame
	return CFrame.new(offset) * info.grips.Left.Rotation
end

-- Turns a piece about an axis parallel to the barrel through `pivot` (in the piece's own space)
local function spinAbout(pivot: Vector3, degrees: number): CFrame
	return CFrame.new(pivot) * CFrame.Angles(0, 0, math.rad(degrees)) * CFrame.new(-pivot)
end

local function pieceSize(info: Info, name: string): Vector3
	local group = info.groups[name]
	return if group then group.size else Vector3.new(0.15, 0.4, 0.2)
end

-- ── Box-magazine swap, shared by the rifle, SMG, sniper, marksman and LMG ──
-- Left hand grabs the mag, strips it out (it falls away), fetches a new one from the pouch,
-- brings it under the mag well, seats it with a push, taps it. Times are fractions of the reload.
-- `grabAt` = where on the mag the hand holds it (its own space), for mags that aren't slim.
local function magSwap(info: Info, from: number, to: number, tilt: CFrame, grabAt: Vector3?): { Keyframe }
	local size = pieceSize(info, "Magazine")
	local grab = grabOn(info, grabAt or Vector3.new(-0.02, -size.Y * 0.25, 0))
	local function at(f: number): number
		return from + (to - from) * f
	end
	return {
		{ t = at(0.12), ease = "inOut", gun = tilt, left = { "group", "Magazine", grab } },
		{ t = at(0.24), ease = "out", groups = { Magazine = { "gun", CFrame.new(0, -0.34, 0.05) } }, events = { "MagOut" } },
		-- Old mag drops away while the hand heads to the pouch
		{
			t = at(0.36),
			ease = "in",
			groups = { Magazine = { "gun", CFrame.new(0.05, -1.6, 0.5) * deg(35, 0, 10) } },
			left = { "camera", POUCH },
		},
		{ t = at(0.48), ease = "inOut", hide = { Magazine = true }, left = { "camera", POUCH } },
		-- New mag in hand, brought up under the well
		{
			t = at(0.52),
			ease = "linear",
			groups = { Magazine = { "hand", "Left", grab:Inverse() } },
			left = { "camera", POUCH },
		},
		{
			t = at(0.78),
			ease = "inOut",
			groups = { Magazine = { "gun", CFrame.new(0, -0.4, 0.08) * deg(-6, 0, 0) } },
			left = { "group", "Magazine", grab },
		},
		-- Seat it with a firm push (overshoots a touch, settles)
		{
			t = at(0.9),
			ease = "back",
			groups = { Magazine = { "rest" } },
			left = { "group", "Magazine", grab },
			gun = tilt * CFrame.new(0, 0.025, 0),
			events = { "MagIn" },
		},
		{ t = at(1), ease = "out", gun = tilt, left = { "group", "Magazine", grab * CFrame.new(0, -0.06, 0) } },
	}
end

local function append(list: { Keyframe }, more: { Keyframe })
	for _, keyframe in more do
		table.insert(list, keyframe)
	end
end

local CLIPS: { [string]: (info: Info) -> { Keyframe } } = {}

-- AR-15: cant the rifle, swap the mag, slap the bolt release if it was empty
CLIPS.Rifle = function(info)
	local tilt = CFrame.new(-0.06, -0.05, 0.02) * deg(8, -8, -26)
	local keys: { Keyframe } = { { t = 0, gun = CFrame.new(), left = { "grip" }, groups = { Magazine = { "rest" } } } }
	append(keys, magSwap(info, 0.02, if info.empty then 0.74 else 0.84, tilt))
	if info.empty then
		local catch = info.points.BoltCatch or Vector3.new(-0.1, -0.02, 0.05)
		table.insert(keys, { t = 0.82, ease = "inOut", left = { "gun", grabOn(info, catch + Vector3.new(-0.12, 0, 0)) } })
		table.insert(keys, { t = 0.86, ease = "back", left = { "gun", grabOn(info, catch) }, gun = tilt * deg(-3, 0, 0), events = { "BoltForward" } })
	end
	table.insert(keys, { t = 1, ease = "inOut", gun = CFrame.new(), left = { "grip" } })
	return keys
end

-- MP5: on empty, lock the cocking handle back first; swap the mag; "HK slap" it closed
CLIPS.SMG = function(info)
	local tilt = CFrame.new(-0.05, -0.05, 0.02) * deg(6, -6, -24)
	local handleGrab = grabOn(info, Vector3.new(-0.06, 0, 0))
	local keys: { Keyframe } = { { t = 0, gun = CFrame.new(), left = { "grip" }, groups = { Magazine = { "rest" }, CockingHandle = { "rest" } } } }
	local swapFrom = 0.02
	if info.empty then
		local locked = CFrame.new(0, 0, 0.3) * deg(0, 0, 35)
		table.insert(keys, { t = 0.1, ease = "inOut", gun = tilt * deg(0, 8, 0), left = { "group", "CockingHandle", handleGrab } })
		table.insert(keys, { t = 0.18, ease = "out", groups = { CockingHandle = { "gun", CFrame.new(0, 0, 0.3) } }, events = { "BoltBack" } })
		table.insert(keys, { t = 0.22, ease = "out", groups = { CockingHandle = { "gun", locked } } })
		swapFrom = 0.22
	end
	append(keys, magSwap(info, swapFrom, if info.empty then 0.8 else 0.86, tilt))
	if info.empty then
		local locked = CFrame.new(0, 0, 0.3) * deg(0, 0, 35)
		table.insert(keys, { t = 0.86, ease = "inOut", groups = { CockingHandle = { "gun", locked } }, left = { "group", "CockingHandle", handleGrab * CFrame.new(-0.15, 0.1, 0) } })
		-- The slap: hand hits the handle down, it snaps forward
		table.insert(keys, { t = 0.9, ease = "in", groups = { CockingHandle = { "rest" } }, left = { "group", "CockingHandle", handleGrab }, gun = tilt * deg(-4, 0, 0), events = { "Slap" } })
	end
	table.insert(keys, { t = 1, ease = "inOut", gun = CFrame.new(), left = { "grip" } })
	return keys
end

-- Pump shotgun: roll it to show the loading port, thumb shells in one by one, rack if empty
CLIPS.Shotgun = function(info)
	local tilt = CFrame.new(-0.08, -0.1, 0.05) * deg(14, -10, -38)
	local port = info.points.LoadingPort or Vector3.new(0, -0.18, 0.15)
	local holder = info.points.Shell or Vector3.new(-0.12, 0, 0.35)
	local shellInHand = CFrame.new(0, 0.02, -0.04) * deg(90, 0, 0) -- shell held between thumb and fingers
	local keys: { Keyframe } = {
		{ t = 0, gun = CFrame.new(), left = { "grip" }, groups = { Pump = { "rest" }, LooseShell = { "rest" } }, hide = { LooseShell = true } },
		{ t = 0.08, ease = "inOut", gun = tilt, left = { "gun", grabOn(info, holder) } },
	}
	local shells = math.clamp(info.rounds, 1, 4)
	local start, finish = 0.08, if info.empty then 0.78 else 0.9
	local each = (finish - start) / shells
	for i = 1, shells do
		local t0 = start + (i - 1) * each
		local atHolder = grabOn(info, holder)
		local underPort = grabOn(info, port + Vector3.new(-0.02, -0.12, 0.12))
		local inPort = grabOn(info, port + Vector3.new(-0.02, -0.02, 0.02))
		-- Take a shell from the side holder...
		table.insert(keys, { t = t0 + each * 0.15, ease = "inOut", left = { "gun", atHolder }, groups = { LooseShell = { "hand", "Left", shellInHand } } })
		-- ...bring it under the port...
		table.insert(keys, { t = t0 + each * 0.55, ease = "inOut", left = { "gun", underPort } })
		-- ...and push it up in with the thumb (it disappears into the tube)
		table.insert(keys, { t = t0 + each * 0.8, ease = "out", left = { "gun", inPort }, gun = tilt * CFrame.new(0, 0.015, 0), events = { "ShellIn" } })
		table.insert(keys, { t = t0 + each * 0.95, ease = "inOut", hide = { LooseShell = true }, left = { "gun", underPort }, gun = tilt })
	end
	if info.empty then
		-- Back on the pump and rack it: back, then forward
		table.insert(keys, { t = 0.84, ease = "inOut", gun = CFrame.new(0, -0.03, 0.02) * deg(4, -4, -8), left = { "group", "Pump" }, groups = { Pump = { "rest" } } })
		table.insert(keys, { t = 0.89, ease = "out", groups = { Pump = { "gun", CFrame.new(0, 0, 0.32) } }, events = { "PumpBack" } })
		table.insert(keys, { t = 0.94, ease = "out", groups = { Pump = { "rest" } }, events = { "PumpForward" } })
	end
	table.insert(keys, { t = 1, ease = "inOut", gun = CFrame.new(), left = { "grip" }, groups = { Pump = { "rest" } } })
	return keys
end

-- Bolt action: right hand opens the bolt (up, back), left hand swaps the mag, bolt closes
CLIPS.Sniper = function(info)
	local tilt = CFrame.new(-0.05, -0.08, 0.05) * deg(6, -6, -16)
	local bolt = info.groups.Bolt
	local axis = (info.points.BoltShroud or Vector3.new(0, 0.05, 0.3)) - (if bolt then bolt.rest.Position else Vector3.zero)
	local knob = info.points.BoltKnob or Vector3.new(0.2, 0, 0.3)
	local knobGrab = CFrame.new(knob - (if bolt then bolt.rest.Position else Vector3.zero)) * info.grips.Right.Rotation * CFrame.new(0.05, -0.05, 0)
	local up = { "gun", spinAbout(axis, 65) }
	local back = { "gun", CFrame.new(0, 0, 0.4) * spinAbout(axis, 65) }
	local keys: { Keyframe } = {
		{ t = 0, gun = CFrame.new(), right = { "grip" }, left = { "grip" }, groups = { Bolt = { "rest" }, Magazine = { "rest" } } },
		{ t = 0.08, ease = "inOut", gun = tilt, right = { "group", "Bolt", knobGrab } },
		{ t = 0.14, ease = "out", groups = { Bolt = up } },
		{ t = 0.2, ease = "out", groups = { Bolt = back }, events = { "BoltBack" } },
	}
	append(keys, magSwap(info, 0.2, 0.78, tilt))
	table.insert(keys, { t = 0.84, ease = "out", groups = { Bolt = up }, right = { "group", "Bolt", knobGrab }, events = { "BoltForward" } })
	table.insert(keys, { t = 0.89, ease = "out", groups = { Bolt = { "rest" } } })
	table.insert(keys, { t = 1, ease = "inOut", gun = CFrame.new(), right = { "grip" }, left = { "grip" } })
	return keys
end

-- Revolver: cylinder out, muzzle up to eject, speedloader in, flick it closed
CLIPS.Revolver = function(info)
	local cylinder = info.groups.Cylinder
	local radius = if cylinder then math.min(cylinder.size.X, cylinder.size.Y) / 2 else 0.17
	local length = if cylinder then cylinder.size.Z else 0.4
	local hinge = Vector3.new(0, -radius * 1.05, 0) -- the crane sits under the cylinder
	local swungOut = { "gun", spinAbout(hinge, 78) }
	local cylinderCenter = if cylinder then cylinder.rest.Position else Vector3.new(0, 0.1, -0.05)
	local latch = info.points.CylinderLatch or (cylinderCenter + Vector3.new(-0.1, 0, 0.2))
	local loaderGrab = CFrame.new(0, 0, 0.12) * info.grips.Left.Rotation -- holding the speedloader's knob
	local keys: { Keyframe } = {
		{ t = 0, gun = CFrame.new(), left = { "grip" }, groups = { Cylinder = { "rest" }, Speedloader = { "rest" } }, hide = { Speedloader = true } },
		-- Thumb on the latch, cylinder swings out
		{ t = 0.1, ease = "inOut", gun = CFrame.new(-0.08, 0, 0.05) * deg(0, -10, 20), left = { "gun", grabOn(info, latch + Vector3.new(-0.08, -0.05, 0)) } },
		{ t = 0.17, ease = "back", groups = { Cylinder = swungOut }, events = { "CylinderOpen" } },
		-- Muzzle up, press the ejector
		{ t = 0.3, ease = "inOut", gun = CFrame.new(-0.12, 0.02, 0.1) * deg(55, -10, 25), left = { "group", "Cylinder", grabOn(info, Vector3.new(-0.08, -0.08, -length * 0.5)) } },
		{ t = 0.36, ease = "out", left = { "group", "Cylinder", grabOn(info, Vector3.new(-0.08, -0.08, -length * 0.1)) }, events = { "Eject" } },
		-- Muzzle down, fetch the speedloader
		{ t = 0.46, ease = "inOut", gun = CFrame.new(-0.08, -0.04, 0.05) * deg(-28, -8, 18), left = { "camera", POUCH } },
		{ t = 0.5, ease = "linear", left = { "camera", POUCH }, groups = { Speedloader = { "hand", "Left", loaderGrab:Inverse() } } },
		-- Line it up behind the cylinder and drop the rounds in
		{ t = 0.66, ease = "inOut", groups = { Speedloader = { "on", "Cylinder", CFrame.new(0, 0, length / 2 + 0.2) } }, left = { "group", "Speedloader", loaderGrab } },
		{ t = 0.72, ease = "out", groups = { Speedloader = { "on", "Cylinder", CFrame.new(0, 0, length / 2 + 0.04) } }, events = { "SpeedloaderIn" } },
		-- Pull the empty loader away
		{ t = 0.78, ease = "in", groups = { Speedloader = { "hand", "Left", loaderGrab:Inverse() } }, left = { "camera", POUCH * CFrame.new(0.2, 0.3, 0) } },
		-- Close the cylinder with a push
		{ t = 0.86, ease = "inOut", hide = { Speedloader = true }, gun = CFrame.new(-0.06, 0, 0.04) * deg(0, -8, 16), left = { "group", "Cylinder", grabOn(info, Vector3.new(-0.1, 0, 0)) } },
		{ t = 0.91, ease = "back", groups = { Cylinder = { "rest" } }, events = { "CylinderClose" } },
		{ t = 1, ease = "inOut", gun = CFrame.new(), left = { "grip" } },
	}
	return keys
end

-- SR-25: the same moves as the AR-15 (it has a bolt catch too)
CLIPS.Marksman = CLIPS.Rifle

-- M249: pop the feed cover, swap the ammo box, lay the new belt on the tray, slam the cover shut
CLIPS.LMG = function(info)
	local tilt = CFrame.new(-0.04, -0.03, 0.02) * deg(8, -10, -14)
	local cover = info.groups.FeedCover
	local coverSize = if cover then cover.size else Vector3.new(0.14, 0.2, 0.48)
	local hinge = Vector3.new(0, -coverSize.Y / 2, -coverSize.Z / 2) -- its front bottom edge
	local open = { "gun", CFrame.new(hinge) * deg(-75, 0, 0) * CFrame.new(-hinge) }
	local latch = grabOn(info, Vector3.new(-0.05, -0.06, coverSize.Z / 2 - 0.03))
	local tray = (if cover then cover.rest.Position else Vector3.new(0, 0.18, -0.04)) + Vector3.new(-0.07, -0.1, 0)
	local box = pieceSize(info, "Magazine")
	local keys: { Keyframe } = {
		{ t = 0, gun = CFrame.new(), left = { "grip" }, groups = { FeedCover = { "rest" }, Magazine = { "rest" } } },
		{ t = 0.08, ease = "inOut", gun = tilt, left = { "group", "FeedCover", latch } },
		{ t = 0.14, ease = "back", groups = { FeedCover = open }, left = { "group", "FeedCover", latch }, events = { "CoverOpen" } },
	}
	append(keys, magSwap(info, 0.14, 0.66, tilt, Vector3.new(-box.X / 2 - 0.04, -box.Y * 0.15, 0)))
	table.insert(keys, { t = 0.74, ease = "inOut", left = { "gun", grabOn(info, tray) }, events = { "BeltIn" } })
	table.insert(keys, { t = 0.82, ease = "inOut", left = { "group", "FeedCover", latch * CFrame.new(0, 0.08, 0) } })
	table.insert(keys, { t = 0.88, ease = "in", groups = { FeedCover = { "rest" } }, left = { "group", "FeedCover", latch }, gun = tilt * CFrame.new(0, -0.02, 0), events = { "CoverClose" } })
	table.insert(keys, { t = 1, ease = "inOut", gun = CFrame.new(), left = { "grip" } })
	return keys
end

-- Glock 18: the left hand lets go, the extended mag drops out down the grip, a fresh one goes
-- in with a slap; if it ran empty, the slide is racked to chamber a round
CLIPS.Autopistol = function(info)
	local tilt = CFrame.new(0.02, 0.02, 0.06) * deg(10, 12, 22)
	local down = -info.grips.Right.UpVector -- out of the bottom of the grip
	local size = pieceSize(info, "Magazine")
	local grab = grabOn(info, Vector3.new(-0.03, -size.Y * 0.35, 0))
	local keys: { Keyframe } = {
		{ t = 0, gun = CFrame.new(), left = { "grip" }, groups = { Magazine = { "rest" }, Slide = { "rest" } } },
		{ t = 0.1, ease = "inOut", gun = tilt, left = { "camera", POUCH * CFrame.new(0.25, 0.45, 0.1) } },
		{ t = 0.18, ease = "out", groups = { Magazine = { "gun", CFrame.new(down * 0.3) } }, events = { "MagOut" } },
		-- Old mag falls away while the hand fetches a new one
		{ t = 0.32, ease = "in", groups = { Magazine = { "gun", CFrame.new(down * 1.6 + Vector3.new(0.05, 0, 0.3)) * deg(25, 0, 10) } }, left = { "camera", POUCH } },
		{ t = 0.4, ease = "inOut", hide = { Magazine = true }, left = { "camera", POUCH } },
		{ t = 0.44, ease = "linear", groups = { Magazine = { "hand", "Left", grab:Inverse() } }, left = { "camera", POUCH } },
		-- Lined up under the grip, then pushed home
		{ t = 0.62, ease = "inOut", groups = { Magazine = { "gun", CFrame.new(down * 0.3) } }, left = { "group", "Magazine", grab } },
		{ t = 0.7, ease = "back", groups = { Magazine = { "rest" } }, left = { "group", "Magazine", grab }, gun = tilt * CFrame.new(0, 0.02, 0), events = { "MagIn" } },
	}
	if info.empty then
		local slide = pieceSize(info, "Slide")
		local pinch = grabOn(info, Vector3.new(-0.07, 0.01, slide.Z / 2 - 0.08)) -- the rear serrations
		table.insert(keys, { t = 0.78, ease = "inOut", left = { "group", "Slide", pinch }, gun = tilt * deg(0, -6, 0) })
		table.insert(keys, { t = 0.84, ease = "out", groups = { Slide = { "gun", CFrame.new(0, 0, 0.16) } }, left = { "group", "Slide", pinch }, events = { "SlideBack" } })
		table.insert(keys, { t = 0.88, ease = "in", groups = { Slide = { "rest" } }, left = { "camera", POUCH * CFrame.new(0.4, 0.7, -0.2) }, events = { "SlideForward" } })
	end
	table.insert(keys, { t = 1, ease = "inOut", gun = CFrame.new(), left = { "grip" } })
	return keys
end

-- Pulling a gun out: it rises from below into position
function ReloadAnimations.Draw(): { Keyframe }
	return {
		{ t = 0, gun = CFrame.new(0.1, -0.9, 0.35) * deg(-55, 15, 20), left = { "grip" }, right = { "grip" } },
		{ t = 0.75, ease = "out", gun = CFrame.new(0, 0.02, 0) * deg(3, 0, 0) },
		{ t = 1, ease = "inOut", gun = CFrame.new() },
	}
end

-- The reload for this gun (falls back to a simple tilt-and-mag-swap)
function ReloadAnimations.Reload(weaponName: string, info: Info): { Keyframe }
	local clip = CLIPS[weaponName]
	if clip then
		return clip(info)
	end
	local tilt = deg(10, -6, -25)
	local keys: { Keyframe } = { { t = 0, gun = CFrame.new(), left = { "grip" }, groups = { Magazine = { "rest" } } } }
	append(keys, magSwap(info, 0.02, 0.88, tilt))
	table.insert(keys, { t = 1, ease = "inOut", gun = CFrame.new(), left = { "grip" } })
	return keys
end

return ReloadAnimations
