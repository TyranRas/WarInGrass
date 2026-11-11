-- The bot plays a turn: thinks, tries many throws "in its head" (simulateShot), picks the
-- one that lands closest to an enemy, turns its aim there slowly, charges and throws.
-- It makes a small mistake on purpose (Config.BOT_AIM_ERROR / BOT_POWER_ERROR).
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("WarInGrassShared")
local Config = require(Shared.Config)

local Bot = {}

local rng = Random.new()
local BLAST = Config.EXPLOSION_RADIUS * 1.5

-- How good is a throw that lands at (x, y)? Smaller is better.
local function score(sim, ant, x: number, y: number, result: string): number
	if result == "water" or result == "gone" then
		return 100000
	end
	local best = math.huge
	for _, other in sim.ants do
		if other.alive and other.team ~= ant.team then
			local dx, dy = other.x - x, (other.y - sim.ANT_HEIGHT / 2) - y
			best = math.min(best, math.sqrt(dx * dx + dy * dy))
		end
	end
	-- don't blow up yourself or your friends
	for _, other in sim.ants do
		if other.alive and other.team == ant.team then
			local dx, dy = other.x - x, (other.y - sim.ANT_HEIGHT / 2) - y
			if math.sqrt(dx * dx + dy * dy) < BLAST then
				best += 500
			end
		end
	end
	return best
end

-- Where should the bot click for chestnut rain? Drops a test chestnut "in its head" from
-- many spots (the wind blows it) and picks the one that falls closest to an enemy.
-- Returns the x to click and how close it falls (smaller is better).
local function planRain(sim, ant): (number, number)
	local bestX, bestScore = ant.x, math.huge
	for x = 0, Config.MAP_WIDTH, 8 do
		local p = { kind = "rain", x = x, y = -12, vx = 0, vy = 40, age = 0, delay = 0 }
		local result = "fly"
		for _ = 1, 400 do
			result = sim:moveAcorn(p, 1 / 30, nil)
			if result ~= "fly" then
				break
			end
		end
		local s = score(sim, ant, p.x, p.y, result)
		if s < bestScore then
			bestX, bestScore = x, s
		end
		if x % 64 == 0 then
			task.wait() -- spread the thinking over frames
		end
	end
	return bestX, bestScore
end

function Bot.takeTurn(sim, ant)
	local turnId = sim.turnId
	local function stillMyTurn(): boolean
		return sim.turnId == turnId and sim.state == "aim" and sim.current == ant and ant.alive
	end

	task.wait(Config.BOT_THINK_TIME)
	if not stillMyTurn() then
		return
	end

	-- try many throws: both directions, many angles and powers
	local bestAim, bestFacing, bestPower, bestScore = 45, ant.facing, 0.6, math.huge
	for _, facing in { 1, -1 } do
		for aim = -20, 85, 5 do
			for power = 0.15, 1.0001, 0.05 do
				local x, y, result = sim:simulateShot(ant, aim, facing, power)
				local s = score(sim, ant, x, y, result)
				if s < bestScore then
					bestAim, bestFacing, bestPower, bestScore = aim, facing, power, s
				end
			end
			task.wait() -- spread the thinking over many frames so the server doesn't freeze
			if not stillMyTurn() then
				return
			end
		end
	end

	-- hard to hit with a throw? sometimes use the chestnut rain instead
	if ant.rainLeft > 0 and bestScore > 45 and rng:NextNumber() < 0.6 then
		local rainX, rainScore = planRain(sim, ant)
		if not stillMyTurn() then
			return
		end
		if rainScore < bestScore and rainScore < 40 then
			sim:input(ant.ownerId, "weapon", 3)
			task.wait(0.8) -- players see the weapon change
			if not stillMyTurn() then
				return
			end
			sim:input(ant.ownerId, "rain", rainX + rng:NextNumber(-Config.BOT_AIM_ERROR, Config.BOT_AIM_ERROR) * 3)
			return
		end
	end

	-- the throw lands near an enemy: sometimes take the chestnut (seeds spread the damage)
	local weapon = if bestScore < BLAST and rng:NextNumber() < 0.4 then 2 else 1
	if weapon ~= ant.weapon then
		sim:input(ant.ownerId, "weapon", weapon)
		task.wait(0.5)
		if not stillMyTurn() then
			return
		end
	end

	-- a small mistake, so the bot can miss
	local targetAim = math.clamp(bestAim + rng:NextNumber(-Config.BOT_AIM_ERROR, Config.BOT_AIM_ERROR), -80, 88)
	local targetPower = math.clamp(bestPower + rng:NextNumber(-Config.BOT_POWER_ERROR, Config.BOT_POWER_ERROR), 0.05, 1)

	-- turn the aim slowly, so players can see what the bot does
	local startAim = ant.aim
	if bestFacing ~= ant.facing then
		startAim = 90 -- turning around: start from straight up
	end
	local turnTime = 0.7
	local t = 0
	while t < turnTime do
		t += task.wait()
		if not stillMyTurn() then
			return
		end
		local k = math.min(1, t / turnTime)
		sim:input(ant.ownerId, "aim", startAim + (targetAim - startAim) * k, bestFacing)
	end
	task.wait(0.3)
	if not stillMyTurn() then
		return
	end

	-- charge and let go at the chosen power
	sim:input(ant.ownerId, "charge")
	while stillMyTurn() and sim.charging and sim.power < targetPower do
		task.wait()
	end
	if stillMyTurn() and sim.charging then
		sim:input(ant.ownerId, "throw")
	end
end

return Bot
