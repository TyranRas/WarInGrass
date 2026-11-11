-- Plays the game sounds listed in Config.SOUNDS (only on this player's computer).
-- Sound.play("explosion") - every sound gets a tiny random change of pitch,
-- so the same sound many times in a row does not get boring.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SoundService = game:GetService("SoundService")

local Shared = ReplicatedStorage:WaitForChild("WarInGrassShared")
local Config = require(Shared.Config)

local Sound = {}

local folder = Instance.new("Folder")
folder.Name = "WarInGrassSounds"
folder.Parent = SoundService

-- one ready Sound for each name (copied when it plays, so sounds can overlap)
local templates: { [string]: Sound } = {}
for name, info in Config.SOUNDS do
	if info.id ~= "" then
		local s = Instance.new("Sound")
		s.Name = name
		s.SoundId = info.id
		s.Volume = info.volume * Config.SOUND_VOLUME
		s.PlaybackSpeed = info.speed
		s.Parent = folder
		templates[name] = s
	end
end

local rng = Random.new()

function Sound.play(name: string, speedChange: number?)
	local template = templates[name]
	if not template then
		return -- unknown name or no sound set ("")
	end
	local s = template:Clone()
	s.PlaybackSpeed = template.PlaybackSpeed * (speedChange or 1) * rng:NextNumber(0.95, 1.05)
	s.Parent = folder
	s.Ended:Connect(function()
		s:Destroy()
	end)
	s:Play()
	task.delay(10, function()
		if s.Parent then
			s:Destroy() -- just in case Ended never comes
		end
	end)
end

return Sound
