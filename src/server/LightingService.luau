-- Sets up the look of the whole game: a warm late-afternoon in the suburbs.
-- Everything here is set by the server, and Lighting replicates to every player.
--
-- Want to tweak the look? Change the numbers below and press Play. Each value has a short
-- note on what it does on screen. Two rules to keep the game fair while you tweak:
--   * Rooms must stay bright enough to spot an enemy standing in a corner.
--   * No thick fog or blur: players have to see each other across the whole map.
--
-- The rendering mode (LightingStyle = Realistic, the new name for "Future" lighting) is also
-- set in default.project.json so the map looks right in Studio while you edit.

local Lighting = game:GetService("Lighting")
local Workspace = game:GetService("Workspace")

local LightingService = {}

-- Sun, shadows and ambient light (the Lighting service itself)
local function setupLighting()
	-- Realistic = the most detailed lighting Roblox has: sharp sun shadows, shadows from lamps,
	-- light that bounces off shiny materials. (The old Technology = Future setting became this.)
	-- PrioritizeLightingQuality = on weaker devices, shrink view distance before lighting quality.
	-- Wrapped in pcall because older Studio versions did not let scripts change these two.
	local ok, err = pcall(function()
		Lighting.LightingStyle = Enum.LightingStyle.Realistic
		Lighting.PrioritizeLightingQuality = true
	end)
	if not ok then
		warn("[LightingService] Could not set LightingStyle from a script (set it in Studio instead):", err)
	end

	-- Time of day in hours. 15.5 = 3:30 PM: the sun is low enough for long, warm shadows but
	-- still high enough that nobody has to aim straight into it. Bigger = lower, oranger sun.
	Lighting.ClockTime = 15.5
	-- Where on Earth we are. Changes the sun's path across the sky (41.7 = Roblox default).
	Lighting.GeographicLatitude = 41.7

	-- How strong the sunlight is. 2 is Roblox's default; higher = punchier sunlit walls.
	Lighting.Brightness = 2.8
	-- Shadows from the sun on and off. Also what makes indoors darker than outdoors.
	Lighting.GlobalShadows = true
	-- Edge blur of sun shadows. 0 = razor sharp, 1 = very blurry. Real sunlight is fairly crisp.
	Lighting.ShadowSoftness = 0.15

	-- Fill light in places the sky can't see (inside the house, under the car). A dim warm grey:
	-- rooms read darker than the yard, but an enemy in a corner is still easy to see.
	-- Raise it (e.g. 80, 76, 72) if rooms feel too dark; it can't be brighter than OutdoorAmbient.
	Lighting.Ambient = Color3.fromRGB(68, 64, 60)
	-- Fill light outdoors, in the shade of walls and trees. Keeps shadows soft instead of black.
	Lighting.OutdoorAmbient = Color3.fromRGB(118, 112, 108)

	-- Extra light that takes its color from the sky. Gives shade a gentle blue-ish tint, like
	-- real life. (We lowered the two Ambient colors above a bit to make room for it.)
	Lighting.EnvironmentDiffuseScale = 0.5
	-- Sky reflections on smooth materials. Makes metal, glass and marble look shiny and real.
	Lighting.EnvironmentSpecularScale = 0.75

	-- Camera exposure, like on a real camera. 0 = neutral, +1 = twice as bright, -1 = half.
	-- Nudge to 0.2 if everything feels dim, or -0.2 if the yard looks washed out.
	Lighting.ExposureCompensation = 0
end

-- Air and haze. The Atmosphere also replaces the old FogStart / FogEnd fog.
local function setupAtmosphere()
	-- Reuse one that already exists (the Baseplate template ships with one) instead of adding a second
	local atmosphere = Lighting:FindFirstChildOfClass("Atmosphere") or Instance.new("Atmosphere")
	-- How thick the air is. Low on purpose: far-off trees fade a little, but a player across
	-- the whole map is still easy to see. Much higher and it starts hiding people far away.
	atmosphere.Density = 0.3
	-- How much the haze covers the sky itself near the horizon. Small = clearer horizon.
	atmosphere.Offset = 0.2
	-- Color of the haze toward the sun: warm, dusty afternoon light
	atmosphere.Color = Color3.fromRGB(205, 190, 165)
	-- Color of the haze away from the sun: a cooler blue-grey, like real late-day sky
	atmosphere.Decay = Color3.fromRGB(110, 112, 125)
	-- Soft glow around the sun in the sky
	atmosphere.Glare = 0.2
	-- Hazy layer just above the horizon
	atmosphere.Haze = 1
	atmosphere.Parent = Lighting
end

-- The sky box and the moving clouds
local function setupSky()
	-- A Sky with no texture ids uses Roblox's built-in sky pictures (no uploads needed).
	-- If the place already has a Sky (maybe with a custom look), keep its textures.
	local sky = Lighting:FindFirstChildOfClass("Sky") or Instance.new("Sky")
	-- Size of the sun disc in degrees. Roblox's default (21) is huge and cartoony.
	sky.SunAngularSize = 12
	sky.CelestialBodiesShown = true
	sky.Parent = Lighting

	-- Real 3D clouds that drift with the wind. They live on Terrain, not in Lighting.
	local terrain = Workspace.Terrain
	local clouds = terrain:FindFirstChildOfClass("Clouds") or Instance.new("Clouds")
	-- How much of the sky is covered. 0.45 = scattered clouds on a nice day.
	clouds.Cover = 0.45
	-- How thick each cloud looks. Lower = thinner, see-through wisps.
	clouds.Density = 0.55
	clouds.Color = Color3.fromRGB(245, 240, 235)
	clouds.Enabled = true
	clouds.Parent = terrain
end

-- Post-processing: filters drawn on top of the finished image, like a camera's settings
local function setupPostEffects()
	-- Color grading for the whole screen
	local color = Lighting:FindFirstChildOfClass("ColorCorrectionEffect") or Instance.new("ColorCorrectionEffect")
	color.Name = "SceneColorCorrection"
	-- Overall brightness of the final image. Leave at 0 and use ExposureCompensation instead.
	color.Brightness = 0
	-- Darks a bit darker, lights a bit lighter: makes the image less flat
	color.Contrast = 0.1
	-- Slightly richer colors. Too much looks like a cartoon again.
	color.Saturation = 0.05
	-- Very slight warm tint for the afternoon mood. White (255, 255, 255) = no tint.
	color.TintColor = Color3.fromRGB(255, 248, 238)
	color.Enabled = true
	color.Parent = Lighting

	-- Glow around very bright things (the sun, ceiling lamps, sun glints on glass)
	local bloom = Lighting:FindFirstChildOfClass("BloomEffect") or Instance.new("BloomEffect")
	bloom.Name = "SceneBloom"
	-- How strong the glow is. Kept low so lamps don't blind you in a gunfight.
	bloom.Intensity = 0.5
	-- How far the glow spreads, in pixels
	bloom.Size = 20
	-- How bright something must be to glow. 2 = only lamps and the sun, not white walls.
	bloom.Threshold = 2
	bloom.Enabled = true
	bloom.Parent = Lighting

	-- Light beams that streak out from the sun when it peeks past walls and trees
	local sunRays = Lighting:FindFirstChildOfClass("SunRaysEffect") or Instance.new("SunRaysEffect")
	sunRays.Name = "SceneSunRays"
	-- Strength of the beams. Subtle: enough to look nice, not enough to blind anyone.
	sunRays.Intensity = 0.08
	-- How far the beams reach across the screen (0 to 1)
	sunRays.Spread = 0.6
	sunRays.Enabled = true
	sunRays.Parent = Lighting

	-- Turn off any depth-of-field blur the place came with (the Baseplate template has one).
	-- In a shooter you must see clearly at every distance.
	for _, child in Lighting:GetChildren() do
		if child:IsA("DepthOfFieldEffect") then
			child.Enabled = false
		end
	end
end

-- Per-map weather on top of the defaults above: MapService.Load calls Apply with the map's name.
-- Anything a map leaves out keeps the default (the values set by the functions above). Same two
-- fairness rules: rooms bright enough to spot someone, haze thin enough to see across the map.
local DEFAULT = {
	ClockTime = 15.5,
	Brightness = 2.8,
	Ambient = Color3.fromRGB(68, 64, 60),
	OutdoorAmbient = Color3.fromRGB(118, 112, 108),
	HazeDensity = 0.3,
	HazeColor = Color3.fromRGB(205, 190, 165),
	HazeDecay = Color3.fromRGB(110, 112, 125),
	Glare = 0.2,
	CloudCover = 0.45,
	CloudDensity = 0.55,
	CloudColor = Color3.fromRGB(245, 240, 235),
	Contrast = 0.1,
	Saturation = 0.05,
	Tint = Color3.fromRGB(255, 248, 238),
	SunRays = 0.08,
}
local PROFILES: { [string]: { [string]: any } } = {
	-- A cold, overcast mountain plateau: grey sky, flat cool light, a little more haze
	Flight9 = {
		ClockTime = 13,
		Brightness = 2,
		Ambient = Color3.fromRGB(78, 82, 90),
		OutdoorAmbient = Color3.fromRGB(140, 146, 158),
		HazeDensity = 0.38,
		HazeColor = Color3.fromRGB(200, 208, 220),
		HazeDecay = Color3.fromRGB(150, 158, 172),
		Glare = 0,
		CloudCover = 0.85,
		CloudDensity = 0.75,
		CloudColor = Color3.fromRGB(205, 210, 218),
		Contrast = 0.12,
		Saturation = -0.08,
		Tint = Color3.fromRGB(236, 243, 255),
		SunRays = 0.02,
	},
	-- A clear city midday: the sun higher and whiter, less of the suburban gold
	Bank = {
		ClockTime = 13.5,
		Brightness = 3,
		HazeColor = Color3.fromRGB(200, 200, 205),
		HazeDecay = Color3.fromRGB(120, 128, 145),
		CloudCover = 0.35,
		Tint = Color3.fromRGB(252, 252, 255),
	},
}

function LightingService.Apply(mapName: string)
	local profile = PROFILES[mapName] or {}
	local function get(key: string): any
		local value = profile[key]
		return if value ~= nil then value else DEFAULT[key]
	end
	Lighting.ClockTime = get("ClockTime")
	Lighting.Brightness = get("Brightness")
	Lighting.Ambient = get("Ambient")
	Lighting.OutdoorAmbient = get("OutdoorAmbient")
	local atmosphere = Lighting:FindFirstChildOfClass("Atmosphere")
	if atmosphere then
		atmosphere.Density = get("HazeDensity")
		atmosphere.Color = get("HazeColor")
		atmosphere.Decay = get("HazeDecay")
		atmosphere.Glare = get("Glare")
	end
	local clouds = Workspace.Terrain:FindFirstChildOfClass("Clouds")
	if clouds then
		clouds.Cover = get("CloudCover")
		clouds.Density = get("CloudDensity")
		clouds.Color = get("CloudColor")
	end
	local color = Lighting:FindFirstChild("SceneColorCorrection") :: ColorCorrectionEffect?
	if color then
		color.Contrast = get("Contrast")
		color.Saturation = get("Saturation")
		color.TintColor = get("Tint")
	end
	local sunRays = Lighting:FindFirstChild("SceneSunRays") :: SunRaysEffect?
	if sunRays then
		sunRays.Intensity = get("SunRays")
	end
end

function LightingService.Start()
	-- Each step reuses objects that already exist, so running this twice is harmless
	setupLighting()
	setupAtmosphere()
	setupSky()
	setupPostEffects()
end

return LightingService
