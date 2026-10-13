-- A player's own settings, kept with their data (PlayerData) so they follow them to every server.
--   Settings:FireServer("TouchLayout", json)   where they moved their phone buttons (client
--                                               MobileControls' EDIT BUTTONS); "" = the defaults
--   Settings:FireServer("LobbyWeapon", name)    the gun they hold in the lobby (ShopMenu's picker
--                                               under SHOP); it's handed to them whenever they're
--                                               out of a match
-- Everything is checked and rebuilt here, never stored as the client sent it.

local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Weapons = require(ReplicatedStorage.Shared.Weapons)
local PlayerData = require(script.Parent.PlayerData)
local WeaponService = require(script.Parent.WeaponService)

local SettingsRemote = ReplicatedStorage.Remotes.Settings :: RemoteEvent

local SettingsService = {}

local MAX_BUTTONS = 40
local lastRequest: { [Player]: number } = {}

-- { [button id] = { x, y (0..1 of the screen), s (size, 0.5..2) } }, or nil if it's not that
local function cleanLayout(json: any): string?
	if typeof(json) ~= "string" or #json > 4000 then
		return nil
	end
	if json == "" then
		return ""
	end
	local ok, decoded = pcall(HttpService.JSONDecode, HttpService, json)
	if not ok or typeof(decoded) ~= "table" then
		return nil
	end
	local clean, count = {}, 0
	for id, spot in decoded do
		if typeof(id) ~= "string" or #id > 24 or typeof(spot) ~= "table" then
			continue
		end
		local x, y, s = spot.x, spot.y, spot.s
		if typeof(x) ~= "number" or typeof(y) ~= "number" or x ~= x or y ~= y then
			continue
		end
		count += 1
		if count > MAX_BUTTONS then
			break
		end
		clean[id] = {
			x = math.clamp(x, 0, 1),
			y = math.clamp(y, 0, 1),
			s = if typeof(s) == "number" and s == s then math.clamp(s, 0.5, 2) else 1,
		}
	end
	return HttpService:JSONEncode(clean)
end

function SettingsService.Start()
	SettingsRemote.OnServerEvent:Connect(function(player, kind, value)
		local now = os.clock()
		if now - (lastRequest[player] or 0) < 0.2 then
			return
		end
		lastRequest[player] = now
		if kind == "LobbyWeapon" then
			if typeof(value) == "string" and Weapons[value] then
				PlayerData.Update(player, function(data)
					data.LobbyWeapon = value
				end, true)
			end
		elseif kind == "TouchLayout" then
			local layout = cleanLayout(value)
			if layout then
				PlayerData.Update(player, function(data)
					data.TouchLayout = layout
				end, true)
			end
		end
	end)
	-- The lobby gun: in their hands as soon as it's loaded or changed, unless they're in a match
	-- (LoadoutService hands it back after one)
	local function watch(player: Player)
		player:GetAttributeChangedSignal("LobbyWeapon"):Connect(function()
			local name = player:GetAttribute("LobbyWeapon")
			if typeof(name) == "string" and Weapons[name] and player:GetAttribute("Location") ~= "Match" then
				WeaponService.SetWeapon(player, name)
			end
		end)
	end
	for _, player in Players:GetPlayers() do
		watch(player)
	end
	Players.PlayerAdded:Connect(watch)
	Players.PlayerRemoving:Connect(function(player)
		lastRequest[player] = nil
	end)
end

return SettingsService
