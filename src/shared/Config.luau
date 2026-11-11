-- All the numbers of the game in one place. Change them and see what happens!
-- (This file is shared: the server and every player use the same numbers.)
local Config = {}

-- Map size in pixels
-- (the whole map is always on the screen, so a bigger map makes everything look smaller;
-- Roblox allows at most 1024 for each side)
Config.MAP_WIDTH = 1024
Config.MAP_HEIGHT = 576
Config.WATER_HEIGHT = 18 -- how high the water is at the bottom

-- Ants
Config.ANT_HP = 100
Config.WALK_SPEED = 30 -- pixels per second
Config.CLIMB_STEP = 4 -- how many pixels an ant can step up
Config.JUMP_SPEED = 130
Config.JUMP_FORWARD = 60
-- On the Wyspy map the jump is bigger, so ants can jump from island to island
Config.ISLAND_JUMP_SPEED = 170 -- about 48 pixels up
Config.ISLAND_JUMP_FORWARD = 110 -- about 125 pixels forward
Config.FALL_DAMAGE_SPEED = 230 -- falling faster than this hurts
Config.GRAVITY = 300
Config.STEP_ANIM = 0.35 -- how fast the legs move for each pixel walked (bigger = faster steps)

-- Throwing (aiming is done with the mouse)
Config.CHARGE_TIME = 1.2 -- seconds to full power
Config.MIN_THROW_SPEED = 60
Config.MAX_THROW_SPEED = 480 -- full power reaches about 770 pixels (the map is 1024 wide)
Config.MAX_WIND = 50

-- Acorn explosion
Config.EXPLOSION_RADIUS = 22
Config.EXPLOSION_DAMAGE = 45 -- damage in the middle of the blast
Config.EXPLOSION_PUSH = 160

-- Weapons (keys 1, 2, 3 in a match)
-- 1 Żołądź: the normal acorn (uses EXPLOSION_* above)
-- 2 Kasztan: explodes, then splits into small seeds that fly out and explode too
Config.CHESTNUT_RADIUS = 18
Config.CHESTNUT_DAMAGE = 30
Config.SEED_COUNT = 5 -- how many seeds come out
Config.SEED_RADIUS = 9
Config.SEED_DAMAGE = 14
Config.SEED_SPEED_UP = 200 -- how high the seeds jump out
Config.SEED_SPEED_SIDE = 110 -- how far sideways
-- 3 Deszcz kasztanów: click a spot on the map, chestnuts fall from the sky there (the wind blows them!)
Config.RAIN_PER_ANT = 1 -- how many times each ant can use it in one match
Config.RAIN_COUNT = 5 -- chestnuts in one rain
Config.RAIN_SPREAD = 40 -- how far apart they fall (pixels left/right of the click)
Config.RAIN_DELAY = 0.25 -- seconds between chestnuts
Config.RAIN_RADIUS = 14
Config.RAIN_DAMAGE = 22
Config.WEAPON_NAMES = { "Żołądź", "Kasztan", "Deszcz" }

-- Turns
Config.TURN_TIME = 30

-- Bot (Single Player)
Config.BOT_THINK_TIME = 1.2 -- seconds the bot "thinks" before aiming
Config.BOT_AIM_ERROR = 4 -- degrees the bot can miss by (bigger = easier bot)
Config.BOT_POWER_ERROR = 0.04 -- how much the bot can miss the power by (0.04 = 4 %)

Config.SINGLE_BOTS = { 1, 2, 3, 5 } -- Single Player: how many enemy bots you can pick

-- Multiplayer
Config.QUICK_MODES = { 1, 2, 3, 5 } -- Quick Match: 1v1, 2v2, 3v3, 5v5
Config.MAX_LOBBY_PLAYERS = 10 -- players (and bots) in one lobby made with Make Lobby

-- Sounds
-- id: the sound. "rbxasset://sounds/..." are built into Roblox. To use a sound from
--     Studio's Toolbox -> Audio, copy its number and write "rbxassetid://NUMBER".
--     "" = no sound.
-- volume: 0 to 1.   speed: 1 = normal, 2 = higher and faster (more "8-bit"), 0.5 = lower.
Config.SOUND_VOLUME = 0.6 -- all sounds together (0 = silent)
Config.SOUNDS = {
	click = { id = "rbxasset://sounds/volume_slider.ogg", volume = 0.6, speed = 1.6 }, -- button
	jump = { id = "rbxasset://sounds/action_jump.mp3", volume = 0.5, speed = 1.5 },
	land = { id = "rbxasset://sounds/action_jump_land.mp3", volume = 0.5, speed = 1.4 },
	throw = { id = "rbxasset://sounds/action_jump.mp3", volume = 0.6, speed = 2.2 },
	explosion = { id = "rbxasset://sounds/impact_explosion_03.mp3", volume = 0.8, speed = 1.1 },
	splash = { id = "rbxasset://sounds/impact_water.mp3", volume = 0.7, speed = 1.2 },
	hurt = { id = "rbxasset://sounds/ouch.ogg", volume = 0.5, speed = 1.8 }, -- a squeaky ant
	ko = { id = "rbxasset://sounds/oof.ogg", volume = 0.6, speed = 1.6 },
	myTurn = { id = "rbxasset://sounds/volume_slider.ogg", volume = 0.8, speed = 1.0 },
	tick = { id = "rbxasset://sounds/volume_slider.ogg", volume = 0.5, speed = 2.4 }, -- last 5 seconds
	praise = { id = "rbxasset://sounds/volume_slider.ogg", volume = 0.8, speed = 2.0 }, -- tutorial "BRAWO!"
	win = { id = "", volume = 0.8, speed = 1 }, -- find a nice one in Toolbox -> Audio!
	lose = { id = "", volume = 0.8, speed = 1 },
}

-- Music (plays in a loop; M or the ♪ button turns it off and on)
-- To change a song: Toolbox -> Audio -> Music, right click -> Copy Asset ID.
Config.MUSIC_VOLUME = 0.35
Config.MUSIC_MENU = "rbxassetid://74672469358926" -- World Map Overworld
Config.MUSIC_GAME = "rbxassetid://74672469358926" -- the same for now (a faster one would be cool!)

-- Teams: name and color
Config.TEAMS = {
	{ name = "Czarne mrówki", color = Color3.fromRGB(30, 30, 35), light = Color3.fromRGB(170, 170, 190) },
	{ name = "Czerwone mrówki", color = Color3.fromRGB(200, 40, 30), light = Color3.fromRGB(255, 120, 100) },
}

return Config
