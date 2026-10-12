-- How far the movement thumbstick is pushed on a touch screen, 0..1 (MovementController: a light
-- push walks slowly, all the way out sprints). Measured straight from the finger driving it: the
-- touch that started on the left half of the screen (every on-screen button is on the right half),
-- from where it went down (Roblox's thumbstick centers itself there) to where it is now.
-- Roblox's own control scripts aren't reachable from game scripts here (this place keeps them in
-- StarterPlayer, not PlayerScripts), so nothing waits on them.

local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local MoveInput = {}

local finger: InputObject? = nil
local origin = Vector3.zero

-- Roughly the thumbstick's radius in pixels (Roblox's is smaller on phones)
local function radius(): number
	local viewport = Workspace.CurrentCamera.ViewportSize
	return if math.min(viewport.X, viewport.Y) <= 500 then 35 else 60
end

-- nil when no finger is on the thumbstick side
function MoveInput.Push(): number?
	if not finger then
		return nil
	end
	local drag = finger.Position - origin
	return math.clamp(Vector2.new(drag.X, drag.Y).Magnitude / radius(), 0, 1)
end

function MoveInput.Start()
	UserInputService.TouchStarted:Connect(function(touch)
		if not finger and touch.Position.X < Workspace.CurrentCamera.ViewportSize.X / 2 then
			finger = touch
			origin = touch.Position
		end
	end)
	UserInputService.TouchEnded:Connect(function(touch)
		if touch == finger then
			finger = nil
		end
	end)
end

return MoveInput
