-- War in Grass: black ants vs red ants. Start of the player's side:
-- builds the screen, shows the menu, and passes messages between the server, the menu
-- (Menu.luau) and the match screen (Game.luau).
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StarterGui = game:GetService("StarterGui")

local Game = require(script.Game)
local Menu = require(script.Menu)
local Music = require(script.Music)

pcall(function()
	StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.All, false)
end)

local net = ReplicatedStorage:WaitForChild("WarInGrassNet") :: Folder
local LobbyRemote = net:WaitForChild("Lobby") :: RemoteEvent
local MatchRemote = net:WaitForChild("Match") :: RemoteEvent
local SnapshotRemote = net:WaitForChild("Snapshot") :: UnreliableRemoteEvent
net:WaitForChild("Input")

local gui = Instance.new("ScreenGui")
gui.Name = "WarInGrass"
gui.IgnoreGuiInset = true
gui.ResetOnSpawn = false
gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
gui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")

Menu.init(gui, net)
Music.init(gui)
Music.play("menu")
Game.init(gui, net, {
	onMenu = function()
		LobbyRemote:FireServer("toMenu")
		Menu.showMain()
		Music.play("menu")
	end,
	onAgain = function()
		Menu.showMain()
		Menu.playAgain()
	end,
	canPlayAgain = Menu.canPlayAgain,
})

LobbyRemote.OnClientEvent:Connect(function(kind: string, a, b, c)
	Menu.message(kind, a, b, c)
end)

MatchRemote.OnClientEvent:Connect(function(name: string, ...)
	if name == "start" then
		Menu.hide()
		Music.play("game")
		Game.start(...)
	else
		Game.event(name, ...)
	end
end)

SnapshotRemote.OnClientEvent:Connect(function(snapshot: buffer)
	Game.snapshot(snapshot)
end)
