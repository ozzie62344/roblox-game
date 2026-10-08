-- F uses your active ability (Recon Pulse, Ghost Step, Deployable Cover). Dash also lives on F,
-- so for Dash this passes the key through to MovementController.
-- Also draws ability effects the server sends: reveals, the pulse wave, "scanned" warnings.

local ContextActionService = game:GetService("ContextActionService")
local Debris = game:GetService("Debris")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Abilities = require(ReplicatedStorage.Shared.Abilities)
local state = require(script.Parent.Parent.PlayerState)
local Hud = require(script.Parent.Parent.Combat.Hud)
local Effects = require(script.Parent.Parent.Combat.Effects)

local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local UseAbility = Remotes:WaitForChild("UseAbility") :: RemoteEvent
local AbilityEffect = Remotes:WaitForChild("AbilityEffect") :: RemoteEvent

local player = Players.LocalPlayer

local AbilityController = {}

local REVEAL_COLOR = Color3.fromRGB(255, 60, 60)

local function revealCharacters(characters: { Model }, duration: number)
	for _, character in characters do
		if not character.Parent or character == player.Character then
			continue
		end
		local highlight = Instance.new("Highlight")
		highlight.Name = "ReconReveal"
		highlight.FillColor = REVEAL_COLOR
		highlight.FillTransparency = 0.6
		highlight.OutlineColor = REVEAL_COLOR
		highlight.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
		highlight.Adornee = character
		highlight.Parent = Effects.GetFolder()
		-- Fade out over the last half second
		task.delay(math.max(duration - 0.5, 0), function()
			TweenService:Create(highlight, TweenInfo.new(0.5), { FillTransparency = 1, OutlineTransparency = 1 }):Play()
		end)
		Debris:AddItem(highlight, duration)
	end
	if #characters > 0 then
		Hud.ShowStatus(`{#characters} ENEMIES REVEALED`, 1.5, REVEAL_COLOR)
	else
		Hud.ShowStatus("NO ENEMIES IN RANGE", 1.5)
	end
end

-- Expanding sphere so everyone can see a scan just happened (and roughly where)
local function pulseWave(origin: Vector3, radius: number)
	local wave = Instance.new("Part")
	wave.Shape = Enum.PartType.Ball
	wave.Anchored = true
	wave.CanCollide = false
	wave.CanQuery = false
	wave.CanTouch = false
	wave.CastShadow = false
	wave.Material = Enum.Material.ForceField
	wave.Color = Color3.fromRGB(255, 90, 90)
	wave.Size = Vector3.one
	wave.Position = origin
	wave.Parent = Effects.GetFolder()
	TweenService:Create(wave, TweenInfo.new(0.8, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Size = Vector3.one * radius * 2,
		Transparency = 1,
	}):Play()
	Debris:AddItem(wave, 0.9)
end

function AbilityController.Start()
	ContextActionService:BindAction("UseAbility", function(_, inputState)
		if inputState ~= Enum.UserInputState.Begin then
			return Enum.ContextActionResult.Sink
		end
		local abilityName = player:GetAttribute("Ability")
		local ability = abilityName and Abilities[abilityName]
		if not ability or ability.Kind ~= "Active" then
			return Enum.ContextActionResult.Pass -- Dash (or nothing): let MovementController have F
		end
		if state.devPanelOpen or state.mouseUnlocked or state.draftOpen or state.spectating then
			return Enum.ContextActionResult.Sink
		end
		if (player:GetAttribute("AbilityCharges") or 0) <= 0 then
			Hud.ShowStatus("NO CHARGES LEFT", 1)
			return Enum.ContextActionResult.Sink
		end
		UseAbility:FireServer(Workspace.CurrentCamera.CFrame.LookVector)
		return Enum.ContextActionResult.Sink
	end, false, Enum.KeyCode.F, Enum.KeyCode.ButtonL1)

	AbilityEffect.OnClientEvent:Connect(function(kind: string, ...)
		if kind == "Reveal" then
			local characters, duration = ...
			revealCharacters(characters, duration)
		elseif kind == "Pulse" then
			local origin, radius = ...
			pulseWave(origin, radius)
		elseif kind == "Scanned" then
			Hud.ShowStatus("YOU'VE BEEN SCANNED", 2, REVEAL_COLOR)
		elseif kind == "GhostStep" then
			local duration = ...
			Hud.ShowStatus("GHOST STEP — SILENT", duration, Color3.fromRGB(150, 200, 255))
		end
	end)
end

return AbilityController
