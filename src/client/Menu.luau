-- The menu: Quick Match (1v1 / 2v2 / 3v3 / 5v5), Make Lobby, Single Player, Tutorial.
-- The menu only asks the server; the server answers with "queue", "lobbyList", "lobby",
-- "notice" and finally the match "start".
-- It looks retro (old console): see Retro.luau.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("WarInGrassShared")
local Config = require(Shared.Config)
local Ui = require(script.Parent.Retro) -- same functions as Ui.luau, but in the retro look
local Retro = Ui
local AntView = require(script.Parent.AntView)

local MENU_ANT_SIZE = 1.6 -- the walking ants in the menu are bigger than in the match
local MENU_ANT_SPEED = 36 -- in map pixels per second (like walking in the match)

local Menu = {}

local root: Frame
local panel: Frame
local screens: { [string]: Frame } = {}
local net: Folder
local noticeLabel: TextLabel
local noticeToken = 0

-- what the player started last (for "Jeszcze raz" after a match)
local lastAction: { any }? = nil

-- searching screen
local searchTitle: TextLabel
local searchCount: TextLabel
-- lobby list screen
local lobbyListFrame: ScrollingFrame
local lobbyEmpty: TextLabel
-- lobby room screen
local roomTitle: TextLabel
local teamLists: { Frame } = {}
local hostButtons: { TextButton } = {}
local roomCount: TextLabel

local function send(action: string, arg: any?)
	(net:FindFirstChild("Lobby") :: RemoteEvent):FireServer(action, arg)
end

local function show(name: string)
	for screenName, frame in screens do
		frame.Visible = screenName == name
	end
	root.Visible = true
end

local function newScreen(name: string, title: string): Frame
	local frame = Instance.new("Frame")
	frame.Name = name
	frame.Size = UDim2.fromScale(1, 1)
	frame.BackgroundTransparency = 1
	frame.ZIndex = 21
	frame.Visible = false
	frame.Parent = panel
	local titleLabel = Ui.label(frame, UDim2.fromScale(0.5, 0.09), UDim2.fromScale(0.85, 0.1), Color3.new(1, 1, 1))
	titleLabel.Text = title
	titleLabel.ZIndex = 22
	screens[name] = frame
	return frame
end

local function clear(container: Instance)
	for _, child in container:GetChildren() do
		if child:IsA("GuiObject") then
			child:Destroy()
		end
	end
end

function Menu.notice(text: string)
	noticeToken += 1
	local token = noticeToken
	noticeLabel.Text = text
	noticeLabel.TextTransparency = 0
	noticeLabel.TextStrokeTransparency = 0.3
	task.delay(2.5, function()
		if noticeToken == token then
			TweenService:Create(noticeLabel, TweenInfo.new(0.5), { TextTransparency = 1, TextStrokeTransparency = 1 }):Play()
		end
	end)
end

---------------------------------------------------------------- building the screens

function Menu.init(gui: ScreenGui, netFolder: Folder)
	net = netFolder

	root = Instance.new("Frame")
	root.Name = "Menu"
	root.Size = UDim2.fromScale(1, 1)
	root.BorderSizePixel = 0
	root.ZIndex = 1
	root.Parent = gui
	local stepScene, groundLine = Retro.scene(root)

	-- two ants from the match walk on the grass: a black one and a red one
	-- (AntView counts in map pixels: 1024 x 576 = the whole menu screen)
	local W, H = Config.MAP_WIDTH, Config.MAP_HEIGHT
	local walkers = {}
	for _, setup in { { team = 1, dir = 1, x = 100 }, { team = 2, dir = -1, x = 780 } } do
		local view = AntView.new(root, setup.team, "", false, MENU_ANT_SIZE)
		view.hpLabel.Visible = false
		view.nameLabel.Visible = false
		table.insert(walkers, { view = view, dir = setup.dir, x = setup.x, pause = 0 })
	end
	local function stepWalkers(dt: number)
		local screenH = root.AbsoluteSize.Y
		if screenH <= 0 then
			return
		end
		local groundY = groundLine() / screenH * H
		for _, ant in walkers do
			local moved = 0
			if ant.pause > 0 then
				ant.pause -= dt -- stops for a moment to look around
			else
				moved = MENU_ANT_SPEED * dt
				ant.x += ant.dir * moved
				if ant.x > W + 30 then
					ant.x = -30
				elseif ant.x < -30 then
					ant.x = W + 30
				end
				if math.random() < dt * 0.12 then
					ant.pause = 1.2
				end
			end
			AntView.draw(ant.view, {
				x = ant.x,
				y = groundY - 1,
				facing = ant.dir,
				aim = 0,
				onGround = true,
				walking = ant.pause <= 0,
				hp = 0,
				isCurrent = false,
				charging = false,
				power = 0,
			}, dt, moved)
		end
	end

	-- logo: yellow pixel letters with a red and a black shadow, bobbing up and down
	local logoBox = Instance.new("Frame")
	logoBox.BackgroundTransparency = 1
	logoBox.AnchorPoint = Vector2.new(0.5, 0.5)
	logoBox.Position = UDim2.fromScale(0.5, 0.1)
	logoBox.Size = UDim2.fromScale(0.62, 0.1)
	logoBox.ZIndex = 6
	logoBox.Parent = root
	local layers = {
		{ color = Color3.new(0, 0, 0), offset = 8 },
		{ color = Color3.fromRGB(200, 40, 30), offset = 4 },
		{ color = Color3.fromRGB(255, 224, 64), offset = 0 },
	}
	for i, layer in layers do
		local text = Ui.label(logoBox, UDim2.new(0.5, layer.offset, 0.5, layer.offset), UDim2.fromScale(1, 1), layer.color)
		text.Text = "WAR IN GRASS"
		text.TextWrapped = false
		text.TextStrokeTransparency = 1
		text.ZIndex = 6 + i
	end
	local subtitle = Ui.label(root, UDim2.fromScale(0.5, 0.19), UDim2.fromScale(0.55, 0.035), Color3.new(1, 1, 1))
	subtitle.Text = "Czarne mrówki kontra czerwone mrówki"
	subtitle.ZIndex = 6

	local time = 0
	RunService.RenderStepped:Connect(function(dt)
		if not root.Visible then
			return
		end
		time += dt
		stepScene(dt)
		stepWalkers(dt)
		-- bob in whole steps of 4 pixels, like an old game
		local bob = math.floor(math.sin(time * 2.5) * 2 + 0.5) * 4
		logoBox.Position = UDim2.new(0.5, 0, 0.1, bob)
	end)

	panel = Ui.panel(root, UDim2.fromScale(0.5, 0.58), UDim2.fromScale(0.5, 0.7), 20)
	local panelAspect = Instance.new("UIAspectRatioConstraint")
	panelAspect.AspectRatio = 1.25
	panelAspect.Parent = panel

	noticeLabel = Ui.label(root, UDim2.fromScale(0.5, 0.96), UDim2.fromScale(0.6, 0.045), Color3.fromRGB(255, 230, 120))
	noticeLabel.ZIndex = 40

	local function wide(y: number): (UDim2, UDim2)
		return UDim2.fromScale(0.5, y), UDim2.fromScale(0.8, 0.13)
	end

	-- main menu
	local main = newScreen("main", "MENU")
	local p, s = wide(0.27)
	local quickButton = Ui.button(main, "Quick Match", p, s, "main", function()
		show("quick")
	end)
	p, s = wide(0.44)
	local lobbyButton = Ui.button(main, "Make Lobby", p, s, "normal", function()
		send("browse")
		show("lobbies")
	end)
	p, s = wide(0.61)
	local singleButton = Ui.button(main, "Single Player", p, s, "normal", function()
		show("single")
	end)
	p, s = wide(0.78)
	local tutorialButton = Ui.button(main, "Tutorial", p, s, "gold", function()
		lastAction = { "single", 1 } -- "Jeszcze raz" after the tutorial = a normal game with 1 bot
		send("tutorial")
	end)
	-- all 4 captions the same size (otherwise the longest one, "Single Player", is smaller)
	local captions = {}
	for _, button in { quickButton, lobbyButton, singleButton, tutorialButton } do
		table.insert(captions, button:FindFirstChild("Caption") :: TextLabel)
	end
	Retro.sameSize(captions)

	-- single player: pick how many enemy bots
	local single = newScreen("single", "Single Player: ile botów?")
	for i, bots in Config.SINGLE_BOTS do
		local col, row = (i - 1) % 2, math.floor((i - 1) / 2)
		Ui.button(
			single,
			if bots == 1 then "1 bot" elseif bots < 5 then bots .. " boty" else bots .. " botów",
			UDim2.fromScale(0.3 + col * 0.4, 0.33 + row * 0.22),
			UDim2.fromScale(0.34, 0.17),
			"main",
			function()
				lastAction = { "single", bots }
				send("single", bots)
			end
		)
	end
	Ui.button(single, "← Wróć", UDim2.fromScale(0.5, 0.82), UDim2.fromScale(0.4, 0.11), "normal", function()
		show("main")
	end)

	-- quick match: pick the size
	local quick = newScreen("quick", "Quick Match: ile na ile?")
	for i, mode in Config.QUICK_MODES do
		local col, row = (i - 1) % 2, math.floor((i - 1) / 2)
		Ui.button(
			quick,
			mode .. " v " .. mode,
			UDim2.fromScale(0.3 + col * 0.4, 0.33 + row * 0.22),
			UDim2.fromScale(0.34, 0.17),
			"main",
			function()
				lastAction = { "quick", mode }
				send("quick", mode)
			end
		)
	end
	Ui.button(quick, "← Wróć", UDim2.fromScale(0.5, 0.82), UDim2.fromScale(0.4, 0.11), "normal", function()
		show("main")
	end)

	-- searching for players
	local searching = newScreen("searching", "Szukam graczy…")
	searchTitle = Ui.label(searching, UDim2.fromScale(0.5, 0.3), UDim2.fromScale(0.8, 0.08), Color3.new(1, 1, 1))
	searchTitle.ZIndex = 22
	searchCount = Ui.label(searching, UDim2.fromScale(0.5, 0.45), UDim2.fromScale(0.6, 0.1), Color3.fromRGB(255, 220, 90))
	searchCount.ZIndex = 22
	local searchHint = Ui.label(searching, UDim2.fromScale(0.5, 0.63), UDim2.fromScale(0.85, 0.12), Color3.fromRGB(200, 215, 200))
	searchHint.Text = "Gra zacznie się sama, gdy będzie dość graczy na tym serwerze"
	searchHint.ZIndex = 22
	Ui.button(searching, "Anuluj", UDim2.fromScale(0.5, 0.82), UDim2.fromScale(0.4, 0.11), "danger", function()
		send("cancel")
		show("main")
	end)

	-- list of lobbies
	local lobbies = newScreen("lobbies", "Lobby")
	lobbyListFrame = Instance.new("ScrollingFrame")
	lobbyListFrame.AnchorPoint = Vector2.new(0.5, 0)
	lobbyListFrame.Position = UDim2.fromScale(0.5, 0.18)
	lobbyListFrame.Size = UDim2.fromScale(0.86, 0.5)
	lobbyListFrame.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
	lobbyListFrame.BackgroundTransparency = 0.3
	lobbyListFrame.BorderSizePixel = 0
	lobbyListFrame.ScrollBarThickness = 8
	lobbyListFrame.ScrollBarImageColor3 = Color3.new(1, 1, 1)
	lobbyListFrame.AutomaticCanvasSize = Enum.AutomaticSize.Y
	lobbyListFrame.CanvasSize = UDim2.new()
	lobbyListFrame.ZIndex = 22
	lobbyListFrame.Parent = lobbies
	local listLayout = Instance.new("UIListLayout")
	listLayout.Padding = UDim.new(0, 6)
	listLayout.SortOrder = Enum.SortOrder.LayoutOrder
	listLayout.Parent = lobbyListFrame
	local listPadding = Instance.new("UIPadding")
	listPadding.PaddingTop = UDim.new(0, 6)
	listPadding.PaddingLeft = UDim.new(0, 6)
	listPadding.PaddingRight = UDim.new(0, 12)
	listPadding.Parent = lobbyListFrame
	lobbyEmpty = Ui.label(lobbies, UDim2.fromScale(0.5, 0.43), UDim2.fromScale(0.8, 0.12), Color3.fromRGB(200, 215, 200))
	lobbyEmpty.Text = "Nie ma jeszcze żadnego lobby. Stwórz swoje!"
	lobbyEmpty.ZIndex = 23
	Ui.button(lobbies, "+ Stwórz lobby", UDim2.fromScale(0.5, 0.77), UDim2.fromScale(0.5, 0.11), "main", function()
		lastAction = nil
		send("create")
	end)
	Ui.button(lobbies, "← Wróć", UDim2.fromScale(0.5, 0.91), UDim2.fromScale(0.3, 0.08), "normal", function()
		show("main")
	end)

	-- inside a lobby
	local room = newScreen("room", "Lobby")
	roomTitle = room:FindFirstChildOfClass("TextLabel") :: TextLabel
	for team = 1, 2 do
		local column = Instance.new("Frame")
		column.Position = UDim2.fromScale(0.05 + (team - 1) * 0.47, 0.17)
		column.Size = UDim2.fromScale(0.43, 0.5)
		column.BackgroundColor3 = Config.TEAMS[team].color
		column.BackgroundTransparency = 0.2
		column.BorderSizePixel = 0
		column.ZIndex = 22
		column.Parent = room
		local edge = Instance.new("UIStroke")
		edge.Thickness = 3
		edge.LineJoinMode = Enum.LineJoinMode.Miter
		edge.Parent = column
		local header = Ui.label(column, UDim2.fromScale(0.5, 0.08), UDim2.fromScale(0.9, 0.12), Config.TEAMS[team].light)
		header.Text = Config.TEAMS[team].name
		header.ZIndex = 23
		local list = Instance.new("Frame")
		list.Position = UDim2.fromScale(0.05, 0.18)
		list.Size = UDim2.fromScale(0.9, 0.8)
		list.BackgroundTransparency = 1
		list.ZIndex = 23
		list.Parent = column
		local layout = Instance.new("UIListLayout")
		layout.Padding = UDim.new(0.01, 0)
		layout.Parent = list
		teamLists[team] = list
	end
	roomCount = Ui.label(room, UDim2.fromScale(0.5, 0.71), UDim2.fromScale(0.9, 0.06), Color3.fromRGB(200, 215, 200))
	roomCount.ZIndex = 22
	Ui.button(room, "Zmień drużynę", UDim2.fromScale(0.27, 0.8), UDim2.fromScale(0.4, 0.09), "normal", function()
		send("team")
	end)
	Ui.button(room, "Wyjdź", UDim2.fromScale(0.73, 0.8), UDim2.fromScale(0.4, 0.09), "danger", function()
		send("leave")
		send("browse")
		show("lobbies")
	end)
	table.insert(hostButtons, Ui.button(room, "+ Bot", UDim2.fromScale(0.17, 0.92), UDim2.fromScale(0.22, 0.08), "normal", function()
		send("addBot")
	end))
	table.insert(hostButtons, Ui.button(room, "- Bot", UDim2.fromScale(0.41, 0.92), UDim2.fromScale(0.22, 0.08), "normal", function()
		send("removeBot")
	end))
	table.insert(hostButtons, Ui.button(room, "▶ Start", UDim2.fromScale(0.74, 0.92), UDim2.fromScale(0.36, 0.08), "main", function()
		send("start")
	end))

	show("main")
end

---------------------------------------------------------------- messages from the server

local function showLobbyList(list)
	clear(lobbyListFrame) -- (the list layout is not a GuiObject, so it stays)
	lobbyEmpty.Visible = #list == 0
	for _, item in list do
		local row = Instance.new("Frame")
		row.Size = UDim2.new(1, 0, 0, 44)
		row.BackgroundColor3 = Color3.fromRGB(16, 24, 64)
		row.BorderSizePixel = 0
		row.ZIndex = 23
		row.Parent = lobbyListFrame
		local edge = Instance.new("UIStroke")
		edge.Color = Color3.new(1, 1, 1)
		edge.Thickness = 2
		edge.LineJoinMode = Enum.LineJoinMode.Miter
		edge.Parent = row
		local name = Ui.label(row, UDim2.fromScale(0.36, 0.5), UDim2.fromScale(0.66, 0.5), Color3.new(1, 1, 1))
		name.Text = "Lobby: " .. item.host
		name.TextXAlignment = Enum.TextXAlignment.Left
		name.ZIndex = 24
		local count = Ui.label(row, UDim2.fromScale(0.73, 0.5), UDim2.fromScale(0.14, 0.6), Color3.fromRGB(255, 220, 90))
		count.Text = item.count .. "/" .. item.max
		count.ZIndex = 24
		local join = Ui.button(row, "Dołącz", UDim2.fromScale(0.9, 0.5), UDim2.fromScale(0.18, 0.8), "main", function()
			lastAction = nil
			send("join", item.id)
		end)
		join.ZIndex = 25
	end
end

local function showRoom(state)
	roomTitle.Text = "Lobby (" .. #state.members .. "/" .. state.max .. ")"
	for team = 1, 2 do
		clear(teamLists[team])
	end
	for _, member in state.members do
		local text = (if member.isBot then "🤖 " elseif member.isHost then "👑 " else "🐜 ") .. member.name
		if member.isMe then
			text ..= " (Ty)"
		end
		local line = Instance.new("TextLabel")
		line.Size = UDim2.fromScale(1, 0.12)
		line.BackgroundTransparency = 1
		line.FontFace = Retro.FONT
		line.Text = text
		Retro.fit(line)
		line.TextColor3 = if member.isMe then Color3.fromRGB(255, 224, 64) else Color3.new(1, 1, 1)
		line.TextStrokeTransparency = 0
		line.TextXAlignment = Enum.TextXAlignment.Left
		line.ZIndex = 24
		line.Parent = teamLists[member.team]
	end
	for _, button in hostButtons do
		button.Visible = state.isHost
	end
	roomCount.Text = if state.isHost
		then "Ty jesteś gospodarzem 👑 Dodaj boty albo poczekaj na graczy i kliknij Start"
		else "Czekamy, aż gospodarz 👑 kliknie Start"
end

function Menu.message(kind: string, a: any, b: any, c: any)
	if kind == "queue" then
		searchTitle.Text = "Quick Match " .. a .. " v " .. a
		searchCount.Text = b .. " / " .. c .. " graczy"
		if root.Visible then
			show("searching")
		end
	elseif kind == "lobbyList" then
		showLobbyList(a)
	elseif kind == "lobby" then
		showRoom(a)
		if root.Visible then
			show("room")
		end
	elseif kind == "notice" then
		Menu.notice(a)
	end
end

---------------------------------------------------------------- show / hide

function Menu.hide()
	root.Visible = false
end

function Menu.showMain()
	show("main")
end

function Menu.canPlayAgain(): boolean
	return lastAction ~= nil
end

function Menu.playAgain()
	if lastAction then
		send(lastAction[1], lastAction[2])
	end
end

return Menu
