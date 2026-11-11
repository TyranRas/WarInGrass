-- The picture of the map on the player's screen (EditableImage).
-- What the map is made of lives in the shared MapData; this file only gives it colors,
-- and shows the holes after explosions.
local AssetService = game:GetService("AssetService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("WarInGrassShared")
local Config = require(Shared.Config)
local MapData = require(Shared.MapData)

local W, H = Config.MAP_WIDTH, Config.MAP_HEIGHT
local M = MapData.M

-- Retro look: the picture is made of bigger "pixels" (B x B map pixels) in a few old-console
-- colors. The map underneath still works pixel by pixel; this only changes the picture.
local B = 2
local GRASS_ROWS = 3 -- grass on top of the ground, in big pixels
local BAND = 28 -- the ground gets darker in steps every BAND map pixels down

-- colors { r, g, b }
local GRASS_TOP = { 184, 248, 24 }
local GRASS = { 0, 168, 0 }
local GRASS_DARK = { 0, 120, 0 }
local DIRT_BANDS = { { 152, 96, 40 }, { 132, 82, 34 }, { 112, 68, 28 }, { 92, 56, 24 }, { 76, 46, 20 } }
local TUNNEL_FLOOR = { 188, 132, 72 }
local BACK_BANDS = { { 64, 38, 20 }, { 54, 32, 17 }, { 44, 26, 14 }, { 36, 21, 12 } }
local STONE = { 128, 128, 136 }
local STONE_LIGHT = { 168, 168, 176 }
local STONE_DARK = { 92, 92, 104 }
local STEM = { 252, 228, 176 }
local STEM_DARK = { 228, 196, 140 }
local CAPS = { { 216, 40, 0 }, { 228, 100, 16 } }
local DOT = { 252, 252, 252 }
local ROOT = { 136, 84, 36 }
local ROOT_DARK = { 100, 60, 24 }
local BLADE = { 0, 168, 0 }
local BLADE_LIGHT = { 88, 216, 84 }

local Map = {}
Map.__index = Map

export type Map = typeof(setmetatable(
	{} :: {
		data: MapData.MapData,
		image: EditableImage,
		back: EditableImage?, -- dark earth wall behind the ground
		pixels: buffer,
		backPixels: buffer,
	},
	Map
))

local function index(x: number, y: number): number
	return (y * W + x) * 4
end

local function writeColor(pixels: buffer, i: number, r: number, g: number, b: number)
	buffer.writeu8(pixels, i, math.clamp(math.floor(r), 0, 255))
	buffer.writeu8(pixels, i + 1, math.clamp(math.floor(g), 0, 255))
	buffer.writeu8(pixels, i + 2, math.clamp(math.floor(b), 0, 255))
	buffer.writeu8(pixels, i + 3, 255)
end

-- Paints one big pixel (B x B map pixels) with one color. color = nil makes it clear.
local function fillBlock(pixels: buffer, bx: number, by: number, color: { number }?)
	for dy = 0, B - 1 do
		for dx = 0, B - 1 do
			local i = index(bx * B + dx, by * B + dy)
			if color then
				writeColor(pixels, i, color[1], color[2], color[3])
			else
				buffer.writeu32(pixels, i, 0)
			end
		end
	end
end

local function band(list: { { number } }, depth: number): { number }
	return list[math.min(#list, math.floor(depth / BAND) + 1)]
end

-- Turns the materials into big colored pixels. `backPixels` gets the dark earth wall that is
-- seen through tunnels and blast holes (everything a bit below the ground line).
-- Each big pixel takes the material of its top-left map pixel.
local function paint(self: Map)
	local data, tops = self.data, self.data.tops
	local rng = Random.new(data.seed + 1) -- only for speckles
	local capColor = CAPS[rng:NextInteger(1, #CAPS)]
	for bx = 0, W / B - 1 do
		local x = bx * B
		local dirtSeen = false -- first dirt from the top gets grass, dirt under a tunnel does not
		local surfaceRow = nil
		local run = 0 -- how many solid big pixels in a row since the last air
		for by = 0, H / B - 1 do
			local y = by * B
			local m = data:material(x, y)
			local depth = math.max(0, y - tops[x])
			local speckle = rng:NextInteger(1, 6) -- 1 = lighter spot, 6 = darker spot
			if y >= tops[x] + 3 then
				local c = band(BACK_BANDS, depth)
				if speckle == 6 then
					c = { c[1] - 10, c[2] - 6, c[3] - 4 }
				end
				fillBlock(self.backPixels, bx, by, c)
			end
			if m == M.AIR then
				fillBlock(self.pixels, bx, by, nil)
				if run > 0 and surfaceRow then
					dirtSeen = true
				end
				run = 0
				continue
			end
			run += 1
			local c: { number }
			if m == M.DIRT then
				surfaceRow = surfaceRow or by
				local row = by - surfaceRow
				if not dirtSeen and row < GRASS_ROWS then
					c = if row == 0 then GRASS_TOP elseif speckle == 6 then GRASS_DARK else GRASS
				elseif run <= 1 and dirtSeen then -- floor of a tunnel
					c = TUNNEL_FLOOR
				else
					c = band(DIRT_BANDS, depth)
					if speckle == 1 then
						c = { c[1] + 18, c[2] + 12, c[3] + 6 }
					elseif speckle == 6 then
						c = { c[1] - 16, c[2] - 10, c[3] - 6 }
					end
				end
			elseif m == M.STONE then
				c = if speckle == 1 then STONE_LIGHT elseif speckle == 6 then STONE_DARK else STONE
			elseif m == M.STEM then
				c = if (bx + by) % 5 == 0 then STEM_DARK else STEM
			elseif m == M.CAP then
				c = capColor
			elseif m == M.DOT then
				c = DOT
			elseif m == M.ROOT then
				c = if (bx + by) % 4 == 0 then ROOT_DARK else ROOT
			else -- BLADE
				c = if speckle <= 2 then BLADE_LIGHT else BLADE
			end
			fillBlock(self.pixels, bx, by, c)
		end
	end
end

local function newImage(): (EditableImage?, string?)
	local ok, image = pcall(function()
		return AssetService:CreateEditableImage({ Size = Vector2.new(W, H) })
	end)
	if not ok or not image then
		return nil, tostring(image)
	end
	return image, nil
end

-- Shows this map. The back wall picture is a nice extra: without it the game still works.
function Map.new(data: MapData.MapData, imageLabel: ImageLabel, backLabel: ImageLabel): (Map?, string?)
	local image, err = newImage()
	if not image then
		return nil, err
	end
	imageLabel.ImageContent = Content.fromObject(image)
	local back = newImage()
	if back then
		backLabel.ImageContent = Content.fromObject(back)
	end

	local self = setmetatable({
		data = data,
		image = image,
		back = back,
		pixels = buffer.create(W * H * 4),
		backPixels = buffer.create(W * H * 4),
	}, Map)
	paint(self)
	if back then
		back:WritePixelsBuffer(Vector2.zero, Vector2.new(W, H), self.backPixels)
	end
	self:refresh()
	return self, nil
end

-- Sends the pixels to the picture on the screen.
function Map.refresh(self: Map)
	self.image:WritePixelsBuffer(Vector2.zero, Vector2.new(W, H), self.pixels)
end

-- Cuts a round hole (in the map data and in the picture) and burns the edge of it,
-- one big pixel at a time.
function Map.explode(self: Map, cx: number, cy: number, radius: number)
	self.data:explode(cx, cy, radius)
	local burn = radius + 4
	local lastX, lastY = W / B - 1, H / B - 1
	for by = math.max(0, math.floor((cy - burn) / B)), math.min(lastY, math.ceil((cy + burn) / B)) do
		for bx = math.max(0, math.floor((cx - burn) / B)), math.min(lastX, math.ceil((cx + burn) / B)) do
			local x, y = bx * B, by * B
			local i = index(x, y)
			if buffer.readu8(self.pixels, i + 3) > 0 then
				if self.data:material(x, y) == M.AIR then
					fillBlock(self.pixels, bx, by, nil)
				elseif (x + 1 - cx) ^ 2 + (y + 1 - cy) ^ 2 <= burn * burn then
					local c = {}
					for k = 0, 2 do
						c[k + 1] = math.floor(buffer.readu8(self.pixels, i + k) * 0.55)
					end
					fillBlock(self.pixels, bx, by, c)
				end
			end
		end
	end
	self:refresh()
end

-- The colors and sizes of the map picture, so the menu can draw the same grass and ground.
Map.PIXEL = B
Map.BAND = BAND
Map.PALETTE = {
	grassTop = GRASS_TOP,
	grass = GRASS,
	grassDark = GRASS_DARK,
	dirtBands = DIRT_BANDS,
	stone = STONE,
	stoneLight = STONE_LIGHT,
	stoneDark = STONE_DARK,
	blade = BLADE,
	bladeLight = BLADE_LIGHT,
}

function Map.destroy(self: Map)
	self.image:Destroy()
	if self.back then
		self.back:Destroy()
	end
end

return Map
