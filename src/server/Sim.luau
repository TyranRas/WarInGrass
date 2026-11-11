-- One match, simulated on the server: ants, walking, jumping, the acorn, explosions,
-- turns and the winner. Players only send what they press (walk, aim, jump, throw);
-- the server decides what happens and tells everyone (events + snapshots).
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("WarInGrassShared")
local Config = require(Shared.Config)
local MapData = require(Shared.MapData)

local W, H = Config.MAP_WIDTH, Config.MAP_HEIGHT
local WATER_Y = H - Config.WATER_HEIGHT
local ANT_HEIGHT = 10 -- pixels of free space an ant needs
local G = Config.GRAVITY

local Sim = {}
Sim.__index = Sim
Sim.ANT_HEIGHT = ANT_HEIGHT

export type Member = { team: number, ownerId: number, name: string, isBot: boolean }

export type Ant = {
	id: number,
	team: number,
	ownerId: number, -- UserId of the player who controls it (0 for a bot)
	name: string,
	isBot: boolean,
	x: number,
	y: number, -- the lowest pixel row of the ant (feet)
	fx: number, -- parts of a pixel that are not moved yet
	fy: number,
	vx: number,
	vy: number,
	hp: number,
	alive: boolean,
	onGround: boolean,
	facing: number, -- 1 = right, -1 = left
	aim: number, -- degrees, 0 = straight forward, 90 = straight up
	walkAcc: number,
	walking: boolean,
	weapon: number, -- 1 acorn, 2 chestnut, 3 chestnut rain
	rainLeft: number, -- how many rains this ant still has
}

-- Everything that flies: "acorn", "chestnut", "seed" (from a chestnut), "rain" (falling chestnut).
-- delay: seconds before it starts falling (rain comes one by one).
export type Projectile = { kind: string, x: number, y: number, vx: number, vy: number, age: number, delay: number }
type Acorn = Projectile

-- explosion size and damage of each kind
local BLASTS = {
	acorn = { radius = Config.EXPLOSION_RADIUS, damage = Config.EXPLOSION_DAMAGE },
	chestnut = { radius = Config.CHESTNUT_RADIUS, damage = Config.CHESTNUT_DAMAGE },
	seed = { radius = Config.SEED_RADIUS, damage = Config.SEED_DAMAGE },
	rain = { radius = Config.RAIN_RADIUS, damage = Config.RAIN_DAMAGE },
}
local KIND_NUMBERS = { acorn = 1, chestnut = 2, seed = 3, rain = 4 } -- for the snapshot
local MAX_FLY_TIME = 15 -- safety: a turn never waits longer for things to land

export type Sim = typeof(setmetatable(
	{} :: {
		map: MapData.MapData,
		ants: { Ant },
		rng: Random,
		emit: (string, ...any) -> (),
		tutorial: boolean,
		state: string, -- "aim", "flying", "settle", "over"
		current: Ant?,
		currentTeam: number,
		nextAntOfTeam: { number },
		turnId: number, -- goes up every turn (the bot uses it to know its turn is still on)
		turnTimeLeft: number,
		settleTime: number,
		wind: number,
		walkDir: number,
		charging: boolean,
		chargeStart: number,
		power: number,
		projectiles: { Projectile },
		flyTime: number,
		winner: number?,
	},
	Sim
))

---------------------------------------------------------------- setup

function Sim.new(seed: number, kind: string, members: { Member }, tutorial: boolean, emit: (string, ...any) -> ()): Sim
	local self = setmetatable({
		map = MapData.new(seed, kind),
		ants = {},
		rng = Random.new(seed + 7),
		emit = emit,
		tutorial = tutorial,
		state = "settle",
		current = nil,
		currentTeam = 1,
		nextAntOfTeam = {},
		turnId = 0,
		turnTimeLeft = 0,
		settleTime = -1.5, -- a short pause at the start (players see the map name)
		wind = 0,
		walkDir = 0,
		charging = false,
		chargeStart = 0,
		power = 0,
		projectiles = {},
		flyTime = 0,
		winner = nil,
	}, Sim)
	self:spawnAnts(members)
	-- nextTurn moves to the next team; in the tutorial the player (team 1) must start
	self.currentTeam = if tutorial then #Config.TEAMS else self.rng:NextInteger(1, #Config.TEAMS)
	return self
end

-- Team 1 starts on the left half, team 2 on the right half, on fairly flat dry land,
-- not too close to each other.
function Sim.spawnAnts(self: Sim, members: { Member })
	local map = self.map
	local function goodSpot(x: number, strict: boolean): boolean
		local y = map:surfaceY(x)
		if y >= WATER_Y - 20 then
			return false
		end
		if not strict then
			return true
		end
		if math.abs(map:surfaceY(x - 4) - y) > 5 or math.abs(map:surfaceY(x + 4) - y) > 5 then
			return false
		end
		for _, other in self.ants do
			if math.abs(other.x - x) < 24 then
				return false
			end
		end
		return true
	end

	for i, member in members do
		local teams = #Config.TEAMS
		local left = (member.team - 1) * W / teams + 40
		local right = member.team * W / teams - 40
		local x = math.floor(self.rng:NextNumber(left, right))
		for try = 1, 400 do
			if goodSpot(x, try <= 300) then
				break
			end
			x = math.floor(self.rng:NextNumber(left, right))
		end
		table.insert(self.ants, {
			id = i,
			team = member.team,
			ownerId = member.ownerId,
			name = member.name,
			isBot = member.isBot,
			x = x,
			y = map:surfaceY(x) - 1,
			fx = 0,
			fy = 0,
			vx = 0,
			vy = 0,
			hp = Config.ANT_HP,
			alive = true,
			onGround = false,
			facing = if member.team == 1 then 1 else -1,
			aim = 30,
			walkAcc = 0,
			walking = false,
			weapon = 1,
			rainLeft = Config.RAIN_PER_ANT,
		})
	end
end

-- What every player needs to know at the start (they build the same map from the seed).
function Sim.startInfo(self: Sim)
	local ants = {}
	for _, ant in self.ants do
		table.insert(ants, { id = ant.id, team = ant.team, ownerId = ant.ownerId, name = ant.name, isBot = ant.isBot })
	end
	return { seed = self.map.seed, kind = self.map.kind, tutorial = self.tutorial, ants = ants }
end

---------------------------------------------------------------- ants

local function bodyFree(map: MapData.MapData, x: number, y: number): boolean
	for h = 0, ANT_HEIGHT - 1 do
		if map:isSolid(x, y - h) then
			return false
		end
	end
	return true
end

function Sim.kill(self: Sim, ant: Ant)
	if not ant.alive then
		return
	end
	ant.alive = false
	ant.hp = 0
	self.emit("kill", ant.id)
end

function Sim.hurt(self: Sim, ant: Ant, amount: number)
	amount = math.floor(amount + 0.5)
	if not ant.alive or amount <= 0 or self.tutorial then
		return
	end
	ant.hp = math.max(0, ant.hp - amount)
	self.emit("damage", ant.id, amount)
	if ant.hp <= 0 then
		self:kill(ant)
	end
end

function Sim.updateAnt(self: Sim, ant: Ant, dt: number)
	local map = self.map
	if not ant.alive then
		return
	end

	if not ant.onGround then
		ant.vy += G * dt
		-- sideways (after a jump or a blast), one pixel at a time
		ant.fx += ant.vx * dt
		while math.abs(ant.fx) >= 1 do
			local step = math.sign(ant.fx)
			ant.fx -= step
			if bodyFree(map, ant.x + step, ant.y) then
				ant.x += step
			else
				ant.vx, ant.fx = 0, 0
			end
		end
		-- up and down, one pixel at a time
		ant.fy += ant.vy * dt
		while ant.fy >= 1 and not map:isSolid(ant.x, ant.y + 1) do
			ant.y += 1
			ant.fy -= 1
		end
		while ant.fy <= -1 do
			if bodyFree(map, ant.x, ant.y - 1) then
				ant.y -= 1
				ant.fy += 1
			else
				ant.vy, ant.fy = 0, 0
			end
		end
	end

	if map:isSolid(ant.x, ant.y + 1) and ant.vy >= 0 then
		if not ant.onGround and ant.vy > Config.FALL_DAMAGE_SPEED then
			self:hurt(ant, (ant.vy - Config.FALL_DAMAGE_SPEED) / 6)
		end
		if not ant.onGround and ant.vy > 110 then
			self.emit("land", ant.id)
		end
		ant.onGround = true
		ant.vx, ant.vy, ant.fx, ant.fy = 0, 0, 0, 0
	else
		ant.onGround = false
	end

	if ant.alive and ant.y >= WATER_Y then
		self.emit("splash", ant.x)
		self:kill(ant)
	end
end

function Sim.walk(self: Sim, ant: Ant, dir: number, dt: number)
	ant.walking = false
	if dir == 0 or not ant.onGround then
		ant.walkAcc = 0
		return
	end
	local map = self.map
	ant.facing = dir
	ant.walking = true
	ant.walkAcc += Config.WALK_SPEED * dt
	while ant.walkAcc >= 1 do
		ant.walkAcc -= 1
		local moved = false
		for lift = 0, Config.CLIMB_STEP do
			if bodyFree(map, ant.x + dir, ant.y - lift) then
				ant.x += dir
				ant.y -= lift
				moved = true
				break
			end
		end
		if not moved then
			ant.walkAcc = 0
			ant.walking = false -- bumped into a wall
			break
		end
		-- walking down a hill: step down small slopes at once (a bigger drop is a fall)
		for _ = 1, Config.CLIMB_STEP do
			if map:isSolid(ant.x, ant.y + 1) then
				break
			end
			ant.y += 1
		end
	end
end

---------------------------------------------------------------- turns

function Sim.nextTurn(self: Sim)
	-- the next team that still has living ants
	for _ = 1, #Config.TEAMS do
		self.currentTeam = self.currentTeam % #Config.TEAMS + 1
		local teamAnts = {}
		for _, ant in self.ants do
			if ant.team == self.currentTeam and ant.alive then
				table.insert(teamAnts, ant)
			end
		end
		if #teamAnts > 0 then
			self.nextAntOfTeam[self.currentTeam] = (self.nextAntOfTeam[self.currentTeam] or 0) % #teamAnts + 1
			self.current = teamAnts[self.nextAntOfTeam[self.currentTeam]]
			break
		end
	end
	self.state = "aim"
	self.turnId += 1
	self.turnTimeLeft = Config.TURN_TIME
	self.wind = self.rng:NextNumber(-Config.MAX_WIND, Config.MAX_WIND)
	self.power, self.charging, self.walkDir = 0, false, 0
	local current = self.current
	if current then
		self.emit("turn", current.id)
	end
end

function Sim.checkGameOver(self: Sim): boolean
	local aliveTeams = {}
	for _, ant in self.ants do
		if ant.alive then
			aliveTeams[ant.team] = true
		end
	end
	local winner, count = 0, 0
	for team in aliveTeams do
		winner = team
		count += 1
	end
	if count > 1 then
		return false
	end
	self.state = "over"
	self.current = nil
	self.winner = winner
	self.emit("over", winner) -- 0 = nobody left (draw)
	return true
end

function Sim.endTurn(self: Sim)
	self.state = "settle"
	self.settleTime = 0
	self.charging = false
	self.walkDir = 0
	if self.current then
		self.current.walking = false
	end
end

---------------------------------------------------------------- acorn

function Sim.explode(self: Sim, x: number, y: number, blastRadius: number?, damage: number?)
	local radius: number = blastRadius or Config.EXPLOSION_RADIUS
	local fullDamage = damage or Config.EXPLOSION_DAMAGE
	x, y = math.floor(x + 0.5), math.floor(y + 0.5) -- whole numbers: every player cuts the same hole
	self.map:explode(x, y, radius)
	self.emit("explode", x, y, radius)

	if self.tutorial then
		return -- practice throws don't hurt or push anyone
	end
	local reach = radius * 1.5
	local push = Config.EXPLOSION_PUSH * radius / Config.EXPLOSION_RADIUS -- small blasts push less
	for _, ant in self.ants do
		if ant.alive then
			local dx, dy = ant.x - x, (ant.y - ANT_HEIGHT / 2) - y
			local d = math.sqrt(dx * dx + dy * dy)
			if d < reach then
				local k = 1 - d / reach
				self:hurt(ant, fullDamage * k)
				if d < 0.01 then
					dx, dy, d = 0, -1, 1
				end
				ant.vx = dx / d * push * k
				ant.vy = (dy / d - 0.6) * push * k
				ant.onGround = false
			end
		end
	end
end

-- Start position and speed of an acorn thrown by this ant.
function Sim.launch(ant: Ant, aimDeg: number, facing: number, power: number): (number, number, number, number)
	local angle = math.rad(aimDeg)
	local dx, dy = math.cos(angle) * facing, -math.sin(angle)
	local speed = Config.MIN_THROW_SPEED + (Config.MAX_THROW_SPEED - Config.MIN_THROW_SPEED) * power
	return ant.x + dx * 8, ant.y - ANT_HEIGHT / 2 + dy * 8, dx * speed, dy * speed
end

-- One step of the acorn's flight. Returns "fly", "ground", "ant", "water" or "gone".
function Sim.moveAcorn(self: Sim, a: Acorn, dt: number, thrower: Ant?): string
	a.age += dt
	a.vx += self.wind * dt
	a.vy += G * dt
	local steps = math.max(1, math.ceil(math.sqrt(a.vx * a.vx + a.vy * a.vy) * dt))
	for _ = 1, steps do
		a.x += a.vx * dt / steps
		a.y += a.vy * dt / steps
		if a.y >= WATER_Y then
			return "water"
		end
		if a.x < -100 or a.x > W + 100 then
			return "gone"
		end
		for _, ant in self.ants do
			if ant.alive and (ant ~= thrower or a.age > 0.2) then
				local dx, dy = ant.x - a.x, (ant.y - ANT_HEIGHT / 2) - a.y
				if dx * dx + dy * dy < 64 then
					return "ant"
				end
			end
		end
		if self.map:isSolid(a.x, a.y) then
			return "ground"
		end
	end
	return "fly"
end

-- Where would this throw land? (The bot uses it to try many throws in its head.)
function Sim.simulateShot(self: Sim, ant: Ant, aimDeg: number, facing: number, power: number): (number, number, string)
	local x, y, vx, vy = Sim.launch(ant, aimDeg, facing, power)
	local a: Acorn = { kind = "acorn", x = x, y = y, vx = vx, vy = vy, age = 0, delay = 0 }
	for _ = 1, 400 do -- at most ~13 seconds of flight
		local result = self:moveAcorn(a, 1 / 30, ant)
		if result ~= "fly" then
			return a.x, a.y, result
		end
	end
	return a.x, a.y, "gone"
end

local function startFlying(self: Sim, ant: Ant)
	self.charging = false
	self.power = 0
	self.walkDir = 0
	self.flyTime = 0
	ant.walking = false
	self.state = "flying"
	self.emit("throw", ant.id)
end

-- Throws the acorn or the chestnut (whatever the ant holds) with the charged power.
function Sim.throw(self: Sim)
	local ant = self.current
	if not ant or self.state ~= "aim" or ant.weapon == 3 then
		return
	end
	local x, y, vx, vy = Sim.launch(ant, ant.aim, ant.facing, self.power)
	local kind = if ant.weapon == 2 then "chestnut" else "acorn"
	table.insert(self.projectiles, { kind = kind, x = x, y = y, vx = vx, vy = vy, age = 0, delay = 0 })
	startFlying(self, ant)
end

-- Chestnut rain: chestnuts fall one by one from above the clicked spot.
function Sim.rain(self: Sim, targetX: number)
	local ant = self.current
	if not ant or self.state ~= "aim" or ant.weapon ~= 3 or ant.rainLeft <= 0 then
		return
	end
	if not self.tutorial then
		ant.rainLeft -= 1 -- practice in the tutorial is free
	end
	targetX = math.clamp(targetX, 0, W)
	for i = 1, Config.RAIN_COUNT do
		table.insert(self.projectiles, {
			kind = "rain",
			x = targetX + self.rng:NextNumber(-Config.RAIN_SPREAD, Config.RAIN_SPREAD),
			y = -12,
			vx = 0,
			vy = 40,
			age = 0,
			delay = (i - 1) * Config.RAIN_DELAY,
		})
	end
	startFlying(self, ant)
	if ant.rainLeft <= 0 then
		ant.weapon = 1 -- no rain left: back to acorns next time
	end
end

-- A chestnut burst: small seeds jump out of the blast (added to `into`).
function Sim.splitChestnut(self: Sim, x: number, y: number, into: { Projectile })
	for _ = 1, Config.SEED_COUNT do
		table.insert(into, {
			kind = "seed",
			x = x,
			y = y - 4,
			vx = self.rng:NextNumber(-Config.SEED_SPEED_SIDE, Config.SEED_SPEED_SIDE),
			vy = -Config.SEED_SPEED_UP * self.rng:NextNumber(0.75, 1.15),
			age = 0,
			delay = 0,
		})
	end
end

-- Everything has landed: the turn ends (in the tutorial the same ant keeps practicing).
function Sim.allLanded(self: Sim)
	table.clear(self.projectiles)
	if self.tutorial then
		self.state = "aim"
		self.emit("practiceDone")
	else
		self:endTurn()
	end
end

---------------------------------------------------------------- input

-- A player (ownerId) pressed something. Only the owner of the current ant may play.
function Sim.input(self: Sim, ownerId: number, action: string, a: any, b: any)
	local ant = self.current
	if not ant or ant.ownerId ~= ownerId or self.state ~= "aim" then
		if action == "tutorialEnd" then
			self:endTutorial()
		end
		return
	end
	if action == "walk" and (a == -1 or a == 0 or a == 1) then
		self.walkDir = a
	elseif action == "aim" and type(a) == "number" and a == a and (b == 1 or b == -1) then
		ant.aim = math.clamp(a, -80, 88)
		if self.walkDir == 0 then
			ant.facing = b
		end
	elseif action == "jump" and ant.onGround then
		local islands = self.map.kind == "islands"
		ant.vy = -(if islands then Config.ISLAND_JUMP_SPEED else Config.JUMP_SPEED)
		ant.vx = ant.facing * (if islands then Config.ISLAND_JUMP_FORWARD else Config.JUMP_FORWARD)
		ant.onGround = false
		ant.walking = false
	elseif action == "charge" and ant.weapon ~= 3 then
		self.charging = true
		self.chargeStart = os.clock()
		self.power = 0
	elseif action == "throw" and self.charging then
		self:throw()
	elseif action == "weapon" and (a == 1 or a == 2 or a == 3) and not self.charging then
		if a ~= 3 or ant.rainLeft > 0 then
			ant.weapon = a
		end
	elseif action == "rain" and type(a) == "number" and a == a then
		self:rain(a)
	elseif action == "tutorialEnd" then
		self:endTutorial()
	end
end

function Sim.endTutorial(self: Sim)
	if self.tutorial then
		self.tutorial = false
		self.turnTimeLeft = Config.TURN_TIME -- the real game starts with a full clock
		self.emit("tutorialEnd")
	end
end

-- A player left the match: their ants are out.
function Sim.removeOwner(self: Sim, ownerId: number)
	for _, ant in self.ants do
		if ant.ownerId == ownerId and not ant.isBot and ant.alive then
			self:kill(ant)
			if ant == self.current and self.state == "aim" then
				self:endTurn()
			end
		end
	end
end

---------------------------------------------------------------- the loop

function Sim.step(self: Sim, dt: number)
	if self.state == "over" then
		return
	end
	dt = math.min(dt, 1 / 20)

	local ant = self.current
	if self.state == "aim" and ant then
		self:walk(ant, self.walkDir, dt)
		if self.charging then
			self.power = math.min(1, (os.clock() - self.chargeStart) / Config.CHARGE_TIME)
			if self.power >= 1 then
				self:throw()
			end
		end
		if not self.tutorial then
			self.turnTimeLeft -= dt
		end
		if self.turnTimeLeft <= 0 or not ant.alive then
			if self.tutorial then
				self:endTutorial()
			end
			self:endTurn()
		end
	end

	for _, other in self.ants do
		self:updateAnt(other, dt)
	end

	if self.state == "flying" then
		self.flyTime += dt
		local landed = {}
		local spawned = {}
		for i, p in self.projectiles do
			if p.delay > 0 then
				p.delay -= dt -- rain: not falling yet
				continue
			end
			-- only the first throw can't hit its own thrower at the start
			local thrower = if p.kind == "acorn" or p.kind == "chestnut" then self.current else nil
			local result = self:moveAcorn(p, dt, thrower)
			if result ~= "fly" then
				table.insert(landed, i)
				if result == "ground" or result == "ant" then
					local blast = BLASTS[p.kind] or BLASTS.acorn
					self:explode(p.x, p.y, blast.radius, blast.damage)
					if p.kind == "chestnut" then
						self:splitChestnut(p.x, p.y, spawned)
					end
				elseif result == "water" and p.kind ~= "seed" then
					self.emit("splash", p.x)
				end
			end
		end
		for n = #landed, 1, -1 do
			table.remove(self.projectiles, landed[n])
		end
		for _, p in spawned do
			table.insert(self.projectiles, p)
		end
		if #self.projectiles == 0 or self.flyTime > MAX_FLY_TIME then
			self:allLanded()
		end
	end

	if self.state == "settle" then
		self.settleTime += dt
		local everyoneStill = true
		for _, other in self.ants do
			if other.alive and not other.onGround then
				everyoneStill = false
			end
		end
		if (everyoneStill and self.settleTime > 1) or self.settleTime > 6 then
			if not self:checkGameOver() then
				self:nextTurn()
			end
		end
	end
end

---------------------------------------------------------------- snapshot

-- Packs everything players need to draw the game into a small buffer
-- (sent about 20 times a second).
local STATES = { aim = 1, flying = 2, settle = 3, over = 4 }
local function coord(v: number): number
	return math.clamp(math.floor((v + 512) * 16 + 0.5), 0, 65535)
end

-- Layout: header (14 bytes), then 7 bytes per ant, then 5 bytes per flying thing.
-- header: 0 state, 1 current ant, 2 time left, 3-4 wind x10, 5 power, 6 flags
-- (1 charging, 4 tutorial), 7 current ant's weapon, 8 its rains left, 9-10 turnId,
-- 11 ant count, 12 flying count, 13 unused
Sim.SNAPSHOT_HEADER, Sim.SNAPSHOT_ANT, Sim.SNAPSHOT_PROJECTILE = 14, 7, 5

function Sim.snapshot(self: Sim): buffer
	local count = #self.ants
	local flying = {}
	for _, p in self.projectiles do
		if p.delay <= 0 and #flying < 40 then
			table.insert(flying, p)
		end
	end
	local antsStart = 14
	local flyStart = antsStart + count * 7
	local b = buffer.create(flyStart + #flying * 5)
	local cur = self.current
	buffer.writeu8(b, 0, STATES[self.state] or 0)
	buffer.writeu8(b, 1, if cur then cur.id else 0)
	buffer.writeu8(b, 2, math.clamp(math.ceil(self.turnTimeLeft), 0, 255))
	buffer.writei16(b, 3, math.floor(self.wind * 10 + 0.5))
	buffer.writeu8(b, 5, math.floor(self.power * 255))
	buffer.writeu8(b, 6, (if self.charging then 1 else 0) + (if self.tutorial then 4 else 0))
	buffer.writeu8(b, 7, if cur then cur.weapon else 1)
	buffer.writeu8(b, 8, if cur then math.clamp(cur.rainLeft, 0, 255) else 0)
	buffer.writeu16(b, 9, self.turnId % 65536)
	buffer.writeu8(b, 11, count)
	buffer.writeu8(b, 12, #flying)
	for i, p in flying do
		local o = flyStart + (i - 1) * 5
		buffer.writeu8(b, o, KIND_NUMBERS[p.kind] or 1)
		buffer.writeu16(b, o + 1, coord(p.x))
		buffer.writeu16(b, o + 3, coord(p.y))
	end
	for i, ant in self.ants do
		local o = antsStart + (i - 1) * 7
		buffer.writeu16(b, o, coord(ant.x))
		buffer.writeu16(b, o + 2, coord(ant.y))
		buffer.writeu8(b, o + 4, math.clamp(ant.hp, 0, 255))
		local flags = (if ant.alive then 1 else 0)
			+ (if ant.onGround then 2 else 0)
			+ (if ant.walking then 4 else 0)
			+ (if ant.facing > 0 then 8 else 0)
		buffer.writeu8(b, o + 5, flags)
		buffer.writei8(b, o + 6, math.clamp(math.floor(ant.aim + 0.5), -128, 127))
	end
	return b
end

return Sim
