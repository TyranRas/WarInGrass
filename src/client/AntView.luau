-- Draws one ant in retro pixel style: a grid of 12 x 8 square "pixels" (each 2 map pixels).
-- Little details: legs step in 2 poses while walking, spread out in the air, the eye looks
-- up/down where the ant aims and blinks, antenna tip twitches, the ant shakes while charging,
-- flashes white when hurt. Name + HP above it.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("WarInGrassShared")
local Config = require(Shared.Config)
local Retro = require(script.Parent.Retro)

local W, H = Config.MAP_WIDTH, Config.MAP_HEIGHT
local GRID_W, GRID_H = 12, 8 -- the ant picture in "pixels"
local CELL = 2 -- one ant pixel = 2 x 2 map pixels
local ANT_W, ANT_H = GRID_W * CELL, GRID_H * CELL -- feet at the bottom middle

local AntView = {}

local function at(x: number, y: number): UDim2
	return UDim2.fromScale(x / W, y / H)
end

-- one rectangle of the ant picture: x, y, w, h in ant pixels (ant looking right)
type Part = { frame: Frame, x: number, y: number, w: number, h: number }

export type View = {
	team: number,
	frame: Frame,
	parts: { Part }, -- every block (they get mirrored when the ant turns)
	body: { Frame }, -- blocks in the team color (they flash when hurt)
	eye: Part,
	antennaTip: Part,
	legsA: { Part }, -- standing / step 1
	legsB: { Part }, -- step 2
	legsAir: { Part }, -- spread out while flying
	hpLabel: TextLabel,
	nameLabel: TextLabel,
	facing: number,
	walkPhase: number,
	nextBlink: number,
	nextTwitch: number,
	flash: number,
}

-- What draw needs to know this frame.
export type Pose = {
	x: number,
	y: number,
	facing: number,
	aim: number,
	onGround: boolean,
	walking: boolean,
	hp: number,
	isCurrent: boolean,
	charging: boolean,
	power: number,
}

local rng = Random.new()

local function place(v: View, part: Part)
	local x = if v.facing == 1 then part.x else GRID_W - part.x - part.w
	part.frame.Position = UDim2.fromScale(x / GRID_W, part.y / GRID_H)
end

-- scale: 1 in the match; the menu uses bigger ants
function AntView.new(parent: Instance, team: number, name: string, isMine: boolean, scale: number?): View
	local color = Config.TEAMS[team].color
	local light = Config.TEAMS[team].light
	local size = scale or 1

	local frame = Instance.new("Frame")
	frame.AnchorPoint = Vector2.new(0.5, 1)
	frame.Size = at(ANT_W * size, ANT_H * size)
	frame.BackgroundTransparency = 1
	frame.ZIndex = 4
	frame.Parent = parent

	local v = {
		team = team,
		frame = frame,
		parts = {},
		body = {},
		facing = if team == 1 then 1 else -1,
		walkPhase = 0,
		nextBlink = os.clock() + rng:NextNumber(1, 4),
		nextTwitch = os.clock() + rng:NextNumber(0.5, 2),
		flash = 0,
	} :: View

	local function part(c: Color3, x: number, y: number, w: number, h: number, isBody: boolean?): Part
		local f = Retro.block(frame, c, UDim2.new(), UDim2.new(w / GRID_W, 1, h / GRID_H, 1), 5)
		local p: Part = { frame = f, x = x, y = y, w = w, h = h }
		table.insert(v.parts, p)
		if isBody then
			table.insert(v.body, f)
		end
		return p
	end

	--   x: 0 1 2 3 4 5 6 7 8 9 10 11
	-- y0:  . . . . . . . . . T .  .     T antenna tip
	-- y1:  . . . . . . . . a . .  .     a antenna
	-- y2:  . . . . . . . . h h h  .     h head
	-- y3:  . b b b . . . h h E h  .     b back part, E eye
	-- y4:  b L b b b . t t h h h  .     L shine, t middle part
	-- y5:  b b b b b w t t . . .  .     w thin waist
	-- y6:  . b b b . legs . . .
	-- y7:  . . . . . feet . . .
	part(color, 1, 3, 3, 1, true) -- back part (abdomen)
	part(color, 0, 4, 5, 2, true)
	part(color, 1, 6, 3, 1, true)
	part(light, 1, 4, 1, 1) -- shine on it
	part(color, 5, 5, 1, 1, true) -- waist
	part(color, 6, 4, 2, 2, true) -- middle part (thorax)
	part(color, 8, 2, 3, 3, true) -- head
	part(color, 7, 3, 1, 1, true)
	part(color, 8, 1, 1, 1, true) -- antenna
	v.antennaTip = part(color, 9, 0, 1, 1, true)
	v.eye = part(Color3.new(1, 1, 1), 9, 3, 1, 1)

	-- legs: knee under the middle part, foot on the ground
	local function legs(knees: { number }, feet: { number }, footY: number): { Part }
		local list = {}
		for i = 1, 3 do
			table.insert(list, part(color, knees[i], 6, 1, 1, true))
			table.insert(list, part(color, feet[i], footY, 1, 1, true))
		end
		return list
	end
	v.legsA = legs({ 5, 7, 8 }, { 4, 7, 10 }, 7)
	v.legsB = legs({ 5, 6, 8 }, { 5, 6, 9 }, 7)
	v.legsAir = legs({ 5, 7, 8 }, { 3, 7, 11 }, 7)

	v.hpLabel = Retro.label(frame, UDim2.fromScale(0.5, -0.3), UDim2.fromScale(1.4, 0.5), light)
	v.hpLabel.TextWrapped = false
	v.nameLabel = Retro.label(frame, UDim2.fromScale(0.5, -0.8), UDim2.fromScale(3.4, 0.45), light)
	v.nameLabel.TextWrapped = false
	v.nameLabel.Text = if isMine then name .. " (Ty)" else name
	v.nameLabel.TextTransparency = 0.1

	for _, p in v.parts do
		place(v, p)
	end
	return v
end

function AntView.hurt(v: View)
	v.flash = 1
end

local function showLegs(list: { Part }, visible: boolean)
	for _, p in list do
		p.frame.Visible = visible
	end
end

function AntView.draw(v: View, pose: Pose, dt: number, movedPixels: number)
	local now = os.clock()
	local shaking = pose.isCurrent and pose.charging

	-- the whole ant; shakes by whole map pixels while charging a throw
	local shake = if shaking then rng:NextInteger(-1, 1) * math.ceil(pose.power * 1.5) else 0
	v.frame.Position = at(math.floor(pose.x + 0.5) + shake, math.floor(pose.y + 0.5) + 1)

	-- turned the other way: mirror all blocks
	if pose.facing ~= v.facing then
		v.facing = pose.facing
		for _, p in v.parts do
			place(v, p)
		end
	end

	-- legs: 2 poses that swap as far as the ant really walked, spread out in the air
	v.walkPhase += movedPixels * Config.STEP_ANIM
	local stepTwo = pose.walking and math.floor(v.walkPhase / math.pi) % 2 == 1
	showLegs(v.legsAir, not pose.onGround)
	showLegs(v.legsA, pose.onGround and not stepTwo)
	showLegs(v.legsB, pose.onGround and stepTwo)

	-- eye: looks up or down where we aim, blinks now and then
	if now > v.nextBlink + 0.12 then
		v.nextBlink = now + rng:NextNumber(2, 5)
	end
	v.eye.frame.Visible = now <= v.nextBlink
	local eyeY = 3
	if pose.isCurrent then
		eyeY = if pose.aim > 35 then 2 elseif pose.aim < -25 then 4 else 3
	end
	if v.eye.y ~= eyeY then
		v.eye.y = eyeY
		place(v, v.eye)
	end

	-- antenna tip twitches forward and back
	if now > v.nextTwitch then
		v.nextTwitch = now + rng:NextNumber(0.4, 2.5)
		v.antennaTip.x = if v.antennaTip.x == 9 then 10 else 9
		place(v, v.antennaTip)
	end

	-- flash white for a moment after getting hurt (blinks, like old games)
	v.flash = math.max(0, v.flash - dt * 2.5)
	local white = v.flash > 0 and math.floor(now * 16) % 2 == 0
	local bodyColor = if white then Color3.new(1, 1, 1) else Config.TEAMS[v.team].color
	for _, f in v.body do
		f.BackgroundColor3 = bodyColor
	end

	v.hpLabel.Text = tostring(pose.hp)
end

function AntView.destroy(v: View)
	v.frame:Destroy()
end

return AntView
