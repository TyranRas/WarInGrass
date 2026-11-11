-- Background music: one song in the menu, one in the match (Config.MUSIC_*), in a loop.
-- When the song changes, the old one fades out and the new one fades in.
-- The ♪ button (top right) and the M key turn the music off and on.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SoundService = game:GetService("SoundService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("WarInGrassShared")
local Config = require(Shared.Config)
local Retro = require(script.Parent.Retro)

local Music = {}

local FADE = 1 -- seconds
local current: Sound? = nil
local currentId = ""
local muted = false
local button: TextButton? = nil

local function targetVolume(): number
	return if muted then 0 else Config.MUSIC_VOLUME
end

local function updateButton()
	if button then
		local caption = button:FindFirstChild("Caption") :: TextLabel?
		if caption then
			caption.Text = if muted then "♪ OFF" else "♪ ON"
			caption.TextTransparency = if muted then 0.5 else 0
		end
	end
end

local function toggle()
	muted = not muted
	if current then
		TweenService:Create(current, TweenInfo.new(0.3), { Volume = targetVolume() }):Play()
	end
	updateButton()
end

-- which: "menu" or "game"
function Music.play(which: string)
	local id = if which == "game" then Config.MUSIC_GAME else Config.MUSIC_MENU
	if id == currentId then
		return -- already playing this song: just keep going
	end
	local old = current
	if old then
		local fade = TweenService:Create(old, TweenInfo.new(FADE), { Volume = 0 })
		fade.Completed:Connect(function()
			old:Destroy()
		end)
		fade:Play()
	end
	currentId = id
	current = nil
	if id == "" then
		return
	end
	local s = Instance.new("Sound")
	s.Name = "Music"
	s.SoundId = id
	s.Looped = true
	s.Volume = 0
	s.Parent = SoundService
	s:Play()
	TweenService:Create(s, TweenInfo.new(FADE), { Volume = targetVolume() }):Play()
	current = s
end

function Music.init(gui: ScreenGui)
	button = Retro.button(gui, "♪ ON", UDim2.fromScale(0.955, 0.125), UDim2.fromScale(0.07, 0.05), "normal", toggle)
	;(button :: TextButton).ZIndex = 80 -- above the menu and the match
	UserInputService.InputBegan:Connect(function(input: InputObject, typing: boolean)
		if not typing and input.KeyCode == Enum.KeyCode.M then
			toggle()
		end
	end)
	updateButton()
end

return Music
