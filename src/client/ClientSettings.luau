-- The player's settings (the SETTINGS menu: Match/SettingsMenu), applied live and kept with their
-- data so they follow them to every server: loaded from the "Settings" player attribute
-- (PlayerData), changes saved a moment after the last one (Settings remote "Prefs", checked by
-- SettingsService against shared/PlayerSettings, which also lists the defaults and ranges).
-- Where each one takes effect:
--   MouseSensitivity / TouchSensitivity  the client's MovementConfig.MouseSensitivity (MouseUnlock,
--                                        drone, cameras): the touch one while the phone buttons show
--   AdsSensitivity                       state.adsSensitivityScale (WeaponController's aim slowdown)
--   InvertY / LeanToggle                 state.invertY (MouseUnlock, drone, cameras) / state.leanToggle
--   Fov                                  the client's MovementConfig.BaseFov (CameraEffects)
--   PerformanceMode                      this client's copy of the bloom, sun rays and clouds: off
--   Master / Effects / Music / UiVolume  SoundGroups
--   CrosshairColor / Size, HitMarkers    Hud
--   ShowStats                            SettingsMenu's FPS / ping readout
-- Anything else can read a value with Get and hear about changes with OnChanged.

local HttpService = game:GetService("HttpService")
local Lighting = game:GetService("Lighting")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage.Shared.MovementConfig)
local PlayerSettings = require(ReplicatedStorage.Shared.PlayerSettings)
local state = require(script.Parent.PlayerState)
local Hud = require(script.Parent.Combat.Hud)
local SoundGroups = require(script.Parent.Audio.SoundGroups)

local SettingsRemote = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("Settings") :: RemoteEvent

local player = Players.LocalPlayer

local ClientSettings = {}

local SAVE_DELAY = 1.5 -- seconds after the last change (dragging a slider is one save)
local CHECK_DELAY = 5 -- then: did it arrive? (the server drops requests that come too fast)
local RESENDS = 2

local BASE_SENSITIVITY = Config.MouseSensitivity -- the game's own speeds (setting 1 = these)

local values = PlayerSettings.Decode(nil) -- (the defaults until their data arrives)
local listeners: { (string) -> () } = {}
local saveToken = 0
local savePending = false
local sentAny = false
local lastTouch: boolean? = nil

-- Performance mode: the extras switched off, and whether each was on before
local switchedOff: { [Instance]: boolean } = {}

local function isExtra(instance: Instance): boolean
	return instance:IsA("BloomEffect") or instance:IsA("SunRaysEffect") or instance:IsA("Clouds")
end

local function setExtra(instance: Instance, performance: boolean)
	local extra = instance :: any
	if performance and switchedOff[instance] == nil then
		switchedOff[instance] = extra.Enabled
		extra.Enabled = false
	elseif not performance and switchedOff[instance] ~= nil then
		extra.Enabled = switchedOff[instance]
		switchedOff[instance] = nil
	end
end

local function applyPerformance(on: boolean)
	for _, parent in { Lighting, Workspace.Terrain } do
		for _, child in parent:GetChildren() do
			if isExtra(child) then
				setExtra(child, on)
			end
		end
	end
	if not on then
		table.clear(switchedOff) -- (anything left was destroyed meanwhile)
	end
end

local function applyLook()
	lastTouch = state.touchControls
	local setting = if state.touchControls then values.TouchSensitivity else values.MouseSensitivity
	Config.MouseSensitivity = BASE_SENSITIVITY * setting
end

local function applyCrosshair()
	Hud.SetCrosshairStyle(PlayerSettings.CrosshairColors[values.CrosshairColor] or Color3.new(1, 1, 1), values.CrosshairSize)
end

local APPLY: { [string]: (any) -> () } = {
	MouseSensitivity = applyLook,
	TouchSensitivity = applyLook,
	AdsSensitivity = function(value)
		state.adsSensitivityScale = value
	end,
	InvertY = function(value)
		state.invertY = value
	end,
	LeanToggle = function(value)
		state.leanToggle = value
	end,
	Fov = function(value)
		Config.BaseFov = value
	end,
	PerformanceMode = applyPerformance,
	MasterVolume = function(value)
		SoundGroups.Master.Volume = value
	end,
	EffectsVolume = function(value)
		SoundGroups.Effects.Volume = value
	end,
	MusicVolume = function(value)
		SoundGroups.Music.Volume = value
	end,
	UiVolume = function(value)
		SoundGroups.UI.Volume = value
	end,
	CrosshairColor = applyCrosshair,
	CrosshairSize = applyCrosshair,
	HitMarkers = function(value)
		Hud.SetHitMarkers(value)
	end,
}

local function changed(key: string)
	local apply = APPLY[key]
	if apply then
		apply(values[key])
	end
	for _, listener in listeners do
		task.spawn(listener, key)
	end
end

-- The stored copy (the attribute) has everything we have
local function stored(): boolean
	local saved = PlayerSettings.Decode(player:GetAttribute("Settings"))
	for key, value in values do
		local other = saved[key]
		if typeof(value) == "number" and typeof(other) == "number" then
			if math.abs(value - other) > 1e-4 then
				return false
			end
		elseif value ~= other then
			return false
		end
	end
	return true
end

local function send(resends: number)
	sentAny = true
	SettingsRemote:FireServer("Prefs", HttpService:JSONEncode(values))
	local token = saveToken
	task.delay(CHECK_DELAY, function()
		if token == saveToken and resends > 0 and not stored() then
			send(resends - 1)
		end
	end)
end

local function scheduleSave()
	saveToken += 1
	savePending = true
	local token = saveToken
	task.delay(SAVE_DELAY, function()
		if token == saveToken then
			savePending = false
			send(RESENDS)
		end
	end)
end

-- Their saved settings arrived (joining): use them. Once we've saved our own, ours are the
-- newest (the attribute only changes when a save lands, maybe an older one): if it doesn't match,
-- send ours again.
local function loadStored()
	if savePending then
		return
	end
	if sentAny then
		if not stored() then
			scheduleSave()
		end
		return
	end
	local saved = PlayerSettings.Decode(player:GetAttribute("Settings"))
	for key, value in saved do
		if values[key] ~= value then
			values[key] = value
			changed(key)
		end
	end
end

function ClientSettings.Get(key: string): any
	return values[key]
end

-- Changes a setting (cleaned up to its range first; nonsense is ignored), applies and saves it
function ClientSettings.Set(key: string, value: any)
	local clean = PlayerSettings.Clean(key, value)
	if clean == nil or values[key] == clean then
		return
	end
	values[key] = clean
	changed(key)
	scheduleSave()
end

-- Everything back to the defaults (one save)
function ClientSettings.Reset()
	local any = false
	for _, def in PlayerSettings.List do
		if values[def.Key] ~= def.Default then
			values[def.Key] = def.Default
			changed(def.Key)
			any = true
		end
	end
	if any then
		scheduleSave()
	end
end

-- `listener(key)` after any setting changes (the menu, a reset, or their data arriving)
function ClientSettings.OnChanged(listener: (string) -> ())
	table.insert(listeners, listener)
end

function ClientSettings.Start()
	SoundGroups.Start()
	for _, def in PlayerSettings.List do
		local apply = APPLY[def.Key]
		if apply then
			apply(values[def.Key])
		end
	end
	loadStored()
	player:GetAttributeChangedSignal("Settings"):Connect(loadStored)

	-- Performance mode: extras that turn up later (a new map's clouds) go straight off too
	for _, parent in { Lighting, Workspace.Terrain } do
		parent.ChildAdded:Connect(function(child)
			if values.PerformanceMode and isExtra(child) then
				task.defer(setExtra, child, true) -- (once the server's properties are in)
			end
		end)
	end
	-- Phone buttons showing or not (a laptop with a touch screen swaps): the matching sensitivity
	RunService.Heartbeat:Connect(function()
		if state.touchControls ~= lastTouch then
			applyLook()
		end
	end)
end

return ClientSettings
