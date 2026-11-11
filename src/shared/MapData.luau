-- What the map is made of: one byte per pixel (a material number), no colors.
-- The server and every player build the SAME map from the same seed (a number that
-- decides all the random choices), so only the seed has to be sent over the network.
-- Explosions are sent as (x, y, radius) and everyone cuts the same hole.
local Config = require(script.Parent.Config)

local W, H = Config.MAP_WIDTH, Config.MAP_HEIGHT
local WATER_Y = H - Config.WATER_HEIGHT
-- the generators were made for a 640 x 360 map; on a bigger map they make more of
-- everything (islands, mushrooms, tunnels) and higher hills
local SCALE_X, SCALE_Y = W / 640, H / 360

local function scaled(n: number): number
	return math.max(1, math.floor(n * SCALE_X + 0.5))
end

local MapData = {}
MapData.__index = MapData

export type MapData = typeof(setmetatable(
	{} :: {
		grid: buffer, -- material of every pixel
		tops: { number }, -- the ground line from the generator (for coloring)
		kind: string,
		name: string,
		seed: number,
	},
	MapData
))

-- Materials. Everything except AIR and BLADE is solid ground.
-- BLADE (grass) is only decoration: ants walk through it and acorns fly through it.
local AIR, DIRT, STONE, STEM, CAP, DOT, ROOT, BLADE = 0, 1, 2, 3, 4, 5, 6, 7
MapData.M = { AIR = AIR, DIRT = DIRT, STONE = STONE, STEM = STEM, CAP = CAP, DOT = DOT, ROOT = ROOT, BLADE = BLADE }

MapData.KINDS = { "meadow", "islands", "anthill", "garden" }
MapData.NAMES = { meadow = "Łąka", islands = "Wyspy", anthill = "Mrowisko", garden = "Ogród" }

local function get(grid: buffer, x: number, y: number): number
	x, y = math.floor(x), math.floor(y)
	if x < 0 or x >= W or y < 0 or y >= H then
		return AIR
	end
	return buffer.readu8(grid, y * W + x)
end

local function set(grid: buffer, x: number, y: number, material: number)
	x, y = math.floor(x), math.floor(y)
	if x >= 0 and x < W and y >= 0 and y < H then
		buffer.writeu8(grid, y * W + x, material)
	end
end

-- Filled oval. With `onlyOn`, it only paints over that material (stones only inside dirt).
local function oval(grid: buffer, cx: number, cy: number, rx: number, ry: number, material: number, onlyOn: number?)
	for y = math.floor(cy - ry), math.ceil(cy + ry) do
		for x = math.floor(cx - rx), math.ceil(cx + rx) do
			local dx, dy = (x - cx) / rx, (y - cy) / ry
			if dx * dx + dy * dy <= 1 and (onlyOn == nil or get(grid, x, y) == onlyOn) then
				set(grid, x, y, material)
			end
		end
	end
end

-- Thick curved line (quadratic curve from p1 through the pull of c to p2).
local function curve(grid: buffer, x1, y1, cx, cy, x2, y2, radius: number, material: number)
	local steps = math.ceil((math.abs(x2 - x1) + math.abs(y2 - y1) + math.abs(cy - y1)) / 2) + 2
	for i = 0, steps do
		local t = i / steps
		local a, b, c = (1 - t) ^ 2, 2 * (1 - t) * t, t ^ 2
		oval(grid, a * x1 + b * cx + c * x2, a * y1 + b * cy + c * y2, radius, radius, material)
	end
end

-- Ground line made of a few sine waves; it slopes into the water at both map sides.
local function hills(rng: Random, base: number, minAmp: number, maxAmp: number): { number }
	local waves = {}
	for i = 1, 4 do
		waves[i] = {
			amp = rng:NextNumber(minAmp, maxAmp) / i,
			freq = rng:NextNumber(0.6, 1.4) * i * math.pi * 2 / W,
			phase = rng:NextNumber(0, math.pi * 2),
		}
	end
	local tops = {}
	for x = 0, W - 1 do
		local top = base
		for _, wave in waves do
			top += wave.amp * math.sin(x * wave.freq + wave.phase)
		end
		local edge = math.min(x, W - 1 - x)
		if edge < 40 then
			top += (40 - edge) * 2
		end
		tops[x] = math.floor(math.clamp(top, 60, H - 5))
	end
	return tops
end

local function noGround(): { number }
	local tops = {}
	for x = 0, W - 1 do
		tops[x] = H
	end
	return tops
end

local function fillBelow(grid: buffer, tops: { number })
	for x = 0, W - 1 do
		for y = tops[x], H - 1 do
			set(grid, x, y, DIRT)
		end
	end
end

-- Pebbles hidden in the dirt.
local function addStones(grid: buffer, rng: Random, count: number)
	for _ = 1, count do
		for _ = 1, 20 do -- look for a dirt spot
			local x, y = rng:NextInteger(10, W - 10), rng:NextInteger(60, WATER_Y)
			if get(grid, x, y) == DIRT then
				oval(grid, x, y, rng:NextNumber(3, 9), rng:NextNumber(2, 6), STONE, DIRT)
				break
			end
		end
	end
end

-- Little tufts of grass on top of dirt that sees the sky.
local function addBlades(grid: buffer, rng: Random)
	local x = 2
	while x < W - 2 do
		local y = 0
		while y < H and get(grid, x, y) == AIR do
			y += 1
		end
		if y < WATER_Y - 4 and get(grid, x, y) == DIRT then
			local height = rng:NextInteger(2, 4)
			local lean = rng:NextInteger(-1, 1)
			for h = 1, height do
				set(grid, x + (if h == height then lean else 0), y - h, BLADE)
			end
		end
		x += rng:NextInteger(2, 5)
	end
end

---------------------------------------------------------------- the 4 kinds of map

-- Each generator paints the grid and returns the ground line (tops[x], H = no ground).
local generators = {}

-- Łąka: rolling hills with pebbles and grass.
function generators.meadow(grid: buffer, rng: Random): { number }
	local tops = hills(rng, H * 0.55, 15 * SCALE_Y, 45 * SCALE_Y)
	fillBelow(grid, tops)
	addStones(grid, rng, scaled(16))
	addBlades(grid, rng)
	return tops
end

-- Wyspy: a few islands with flat tops sticking out of the water.
function generators.islands(grid: buffer, rng: Random): { number }
	local tops = noGround()
	local count = rng:NextInteger(scaled(3), scaled(4))
	local bottom = WATER_Y + 12
	for i = 1, count do
		local cx = (i - 0.5) / count * W + rng:NextNumber(-10, 10)
		local half = rng:NextNumber(48, W / count / 2 - 8)
		local peak = rng:NextNumber(H * 0.48, H * 0.68)
		local bumpAmp, bumpFreq, bumpPhase = rng:NextNumber(2, 6), rng:NextNumber(0.04, 0.1), rng:NextNumber(0, 6)
		for x = math.floor(cx - half), math.ceil(cx + half) do
			local k = (x - cx) / half
			if math.abs(k) <= 1 and x >= 0 and x < W then
				local shape = math.min(1, (1 - k * k) * 1.8) ^ 0.8 -- 1 on the flat top, 0 at the shore
				local top = bottom - (bottom - peak) * shape + bumpAmp * math.sin(x * bumpFreq + bumpPhase) * shape
				tops[x] = math.floor(top)
				for y = tops[x], H - 1 do
					set(grid, x, y, DIRT)
				end
			end
		end
	end
	addStones(grid, rng, scaled(10))
	addBlades(grid, rng)
	return tops
end

-- Mrowisko: high ground full of winding tunnels and chambers.
function generators.anthill(grid: buffer, rng: Random): { number }
	local tops = hills(rng, H * 0.38, 8 * SCALE_Y, 28 * SCALE_Y)
	fillBelow(grid, tops)
	addStones(grid, rng, scaled(14))

	local chambers = {}
	for _ = 1, rng:NextInteger(scaled(4), scaled(6)) do
		local x = rng:NextNumber(70, W - 70)
		local y = tops[math.floor(x)] + rng:NextNumber(25, 60)
		local angle = rng:NextNumber(0, math.pi * 2)
		local radius = rng:NextNumber(7, 9) -- ants are 10 pixels tall, tunnels must fit them
		for step = 1, rng:NextInteger(110, 200) do
			oval(grid, x, y, radius, radius, AIR)
			angle += rng:NextNumber(-0.35, 0.35)
			x += math.cos(angle) * 2
			y += math.sin(angle) * 1.4
			-- stay inside the ground: turn back from the edges and the water
			if x < 50 or x > W - 50 then
				angle = math.pi - angle
				x = math.clamp(x, 50, W - 50)
			end
			if y > WATER_Y - 30 or y < tops[math.floor(x)] + 22 then
				angle = -angle
				y = math.clamp(y, tops[math.floor(x)] + 22, WATER_Y - 30)
			end
			if step % 70 == 0 then
				table.insert(chambers, { x, y })
			end
		end
	end
	for _, c in chambers do
		oval(grid, c[1], c[2], rng:NextNumber(16, 26), rng:NextNumber(9, 13), AIR)
	end
	-- a couple of entrances from the surface
	for _ = 1, scaled(2) do
		local x = rng:NextNumber(90, W - 90)
		local top = tops[math.floor(x)]
		curve(grid, x, top - 4, x + rng:NextNumber(-30, 30), top + 25, x + rng:NextNumber(-40, 40), top + 50, 7, AIR)
	end
	addBlades(grid, rng)
	return tops
end

-- Ogród: low ground with giant mushrooms and root arches to climb.
function generators.garden(grid: buffer, rng: Random): { number }
	local tops = hills(rng, H * 0.68, 6 * SCALE_Y, 18 * SCALE_Y)
	fillBelow(grid, tops)
	addStones(grid, rng, scaled(8))

	-- roots: arches that go up out of the ground and back down
	for _ = 1, rng:NextInteger(scaled(2), scaled(3)) do
		local x1 = rng:NextNumber(50, W - 200)
		local x2 = x1 + rng:NextNumber(70, 150)
		local y1, y2 = tops[math.floor(x1)] + 4, tops[math.floor(x2)] + 4
		local lift = rng:NextNumber(30, 60)
		curve(grid, x1, y1, (x1 + x2) / 2, math.min(y1, y2) - lift * 2, x2, y2, rng:NextNumber(2.5, 3.5), ROOT)
	end

	-- mushrooms: a stem and a round cap with white dots
	local count = rng:NextInteger(scaled(3), scaled(4))
	for i = 1, count do
		local x = (i - 0.5) / count * W + rng:NextNumber(-25, 25)
		local ground = tops[math.floor(math.clamp(x, 0, W - 1))]
		local capY = ground - rng:NextNumber(35, 80)
		local stem = rng:NextNumber(4, 6)
		for y = math.floor(capY), ground + 3 do
			for sx = -stem, stem do
				set(grid, x + sx, y, STEM)
			end
		end
		local rx, ry = rng:NextNumber(24, 38), rng:NextNumber(13, 19)
		for y = math.floor(capY - ry), math.floor(capY + 3) do
			for cx = math.floor(x - rx), math.ceil(x + rx) do
				local dx, dy = (cx - x) / rx, (y - capY) / ry
				if dx * dx + dy * dy <= 1 then
					set(grid, cx, y, CAP)
				end
			end
		end
		for _ = 1, rng:NextInteger(4, 6) do
			local r = rng:NextNumber(2, 3.5)
			oval(grid, x + rng:NextNumber(-rx * 0.7, rx * 0.7), capY - rng:NextNumber(2, ry * 0.75), r, r, DOT, CAP)
		end
	end
	addBlades(grid, rng)
	return tops
end

---------------------------------------------------------------- map object

-- Picks a map kind, never the same as `previousKind`.
function MapData.pickKind(rng: Random, previousKind: string?): string
	local choices = {}
	for _, kind in MapData.KINDS do
		if kind ~= previousKind then
			table.insert(choices, kind)
		end
	end
	return choices[rng:NextInteger(1, #choices)]
end

-- Builds the map of this kind from this seed (same seed + kind = same map everywhere).
function MapData.new(seed: number, kind: string): MapData
	local grid = buffer.create(W * H)
	local tops = generators[kind](grid, Random.new(seed))
	return setmetatable({ grid = grid, tops = tops, kind = kind, name = MapData.NAMES[kind], seed = seed }, MapData)
end

function MapData.material(self: MapData, x: number, y: number): number
	return get(self.grid, x, y)
end

function MapData.isSolid(self: MapData, x: number, y: number): boolean
	local m = get(self.grid, x, y)
	return m ~= AIR and m ~= BLADE
end

-- The first solid pixel from the top in column x (H if there is no ground).
function MapData.surfaceY(self: MapData, x: number): number
	for y = 0, H - 1 do
		if self:isSolid(x, y) then
			return y
		end
	end
	return H
end

-- Cuts a round hole. Use whole numbers for cx, cy so everyone cuts exactly the same pixels.
function MapData.explode(self: MapData, cx: number, cy: number, radius: number)
	for y = math.max(0, math.floor(cy - radius)), math.min(H - 1, math.ceil(cy + radius)) do
		for x = math.max(0, math.floor(cx - radius)), math.min(W - 1, math.ceil(cx + radius)) do
			if (x - cx) ^ 2 + (y - cy) ^ 2 <= radius * radius then
				buffer.writeu8(self.grid, y * W + x, AIR)
			end
		end
	end
end

return MapData
