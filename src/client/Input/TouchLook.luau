-- Turning the camera by dragging a finger, for the views that steer the camera themselves (your
-- drone, the defender cameras). Everywhere else Roblox's own camera already handles touch drags.
-- A drag is a touch that starts on the screen itself, not on a button or the thumbstick.

local UserInputService = game:GetService("UserInputService")

local state = require(script.Parent.Parent.PlayerState)

local TouchLook = {}

local dragging: InputObject? = nil
local last = Vector3.zero
local pending = Vector2.zero

-- Pixels dragged since the last call (added to the mouse delta by DroneController / CamsController)
function TouchLook.Consume(): Vector2
	local delta = pending
	pending = Vector2.zero
	return delta
end

function TouchLook.Start()
	UserInputService.TouchStarted:Connect(function(touch, processed)
		if processed or dragging then
			return
		end
		dragging = touch
		last = touch.Position
	end)
	UserInputService.TouchMoved:Connect(function(touch)
		if touch ~= dragging then
			return
		end
		local delta = touch.Position - last
		last = touch.Position
		if state.droning then -- (drags in normal play are Roblox's camera's)
			pending += Vector2.new(delta.X, delta.Y)
		end
	end)
	UserInputService.TouchEnded:Connect(function(touch)
		if touch == dragging then
			dragging = nil
		end
	end)
end

return TouchLook
