-- Tags in front of names in chat. Every menu with something to show adds a function, and each
-- message gets the tags in order: ShopMenu's gold [VIP] (the VIP pass), then ClanMenu's [TAG]
-- (their clan) → "[VIP] [ABC] Name". There's only one TextChatService.OnIncomingMessage, so it
-- lives here.

local Players = game:GetService("Players")
local TextChatService = game:GetService("TextChatService")

local ChatTags = {}

type Tagger = { order: number, tag: (Player) -> string? }

local taggers: { Tagger } = {}

local function onIncomingMessage(message: TextChatMessage): TextChatMessageProperties
	local properties = Instance.new("TextChatMessageProperties")
	local source = message.TextSource
	local sender = if source then Players:GetPlayerByUserId(source.UserId) else nil
	if sender then
		local tags = {}
		for _, tagger in taggers do
			local text = tagger.tag(sender)
			if text then
				table.insert(tags, text)
			end
		end
		if #tags > 0 then
			properties.PrefixText = `{table.concat(tags, " ")} {message.PrefixText}`
		end
	end
	return properties
end

-- `tag(sender)` returns the (rich) text to put before a sender's name, or nil for none. Lower
-- `order` goes first.
function ChatTags.Add(order: number, tag: (Player) -> string?)
	table.insert(taggers, { order = order, tag = tag })
	table.sort(taggers, function(a, b)
		return a.order < b.order
	end)
	TextChatService.OnIncomingMessage = onIncomingMessage
end

return ChatTags
