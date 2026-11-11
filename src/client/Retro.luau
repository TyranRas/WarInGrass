-- The retro (old console) look of the menu: pixel font, square buttons with a thick black
-- edge that press down, dialog-box panels, and a pixel scene behind the menu
-- (sky, clouds, grass, two walking pixel ants, old-TV lines).
-- Same functions as Ui.luau (label, panel, button), so the menu can just use this instead.
-- The match screen still uses Ui.luau.
local AssetService = game:GetService("AssetService")

local Sound = require(script.Parent.Sound)

local Retro = {}

Retro.FONT = Font.new("rbxasset://fonts/families/PressStart2P.json")

local BLACK = Color3.new(0, 0, 0)
local WHITE = Color3.new(1, 1, 1)
Retro.SKY = Color3.fromRGB(92, 148, 252)
local PANEL = Color3.fromRGB(16, 24, 64)

local BUTTON_COLORS = {
	main = Color3.fromRGB(56, 184, 56), -- green: the main thing to do
	normal = Color3.fromRGB(0, 112, 236), -- blue
	danger = Color3.fromRGB(216, 40, 0), -- red: leave, cancel
	gold = Color3.fromRGB(240, 172, 0),
}
local BUTTON_DEPTH = 6 -- pixels the button stands above its dark "side"

local function stroke(parent: Instance, color: Color3, thickness: number)
	local s = Instance.new("UIStroke")
	s.Color = color
	s.Thickness = thickness
	s.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	s.LineJoinMode = Enum.LineJoinMode.Miter -- square corners
	s.Parent = parent
	return s
end

local function block(parent: Instance, color: Color3, position: UDim2, size: UDim2, z: number): Frame
	local frame = Instance.new("Frame")
	frame.BackgroundColor3 = color
	frame.BorderSizePixel = 0
	frame.Position = position
	frame.Size = size
	frame.ZIndex = z
	frame.Parent = parent
	return frame
end
Retro.block = block -- a plain square block (no round corners)
Retro.stroke = stroke -- a square-cornered edge

-- Old-TV lines over everything: thin dark lines across the whole parent, every few pixels.
-- Each line is its own long frame (a repeated tiny picture made broken, slanted lines on
-- screens with zoom). They are made again when the size of the parent changes.
local TV_LINE_GAP = 3 -- pixels from one line to the next
function Retro.tvLines(parent: GuiObject, z: number)
	local overlay = Instance.new("Frame")
	overlay.Name = "TvLines"
	overlay.BackgroundTransparency = 1
	overlay.Size = UDim2.fromScale(1, 1)
	overlay.ClipsDescendants = true
	overlay.ZIndex = z
	overlay.Parent = parent
	local lines: { Frame } = {}
	local function build()
		local needed = math.ceil(overlay.AbsoluteSize.Y / TV_LINE_GAP)
		for i = #lines + 1, needed do
			local line = block(overlay, BLACK, UDim2.fromOffset(0, (i - 1) * TV_LINE_GAP), UDim2.new(1, 0, 0, 1), z)
			line.BackgroundTransparency = 0.85
			lines[i] = line
		end
		for i, line in lines do
			line.Visible = i <= needed
		end
	end
	overlay:GetPropertyChangedSignal("AbsoluteSize"):Connect(build)
	build()
end

-- Dark corners, like the round edge of an old TV screen.
-- A small picture (clear in the middle, darker toward the corners) stretched over the parent.
Retro.VIGNETTE_STRENGTH = 0.6 -- 0 = no dark corners, 1 = black corners
function Retro.vignette(parent: Instance, z: number)
	pcall(function()
		local w, h = 64, 36
		local image = AssetService:CreateEditableImage({ Size = Vector2.new(w, h) })
		local pixels = buffer.create(w * h * 4)
		for y = 0, h - 1 do
			for x = 0, w - 1 do
				-- distance from the middle: 0 in the middle, about 1.4 in the corners
				local dx, dy = (x + 0.5) / w * 2 - 1, (y + 0.5) / h * 2 - 1
				local d = math.sqrt(dx * dx + dy * dy)
				local dark = math.clamp((d - 0.6) / 0.8, 0, 1) ^ 1.6
				buffer.writeu8(pixels, (y * w + x) * 4 + 3, math.floor(dark * Retro.VIGNETTE_STRENGTH * 255))
			end
		end
		image:WritePixelsBuffer(Vector2.zero, Vector2.new(w, h), pixels)
		local overlay = Instance.new("ImageLabel")
		overlay.Name = "Vignette"
		overlay.BackgroundTransparency = 1
		overlay.Size = UDim2.fromScale(1, 1)
		overlay.ImageContent = Content.fromObject(image)
		overlay.ZIndex = z
		overlay.Parent = parent
	end)
end

-- TextScaled does not grow this pixel font properly, so we count the size ourselves.
-- In Press Start 2P every letter is a square as wide as it is tall, so:
-- one line: size = box width / number of letters (but not taller than the box).
-- wrapped text: the biggest size where all the words still fit in the box.
local MIN_TEXT, MAX_TEXT = 8, 96
local LINE_HEIGHT = 1.15

local function linesNeeded(words: { number }, perLine: number): number
	local lines, used = 1, 0
	for _, length in words do
		if used == 0 then
			used = length
		elseif used + 1 + length <= perLine then
			used += 1 + length
		else
			lines += 1
			used = length
		end
		if length > perLine then
			return math.huge -- one word does not fit at all
		end
	end
	return lines
end

-- labels that must all have the same text size (see Retro.sameSize)
local groups: { [TextLabel]: { TextLabel } } = {}

local fitText: (label: TextLabel) -> ()

-- The biggest text size that fits this label's box (nil if it can't be measured yet).
local function bestSize(label: TextLabel): number?
	local box = label.AbsoluteSize
	if box.X <= 0 or box.Y <= 0 or label.Text == "" then
		return nil
	end
	local best = MIN_TEXT
	if label.TextWrapped then
		local words = {}
		for word in string.gmatch(label.Text, "%S+") do
			table.insert(words, utf8.len(word) or #word)
		end
		for size = math.min(MAX_TEXT, math.floor(box.Y)), MIN_TEXT, -1 do
			local perLine = math.floor(box.X / size)
			if linesNeeded(words, perLine) * size * LINE_HEIGHT <= box.Y then
				best = size
				break
			end
		end
	else
		local letters = utf8.len(label.Text) or #label.Text
		best = math.floor(math.min(box.Y, box.X / math.max(letters, 1), MAX_TEXT))
	end
	return math.max(MIN_TEXT, best)
end

fitText = function(label: TextLabel)
	local group = groups[label]
	if not group then
		local size = bestSize(label)
		if size then
			label.TextSize = size
		end
		return
	end
	-- a group: everyone gets the smallest size, so all texts look the same
	local smallest = math.huge
	for _, other in group do
		smallest = math.min(smallest, bestSize(other) or math.huge)
	end
	if smallest < math.huge then
		for _, other in group do
			other.TextSize = smallest
		end
	end
end

-- Makes these pixel texts (for example the captions of buttons in one column) always the
-- same size: the biggest size that fits in all of them.
function Retro.sameSize(labels: { TextLabel })
	for _, label in labels do
		groups[label] = labels
	end
	fitText(labels[1])
end

-- Makes a pixel text keep the biggest size that fits its box (also after Text changes).
function Retro.fit(label: TextLabel)
	label.TextScaled = false
	label:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
		fitText(label)
	end)
	label:GetPropertyChangedSignal("Text"):Connect(function()
		fitText(label)
	end)
	label:GetPropertyChangedSignal("TextWrapped"):Connect(function()
		fitText(label)
	end)
	fitText(label)
end

-- A pixel text as big as fits its box. Position is the middle of the text.
function Retro.label(parent: Instance, position: UDim2, size: UDim2, color: Color3): TextLabel
	local text = Instance.new("TextLabel")
	text.BackgroundTransparency = 1
	text.AnchorPoint = Vector2.new(0.5, 0.5)
	text.Position = position
	text.Size = size
	text.FontFace = Retro.FONT
	text.TextWrapped = true
	text.TextColor3 = color
	text.TextStrokeColor3 = BLACK
	text.TextStrokeTransparency = 0
	text.Text = ""
	text.ZIndex = 10
	text.Parent = parent
	Retro.fit(text)
	return text
end

-- A dark-blue dialog box: thick black edge and a white line inside, like old RPG games.
function Retro.panel(parent: Instance, position: UDim2, size: UDim2, z: number?): Frame
	local frame = Instance.new("Frame")
	frame.AnchorPoint = Vector2.new(0.5, 0.5)
	frame.Position = position
	frame.Size = size
	frame.BackgroundColor3 = PANEL
	frame.BackgroundTransparency = 0.05
	frame.BorderSizePixel = 0
	frame.ZIndex = z or 20
	stroke(frame, BLACK, 5)
	local inner = Instance.new("Frame")
	inner.Name = "Border"
	inner.BackgroundTransparency = 1
	inner.Position = UDim2.fromOffset(6, 6)
	inner.Size = UDim2.new(1, -12, 1, -12)
	inner.ZIndex = frame.ZIndex
	stroke(inner, WHITE, 3)
	inner.Parent = frame
	frame.Parent = parent
	return frame
end

-- A square button with a thick black edge and a dark "side" under it.
-- Mouse over: it gets lighter and a blinking ▶ shows next to it. Click: it presses down.
function Retro.button(parent: Instance, text: string, position: UDim2, size: UDim2, kind: string?, onClick: () -> ()): TextButton
	local color = BUTTON_COLORS[kind or "normal"] or BUTTON_COLORS.normal
	local z = (if parent:IsA("GuiObject") then parent.ZIndex else 20) + 1

	-- the dark side of the button (seen under it)
	local side = Instance.new("Frame")
	side.AnchorPoint = Vector2.new(0.5, 0.5)
	side.Position = position + UDim2.fromOffset(0, BUTTON_DEPTH)
	side.Size = size
	side.BackgroundColor3 = color:Lerp(BLACK, 0.55)
	side.BorderSizePixel = 0
	side.ZIndex = z
	stroke(side, BLACK, 3)
	side.Parent = parent

	local button = Instance.new("TextButton")
	button.AnchorPoint = Vector2.new(0.5, 0.5)
	button.Position = position
	button.Size = size
	button.BackgroundColor3 = color
	button.BorderSizePixel = 0
	button.AutoButtonColor = false
	button.Text = ""
	button.ZIndex = z + 1
	stroke(button, BLACK, 3)

	-- light line on top, like light falling on a block
	local shine = block(button, color:Lerp(WHITE, 0.35), UDim2.new(), UDim2.new(1, 0, 0, 4), z + 2)
	shine.Name = "Shine"

	local caption = Retro.label(button, UDim2.fromScale(0.5, 0.52), UDim2.fromScale(0.92, 0.55), WHITE)
	caption.Name = "Caption"
	caption.Text = text
	caption.TextWrapped = false
	caption.ZIndex = z + 3

	-- blinking arrow next to the button under the mouse
	local cursor = Retro.label(button, UDim2.new(0, -10, 0.5, 0), UDim2.fromScale(0.5, 0.5), Color3.fromRGB(255, 224, 64))
	cursor.AnchorPoint = Vector2.new(1, 0.5)
	cursor.Text = "▶"
	cursor.ZIndex = z + 3
	cursor.Visible = false
	local aspect = Instance.new("UIAspectRatioConstraint")
	aspect.DominantAxis = Enum.DominantAxis.Height
	aspect.Parent = cursor

	local hoverToken = 0 -- each mouse-over gets a new number, so only one blink loop runs
	local function setPressed(pressed: boolean)
		button.Position = if pressed then position + UDim2.fromOffset(0, BUTTON_DEPTH - 1) else position
	end
	button.MouseEnter:Connect(function()
		hoverToken += 1
		local token = hoverToken
		button.BackgroundColor3 = color:Lerp(WHITE, 0.18)
		task.spawn(function()
			while hoverToken == token and button.Parent do
				cursor.Visible = not cursor.Visible
				task.wait(0.25)
			end
			if hoverToken == token then
				cursor.Visible = false
			end
		end)
	end)
	button.MouseLeave:Connect(function()
		hoverToken += 1
		cursor.Visible = false
		button.BackgroundColor3 = color
		setPressed(false)
	end)
	button.MouseButton1Down:Connect(function()
		setPressed(true)
	end)
	button.MouseButton1Up:Connect(function()
		setPressed(false)
	end)
	button.Activated:Connect(function()
		setPressed(false)
		Sound.play("click")
		onClick()
	end)

	-- the side hides, moves up/down in layers and goes away together with the button
	button:GetPropertyChangedSignal("Visible"):Connect(function()
		side.Visible = button.Visible
	end)
	button:GetPropertyChangedSignal("ZIndex"):Connect(function()
		side.ZIndex = button.ZIndex - 1
	end)
	button.Destroying:Connect(function()
		side:Destroy()
	end)

	button.Parent = parent
	return button
end

---------------------------------------------------------------- the pixel scene behind the menu

local P = 4 -- size of one "pixel" of the sun and clouds, in screen pixels

-- A pixel cloud 16 x 6 "pixels". Its parts use scale, so the size of the cloud frame sets
-- how big it is (menu: in screen pixels, match: in map pixels).
function Retro.cloud(parent: Instance, size: UDim2, z: number): Frame
	local cloud = Instance.new("Frame")
	cloud.BackgroundTransparency = 1
	cloud.Size = size
	cloud.ZIndex = z
	cloud.Parent = parent
	local function part(color: Color3, x: number, y: number, w: number, h: number)
		block(cloud, color, UDim2.fromScale(x / 16, y / 6), UDim2.fromScale(w / 16, h / 6), z)
	end
	part(Color3.fromRGB(188, 220, 255), 0, 4, 16, 2) -- shadow under it
	part(WHITE, 0, 2, 16, 2)
	part(WHITE, 3, 0, 6, 2)
	part(WHITE, 9, 1, 4, 1)
	return cloud
end

-- The ground at the bottom of the menu: painted exactly like the map in the match
-- (same colors and big pixels from Map.luau): grass blades, bright grass line, green grass,
-- dirt getting darker in steps, small stones. One picture texel = one big map pixel.
local GROUND_W, GROUND_H = 512, 48 -- in big pixels (512 = the map width 1024 / 2)
local BLADE_ROWS = 8 -- rows above the ground line, for the grass blades

local function paintGround(): EditableImage
	local Map = require(script.Parent.Map)
	local pal = Map.PALETTE
	local rng = Random.new(11)
	local image = AssetService:CreateEditableImage({ Size = Vector2.new(GROUND_W, GROUND_H) })
	local pixels = buffer.create(GROUND_W * GROUND_H * 4)
	local function put(x: number, y: number, c: { number })
		if x < 0 or x >= GROUND_W or y < 0 or y >= GROUND_H then
			return
		end
		local i = (y * GROUND_W + x) * 4
		buffer.writeu8(pixels, i, math.clamp(c[1], 0, 255))
		buffer.writeu8(pixels, i + 1, math.clamp(c[2], 0, 255))
		buffer.writeu8(pixels, i + 2, math.clamp(c[3], 0, 255))
		buffer.writeu8(pixels, i + 3, 255)
	end
	for x = 0, GROUND_W - 1 do
		-- grass blades sticking up (like the decoration blades on the map)
		if rng:NextNumber() < 0.14 then
			local height = rng:NextInteger(1, 4)
			local color = if rng:NextNumber() < 0.35 then pal.bladeLight else pal.blade
			for h = 1, height do
				put(x, BLADE_ROWS - h, color)
			end
		end
		for y = BLADE_ROWS, GROUND_H - 1 do
			local row = y - BLADE_ROWS
			local speckle = rng:NextInteger(1, 6)
			local c
			if row == 0 then
				c = pal.grassTop
			elseif row < 3 then
				c = if speckle == 6 then pal.grassDark else pal.grass
			else
				local depth = row * Map.PIXEL
				local base = pal.dirtBands[math.min(#pal.dirtBands, math.floor(depth / Map.BAND) + 1)]
				c = base
				if speckle == 1 then
					c = { base[1] + 18, base[2] + 12, base[3] + 6 }
				elseif speckle == 6 then
					c = { base[1] - 16, base[2] - 10, base[3] - 6 }
				end
			end
			put(x, y, c)
		end
	end
	-- a few small stones in the dirt
	for _ = 1, 14 do
		local sx, sy = rng:NextInteger(0, GROUND_W - 3), rng:NextInteger(BLADE_ROWS + 6, GROUND_H - 3)
		put(sx, sy, pal.stone)
		put(sx + 1, sy, pal.stoneLight)
		put(sx, sy + 1, pal.stoneDark)
		put(sx + 1, sy + 1, pal.stone)
	end
	image:WritePixelsBuffer(Vector2.zero, Vector2.new(GROUND_W, GROUND_H), pixels)
	return image
end

-- Builds the scene inside root. Returns:
--   a function to call every frame (moves the clouds),
--   a function that tells how many screen pixels from the top of root the grass line is
--   (the menu puts its walking ants there).
function Retro.scene(root: Frame): ((dt: number) -> (), () -> number)
	root.BackgroundColor3 = Retro.SKY
	local rng = Random.new(7)

	-- sun in the corner
	local sun = block(root, Color3.fromRGB(252, 216, 56), UDim2.new(0.88, 0, 0.06, 0), UDim2.fromOffset(14 * P, 14 * P), 1)
	stroke(sun, Color3.fromRGB(248, 120, 0), P)

	-- clouds
	local clouds = {}
	for _ = 1, 5 do
		local cloud = Retro.cloud(root, UDim2.fromOffset(16 * P, 6 * P), 2)
		table.insert(clouds, { frame = cloud, x = rng:NextNumber(-0.1, 1), y = rng:NextNumber(0.03, 0.45), speed = rng:NextNumber(0.006, 0.014) })
	end

	-- the ground, as wide as the screen, square pixels
	local ground = Instance.new("ImageLabel")
	ground.Name = "Ground"
	ground.AnchorPoint = Vector2.new(0, 1)
	ground.Position = UDim2.fromScale(0, 1)
	ground.Size = UDim2.fromScale(1, 1)
	ground.BackgroundTransparency = 1
	ground.ResampleMode = Enum.ResamplerMode.Pixelated
	ground.ZIndex = 3
	ground.Parent = root
	local aspect = Instance.new("UIAspectRatioConstraint")
	aspect.AspectRatio = GROUND_W / GROUND_H
	aspect.DominantAxis = Enum.DominantAxis.Width
	aspect.Parent = ground
	local ok, image = pcall(paintGround)
	if ok then
		ground.ImageContent = Content.fromObject(image)
	else
		-- no EditableImage: a plain green and brown ground instead
		ground.BackgroundTransparency = 0
		ground.BackgroundColor3 = Color3.fromRGB(152, 96, 40)
		block(ground, Color3.fromRGB(0, 168, 0), UDim2.fromScale(0, BLADE_ROWS / GROUND_H), UDim2.fromScale(1, 3 / GROUND_H), 3)
	end

	-- dark corners and old-TV lines over everything
	Retro.vignette(root, 49)
	Retro.tvLines(root, 50)

	local function step(dt: number)
		for _, c in clouds do
			c.x += c.speed * dt
			if c.x > 1.05 then
				c.x = -0.15
			end
			-- move in whole "pixels" so it looks like an old game
			local px = math.floor(c.x * root.AbsoluteSize.X / P) * P
			c.frame.Position = UDim2.new(0, px, c.y, 0)
		end
	end
	local function groundLine(): number
		return ground.AbsolutePosition.Y - root.AbsolutePosition.Y + ground.AbsoluteSize.Y * BLADE_ROWS / GROUND_H
	end
	return step, groundLine
end

return Retro
