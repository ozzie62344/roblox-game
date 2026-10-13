-- PROGRESS: your level, the reward track, daily challenges, the daily login reward and the
-- leaderboards (rules and numbers: shared/Progression; the server: ProgressService and
-- LeaderboardService, which check everything).
--   Lobby, top middle: your level badge, an XP bar and the PROGRESS button (a red dot when
--   today's daily reward is waiting).
--   The PROGRESS screen, four tabs:
--     LEVELS       the reward track, a card per level: reached ones ticked, the next one in gold
--                  with the XP still to go (rewards unlock by themselves, nothing to claim)
--     CHALLENGES   today's 3 challenges with progress bars, and how long until new ones
--     DAILY        the week of login rewards, today's to CLAIM, your streak
--     TOP PLAYERS  the leaderboards (most kills, most wins, highest level) and your own numbers
--   Daily reward popup: comes up by itself in the lobby when today's is waiting (CLAIM / LATER).
--   Anywhere: "LEVEL UP!" and "CHALLENGE COMPLETE" banners. At the end of a match: the XP card
--   (what the match was worth and for what, the bar filling up, LEVEL UP! and what it unlocked).
-- Reads the player attributes PlayerData publishes (Xp, Stats, DailyDay, DailyStreak, Challenges)
-- and ReplicatedStorage.Leaderboards.

local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Attachments = require(ReplicatedStorage.Shared.Attachments)
local Progression = require(ReplicatedStorage.Shared.Progression)
local Skins = require(ReplicatedStorage.Shared.Skins)
local Sounds = require(ReplicatedStorage.Shared.Sounds)
local Effects = require(script.Parent.Parent.Combat.Effects)
local state = require(script.Parent.Parent.PlayerState)
local MenuStyle = require(script.Parent.MenuStyle)

local MatchState = ReplicatedStorage:WaitForChild("MatchState")
local Progress = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("Progress") :: RemoteEvent

local player = Players.LocalPlayer

local ProgressMenu = {}

local CARD = Color3.fromRGB(36, 39, 48)
local EDGE = Color3.fromRGB(60, 64, 76)
local GOLD = Color3.fromRGB(255, 196, 60)
local GOLD_TEXT = Color3.fromRGB(255, 225, 120)
local XP_BLUE = Color3.fromRGB(80, 170, 255)
local SOFT_TEXT = Color3.fromRGB(170, 176, 190)
local LOCKED_TEXT = Color3.fromRGB(120, 124, 135)
local TABS = { "Levels", "Challenges", "Daily", "Top" }
local TAB_NAMES = { Levels = "Levels", Challenges = "Challenges", Daily = "Daily", Top = "Top Players" }
local BOARDS = { { "Kills", "MOST KILLS" }, { "Wins", "MOST WINS" }, { "Level", "HIGHEST LEVEL" } }
local LEVEL_CARD_WIDTH, LEVEL_CARD_GAP = 150, 10
-- End-of-match card: what each kind of XP is called, in this order
local GAIN_NAMES = {
	{ "KILL", "KILLS" },
	{ "HEADSHOT", "HEADSHOTS" },
	{ "DEFUSER PLANTED", "PLANT" },
	{ "DEFUSER DISABLED", "DISABLE" },
	{ "ROUND WON", "ROUNDS" },
	{ "MATCH COMPLETE", "MATCH" },
	{ "MATCH WON", "WIN" },
	{ "CHALLENGE", "CHALLENGES" },
}

type Bar = { badge: TextLabel, level: TextLabel?, xp: TextLabel, fill: Frame }
type Tile = { frame: Frame, check: Frame, note: TextLabel }
type ChallengeRow = { frame: Frame, task: TextLabel, fill: Frame, count: TextLabel, credits: TextLabel, xp: TextLabel, check: Frame }
type BoardRow = { frame: Frame, face: ImageLabel, who: TextLabel, value: TextLabel }

local gui: ScreenGui
local widget: Frame
local widgetBar: Bar
local widgetDot: Frame
local screen: Frame
local screenBar: Bar
local offlineLabel: TextLabel
local tabButtons: { [string]: TextButton } = {}
local tabDot: Frame
local pages: { [string]: Frame } = {}
local nextLabel: TextLabel
local track: ScrollingFrame
local levelCards: { [number]: Frame } = {}
local challengeRows: { ChallengeRow } = {}
local challengeFooter: TextLabel
local dailyTiles: { Tile } = {}
local streakLabel: TextLabel
local claimButton: TextButton
local waitLabel: TextLabel
local boardRows: { [string]: { BoardRow } } = {}
local boardEmpty: { [string]: TextLabel } = {}
local youLabel: TextLabel
local boardStatus: TextLabel
local popupBack: Frame
local popupTiles: { Tile } = {}
local popupStreak: TextLabel
local popupClaim: TextButton
local banner: CanvasGroup
local bannerTitle: TextLabel
local bannerSub: TextLabel
local summary: Frame
local summaryBar: Bar
local summaryGain: TextLabel
local summaryBreakdown: TextLabel
local summaryUnlocked: TextLabel
local summaryStamp: TextLabel

local tab = "Levels"
local screenOpen = false
local popupDismissedDay = -1 -- LATER: don't pop up again today
local claiming = 0 -- os.clock() of the last CLAIM press (one at a time until the answer comes)
local bannerCount = 0
local lastTick = 0
-- This match: XP when it started, and what it was earned for (reason → XP)
local matchStartXp: number? = nil
local matchStartCredits: number? = nil -- (the XP card also says how many coins the match paid)
local summaryCoins: TextLabel
local matchGains: { [string]: number } = {}
local summaryOpen = false
local summaryOpenedAt = 0
local shownXp = 0
local shownLevel = 1

-- ─── Reading the player's data ─────────────────────────────────────────────────

local function formatNumber(amount: number): string
	local digits = tostring(math.floor(amount))
	local grouped = string.reverse((string.gsub(string.reverse(digits), "(%d%d%d)", "%1,")))
	return (string.gsub(grouped, "^,", ""))
end

local function decode(attribute: string): any
	local json = player:GetAttribute(attribute)
	if typeof(json) ~= "string" or json == "" then
		return nil
	end
	local ok, value = pcall(HttpService.JSONDecode, HttpService, json)
	return if ok then value else nil
end

-- (the data hasn't loaded until PlayerData publishes it)
local function loaded(): boolean
	return typeof(player:GetAttribute("Xp")) == "number"
end

local function xp(): number
	local value = player:GetAttribute("Xp")
	return if typeof(value) == "number" then value else 0
end

local function number(attribute: string): number
	local value = player:GetAttribute(attribute)
	return if typeof(value) == "number" then value else 0
end

local function today(): number
	return Progression.Day(Workspace:GetServerTimeNow())
end

local function dailyReady(): boolean
	return loaded() and number("DailyDay") < today()
end

-- "5H 12M" until the next UTC day (new challenges, the next daily reward)
local function untilTomorrow(): string
	local now = Workspace:GetServerTimeNow()
	local left = math.max(0, (Progression.Day(now) + 1) * 86400 - now)
	local hours, minutes = math.floor(left / 3600), math.floor(left % 3600 / 60)
	return if hours > 0 then `{hours}H {minutes}M` else `{math.max(minutes, 1)}M`
end

local function inLobbyMenu(): boolean
	return MatchState:GetAttribute("ServerKind") == "Lobby"
		and player:GetAttribute("Location") == "Lobby"
		and MatchState:GetAttribute("Phase") == "Waiting"
end

-- Items and credits unlocked going from `fromLevel` up to `toLevel` ("RED DOT · 350 CREDITS")
local function unlockText(fromLevel: number, toLevel: number): string
	local items, credits = {}, 0
	for level = fromLevel, toLevel do
		local reward = Progression.RewardFor(level)
		if reward.Kind == "Credits" then
			credits += reward.Amount
		else
			table.insert(items, Progression.RewardText(reward))
		end
	end
	if credits > 0 then
		table.insert(items, `{formatNumber(credits)} CREDITS`)
	end
	return table.concat(items, " · ")
end

-- ─── Building blocks ───────────────────────────────────────────────────────────

-- Smaller text needs a thinner outline than MenuStyle's chunky one
local function thinOutline(label: TextLabel, thickness: number)
	(label:FindFirstChildOfClass("UIStroke") :: UIStroke).Thickness = thickness
end

local function leftText(parent: Instance, text: string, size: UDim2, position: UDim2, anchor: Vector2?): TextLabel
	local label = MenuStyle.Text(parent, text, size, position, anchor)
	label.TextXAlignment = Enum.TextXAlignment.Left
	return label
end

-- A gold coin: rim, face and a lighter middle (like the shop's)
local function coin(parent: Instance, size: number, position: UDim2, anchor: Vector2?): Frame
	local outer = Instance.new("Frame")
	outer.Name = "Coin"
	outer.AnchorPoint = anchor or Vector2.new(0.5, 0.5)
	outer.Position = position
	outer.Size = UDim2.fromOffset(size, size)
	outer.BackgroundColor3 = GOLD
	MenuStyle.Corner(outer, UDim.new(1, 0))
	MenuStyle.Rim(outer, Color3.fromRGB(150, 95, 20), math.max(1.5, size * 0.09))
	local inner = Instance.new("Frame")
	inner.AnchorPoint = Vector2.new(0.5, 0.5)
	inner.Position = UDim2.fromScale(0.5, 0.5)
	inner.Size = UDim2.fromScale(0.5, 0.5)
	inner.BackgroundColor3 = Color3.fromRGB(255, 228, 130)
	MenuStyle.Corner(inner, UDim.new(1, 0))
	inner.Parent = outer
	outer.Parent = parent
	return outer
end

local function shine(parent: Instance)
	local gradient = Instance.new("UIGradient")
	gradient.Rotation = 90
	gradient.Color = ColorSequence.new(Color3.new(1, 1, 1), Color3.fromRGB(185, 185, 185))
	gradient.Parent = parent
end

-- A round blue level badge ("LV" over the number); returns the number's label
local function badge(parent: Instance, size: number, position: UDim2, anchor: Vector2?): TextLabel
	local circle = Instance.new("Frame")
	circle.Name = "Badge"
	circle.AnchorPoint = anchor or Vector2.zero
	circle.Position = position
	circle.Size = UDim2.fromOffset(size, size)
	circle.BackgroundColor3 = XP_BLUE
	MenuStyle.Corner(circle, UDim.new(1, 0))
	MenuStyle.Rim(circle, Color3.fromRGB(20, 55, 110), math.max(2, size * 0.06))
	shine(circle)
	local lv = MenuStyle.Text(circle, "LV", UDim2.fromScale(0.4, 0.22), UDim2.fromScale(0.5, 0.24), Vector2.new(0.5, 0.5))
	thinOutline(lv, 1.5)
	local value = MenuStyle.Text(circle, "1", UDim2.fromScale(0.72, 0.46), UDim2.fromScale(0.5, 0.6), Vector2.new(0.5, 0.5))
	circle.Parent = parent
	return value
end

-- A rounded bar; returns its fill (set its width with Size.X scale)
local function bar(parent: Instance, size: UDim2, position: UDim2, color: Color3): Frame
	local back = Instance.new("Frame")
	back.Position = position
	back.Size = size
	back.BackgroundColor3 = Color3.fromRGB(14, 16, 22)
	MenuStyle.Corner(back, UDim.new(1, 0))
	MenuStyle.Rim(back, EDGE, 2)
	back.Parent = parent
	local fill = Instance.new("Frame")
	fill.Name = "Fill"
	fill.Size = UDim2.fromScale(0, 1)
	fill.BackgroundColor3 = color
	MenuStyle.Corner(fill, UDim.new(1, 0))
	shine(fill)
	fill.Parent = back
	return fill
end

local function showLevel(view: Bar, total: number)
	local level, into, needed = Progression.LevelFor(total)
	view.badge.Text = tostring(level)
	if view.level then
		view.level.Text = `LEVEL {level}`
	end
	view.xp.Text = `{formatNumber(into)} / {formatNumber(needed)} XP`
	view.fill.Size = UDim2.fromScale(math.clamp(into / needed, 0.02, 1), 1)
end

-- A little red dot with "!" (something's waiting)
local function alertDot(parent: Instance, position: UDim2): Frame
	local dot = Instance.new("Frame")
	dot.Name = "Dot"
	dot.AnchorPoint = Vector2.new(0.5, 0.5)
	dot.Position = position
	dot.Size = UDim2.fromOffset(24, 24)
	dot.BackgroundColor3 = MenuStyle.Red
	dot.Visible = false
	MenuStyle.Corner(dot, UDim.new(1, 0))
	MenuStyle.Rim(dot, Color3.new(1, 1, 1), 2)
	thinOutline(MenuStyle.Text(dot, "!", UDim2.fromScale(0.7, 0.7), UDim2.fromScale(0.5, 0.5), Vector2.new(0.5, 0.5)), 1.5)
	dot.Parent = parent
	return dot
end

-- ─── Banners and the end-of-match card ─────────────────────────────────────────

local function showBanner(title: string, sub: string, color: Color3)
	bannerCount += 1
	local mine = bannerCount
	bannerTitle.Text = title
	bannerTitle.TextColor3 = color
	bannerSub.Text = sub
	banner.GroupTransparency = 0
	local scale = banner:FindFirstChild("Pop") :: UIScale
	scale.Scale = 0.6
	TweenService:Create(scale, TweenInfo.new(0.35, Enum.EasingStyle.Back), { Scale = 1 }):Play()
	task.delay(3.2, function()
		if bannerCount == mine then
			TweenService:Create(banner, TweenInfo.new(0.6), { GroupTransparency = 1 }):Play()
		end
	end)
end

local function stamp(label: TextLabel)
	local scale = label:FindFirstChildOfClass("UIScale") :: UIScale
	label.Visible = true
	scale.Scale = 2
	TweenService:Create(scale, TweenInfo.new(0.35, Enum.EasingStyle.Back), { Scale = 1 }):Play()
end

local function openSummary()
	summaryOpen = true
	summaryOpenedAt = os.clock()
	shownXp = matchStartXp or xp()
	shownLevel = Progression.LevelFor(shownXp)
	summaryStamp.Visible = false
	summary.Visible = not state.resultsOpen -- (waits for the match results screen: update)
end

local function closeSummary()
	summaryOpen = false
	summary.Visible = false
end

-- The bar fills up from where the match started to where you are now (crossing levels: LEVEL UP!)
local function updateSummary(dt: number)
	local start = matchStartXp or xp()
	local target = xp()
	if os.clock() - summaryOpenedAt > 0.8 and shownXp < target then
		shownXp = math.min(target, shownXp + math.max((target - start) / 1.8, 300) * dt)
	end
	local level = Progression.LevelFor(shownXp)
	if level > shownLevel then
		shownLevel = level
		stamp(summaryStamp)
		Effects.Sound(Sounds.Shop.Buy, nil, Sounds.Shop.Volume, 1.25)
	end
	showLevel(summaryBar, shownXp)
	summaryGain.Text = `+{formatNumber(math.max(0, target - start))} XP`
	local credits = player:GetAttribute("Credits")
	local coins = if typeof(credits) == "number" and matchStartCredits then math.max(0, credits - matchStartCredits) else 0
	summaryCoins.Text = `+{formatNumber(coins)} COINS THIS GAME`
	local parts = {}
	for _, gain in GAIN_NAMES do
		local amount = matchGains[gain[1]]
		if amount and amount > 0 then
			table.insert(parts, `{gain[2]} +{formatNumber(amount)}`)
		end
	end
	summaryBreakdown.Text = table.concat(parts, " · ")
	local startLevel = Progression.LevelFor(start)
	summaryUnlocked.Text = if shownLevel > startLevel then "UNLOCKED: " .. unlockText(startLevel + 1, shownLevel) else ""
end

-- ─── Refresh ───────────────────────────────────────────────────────────────────

local function refreshLevels()
	local level, into, needed = Progression.LevelFor(xp())
	for l, card in levelCards do
		local reached = l <= level
		local upNext = l == level + 1
		local rim = card:FindFirstChild("Rim") :: UIStroke
		rim.Color = if upNext then GOLD elseif reached then MenuStyle.Green else EDGE
		rim.Thickness = if upNext then 4 else 2
		card.BackgroundColor3 = if upNext then Color3.fromRGB(58, 52, 36) else CARD
		;(card:FindFirstChild("Check") :: Frame).Visible = reached
		local status = card:FindFirstChild("Status") :: TextLabel
		status.Text = if reached then "UNLOCKED" elseif upNext then `{formatNumber(needed - into)} XP TO GO` else "LOCKED"
		status.TextColor3 = if reached then Color3.fromRGB(120, 255, 100) elseif upNext then GOLD_TEXT else LOCKED_TEXT
	end
	local nextItem = Progression.NextItemLevel(level)
	nextLabel.Text = if nextItem then `NEXT ITEM · LEVEL {nextItem}: {Progression.RewardText(Progression.RewardFor(nextItem))}`
		else `EVERY LEVEL FROM HERE: {Progression.AfterTrack} CREDITS`
end

local function refreshChallenges()
	local info = decode("Challenges")
	local list = if typeof(info) == "table" and typeof(info.List) == "table" then info.List else {}
	for i, row in challengeRows do
		local entry = list[i]
		local challenge = typeof(entry) == "table" and Progression.ChallengeById[entry.Id]
		row.frame.Visible = challenge ~= nil
		if not challenge then
			continue
		end
		local progress = math.clamp(if typeof(entry.Progress) == "number" then entry.Progress else 0, 0, challenge.Goal)
		local done = progress >= challenge.Goal
		row.task.Text = string.upper(challenge.Text)
		row.task.TextColor3 = if done then Color3.fromRGB(120, 255, 100) else Color3.new(1, 1, 1)
		row.fill.Size = UDim2.fromScale(math.max(progress / challenge.Goal, 0.02), 1)
		row.fill.BackgroundColor3 = if done then MenuStyle.Green else XP_BLUE
		row.count.Text = if done then "DONE!" else `{progress} / {challenge.Goal}`
		row.credits.Text = `+{formatNumber(challenge.Credits)}`
		row.xp.Text = `+{formatNumber(challenge.Xp)} XP`
		row.check.Visible = done
		;(row.frame:FindFirstChild("Rim") :: UIStroke).Color = if done then MenuStyle.Green else EDGE
	end
	challengeFooter.Text = if #list == 0 then "LOADING YOUR CHALLENGES..." else `NEW CHALLENGES IN {untilTomorrow()} · FINISH THEM IN MATCHES`
end

-- Ticks the claimed days of this week, rims today's in gold
local function refreshTiles(tiles: { Tile })
	local ready = dailyReady()
	local streak = number("DailyStreak")
	local week = #Progression.Daily
	local current: number? = nil -- today's tile, if it's waiting
	local claimed = 0 -- tiles ticked
	if ready then
		local nextStreak = Progression.NextDaily(number("DailyDay"), streak, today())
		current = (nextStreak - 1) % week + 1
		claimed = (current :: number) - 1
	elseif streak > 0 then
		claimed = (streak - 1) % week + 1
	end
	for i, tile in tiles do
		local isToday = i == current
		local rim = tile.frame:FindFirstChild("Rim") :: UIStroke
		rim.Color = if isToday then GOLD elseif i <= claimed then MenuStyle.Green else EDGE
		rim.Thickness = if isToday then 4 else 2
		tile.frame.BackgroundColor3 = if isToday then Color3.fromRGB(58, 52, 36) else CARD
		tile.check.Visible = i <= claimed
		tile.note.Text = if isToday then "TODAY" elseif i <= claimed then "CLAIMED" elseif not ready and i == claimed + 1 then "TOMORROW" else ""
		tile.note.TextColor3 = if isToday then GOLD_TEXT elseif i <= claimed then Color3.fromRGB(120, 255, 100) else SOFT_TEXT
	end
end

local function streakText(): string
	local streak = number("DailyStreak")
	if dailyReady() then
		local nextStreak, credits = Progression.NextDaily(number("DailyDay"), streak, today())
		return if nextStreak > 1 then `DAY {nextStreak} IN A ROW · CLAIM {credits} CREDITS` else `CLAIM {credits} CREDITS · COME BACK TOMORROW FOR MORE`
	end
	return if streak > 0 then `{streak} DAY STREAK · MISS A DAY AND IT STARTS OVER` else ""
end

local function refreshDaily()
	refreshTiles(dailyTiles)
	refreshTiles(popupTiles)
	local ready = dailyReady()
	streakLabel.Text = streakText()
	popupStreak.Text = streakText()
	claimButton.Visible = ready
	waitLabel.Visible = not ready
	waitLabel.Text = if loaded() then `NEXT REWARD IN {untilTomorrow()}` else "LOADING..."
	local waiting = os.clock() - claiming < 3
	MenuStyle.SetButtonColor(claimButton, if waiting then MenuStyle.Grey else MenuStyle.Green)
	MenuStyle.SetButtonColor(popupClaim, if waiting then MenuStyle.Grey else MenuStyle.Green)
end

local function refreshTop()
	local folder = ReplicatedStorage:FindFirstChild("Leaderboards")
	for _, info in BOARDS do
		local board = info[1]
		local raw = folder and folder:GetAttribute(board)
		local ok, list = pcall(HttpService.JSONDecode, HttpService, if typeof(raw) == "string" then raw else "[]")
		local entries = if ok and typeof(list) == "table" then list else {}
		for i, row in boardRows[board] do
			local entry = entries[i]
			row.frame.Visible = typeof(entry) == "table"
			if typeof(entry) == "table" then
				local id = tonumber(entry.Id) or 0
				row.who.Text = tostring(entry.Name)
				row.who.TextColor3 = if id == player.UserId then GOLD_TEXT else Color3.new(1, 1, 1)
				row.value.Text = if board == "Level" then `LV {entry.Value}` else formatNumber(tonumber(entry.Value) or 0)
				row.face.Image = if id > 0 then `rbxthumb://type=AvatarHeadShot&id={id}&w=48&h=48` else ""
			end
		end
		boardEmpty[board].Visible = #entries == 0
	end
	local stats = decode("Stats")
	if typeof(stats) == "table" then
		local level = Progression.LevelFor(xp())
		youLabel.Text = `YOU · {formatNumber(stats.Kills or 0)} KILLS · {formatNumber(stats.Headshots or 0)} HEADSHOTS · {formatNumber(stats.Wins or 0)} WINS · {formatNumber(stats.Matches or 0)} MATCHES · LEVEL {level}`
	else
		youLabel.Text = ""
	end
	local live = folder and folder:GetAttribute("Live") == true
	boardStatus.Text = if live then "TOP PLAYERS WORLDWIDE · UPDATED EVERY FEW MINUTES" else "LEADERBOARDS OFFLINE · SHOWING PLAYERS IN THIS SERVER"
end

local function refresh()
	local total = xp()
	showLevel(widgetBar, total)
	showLevel(screenBar, total)
	offlineLabel.Visible = player:GetAttribute("DataOffline") == true
	for name, button in tabButtons do
		MenuStyle.SetButtonColor(button, if name == tab then MenuStyle.Gold else MenuStyle.Grey)
	end
	for name, page in pages do
		page.Visible = name == tab
	end
	local ready = dailyReady()
	widgetDot.Visible = ready
	tabDot.Visible = ready
	refreshLevels()
	refreshChallenges()
	refreshDaily()
	if tab == "Top" then
		refreshTop()
	end
end

local function selectTab(name: string)
	tab = name
	refresh()
	if name == "Levels" then
		-- Scroll so the next level is in view
		local level = Progression.LevelFor(xp())
		track.CanvasPosition = Vector2.new(math.max(0, (level - 3) * (LEVEL_CARD_WIDTH + LEVEL_CARD_GAP)), 0)
	end
end

local function claim()
	if not dailyReady() or os.clock() - claiming < 3 then
		return
	end
	claiming = os.clock()
	Progress:FireServer("ClaimDaily")
	refresh()
end

-- ─── Building ──────────────────────────────────────────────────────────────────

-- One card on the reward track: the level, the reward's picture and name, and its state
local function levelCard(level: number): Frame
	local reward = Progression.RewardFor(level)
	local card = Instance.new("Frame")
	card.Name = "Level" .. level
	card.LayoutOrder = level
	card.Size = UDim2.fromOffset(LEVEL_CARD_WIDTH, 320)
	card.BackgroundColor3 = CARD
	MenuStyle.Corner(card, UDim.new(0, 12))
	MenuStyle.Rim(card, EDGE, 2).Name = "Rim"
	local title = leftText(card, `LEVEL {level}`, UDim2.new(1, -46, 0, 26), UDim2.fromOffset(12, 12))
	thinOutline(title, 2)

	local art = Instance.new("Frame")
	art.AnchorPoint = Vector2.new(0.5, 0)
	art.Position = UDim2.new(0.5, 0, 0, 52)
	art.Size = UDim2.fromOffset(122, 112)
	art.BackgroundTransparency = 1
	art.ClipsDescendants = true
	MenuStyle.Corner(art, UDim.new(0, 10))
	art.Parent = card
	local kind = "CREDITS"
	if reward.Kind == "Skin" then
		local skin = Skins.ById[reward.Id]
		kind = "SKIN · NOT IN THE SHOP"
		art.BackgroundTransparency = 0
		art.BackgroundColor3 = Color3.new(1, 1, 1)
		local paint = Instance.new("UIGradient")
		paint.Color = ColorSequence.new(skin.Colors[1], skin.Colors[#skin.Colors])
		paint.Rotation = 35
		paint.Parent = art
		MenuStyle.Rim(art, Skins.Rarities[skin.Rarity].Color, 3)
		local trim = Instance.new("Frame")
		trim.AnchorPoint = Vector2.new(0, 1)
		trim.Position = UDim2.new(0, 0, 1, -10)
		trim.Size = UDim2.new(1, 0, 0, 8)
		trim.BorderSizePixel = 0
		trim.BackgroundColor3 = skin.Trim
		trim.Parent = art
		if skin.Rainbow then
			trim.BackgroundColor3 = Color3.new(1, 1, 1)
			local keys = {}
			for i = 0, 6 do
				table.insert(keys, ColorSequenceKeypoint.new(i / 6, Color3.fromHSV(i / 6, 0.9, 1)))
			end
			local rainbow = Instance.new("UIGradient")
			rainbow.Color = ColorSequence.new(keys)
			rainbow.Parent = trim
		end
		local rarity = MenuStyle.Text(art, string.upper(skin.Rarity), UDim2.new(1, -16, 0, 18), UDim2.fromOffset(8, 8))
		rarity.TextXAlignment = Enum.TextXAlignment.Left
		thinOutline(rarity, 1.5)
	elseif reward.Kind == "Attachment" then
		local attachment = Attachments.ById[reward.Id]
		kind = "ATTACHMENT"
		art.BackgroundTransparency = 0
		art.BackgroundColor3 = Color3.fromRGB(46, 50, 62)
		MenuStyle.Rim(art, MenuStyle.Blue, 3)
		local slot = MenuStyle.Text(art, Attachments.SlotNames[attachment.Slot], UDim2.new(1, -16, 0, 18), UDim2.new(0.5, 0, 0, 12), Vector2.new(0.5, 0))
		slot.TextColor3 = SOFT_TEXT
		thinOutline(slot, 1.5)
		local name = MenuStyle.Text(art, string.upper(attachment.Name), UDim2.new(1, -16, 0, 40), UDim2.fromScale(0.5, 0.6), Vector2.new(0.5, 0.5))
		name.TextWrapped = true
	else
		coin(art, 62, UDim2.fromScale(0.5, 0.4))
		local amount = MenuStyle.Text(art, `+{formatNumber(reward.Amount)}`, UDim2.new(1, -10, 0, 28), UDim2.new(0.5, 0, 1, -6), Vector2.new(0.5, 1))
		amount.TextColor3 = GOLD_TEXT
	end

	local name = MenuStyle.Text(card, Progression.RewardText(reward), UDim2.new(1, -16, 0, 44), UDim2.new(0.5, 0, 0, 174), Vector2.new(0.5, 0))
	name.TextWrapped = true
	thinOutline(name, 1.5)
	local kindLabel = MenuStyle.Text(card, kind, UDim2.new(1, -16, 0, 16), UDim2.new(0.5, 0, 0, 224), Vector2.new(0.5, 0))
	kindLabel.TextColor3 = SOFT_TEXT
	thinOutline(kindLabel, 1)
	local status = MenuStyle.Text(card, "", UDim2.new(1, -16, 0, 22), UDim2.new(0.5, 0, 1, -14), Vector2.new(0.5, 1))
	status.Name = "Status"
	thinOutline(status, 1.5)
	MenuStyle.Check(card, UDim2.new(1, -24, 0, 24))
	return card
end

local function buildLevels(page: Frame)
	nextLabel = leftText(page, "", UDim2.new(1, 0, 0, 24), UDim2.new())
	nextLabel.TextColor3 = GOLD_TEXT
	thinOutline(nextLabel, 2)
	track = Instance.new("ScrollingFrame")
	track.Position = UDim2.fromOffset(0, 34)
	track.Size = UDim2.new(1, 0, 0, 350)
	track.BackgroundTransparency = 1
	track.BorderSizePixel = 0
	track.ScrollingDirection = Enum.ScrollingDirection.X
	track.ScrollBarThickness = 8
	track.ScrollBarImageColor3 = Color3.fromRGB(120, 124, 135)
	local count = Progression.TrackLength - 1
	track.CanvasSize = UDim2.fromOffset(count * (LEVEL_CARD_WIDTH + LEVEL_CARD_GAP) + 4, 0)
	track.Parent = page
	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Horizontal
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Padding = UDim.new(0, LEVEL_CARD_GAP)
	layout.Parent = track
	local padding = Instance.new("UIPadding")
	padding.PaddingTop = UDim.new(0, 4)
	padding.PaddingLeft = UDim.new(0, 4)
	padding.Parent = track
	for level = 2, Progression.TrackLength do
		levelCards[level] = levelCard(level)
		levelCards[level].Parent = track
	end
end

local function buildChallenges(page: Frame)
	for i = 1, Progression.ChallengesPerDay do
		local frame = Instance.new("Frame")
		frame.Position = UDim2.fromOffset(0, (i - 1) * 114)
		frame.Size = UDim2.new(1, 0, 0, 102)
		frame.BackgroundColor3 = CARD
		MenuStyle.Corner(frame, UDim.new(0, 12))
		MenuStyle.Rim(frame, EDGE, 2).Name = "Rim"
		frame.Parent = page
		local taskLabel = leftText(frame, "", UDim2.fromOffset(640, 32), UDim2.fromOffset(20, 12))
		local fill = bar(frame, UDim2.fromOffset(560, 22), UDim2.fromOffset(20, 60), XP_BLUE)
		local count = leftText(frame, "", UDim2.fromOffset(120, 24), UDim2.fromOffset(596, 59))
		thinOutline(count, 2)
		-- Rewards on the right: credits (with a coin) over XP
		coin(frame, 26, UDim2.new(1, -196, 0, 32))
		local credits = leftText(frame, "", UDim2.fromOffset(110, 26), UDim2.new(1, -176, 0, 19))
		credits.TextColor3 = GOLD_TEXT
		thinOutline(credits, 2)
		local xpLabel = leftText(frame, "", UDim2.fromOffset(150, 24), UDim2.new(1, -206, 0, 58))
		xpLabel.TextColor3 = XP_BLUE
		thinOutline(xpLabel, 2)
		local check = MenuStyle.Check(frame, UDim2.new(1, -36, 0.5, 0))
		challengeRows[i] = { frame = frame, task = taskLabel, fill = fill, count = count, credits = credits, xp = xpLabel, check = check }
	end
	challengeFooter = MenuStyle.Text(page, "", UDim2.new(1, 0, 0, 24), UDim2.new(0.5, 0, 0, 352), Vector2.new(0.5, 0))
	challengeFooter.TextColor3 = SOFT_TEXT
	thinOutline(challengeFooter, 1.5)
end

-- A week of daily reward tiles (DAY 1..7, a coin and the credits), centered in `parent`
local function dailyRow(parent: Instance, tileSize: Vector2, y: number): { Tile }
	local row = Instance.new("Frame")
	row.AnchorPoint = Vector2.new(0.5, 0)
	row.Position = UDim2.new(0.5, 0, 0, y)
	row.Size = UDim2.new(1, 0, 0, tileSize.Y)
	row.BackgroundTransparency = 1
	row.Parent = parent
	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Horizontal
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Padding = UDim.new(0, 10)
	layout.Parent = row
	local tiles = {}
	for i, credits in Progression.Daily do
		local frame = Instance.new("Frame")
		frame.LayoutOrder = i
		frame.Size = UDim2.fromOffset(tileSize.X, tileSize.Y)
		frame.BackgroundColor3 = CARD
		MenuStyle.Corner(frame, UDim.new(0, 12))
		MenuStyle.Rim(frame, EDGE, 2).Name = "Rim"
		frame.Parent = row
		local day = MenuStyle.Text(frame, `DAY {i}`, UDim2.new(0.8, 0, 0.15, 0), UDim2.fromScale(0.5, 0.06), Vector2.new(0.5, 0))
		thinOutline(day, 2)
		-- (the last day of the week is the big one: a bigger coin)
		local coinSize = math.floor(tileSize.X * (if i == #Progression.Daily then 0.52 else 0.4))
		coin(frame, coinSize, UDim2.fromScale(0.5, 0.45))
		local amount = MenuStyle.Text(frame, `+{credits}`, UDim2.new(0.8, 0, 0.15, 0), UDim2.fromScale(0.5, 0.64), Vector2.new(0.5, 0))
		amount.TextColor3 = GOLD_TEXT
		local note = MenuStyle.Text(frame, "", UDim2.new(0.86, 0, 0.11, 0), UDim2.new(0.5, 0, 1, -8), Vector2.new(0.5, 1))
		thinOutline(note, 1.5)
		local check = MenuStyle.Check(frame, UDim2.new(1, -18, 0, 18))
		table.insert(tiles, { frame = frame, check = check, note = note })
	end
	return tiles
end

local function buildDaily(page: Frame)
	dailyTiles = dailyRow(page, Vector2.new(124, 176), 10)
	streakLabel = MenuStyle.Text(page, "", UDim2.new(1, 0, 0, 28), UDim2.new(0.5, 0, 0, 204), Vector2.new(0.5, 0))
	streakLabel.TextColor3 = GOLD_TEXT
	thinOutline(streakLabel, 2)
	claimButton = MenuStyle.Button(page, "Claim", MenuStyle.Green, UDim2.fromOffset(280, 76), UDim2.new(0.5, 0, 0, 250), Vector2.new(0.5, 0))
	claimButton.Activated:Connect(claim)
	waitLabel = MenuStyle.Text(page, "", UDim2.fromOffset(600, 30), UDim2.new(0.5, 0, 0, 268), Vector2.new(0.5, 0))
	waitLabel.TextColor3 = SOFT_TEXT
	local note = MenuStyle.Text(page, "A NEW REWARD EVERY DAY (UTC) · CLAIM DAYS IN A ROW FOR BIGGER ONES", UDim2.new(1, 0, 0, 18), UDim2.new(0.5, 0, 0, 350), Vector2.new(0.5, 0))
	note.TextColor3 = SOFT_TEXT
	thinOutline(note, 1)
end

local function buildTop(page: Frame)
	for i, info in BOARDS do
		local board = info[1]
		local column = Instance.new("Frame")
		column.Position = UDim2.fromOffset((i - 1) * 342, 0)
		column.Size = UDim2.fromOffset(316, 336)
		column.BackgroundColor3 = CARD
		MenuStyle.Corner(column, UDim.new(0, 12))
		MenuStyle.Rim(column, EDGE, 2)
		column.Parent = page
		local heading = MenuStyle.Text(column, info[2], UDim2.new(1, -20, 0, 28), UDim2.new(0.5, 0, 0, 8), Vector2.new(0.5, 0))
		heading.TextColor3 = GOLD_TEXT
		boardRows[board] = {}
		for r = 1, 10 do
			local row = Instance.new("Frame")
			row.Position = UDim2.fromOffset(8, 42 + (r - 1) * 29)
			row.Size = UDim2.new(1, -16, 0, 27)
			row.BackgroundColor3 = Color3.new(1, 1, 1)
			row.BackgroundTransparency = if r % 2 == 1 then 0.95 else 1
			row.Visible = false
			MenuStyle.Corner(row, UDim.new(0, 6))
			row.Parent = column
			local rank = MenuStyle.Text(row, tostring(r), UDim2.fromOffset(26, 20), UDim2.new(0, 2, 0.5, 0), Vector2.new(0, 0.5))
			rank.TextColor3 = if r == 1 then GOLD_TEXT else SOFT_TEXT
			thinOutline(rank, 1.5)
			local face = Instance.new("ImageLabel")
			face.AnchorPoint = Vector2.new(0, 0.5)
			face.Position = UDim2.new(0, 32, 0.5, 0)
			face.Size = UDim2.fromOffset(24, 24)
			face.BackgroundColor3 = Color3.fromRGB(46, 50, 60)
			MenuStyle.Corner(face, UDim.new(1, 0))
			face.Parent = row
			local who = leftText(row, "", UDim2.new(1, -150, 0, 20), UDim2.new(0, 62, 0.5, 0), Vector2.new(0, 0.5))
			thinOutline(who, 1.5)
			local value = MenuStyle.Text(row, "", UDim2.fromOffset(80, 20), UDim2.new(1, -4, 0.5, 0), Vector2.new(1, 0.5))
			value.TextXAlignment = Enum.TextXAlignment.Right
			value.TextColor3 = GOLD_TEXT
			thinOutline(value, 1.5)
			table.insert(boardRows[board], { frame = row, face = face, who = who, value = value })
		end
		local empty = MenuStyle.Text(column, "NOBODY YET · PLAY A MATCH!", UDim2.new(1, -30, 0, 20), UDim2.fromScale(0.5, 0.5), Vector2.new(0.5, 0.5))
		empty.TextColor3 = SOFT_TEXT
		thinOutline(empty, 1.5)
		boardEmpty[board] = empty
	end
	youLabel = MenuStyle.Text(page, "", UDim2.new(1, 0, 0, 22), UDim2.new(0.5, 0, 0, 344), Vector2.new(0.5, 0))
	thinOutline(youLabel, 1.5)
	boardStatus = MenuStyle.Text(page, "", UDim2.new(1, 0, 0, 16), UDim2.new(0.5, 0, 0, 372), Vector2.new(0.5, 0))
	boardStatus.TextColor3 = SOFT_TEXT
	thinOutline(boardStatus, 1)
end

local function buildWidget()
	-- Lobby, top middle: [LV badge][LEVEL n · xp bar][PROGRESS]
	widget = Instance.new("Frame")
	widget.Name = "LobbyLevel"
	widget.AnchorPoint = Vector2.new(0.5, 0)
	widget.Position = UDim2.new(0.5, 0, 0, 10)
	widget.Size = UDim2.fromOffset(520, 58)
	widget.BackgroundTransparency = 1
	widget.Visible = false
	widget.Parent = gui
	MenuStyle.FitToScreen(widget, Vector2.new(760, 480))
	local info = Instance.new("Frame")
	info.AnchorPoint = Vector2.new(0, 0.5)
	info.Position = UDim2.new(0, 34, 0.5, 0)
	info.Size = UDim2.fromOffset(306, 48)
	info.BackgroundColor3 = MenuStyle.Panel
	info.BackgroundTransparency = 0.1
	MenuStyle.Corner(info, UDim.new(0, 12))
	MenuStyle.Rim(info, EDGE, 3)
	info.Parent = widget
	local level = leftText(info, "", UDim2.fromOffset(120, 20), UDim2.fromOffset(34, 4))
	thinOutline(level, 2)
	local xpLabel = MenuStyle.Text(info, "", UDim2.fromOffset(150, 16), UDim2.new(1, -12, 0, 6), Vector2.new(1, 0))
	xpLabel.TextXAlignment = Enum.TextXAlignment.Right
	xpLabel.TextColor3 = SOFT_TEXT
	thinOutline(xpLabel, 1.5)
	local fill = bar(info, UDim2.new(1, -46, 0, 12), UDim2.fromOffset(34, 28), XP_BLUE)
	local levelNumber = badge(widget, 58, UDim2.new(0, 0, 0.5, 0), Vector2.new(0, 0.5))
	widgetBar = { badge = levelNumber, level = level, xp = xpLabel, fill = fill }
	local button = MenuStyle.Button(widget, "Progress", MenuStyle.Blue, UDim2.fromOffset(170, 58), UDim2.new(1, 0, 0.5, 0), Vector2.new(1, 0.5))
	button.Activated:Connect(ProgressMenu.Open)
	widgetDot = alertDot(button, UDim2.new(1, -4, 0, 4))
end

local function buildScreen()
	screen = Instance.new("Frame")
	screen.Name = "Screen"
	screen.Size = UDim2.fromScale(1, 1)
	screen.BackgroundColor3 = Color3.new(0, 0, 0)
	screen.BackgroundTransparency = 0.2
	screen.Active = true
	screen.Visible = false
	screen.Parent = gui
	local content = Instance.new("Frame")
	content.AnchorPoint = Vector2.new(0.5, 0.5)
	content.Position = UDim2.fromScale(0.5, 0.5)
	content.Size = UDim2.fromOffset(1000, 600)
	content.BackgroundTransparency = 1
	content.Parent = screen
	MenuStyle.FitToScreen(content, Vector2.new(1000, 600))

	leftText(content, "PROGRESS", UDim2.fromOffset(300, 64), UDim2.new())
	-- Your level, top right
	local levelNumber = badge(content, 62, UDim2.new(1, -330, 0, 0))
	local level = leftText(content, "", UDim2.fromOffset(120, 24), UDim2.new(1, -258, 0, 6))
	local xpLabel = MenuStyle.Text(content, "", UDim2.fromOffset(150, 18), UDim2.new(1, 0, 0, 9), Vector2.new(1, 0))
	xpLabel.TextXAlignment = Enum.TextXAlignment.Right
	xpLabel.TextColor3 = SOFT_TEXT
	thinOutline(xpLabel, 1.5)
	local fill = bar(content, UDim2.fromOffset(258, 16), UDim2.new(1, -258, 0, 38), XP_BLUE)
	screenBar = { badge = levelNumber, level = level, xp = xpLabel, fill = fill }

	for i, name in TABS do
		local button = MenuStyle.Button(content, TAB_NAMES[name], MenuStyle.Grey, UDim2.fromOffset(236, 50), UDim2.fromOffset((i - 1) * 254, 76))
		button.Activated:Connect(function()
			selectTab(name)
		end)
		tabButtons[name] = button
		local page = Instance.new("Frame")
		page.Name = name
		page.Position = UDim2.fromOffset(0, 140)
		page.Size = UDim2.fromOffset(1000, 390)
		page.BackgroundTransparency = 1
		page.Visible = false
		page.Parent = content
		pages[name] = page
	end
	tabDot = alertDot(tabButtons.Daily, UDim2.new(1, -4, 0, 4))
	buildLevels(pages.Levels)
	buildChallenges(pages.Challenges)
	buildDaily(pages.Daily)
	buildTop(pages.Top)

	local back = MenuStyle.Button(content, "Back", MenuStyle.Red, UDim2.fromOffset(240, 64), UDim2.new(0.5, 0, 1, 0), Vector2.new(0.5, 1))
	back.Activated:Connect(ProgressMenu.Close)
	offlineLabel = leftText(content, "SAVING IS OFF ON THIS SERVER · PROGRESS WON'T BE KEPT", UDim2.fromOffset(360, 18), UDim2.new(0, 0, 1, -24), Vector2.new(0, 0.5))
	offlineLabel.TextColor3 = Color3.fromRGB(255, 120, 110)
	thinOutline(offlineLabel, 1.5)
end

local function buildPopup()
	popupBack = Instance.new("Frame")
	popupBack.Name = "DailyPopup"
	popupBack.Size = UDim2.fromScale(1, 1)
	popupBack.BackgroundColor3 = Color3.new(0, 0, 0)
	popupBack.BackgroundTransparency = 0.45
	popupBack.Active = true
	popupBack.Visible = false
	popupBack.Parent = gui
	local panel = Instance.new("Frame")
	panel.AnchorPoint = Vector2.new(0.5, 0.5)
	panel.Position = UDim2.fromScale(0.5, 0.5)
	panel.Size = UDim2.fromOffset(820, 380)
	panel.BackgroundColor3 = MenuStyle.Panel
	MenuStyle.Corner(panel, UDim.new(0, 16))
	MenuStyle.Rim(panel, GOLD, 3)
	panel.Parent = popupBack
	MenuStyle.FitToScreen(panel, Vector2.new(820, 380))
	MenuStyle.Text(panel, "DAILY REWARD", UDim2.new(1, -40, 0, 52), UDim2.new(0.5, 0, 0, 12), Vector2.new(0.5, 0))
	popupStreak = MenuStyle.Text(panel, "", UDim2.new(1, -40, 0, 22), UDim2.new(0.5, 0, 0, 66), Vector2.new(0.5, 0))
	popupStreak.TextColor3 = GOLD_TEXT
	thinOutline(popupStreak, 2)
	popupTiles = dailyRow(panel, Vector2.new(102, 150), 100)
	popupClaim = MenuStyle.Button(panel, "Claim", MenuStyle.Green, UDim2.fromOffset(260, 70), UDim2.new(0.5, -140, 1, -18), Vector2.new(0.5, 1))
	popupClaim.Activated:Connect(claim)
	local later = MenuStyle.Button(panel, "Later", MenuStyle.Grey, UDim2.fromOffset(200, 70), UDim2.new(0.5, 130, 1, -18), Vector2.new(0.5, 1))
	later.Activated:Connect(function()
		popupDismissedDay = today()
		popupBack.Visible = false
	end)
end

local function buildMatchBits()
	-- Banner: LEVEL UP! / CHALLENGE COMPLETE
	banner = Instance.new("CanvasGroup")
	banner.Name = "Banner"
	banner.AnchorPoint = Vector2.new(0.5, 0.5)
	banner.Position = UDim2.fromScale(0.5, 0.27)
	banner.Size = UDim2.fromOffset(760, 110)
	banner.BackgroundTransparency = 1
	banner.GroupTransparency = 1
	banner.Parent = gui
	local pop = Instance.new("UIScale")
	pop.Name = "Pop"
	pop.Parent = banner
	bannerTitle = MenuStyle.Text(banner, "", UDim2.new(1, 0, 0, 62), UDim2.new(0.5, 0, 0, 0), Vector2.new(0.5, 0))
	bannerSub = MenuStyle.Text(banner, "", UDim2.new(1, 0, 0, 28), UDim2.new(0.5, 0, 0, 70), Vector2.new(0.5, 0))
	thinOutline(bannerSub, 2)

	-- End-of-match XP card, bottom middle (out of the way of the results screen)
	summary = Instance.new("Frame")
	summary.Name = "MatchXp"
	summary.AnchorPoint = Vector2.new(0.5, 1)
	summary.Position = UDim2.new(0.5, 0, 1, -16)
	summary.Size = UDim2.fromOffset(540, 176)
	summary.BackgroundColor3 = MenuStyle.Panel
	summary.BackgroundTransparency = 0.08
	summary.Visible = false
	MenuStyle.Corner(summary, UDim.new(0, 14))
	MenuStyle.Rim(summary, XP_BLUE, 3)
	summary.Parent = gui
	MenuStyle.FitToScreen(summary, Vector2.new(900, 560))
	leftText(summary, "MATCH XP", UDim2.fromOffset(200, 30), UDim2.fromOffset(18, 10))
	summaryGain = MenuStyle.Text(summary, "", UDim2.fromOffset(240, 38), UDim2.new(1, -18, 0, 6), Vector2.new(1, 0))
	summaryGain.TextXAlignment = Enum.TextXAlignment.Right
	summaryGain.TextColor3 = XP_BLUE
	summaryBreakdown = leftText(summary, "", UDim2.new(1, -36, 0, 18), UDim2.fromOffset(18, 46))
	summaryBreakdown.TextColor3 = SOFT_TEXT
	thinOutline(summaryBreakdown, 1.5)
	summaryCoins = leftText(summary, "", UDim2.new(1, -36, 0, 22), UDim2.fromOffset(18, 68))
	summaryCoins.TextColor3 = GOLD_TEXT
	thinOutline(summaryCoins, 2)
	local levelNumber = badge(summary, 56, UDim2.fromOffset(18, 98))
	local level = leftText(summary, "", UDim2.fromOffset(160, 22), UDim2.fromOffset(86, 100))
	thinOutline(level, 2)
	local xpLabel = MenuStyle.Text(summary, "", UDim2.fromOffset(200, 18), UDim2.new(1, -18, 0, 102), Vector2.new(1, 0))
	xpLabel.TextXAlignment = Enum.TextXAlignment.Right
	xpLabel.TextColor3 = SOFT_TEXT
	thinOutline(xpLabel, 1.5)
	local fill = bar(summary, UDim2.new(1, -104, 0, 16), UDim2.fromOffset(86, 128), XP_BLUE)
	summaryBar = { badge = levelNumber, level = level, xp = xpLabel, fill = fill }
	summaryUnlocked = leftText(summary, "", UDim2.new(1, -104, 0, 16), UDim2.fromOffset(86, 150))
	summaryUnlocked.TextColor3 = GOLD_TEXT
	thinOutline(summaryUnlocked, 1.5)
	summaryStamp = MenuStyle.Text(summary, "LEVEL UP!", UDim2.fromOffset(300, 60), UDim2.new(0.5, 0, 0, -8), Vector2.new(0.5, 1))
	summaryStamp.TextColor3 = Color3.fromRGB(120, 255, 100)
	summaryStamp.Rotation = -6
	summaryStamp.Visible = false
	Instance.new("UIScale").Parent = summaryStamp
end

local function build()
	gui = Instance.new("ScreenGui")
	gui.Name = "Progress"
	gui.IgnoreGuiInset = true
	gui.ResetOnSpawn = false
	gui.DisplayOrder = 8 -- over the lobby menu, the shop's and the party's buttons
	gui.Parent = player:WaitForChild("PlayerGui")
	buildWidget()
	buildScreen()
	buildPopup()
	buildMatchBits()
end

-- ─── Running ───────────────────────────────────────────────────────────────────

function ProgressMenu.Open()
	if screenOpen then
		return
	end
	screenOpen = true
	screen.Visible = true
	popupBack.Visible = false
	selectTab(if dailyReady() then "Daily" else tab)
end

function ProgressMenu.Close()
	screenOpen = false
	screen.Visible = false
end

-- The match starting / ending: the XP card's starting point, and the card itself
local function onPhase()
	local phase = MatchState:GetAttribute("Phase")
	if phase == "Waiting" or phase == nil then
		matchStartXp = nil
		matchStartCredits = nil
		table.clear(matchGains)
		closeSummary()
		return
	end
	if matchStartXp == nil and loaded() then
		matchStartXp = xp()
		local credits = player:GetAttribute("Credits")
		matchStartCredits = if typeof(credits) == "number" then credits else nil
		table.clear(matchGains)
	end
	if phase == "MatchOver" then
		openSummary()
	else
		closeSummary()
	end
end

local function update(dt: number)
	local lobby = inLobbyMenu()
	if screenOpen and not lobby then
		ProgressMenu.Close() -- a match is starting
	end
	local otherMenu = state.shopOpen or state.modesOpen or state.partyOpen
	widget.Visible = lobby and not screenOpen and not otherMenu
	-- Daily reward waiting: pops up by itself (once a day if you say LATER)
	if lobby and dailyReady() and not screenOpen and not otherMenu and popupDismissedDay ~= today() then
		if not popupBack.Visible then
			popupBack.Visible = true
			refresh()
		end
	elseif popupBack.Visible and (not lobby or not dailyReady() or otherMenu) then
		popupBack.Visible = false
	end
	if summaryOpen then
		-- After the match results screen (MatchResults): the bar fills once that's out of the way
		local show = not state.resultsOpen
		if show and not summary.Visible then
			summaryOpenedAt = os.clock()
		end
		summary.Visible = show
		updateSummary(dt)
	end
	-- Timers ("NEW CHALLENGES IN ...") and the leaderboards, once a second while something shows them
	if (screenOpen or popupBack.Visible) and os.clock() - lastTick > 1 then
		lastTick = os.clock()
		refresh()
	end
end

function ProgressMenu.Start()
	build()
	refresh()
	for _, attribute in { "Xp", "DailyDay", "DailyStreak", "Challenges", "Stats", "DataOffline" } do
		player:GetAttributeChangedSignal(attribute):Connect(refresh)
	end
	player:GetAttributeChangedSignal("Xp"):Connect(function()
		-- (joined mid-match: the card counts from when your data came in)
		if matchStartXp == nil and MatchState:GetAttribute("Phase") ~= "Waiting" then
			onPhase()
		end
	end)
	MatchState:GetAttributeChangedSignal("Phase"):Connect(onPhase)
	onPhase()

	Progress.OnClientEvent:Connect(function(event, a, b)
		if event == "Xp" and typeof(a) == "number" and typeof(b) == "string" then
			if matchStartXp ~= nil then
				matchGains[b] = (matchGains[b] or 0) + a
			end
		elseif event == "LevelUp" and typeof(a) == "number" and typeof(b) == "number" then
			if not summaryOpen then -- (the XP card stamps it itself)
				showBanner("LEVEL UP!", `LEVEL {a} · {unlockText(b, a)}`, Color3.fromRGB(120, 255, 100))
				Effects.Sound(Sounds.Shop.Buy, nil, Sounds.Shop.Volume, 1.25)
			end
		elseif event == "Challenge" and typeof(a) == "string" then
			local challenge = Progression.ChallengeById[a]
			if challenge then
				showBanner("CHALLENGE COMPLETE", `{string.upper(challenge.Text)} · +{challenge.Credits} CREDITS · +{challenge.Xp} XP`, GOLD_TEXT)
				Effects.Sound(Sounds.Shop.Credits, nil, Sounds.Shop.Volume, 1.4)
			end
		elseif event == "Daily" and typeof(a) == "number" and typeof(b) == "number" then
			claiming = 0
			popupBack.Visible = false
			showBanner("DAILY REWARD", `DAY {a} · +{b} CREDITS` .. (if a == Skins.DailyStreakDays then " · DAYBREAK SKIN UNLOCKED!" else ""), GOLD_TEXT)
			Effects.Sound(Sounds.Shop.Buy, nil, Sounds.Shop.Volume, 1.25)
			refresh()
		end
	end)
	RunService.RenderStepped:Connect(update)
end

return ProgressMenu
