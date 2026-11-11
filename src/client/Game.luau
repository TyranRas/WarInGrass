-- The match screen. The server plays the match; this file draws what the server sends
-- (snapshots ~20 times a second + events like explosions) and sends what the player
-- presses (only on their own turn).
local ContextActionService = game:GetService("ContextActionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("WarInGrassShared")
local Config = require(Shared.Config)
local MapData = require(Shared.MapData)
local Map = require(script.Parent.Map)
local AntView = require(script.Parent.AntView)
local Retro = require(script.Parent.Retro) -- the retro look (same as the menu)
local Sound = require(script.Parent.Sound)
local Ui = Retro

local W, H = Config.MAP_WIDTH, Config.MAP_HEIGHT
local WATER_Y = H - Config.WATER_HEIGHT
local ANT_HEIGHT = 10
local AIM_SEND_EVERY = 1 / 15 -- how often the aim is sent to the server (at most)

local player = Players.LocalPlayer
local myId = player.UserId

local Game = {}

---------------------------------------------------------------- types

type Ant = {
	id: number,
	team: number,
	ownerId: number,
	name: string,
	isBot: boolean,
	view: AntView.View,
	x: number?, -- where it is drawn (slides toward tx, ty)
	y: number?,
	tx: number,
	ty: number,
	hp: number,
	alive: boolean,
	onGround: boolean,
	walking: boolean,
	facing: number,
	aim: number,
}

type Snap = {
	state: string,
	cur: number,
	time: number,
	wind: number,
	power: number,
	charging: boolean,
	tutorial: boolean,
	weapon: number, -- weapon of the ant whose turn it is (1 acorn, 2 chestnut, 3 rain)
	rainLeft: number,
	flying: { { kind: number, x: number, y: number } }, -- 1 acorn, 2 chestnut, 3 seed, 4 rain
	turnId: number,
}

---------------------------------------------------------------- screen

local function at(x: number, y: number): UDim2
	return UDim2.fromScale(x / W, y / H)
end

local root: Frame
local world: Frame
local backImage: ImageLabel
local terrainImage: ImageLabel
local turnLabel: TextLabel
local timerLabel: TextLabel
local messageLabel: TextLabel
local subMessageLabel: TextLabel
local tutorialPanel: Frame
local tutorialText: TextLabel
local tutorialHint: TextLabel
local powerBack: Frame
local powerCells: { Frame } = {}
local windBox: Frame
local windBoxStroke: UIStroke
local windValue: TextLabel
local windCells: { Frame } = {} -- 1..10 left of the middle, 11..20 right
local crosshair: Frame
local marker: Frame
local markerParts: { Frame } = {}
local weaponBar: Frame
local weaponSlots: { { box: Frame, stroke: UIStroke, name: TextLabel, count: TextLabel? } } = {}
local rainTarget: Frame -- shows where the chestnut rain will fall (follows the mouse)
local skyClouds: { { frame: Frame, x: number, y: number, speed: number } } = {}
local waves: { Frame } = {}
local resultPanel: Frame
local resultTitle: TextLabel
local resultSub: TextLabel
local againButton: TextButton

local net: Folder
local callbacks: { onMenu: () -> (), onAgain: () -> (), canPlayAgain: () -> boolean }

---------------------------------------------------------------- match state

local data: MapData.MapData? = nil
local mapView: Map.Map? = nil
local ants: { [number]: Ant } = {}
local snap: Snap? = nil
-- pictures of the flying things (number i = the i-th thing in the snapshot)
local flyViews: { { frame: Frame, kind: number, shown: Vector2 } } = {}
local running = false
local isTutorial = false
local shownWind = 0
local lastSentWalk = 0
local lastSentAim, lastSentFacing, lastAimSend = 999, 0, 0
local localCharging = false
local localAim, localFacing = 30, 1
local keys: { [Enum.KeyCode]: boolean } = {}
local messageToken = 0

local function sendInput(action: string, a: any?, b: any?)
	(net:FindFirstChild("Input") :: RemoteEvent):FireServer(action, a, b)
end

-- Where the mouse is, in map pixels (nil if the map is not on the screen yet).
local function mouseOnMap(): Vector2?
	local mouse = player:GetMouse()
	local pos, size = world.AbsolutePosition, world.AbsoluteSize
	if size.X <= 0 or size.Y <= 0 then
		return nil
	end
	return Vector2.new((mouse.X - pos.X) / size.X * W, (mouse.Y - pos.Y) / size.Y * H)
end

-- Pixel pictures of the flying things: 1 acorn, 2 chestnut, 3 seed, 4 rain chestnut.
local function makeFlyView(kind: number): Frame
	local view = Instance.new("Frame")
	view.AnchorPoint = Vector2.new(0.5, 0.5)
	view.BackgroundTransparency = 1
	view.ZIndex = 5
	view.Parent = world
	local parts, gridW, gridH
	if kind == 1 then -- acorn 4 x 5: stem, dark cap, light body
		view.Size = at(8, 10)
		gridW, gridH = 4, 5
		parts = {
			{ 1.5, 0, 1, 1, Color3.fromRGB(88, 56, 24) },
			{ 0, 1, 4, 1, Color3.fromRGB(104, 64, 24) },
			{ 0.5, 2, 3, 2, Color3.fromRGB(196, 132, 56) },
			{ 1, 4, 2, 1, Color3.fromRGB(196, 132, 56) },
			{ 1, 2, 1, 1, Color3.fromRGB(236, 184, 104) },
		}
	elseif kind == 3 then -- seed 2 x 2
		view.Size = at(4, 4)
		gridW, gridH = 2, 2
		parts = {
			{ 0, 0, 2, 2, Color3.fromRGB(232, 196, 120) },
			{ 1, 1, 1, 1, Color3.fromRGB(160, 116, 56) },
		}
	else -- chestnut 5 x 5: shiny dark brown with a pale spot
		view.Size = at(10, 10)
		gridW, gridH = 5, 5
		parts = {
			{ 1, 0, 3, 1, Color3.fromRGB(110, 48, 18) },
			{ 0, 1, 5, 3, Color3.fromRGB(110, 48, 18) },
			{ 1, 4, 3, 1, Color3.fromRGB(110, 48, 18) },
			{ 1, 1, 1, 1, Color3.fromRGB(196, 110, 60) },
			{ 1, 3, 3, 1, Color3.fromRGB(224, 196, 150) },
		}
	end
	for _, r in parts do
		Retro.block(view, r[5], UDim2.fromScale(r[1] / gridW, r[2] / gridH), UDim2.fromScale(r[3] / gridW, r[4] / gridH), 5)
	end
	return view
end

local function currentAnt(): Ant?
	return if snap and snap.cur > 0 then ants[snap.cur] else nil
end

local function isMyTurn(): boolean
	local ant = currentAnt()
	return snap ~= nil and snap.state == "aim" and ant ~= nil and ant.ownerId == myId and ant.alive
end

local function myTeam(): number?
	for _, ant in ants do
		if ant.ownerId == myId then
			return ant.team
		end
	end
	return nil
end

-- A big message in the middle for a moment (or until replaced).
local function flashMessage(text: string, color: Color3?, seconds: number?)
	messageToken += 1
	local token = messageToken
	messageLabel.TextColor3 = color or Color3.new(1, 1, 1)
	messageLabel.Text = text
	subMessageLabel.Text = ""
	task.delay(seconds or 2, function()
		if messageToken == token then
			messageLabel.Text = ""
		end
	end)
end

local function floatingText(text: string, x: number, y: number, color: Color3)
	local t = Ui.label(world, at(x, y), at(60, 14), color)
	t.TextWrapped = false
	t.ZIndex = 12
	-- rises in whole steps, like an old game
	TweenService:Create(t, TweenInfo.new(1.2, Enum.EasingStyle.Linear), { Position = at(x, y - 35) }):Play()
	task.delay(0.9, function()
		t.Visible = false
		task.wait(0.1)
		t.Visible = true
		task.wait(0.1)
		t:Destroy()
	end)
end

-- A little cloud of square dust (landing after a fall).
local function dust(x: number, y: number)
	for i = -1, 1 do
		local puff = Retro.block(world, Color3.fromRGB(220, 200, 160), at(x + i * 4, y - 2), at(4, 4), 5)
		puff.AnchorPoint = Vector2.new(0.5, 0.5)
		TweenService:Create(puff, TweenInfo.new(0.5), {
			Position = at(x + i * 10, y - 6),
			Size = at(2, 2),
			BackgroundTransparency = 1,
		}):Play()
		task.delay(0.5, puff.Destroy, puff)
	end
end

-- A pixel explosion: a big square flash and square sparks flying out.
local SPARK_COLORS = {
	Color3.fromRGB(252, 252, 252),
	Color3.fromRGB(252, 216, 56),
	Color3.fromRGB(248, 120, 0),
	Color3.fromRGB(216, 40, 0),
}
local sparkRng = Random.new()
local function pixelBlast(x: number, y: number, radius: number)
	local flash = Retro.block(world, SPARK_COLORS[2], at(x, y), at(radius * 1.6, radius * 1.6), 7)
	flash.AnchorPoint = Vector2.new(0.5, 0.5)
	task.spawn(function()
		-- the flash changes color in steps: white, yellow, orange, red, gone
		for _, c in { SPARK_COLORS[1], SPARK_COLORS[2], SPARK_COLORS[3], SPARK_COLORS[4] } do
			flash.BackgroundColor3 = c
			task.wait(0.06)
		end
		flash:Destroy()
	end)
	for _ = 1, 16 do
		local angle = sparkRng:NextNumber(0, math.pi * 2)
		local far = radius * sparkRng:NextNumber(0.8, 1.8)
		local size = sparkRng:NextInteger(2, 3) * 2
		local spark = Retro.block(world, SPARK_COLORS[sparkRng:NextInteger(1, 4)], at(x, y), at(size, size), 7)
		spark.AnchorPoint = Vector2.new(0.5, 0.5)
		local time = sparkRng:NextNumber(0.3, 0.55)
		TweenService:Create(spark, TweenInfo.new(time, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
			Position = at(x + math.cos(angle) * far, y + math.sin(angle) * far),
		}):Play()
		task.delay(time, spark.Destroy, spark)
	end
end

---------------------------------------------------------------- wind meter + streaks

local WEAK, MEDIUM, STRONG = Color3.fromRGB(56, 200, 56), Color3.fromRGB(252, 216, 56), Color3.fromRGB(232, 56, 24)
local CELL_OFF = Color3.fromRGB(36, 40, 64)

local function levelColor(level: number): Color3
	return if level <= 4 then WEAK elseif level <= 7 then MEDIUM else STRONG
end

-- d goes from -1 (full left) to 1 (full right). The bar lights up cells from the middle out.
local function showWind(d: number)
	local number = math.floor(math.abs(d) * 10 + 0.5)
	for i, cell in windCells do
		local level = if i <= 10 then 11 - i else i - 10 -- 1 next to the middle, 10 at the end
		local lit = number > 0 and level <= number and ((i <= 10) == (d < 0))
		cell.BackgroundColor3 = if lit then levelColor(level) else CELL_OFF
	end
	windValue.Text = if number == 0 then "0" elseif d < 0 then "←" .. number else number .. "→"
	windValue.TextColor3 = if number == 0 then Color3.new(1, 1, 1) else levelColor(number)
end

-- Small white streaks fly through the air with the wind: more, longer and faster when
-- it blows hard. Only for looks.
type Streak = { x: number, y: number, phase: number, view: Frame }
local streaks: { Streak } = {}
local MAX_STREAKS = 50
local streakRng = Random.new()

local function updateStreaks(dt: number)
	local t = os.clock()
	local strength = math.abs(shownWind) / Config.MAX_WIND
	local active = 8 + math.floor(strength * (MAX_STREAKS - 8))
	for i, s in streaks do
		if i > active then
			s.view.Visible = false
			continue
		end
		if not s.view.Visible then
			s.x, s.y = streakRng:NextNumber(0, W), streakRng:NextNumber(0, H * 0.7)
			s.view.Visible = true
		end
		s.x += (shownWind * 2.5 + math.sin(t * 1.7 + s.phase) * 3) * dt
		s.y += math.cos(t * 1.3 + s.phase) * 4 * dt
		if s.x > W + 6 then
			s.x, s.y = -6, streakRng:NextNumber(0, H * 0.7)
		elseif s.x < -6 then
			s.x, s.y = W + 6, streakRng:NextNumber(0, H * 0.7)
		end
		-- square streaks on whole 2-pixel steps (retro)
		s.view.Position = at(math.floor(s.x / 2) * 2, math.floor(s.y / 2) * 2)
		s.view.Size = at(math.floor((4 + strength * 12) / 2) * 2, 2)
		s.view.BackgroundTransparency = if math.sin(t * 2.3 + s.phase) > 0 then 0.35 else 0.6
		-- no wind under the ground (in tunnels and blast holes): hide the streak there.
		-- (Over the ground it is hidden anyway: the ground picture is drawn on top of it.)
		local map = data
		if map then
			local column = math.clamp(math.floor(s.x), 0, W - 1)
			if s.y >= map.tops[column] then
				s.view.BackgroundTransparency = 1
			end
		end
	end
end

---------------------------------------------------------------- tutorial

-- Steps with `goal` wait until the player does it, then say "Brawo!" for a moment.
-- Steps without a goal only show text and go on after a mouse click.
type TutorialStep = { text: string, goal: string?, need: number?, highlightWind: boolean? }
local TUTORIAL: { TutorialStep } = {
	{ text = "Witaj w War in Grass! Czarne mrówki walczą z czerwonymi. Rzucajcie w siebie żołędziami!" },
	{ text = "Chodź na A i D", goal = "walk", need = 60 },
	{ text = "Skocz na W", goal = "jump" },
	{ text = "Celuj myszą: rusz kursorem w górę i w dół, a mrówka spojrzy w tę stronę", goal = "aim", need = 90 },
	{ text = "Przytrzymaj Spację, żeby nabrać siły, i puść, żeby rzucić żołędziem", goal = "throw" },
	{
		text = "Wiatr znosi żołądź! Pasek w lewym górnym rogu pokazuje, w którą stronę i jak mocno wieje",
		highlightWind = true,
	},
	{ text = "Nie wpadnij do wody! Masz 30 sekund na turę. Teraz zagraj z botem. Powodzenia!" },
}
local CLICK_DELAY = 1.5 -- a click in the first seconds of a step does nothing (no skipping by accident)
local PRAISE_TIME = 1.5 -- how long "Brawo!" stays
local tutorialStep = 0 -- 0 = tutorial is off
local tutorialTime = 0
local tutorialAmount = 0
local tutorialPraising = false

local function popTutorialPanel()
	tutorialPanel.Size = UDim2.fromScale(0.56, 0.12)
	TweenService:Create(tutorialPanel, TweenInfo.new(0.25, Enum.EasingStyle.Back), { Size = UDim2.fromScale(0.62, 0.14) })
		:Play()
end

local function setTutorialStep(n: number)
	local wasOn = tutorialStep > 0
	tutorialStep = if n > #TUTORIAL then 0 else n
	tutorialTime, tutorialAmount, tutorialPraising = 0, 0, false
	local step = TUTORIAL[tutorialStep]
	tutorialPanel.Visible = step ~= nil
	if not step then
		if wasOn and running then
			sendInput("tutorialEnd") -- the real game starts
		end
		return
	end
	tutorialText.Text = step.text
	tutorialHint.Text = "Krok " .. tutorialStep .. "/" .. #TUTORIAL
		.. (if step.goal then "" else " • kliknij, aby dalej")
		.. " • Enter: pomiń tutorial"
	popTutorialPanel()
end

local function tutorialProgress(goal: string, amount: number)
	local step = TUTORIAL[tutorialStep]
	if step and step.goal == goal and not tutorialPraising then
		tutorialAmount += amount
		if tutorialAmount >= (step.need or 1) then
			tutorialPraising = true
			tutorialTime = 0
			tutorialText.Text = "BRAWO!"
			Sound.play("praise")
			popTutorialPanel()
		end
	end
end

---------------------------------------------------------------- building the screen

function Game.init(gui: ScreenGui, netFolder: Folder, cb)
	net = netFolder
	callbacks = cb

	root = Instance.new("Frame")
	root.Name = "Game"
	root.Size = UDim2.fromScale(1, 1)
	root.BackgroundColor3 = Color3.new(0, 0, 0) -- black bars around the map, like an old TV
	root.BorderSizePixel = 0
	root.Visible = false
	root.Parent = gui

	-- The world keeps the shape of the map on any screen.
	-- Layers (ZIndex): clouds 0, back wall 1, wind streaks 2 (the ground hides them),
	-- ground 3, ants 4, acorn 5, water 6,
	-- explosions 7, aim 8, dark corners 9, texts 10+, panels 20+, TV lines 60.
	world = Instance.new("Frame")
	world.AnchorPoint = Vector2.new(0.5, 0.5)
	world.Position = UDim2.fromScale(0.5, 0.5)
	world.Size = UDim2.fromScale(1, 1)
	world.BackgroundColor3 = Retro.SKY -- one flat sky color, like old consoles
	world.BorderSizePixel = 0
	world.ClipsDescendants = true
	world.Parent = root
	local aspect = Instance.new("UIAspectRatioConstraint")
	aspect.AspectRatio = W / H
	aspect.Parent = world

	-- pixel clouds far behind everything; the wind pushes them
	local cloudRng = Random.new(3)
	for _ = 1, 6 do
		local cloud = Retro.cloud(world, at(48, 18), 0)
		table.insert(skyClouds, {
			frame = cloud,
			x = cloudRng:NextNumber(-50, W),
			y = cloudRng:NextNumber(8, H * 0.35),
			speed = cloudRng:NextNumber(3, 7),
		})
	end

	-- dark earth wall behind the ground, seen through tunnels and blast holes
	backImage = Instance.new("ImageLabel")
	backImage.Size = UDim2.fromScale(1, 1)
	backImage.BackgroundTransparency = 1
	backImage.ResampleMode = Enum.ResamplerMode.Pixelated
	backImage.ZIndex = 1
	backImage.Parent = world

	terrainImage = Instance.new("ImageLabel")
	terrainImage.Size = UDim2.fromScale(1, 1)
	terrainImage.BackgroundTransparency = 1
	terrainImage.ResampleMode = Enum.ResamplerMode.Pixelated
	terrainImage.ZIndex = 3
	terrainImage.Parent = world

	-- water: flat retro blue with a light wave line on top that moves in steps
	local water = Retro.block(world, Color3.fromRGB(0, 88, 248), at(0, WATER_Y), UDim2.fromScale(1, 1 - WATER_Y / H), 6)
	water.BackgroundTransparency = 0.1
	Retro.block(world, Color3.fromRGB(60, 188, 252), at(0, WATER_Y), UDim2.new(1, 0, 0, 0) + at(0, 2), 6)
	for x = 0, W, 16 do
		table.insert(waves, Retro.block(world, Color3.fromRGB(188, 236, 252), at(x, WATER_Y - 2), at(8, 2), 6))
	end

	-- dark corners (under the texts, so they stay easy to read) and old-TV lines over all
	Retro.vignette(world, 9)
	Retro.tvLines(world, 60)

	turnLabel = Ui.label(world, UDim2.fromScale(0.5, 0.05), UDim2.fromScale(0.5, 0.05), Color3.new(1, 1, 1))
	turnLabel.TextWrapped = false
	timerLabel = Ui.label(world, UDim2.fromScale(0.85, 0.05), UDim2.fromScale(0.08, 0.06), Color3.new(1, 1, 1))
	timerLabel.TextWrapped = false
	local helpLabel = Ui.label(world, UDim2.fromScale(0.5, 0.975), UDim2.fromScale(0.9, 0.03), Color3.fromRGB(230, 240, 255))
	helpLabel.TextWrapped = false
	helpLabel.Text = "A D: chodź  W: skok  Mysz: cel  Spacja: rzut  1 2 3: broń"
	messageLabel = Ui.label(world, UDim2.fromScale(0.5, 0.4), UDim2.fromScale(0.8, 0.1), Color3.new(1, 1, 1))
	messageLabel.TextWrapped = false
	subMessageLabel = Ui.label(world, UDim2.fromScale(0.5, 0.5), UDim2.fromScale(0.7, 0.06), Color3.new(1, 1, 1))

	local leaveButton = Ui.button(world, "Wyjdź", UDim2.fromScale(0.95, 0.05), UDim2.fromScale(0.08, 0.055), "danger", function()
		Game.stop()
		callbacks.onMenu()
	end)
	leaveButton.ZIndex = 15 -- above the map pictures

	-- tutorial box near the top: what to do now + small hint line (yellow inner edge)
	tutorialPanel = Ui.panel(world, UDim2.fromScale(0.5, 0.2), UDim2.fromScale(0.62, 0.14), 20)
	tutorialPanel.Visible = false
	local border = tutorialPanel:FindFirstChild("Border")
	if border then
		(border:FindFirstChildOfClass("UIStroke") :: UIStroke).Color = Color3.fromRGB(252, 216, 56)
	end
	tutorialText = Ui.label(tutorialPanel, UDim2.fromScale(0.5, 0.42), UDim2.fromScale(0.92, 0.5), Color3.new(1, 1, 1))
	tutorialText.ZIndex = 21
	tutorialHint = Ui.label(tutorialPanel, UDim2.fromScale(0.5, 0.82), UDim2.fromScale(0.9, 0.16), Color3.fromRGB(200, 210, 200))
	tutorialHint.TextWrapped = false
	tutorialHint.ZIndex = 21

	-- power bar: 20 cells that light up from yellow to red
	powerBack = Retro.block(world, Color3.new(0, 0, 0), UDim2.fromScale(0.5, 0.925), UDim2.fromScale(0.3, 0.03), 10)
	powerBack.AnchorPoint = Vector2.new(0.5, 0.5)
	Retro.stroke(powerBack, Color3.new(1, 1, 1), 2)
	for i = 1, 20 do
		local cell = Retro.block(
			powerBack,
			CELL_OFF,
			UDim2.new((i - 1) / 20, 2, 0, 2),
			UDim2.new(1 / 20, -3, 1, -4),
			11
		)
		powerCells[i] = cell
	end

	-- wind meter: "WIATR", a row of cells lighting up left or right from the middle, number
	windBox = Retro.block(world, Color3.fromRGB(16, 24, 64), UDim2.fromScale(0.015, 0.025), UDim2.fromScale(0.25, 0.09), 10)
	windBox.BackgroundTransparency = 0.1
	windBoxStroke = Retro.stroke(windBox, Color3.new(0, 0, 0), 3) -- blinks yellow when the tutorial talks about wind
	local windTitle = Ui.label(windBox, UDim2.fromScale(0.38, 0.28), UDim2.fromScale(0.66, 0.34), Color3.new(1, 1, 1))
	windTitle.TextWrapped = false
	windTitle.Text = "WIATR"
	windValue = Ui.label(windBox, UDim2.fromScale(0.86, 0.5), UDim2.fromScale(0.24, 0.45), Color3.new(1, 1, 1))
	windValue.TextWrapped = false
	local windBar = Retro.block(world, Color3.new(0, 0, 0), UDim2.fromScale(0.05, 0.56), UDim2.fromScale(0.66, 0.3), 11)
	windBar.Parent = windBox
	for i = 1, 20 do
		local gap = if i == 11 then 4 else 2 -- a bigger gap in the middle
		windCells[i] = Retro.block(windBar, CELL_OFF, UDim2.new((i - 1) / 20, gap, 0, 2), UDim2.new(1 / 20, -gap - 1, 1, -4), 12)
	end

	for _ = 1, MAX_STREAKS do
		local view = Retro.block(world, Color3.new(1, 1, 1), UDim2.new(), at(6, 2), 2)
		view.AnchorPoint = Vector2.new(0.5, 0.5)
		view.Visible = false
		table.insert(streaks, {
			x = streakRng:NextNumber(0, W),
			y = streakRng:NextNumber(0, H * 0.7),
			phase = streakRng:NextNumber(0, 10),
			view = view,
		})
	end

	-- crosshair: a pixel "+" with a hole in the middle
	crosshair = Instance.new("Frame")
	crosshair.AnchorPoint = Vector2.new(0.5, 0.5)
	crosshair.Size = at(10, 10)
	crosshair.BackgroundTransparency = 1
	crosshair.ZIndex = 8
	crosshair.Parent = world
	local red = Color3.fromRGB(252, 56, 56)
	for _, r in { { 4, 0, 2, 3 }, { 4, 7, 2, 3 }, { 0, 4, 3, 2 }, { 7, 4, 3, 2 } } do
		Retro.block(crosshair, red, UDim2.fromScale(r[1] / 10, r[2] / 10), UDim2.fromScale(r[3] / 10, r[4] / 10), 8)
	end

	-- a pixel arrow pointing down, bouncing above the ant whose turn it is
	marker = Instance.new("Frame")
	marker.AnchorPoint = Vector2.new(0.5, 0.5)
	marker.Size = at(10, 6)
	marker.BackgroundTransparency = 1
	marker.ZIndex = 8
	marker.Parent = world
	for _, r in { { 0, 0, 10, 2 }, { 2, 2, 6, 2 }, { 4, 4, 2, 2 } } do
		local part = Retro.block(marker, Color3.new(1, 1, 1), UDim2.fromScale(r[1] / 10, r[2] / 6), UDim2.fromScale(r[3] / 10, r[4] / 6), 8)
		Retro.stroke(part, Color3.new(0, 0, 0), 1)
		table.insert(markerParts, part)
	end

	-- weapon bar (bottom left, on my turn): 3 boxes, the chosen one has a yellow edge
	weaponBar = Instance.new("Frame")
	weaponBar.Position = UDim2.fromScale(0.015, 0.845)
	weaponBar.Size = UDim2.fromScale(0.3, 0.08)
	weaponBar.BackgroundTransparency = 1
	weaponBar.ZIndex = 10
	weaponBar.Visible = false
	weaponBar.Parent = world
	for i, weaponName in Config.WEAPON_NAMES do
		local box = Retro.block(weaponBar, Color3.fromRGB(16, 24, 64), UDim2.fromScale((i - 1) / 3, 0), UDim2.new(1 / 3, -6, 1, 0), 10)
		local edge = Retro.stroke(box, Color3.new(0, 0, 0), 3)
		local key = Ui.label(box, UDim2.fromScale(0.16, 0.3), UDim2.fromScale(0.22, 0.4), Color3.fromRGB(252, 216, 56))
		key.TextWrapped = false
		key.Text = tostring(i)
		key.ZIndex = 11
		local nameLabel = Ui.label(box, UDim2.fromScale(0.5, 0.72), UDim2.fromScale(0.9, 0.36), Color3.new(1, 1, 1))
		nameLabel.TextWrapped = false
		nameLabel.Text = weaponName
		nameLabel.ZIndex = 11
		local countLabel = nil
		if i == 3 then
			countLabel = Ui.label(box, UDim2.fromScale(0.72, 0.3), UDim2.fromScale(0.4, 0.36), Color3.new(1, 1, 1))
			countLabel.TextWrapped = false
			countLabel.ZIndex = 11
		end
		weaponSlots[i] = { box = box, stroke = edge, name = nameLabel, count = countLabel }
	end

	-- chestnut rain aim: a pixel cloud at the top of the map with drops under it, follows the mouse
	rainTarget = Instance.new("Frame")
	rainTarget.AnchorPoint = Vector2.new(0.5, 0)
	rainTarget.Size = at(48, 80)
	rainTarget.BackgroundTransparency = 1
	rainTarget.ZIndex = 8
	rainTarget.Visible = false
	rainTarget.Parent = world
	local rainCloud = Retro.cloud(rainTarget, UDim2.fromScale(1, 18 / 80), 8)
	rainCloud.BackgroundTransparency = 1
	for row = 0, 4 do
		for _, dx in { 12, 24, 36 } do
			local drop = Retro.block(
				rainTarget,
				Color3.fromRGB(150, 80, 30),
				UDim2.fromScale((dx + (row % 2) * 4 - 2) / 48, (24 + row * 11) / 80),
				UDim2.fromScale(4 / 48, 4 / 80),
				8
			)
			drop.BackgroundTransparency = row * 0.15
		end
	end

	-- end of the match: who won + buttons
	resultPanel = Ui.panel(world, UDim2.fromScale(0.5, 0.45), UDim2.fromScale(0.5, 0.36), 30)
	resultPanel.Visible = false
	resultTitle = Ui.label(resultPanel, UDim2.fromScale(0.5, 0.25), UDim2.fromScale(0.9, 0.26), Color3.new(1, 1, 1))
	resultTitle.ZIndex = 31
	resultSub = Ui.label(resultPanel, UDim2.fromScale(0.5, 0.5), UDim2.fromScale(0.9, 0.16), Color3.new(1, 1, 1))
	resultSub.ZIndex = 31
	Ui.button(resultPanel, "Menu", UDim2.fromScale(0.28, 0.78), UDim2.fromScale(0.4, 0.24), "normal", function()
		Game.stop()
		callbacks.onMenu()
	end)
	againButton = Ui.button(resultPanel, "Jeszcze raz", UDim2.fromScale(0.72, 0.78), UDim2.fromScale(0.4, 0.24), "main", function()
		Game.stop()
		callbacks.onAgain()
	end)

	-- a mouse click moves on from a tutorial step that only shows text
	-- (and with the chestnut rain chosen, a click on the map calls the rain there)
	UserInputService.InputBegan:Connect(function(input: InputObject, onButton: boolean)
		if
			running
			and not onButton
			and input.UserInputType == Enum.UserInputType.MouseButton1
			and isMyTurn()
			and snap
			and snap.weapon == 3
		then
			local mx = mouseOnMap()
			if mx then
				sendInput("rain", mx.X)
			end
		end
		local step = TUTORIAL[tutorialStep]
		if
			running
			and input.UserInputType == Enum.UserInputType.MouseButton1
			and step
			and not step.goal
			and tutorialTime >= CLICK_DELAY
		then
			setTutorialStep(tutorialStep + 1)
		end
	end)

	RunService.RenderStepped:Connect(function(dt)
		if running then
			Game.render(math.min(dt, 1 / 20))
		end
	end)
end

---------------------------------------------------------------- keys

local WEAPON_KEYS = {
	[Enum.KeyCode.One] = 1,
	[Enum.KeyCode.Two] = 2,
	[Enum.KeyCode.Three] = 3,
	[Enum.KeyCode.KeypadOne] = 1,
	[Enum.KeyCode.KeypadTwo] = 2,
	[Enum.KeyCode.KeypadThree] = 3,
}

local function onKey(_: string, inputState: Enum.UserInputState, input: InputObject)
	local key = input.KeyCode
	if inputState == Enum.UserInputState.Begin then
		keys[key] = true
		if (key == Enum.KeyCode.W or key == Enum.KeyCode.Up) and isMyTurn() then
			sendInput("jump")
			tutorialProgress("jump", 1)
		elseif key == Enum.KeyCode.Space and isMyTurn() and snap and snap.weapon ~= 3 then
			localCharging = true
			sendInput("charge")
		elseif WEAPON_KEYS[key] and isMyTurn() and not localCharging then
			local weapon = WEAPON_KEYS[key]
			if weapon == 3 and snap and snap.rainLeft <= 0 then
				flashMessage("Nie masz już deszczu!", Color3.fromRGB(252, 120, 100), 1.2)
			else
				sendInput("weapon", weapon)
				Sound.play("click")
			end
		elseif key == Enum.KeyCode.Return and tutorialStep > 0 then
			setTutorialStep(0) -- skip the tutorial
		end
	else
		keys[key] = nil
		if key == Enum.KeyCode.Space and localCharging then
			localCharging = false
			sendInput("throw")
		end
	end
	return Enum.ContextActionResult.Sink
end

local function held(a: Enum.KeyCode, b: Enum.KeyCode): number
	return if keys[a] or keys[b] then 1 else 0
end

---------------------------------------------------------------- start / stop

function Game.start(info)
	Game.stop()
	running = true
	root.Visible = true
	resultPanel.Visible = false
	messageLabel.Text, subMessageLabel.Text = "", ""
	isTutorial = info.tutorial == true
	snap = nil
	shownWind = 0
	lastSentWalk, lastSentAim, lastSentFacing = 0, 999, 0
	localCharging = false
	table.clear(keys)

	data = MapData.new(info.seed, info.kind)
	local view, err = Map.new(data :: MapData.MapData, terrainImage, backImage)
	mapView = view
	if not view then
		messageLabel.TextColor3 = Color3.fromRGB(255, 120, 100)
		messageLabel.Text = "Nie udało się zrobić mapy :("
		subMessageLabel.Text = "EditableImage nie działa: " .. tostring(err)
	end

	for _, a in info.ants do
		ants[a.id] = {
			id = a.id,
			team = a.team,
			ownerId = a.ownerId,
			name = a.name,
			isBot = a.isBot,
			view = AntView.new(world, a.team, a.name, a.ownerId == myId and not a.isBot),
			x = nil,
			y = nil,
			tx = 0,
			ty = 0,
			hp = Config.ANT_HP,
			alive = true,
			onGround = true,
			walking = false,
			facing = if a.team == 1 then 1 else -1,
			aim = 30,
		}
		ants[a.id].view.frame.Visible = false -- until the first snapshot says where it is
	end

	if view then
		flashMessage("Mapa: " .. (data :: MapData.MapData).name, nil, 2.5)
	end
	setTutorialStep(if isTutorial then 1 else 0)

	ContextActionService:BindActionAtPriority(
		"WarInGrassKeys",
		onKey,
		false,
		Enum.ContextActionPriority.High.Value + 100,
		Enum.KeyCode.Left,
		Enum.KeyCode.Right,
		Enum.KeyCode.Up,
		Enum.KeyCode.A,
		Enum.KeyCode.D,
		Enum.KeyCode.W,
		Enum.KeyCode.Space,
		Enum.KeyCode.Return,
		Enum.KeyCode.One,
		Enum.KeyCode.Two,
		Enum.KeyCode.Three,
		Enum.KeyCode.KeypadOne,
		Enum.KeyCode.KeypadTwo,
		Enum.KeyCode.KeypadThree
	)
end

function Game.stop()
	if not running then
		return
	end
	running = false
	root.Visible = false
	ContextActionService:UnbindAction("WarInGrassKeys")
	tutorialStep = 0
	tutorialPanel.Visible = false
	for _, ant in ants do
		AntView.destroy(ant.view)
	end
	table.clear(ants)
	for _, v in flyViews do
		v.frame:Destroy()
	end
	table.clear(flyViews)
	if mapView then
		mapView:destroy()
		mapView = nil
	end
	data, snap = nil, nil
end

function Game.isRunning(): boolean
	return running
end

---------------------------------------------------------------- from the server

local STATE_NAMES = { "aim", "flying", "settle", "over" }

local function coord(v: number): number
	return v / 16 - 512
end

function Game.snapshot(b: buffer)
	if not running then
		return
	end
	-- layout: see Sim.snapshot on the server
	local flags = buffer.readu8(b, 6)
	local count = buffer.readu8(b, 11)
	local flyStart = 14 + count * 7
	local flying = {}
	for i = 1, buffer.readu8(b, 12) do
		local o = flyStart + (i - 1) * 5
		table.insert(flying, { kind = buffer.readu8(b, o), x = coord(buffer.readu16(b, o + 1)), y = coord(buffer.readu16(b, o + 3)) })
	end
	local s: Snap = {
		state = STATE_NAMES[buffer.readu8(b, 0)] or "settle",
		cur = buffer.readu8(b, 1),
		time = buffer.readu8(b, 2),
		wind = buffer.readi16(b, 3) / 10,
		power = buffer.readu8(b, 5) / 255,
		charging = bit32.band(flags, 1) ~= 0,
		tutorial = bit32.band(flags, 4) ~= 0,
		weapon = buffer.readu8(b, 7),
		rainLeft = buffer.readu8(b, 8),
		flying = flying,
		turnId = buffer.readu16(b, 9),
	}
	-- last 5 seconds of a turn: tick every second
	local before = snap
	if before and s.state == "aim" and not s.tutorial and s.time <= 5 and s.time > 0 and s.time ~= before.time then
		Sound.play("tick")
	end
	snap = s
	for id = 1, count do
		local ant = ants[id]
		if ant then
			local o = 14 + (id - 1) * 7
			ant.tx = coord(buffer.readu16(b, o))
			ant.ty = coord(buffer.readu16(b, o + 2))
			ant.hp = buffer.readu8(b, o + 4)
			local f = buffer.readu8(b, o + 5)
			ant.alive = bit32.band(f, 1) ~= 0
			local wasOnGround = ant.onGround
			ant.onGround = bit32.band(f, 2) ~= 0
			-- the ant whose turn it is left the ground while aiming = it jumped
			if wasOnGround and not ant.onGround and id == s.cur and s.state == "aim" then
				Sound.play("jump")
			end
			ant.walking = bit32.band(f, 4) ~= 0
			-- my own aim is drawn from my mouse (no waiting for the server)
			if not (ant.id == s.cur and ant.ownerId == myId and s.state == "aim") then
				ant.facing = if bit32.band(f, 8) ~= 0 then 1 else -1
				ant.aim = buffer.readi8(b, o + 6)
			end
		end
	end
end

local function showResult(winner: number)
	resultPanel.Visible = true
	local mine = myTeam()
	if winner == 0 then
		resultTitle.Text = "Remis!"
		resultTitle.TextColor3 = Color3.new(1, 1, 1)
	else
		resultTitle.Text = "Wygrywają " .. Config.TEAMS[winner].name .. "!"
		resultTitle.TextColor3 = Config.TEAMS[winner].light
	end
	if mine == nil or winner == 0 then
		resultSub.Text = ""
		Sound.play("lose")
	elseif mine == winner then
		resultSub.Text = "WYGRAŁEŚ!"
		Sound.play("win")
	else
		resultSub.Text = "Tym razem się nie udało. Spróbuj jeszcze raz!"
		Sound.play("lose")
	end
	againButton.Visible = callbacks.canPlayAgain()
	tutorialPanel.Visible = false
	tutorialStep = 0
end

function Game.event(name: string, ...)
	if not running then
		return
	end
	local args = { ... }
	if name == "turn" then
		lastSentWalk = 0
		lastSentAim = 999
		localCharging = false
		local ant = ants[args[1]]
		if ant and ant.ownerId == myId and not ant.isBot and tutorialStep == 0 then
			flashMessage("Twoja tura!", Config.TEAMS[ant.team].light, 1.2)
			Sound.play("myTurn")
		end
	elseif name == "throw" then
		Sound.play("throw")
	elseif name == "explode" then
		local x, y, radius = args[1], args[2], args[3]
		if mapView then
			mapView:explode(x, y, radius)
		end
		pixelBlast(x, y, radius)
		-- small blasts (seeds, rain) sound higher
		Sound.play("explosion", math.clamp(Config.EXPLOSION_RADIUS / radius, 1, 1.8))
	elseif name == "damage" then
		local ant = ants[args[1]]
		if ant then
			AntView.hurt(ant.view)
			Sound.play("hurt")
			floatingText("-" .. args[2], ant.x or ant.tx, (ant.y or ant.ty) - 22, Config.TEAMS[ant.team].light)
		end
	elseif name == "kill" then
		local ant = ants[args[1]]
		if ant then
			ant.alive = false
			ant.view.frame.Visible = false
			floatingText("KO!", ant.x or ant.tx, (ant.y or ant.ty) - 12, Color3.new(1, 1, 1))
			Sound.play("ko")
		end
	elseif name == "splash" then
		floatingText("PLUSK!", args[1], WATER_Y - 8, Color3.new(1, 1, 1))
		Sound.play("splash")
	elseif name == "land" then
		local ant = ants[args[1]]
		if ant then
			dust(ant.x or ant.tx, ant.y or ant.ty)
			Sound.play("land")
		end
	elseif name == "practiceDone" then
		tutorialProgress("throw", 1)
	elseif name == "tutorialEnd" then
		if tutorialStep > 0 then
			tutorialStep = 0
			tutorialPanel.Visible = false
		end
	elseif name == "over" then
		showResult(args[1])
	end
end

---------------------------------------------------------------- every frame

-- My ant aims at the mouse. While walking it keeps looking where it walks.
local function aimAtMouse(ant: Ant, walkDir: number)
	local mouse = player:GetMouse()
	local pos, size = world.AbsolutePosition, world.AbsoluteSize
	if size.X <= 0 or size.Y <= 0 or not ant.x or not ant.y then
		return
	end
	local mx = (mouse.X - pos.X) / size.X * W
	local my = (mouse.Y - pos.Y) / size.Y * H
	local dx, dy = mx - ant.x, (ant.y - ANT_HEIGHT / 2) - my
	if walkDir ~= 0 then
		localFacing = walkDir
	elseif math.abs(dx) > 1 then
		localFacing = if dx > 0 then 1 else -1
	end
	local before = localAim
	localAim = math.clamp(math.deg(math.atan2(dy, dx * localFacing)), -80, 88)
	tutorialProgress("aim", math.abs(localAim - before))
	ant.aim, ant.facing = localAim, localFacing

	local now = os.clock()
	if (math.abs(localAim - lastSentAim) > 0.5 or localFacing ~= lastSentFacing) and now - lastAimSend >= AIM_SEND_EVERY then
		lastSentAim, lastSentFacing, lastAimSend = localAim, localFacing, now
		sendInput("aim", localAim, localFacing)
	end
end

function Game.render(dt: number)
	local s = snap
	if not s then
		return
	end
	local cur = currentAnt()

	-- my turn: walking keys and the mouse
	if isMyTurn() and cur then
		local walkDir = held(Enum.KeyCode.Right, Enum.KeyCode.D) - held(Enum.KeyCode.Left, Enum.KeyCode.A)
		if walkDir ~= lastSentWalk then
			lastSentWalk = walkDir
			sendInput("walk", walkDir)
		end
		aimAtMouse(cur, walkDir)
	end

	-- ants slide smoothly to where the server says they are
	for _, ant in ants do
		if not ant.alive then
			ant.view.frame.Visible = false
			continue
		end
		local x, y = ant.x, ant.y
		if not x or not y or math.abs(ant.tx - x) > 40 or math.abs(ant.ty - y) > 40 then
			x, y = ant.tx, ant.ty -- first time (or a big jump): go there at once
		else
			local k = math.min(1, dt * 15)
			x += (ant.tx - x) * k
			y += (ant.ty - y) * k
		end
		local moved = math.abs(x - (ant.x or x))
		if isTutorial and ant == cur and ant.ownerId == myId and ant.walking then
			tutorialProgress("walk", moved)
		end
		ant.x, ant.y = x, y
		ant.view.frame.Visible = true
		AntView.draw(ant.view, {
			x = x,
			y = y,
			facing = ant.facing,
			aim = ant.aim,
			onGround = ant.onGround,
			walking = ant.walking,
			hp = ant.hp,
			isCurrent = ant == cur and s.state == "aim",
			charging = s.charging,
			power = s.power,
		}, dt, moved)
	end

	-- the acorn
	-- everything that flies (acorn, chestnut, seeds, rain): slides to where the server says
	for i, f in s.flying do
		local target = Vector2.new(f.x, f.y)
		local v = flyViews[i]
		if v and v.kind ~= f.kind then
			v.frame:Destroy()
			v = nil
		end
		if not v then
			v = { frame = makeFlyView(f.kind), kind = f.kind, shown = target }
			flyViews[i] = v
		end
		local fly = v :: { frame: Frame, kind: number, shown: Vector2 }
		if (fly.shown - target).Magnitude > 60 then
			fly.shown = target -- a different thing took this place in the list: jump there
		end
		fly.shown = fly.shown:Lerp(target, math.min(1, dt * 20))
		fly.frame.Position = at(math.floor(fly.shown.X / 2) * 2, math.floor(fly.shown.Y / 2) * 2)
		-- spins in quarter turns, like an old game (seeds are too small to spin)
		fly.frame.Rotation = if f.kind == 3 then 0 else (math.floor(os.clock() * 10) + i) % 4 * 90
	end
	for i = #flyViews, #s.flying + 1, -1 do
		flyViews[i].frame:Destroy()
		flyViews[i] = nil
	end

	-- crosshair, turn marker, power bar (rain has no throw: it shows the rain cloud instead)
	local showAim = s.state == "aim" and cur ~= nil and cur.x ~= nil
	local rainChosen = s.weapon == 3
	crosshair.Visible = showAim and not rainChosen
	marker.Visible = showAim
	powerBack.Visible = showAim and not rainChosen
	local mine = isMyTurn()
	rainTarget.Visible = mine and rainChosen
	if mine and rainChosen then
		local m = mouseOnMap()
		if m then
			rainTarget.Position = at(math.floor(math.clamp(m.X, 0, W) / 2) * 2, 4)
		end
	end

	-- weapon bar: on my turn; the chosen weapon has a yellow edge
	weaponBar.Visible = mine
	if mine then
		for i, slot in weaponSlots do
			local chosen = s.weapon == i
			local empty = i == 3 and s.rainLeft <= 0
			slot.stroke.Color = if chosen then Color3.fromRGB(252, 216, 56) else Color3.new(0, 0, 0)
			slot.box.BackgroundColor3 = if chosen then Color3.fromRGB(40, 56, 140) else Color3.fromRGB(16, 24, 64)
			slot.name.TextTransparency = if empty then 0.6 else 0
			if slot.count then
				slot.count.Text = "x" .. s.rainLeft
			end
		end
	end
	if showAim and cur and cur.x and cur.y then
		local angle = math.rad(cur.aim)
		local cx = cur.x + math.cos(angle) * cur.facing * 26
		local cy = cur.y - ANT_HEIGHT / 2 - math.sin(angle) * 26
		crosshair.Position = at(math.floor(cx / 2) * 2, math.floor(cy / 2) * 2)
		-- the arrow hops between 2 heights (retro)
		local hop = if math.floor(os.clock() * 4) % 2 == 0 then 0 else 3
		marker.Position = at(math.floor(cur.x / 2) * 2, math.floor(cur.y) - 42 + hop)
		for _, part in markerParts do
			part.BackgroundColor3 = Config.TEAMS[cur.team].light
		end
		local lit = math.ceil(s.power * #powerCells - 0.01)
		for i, cell in powerCells do
			local k = (i - 1) / (#powerCells - 1)
			cell.BackgroundColor3 = if i <= lit
				then Color3.fromRGB(252, 216, 56):Lerp(Color3.fromRGB(232, 40, 16), k)
				else CELL_OFF
		end
	end

	-- sky clouds drift with the wind (slowly), on whole 2-pixel steps
	for _, c in skyClouds do
		c.x += (c.speed * 0.3 + shownWind * 0.4) * dt
		if c.x > W + 10 then
			c.x = -60
		elseif c.x < -60 then
			c.x = W + 10
		end
		c.frame.Position = at(math.floor(c.x / 2) * 2, math.floor(c.y / 2) * 2)
	end

	-- the wave line on the water shifts back and forth
	local waveShift = if math.floor(os.clock() * 2.5) % 2 == 0 then 0 else 8
	for i, wave in waves do
		wave.Position = at((i - 1) * 16 + waveShift, WATER_Y - 2)
	end

	-- top line: whose turn, time left
	if s.state ~= "over" and cur then
		local team = Config.TEAMS[cur.team]
		if cur.ownerId == myId and not cur.isBot then
			turnLabel.Text = "Twoja tura! (" .. team.name .. ")"
		else
			turnLabel.Text = "Tura: " .. cur.name .. " (" .. team.name .. ")"
		end
		turnLabel.TextColor3 = team.light
		timerLabel.Text = if s.tutorial then "--" else tostring(s.time)
		timerLabel.TextColor3 = if not s.tutorial and s.time <= 5 then Color3.fromRGB(252, 56, 56) else Color3.new(1, 1, 1)
	else
		turnLabel.Text = ""
		timerLabel.Text = ""
	end

	-- wind
	shownWind += (s.wind - shownWind) * math.min(1, dt * 3)
	showWind(shownWind / Config.MAX_WIND)
	windBox.Visible = s.state ~= "over"
	updateStreaks(dt)

	-- tutorial: after "Brawo!" go to the next step; the wind meter blinks when explained
	local step = TUTORIAL[tutorialStep]
	if step then
		tutorialTime += dt
		if tutorialPraising and tutorialTime >= PRAISE_TIME then
			setTutorialStep(tutorialStep + 1)
		end
	end
	local highlight = step ~= nil and step.highlightWind == true and math.floor(os.clock() * 4) % 2 == 0
	windBoxStroke.Color = if highlight then Color3.fromRGB(252, 216, 56) else Color3.new(0, 0, 0)
end

return Game
