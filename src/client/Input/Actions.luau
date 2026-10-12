-- The game's key actions by name ("Fire", "Reload", "LeanLeft"...), so the on-screen buttons
-- (MobileControls) run exactly the handler the key runs. Controllers bind their keys through here
-- instead of ContextActionService directly; it binds them the same way and remembers the handler
-- (game scripts aren't allowed ContextActionService:CallFunction).

local ContextActionService = game:GetService("ContextActionService")

type Handler = (string, Enum.UserInputState, InputObject?) -> Enum.ContextActionResult?

local Actions = {}

local handlers: { [string]: Handler } = {}

function Actions.Bind(name: string, handler: Handler, ...: Enum.KeyCode | Enum.UserInputType)
	handlers[name] = handler
	ContextActionService:BindAction(name, handler :: any, false, ...)
end

function Actions.BindAtPriority(name: string, handler: Handler, priority: number, ...: Enum.KeyCode | Enum.UserInputType)
	handlers[name] = handler
	ContextActionService:BindActionAtPriority(name, handler :: any, false, priority, ...)
end

-- Runs an action's handler as if its key went down (Begin) or came back up (End)
function Actions.Call(name: string, inputState: Enum.UserInputState): Enum.ContextActionResult?
	local handler = handlers[name]
	if handler then
		return handler(name, inputState, nil)
	end
	return nil
end

return Actions
