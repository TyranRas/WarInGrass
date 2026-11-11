-- The game server: menu actions, Quick Match queues, lobbies (Make Lobby), and all the
-- matches that are being played on this server at the same time.
--
-- Network (folder ReplicatedStorage.WarInGrassNet):
--   Lobby    (RemoteEvent)  menu <-> server: quick, cancel, single, tutorial, browse, create,
--                           join, leave, team, addBot, removeBot, start, toMenu
--   Match    (RemoteEvent)  server -> players: "start" + match events (turn, explode, ...)
--   Input    (RemoteEvent)  player -> server: walk, aim, jump, charge, throw, tutorialEnd
--   Snapshot (UnreliableRemoteEvent) server -> players: where everything is, ~20 times a second
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("WarInGrassShared")
local Config = require(Shared.Config)
local MapData = require(Shared.MapData)
local Sim = require(script.Parent.Sim)
local Bot = require(script.Parent.Bot)

local net = Instance.new("Folder")
net.Name = "WarInGrassNet"
local function remote(className: string, name: string): any
	local r = Instance.new(className)
	r.Name = name
	r.Parent = net
	return r
end
local LobbyRemote: RemoteEvent = remote("RemoteEvent", "Lobby")
local MatchRemote: RemoteEvent = remote("RemoteEvent", "Match")
local InputRemote: RemoteEvent = remote("RemoteEvent", "Input")
local SnapshotRemote: UnreliableRemoteEvent = remote("UnreliableRemoteEvent", "Snapshot")
net.Parent = ReplicatedStorage

local SNAPSHOT_EVERY = 1 / 20

---------------------------------------------------------------- types and state

type Member = { player: Player?, team: number, botName: string? } -- player = nil means a bot

type Lobby = { id: number, hostId: number, members: { Member } }

type Match = {
	sim: Sim.Sim,
	players: { Player },
	snapshotTimer: number,
	over: boolean,
}

type Info = {
	where: string, -- "menu", "queue", "lobby", "match"
	queueMode: number?,
	lobby: Lobby?,
	match: Match?,
	lastKind: string?, -- so the next match gets a different map
}

local infos: { [Player]: Info } = {}
local queues: { [number]: { Player } } = {}
local lobbies: { [number]: Lobby } = {}
local matches: { Match } = {}
local nextLobbyId = 1
local rng = Random.new()

for _, mode in Config.QUICK_MODES do
	queues[mode] = {}
end

local function info(player: Player): Info
	local i = infos[player]
	if not i then
		i = { where = "menu" }
		infos[player] = i
	end
	return i
end

local function notice(player: Player, text: string)
	LobbyRemote:FireClient(player, "notice", text)
end

---------------------------------------------------------------- matches

local function finishMatch(match: Match)
	match.over = true
	-- players can start something new right away (their screen shows the result
	-- until they click "Menu")
	for _, player in match.players do
		local i = infos[player]
		if i and i.match == match then
			i.where, i.match = "menu", nil
		end
	end
	task.delay(3, function()
		local index = table.find(matches, match)
		if index then
			table.remove(matches, index)
		end
	end)
end

-- members: who plays on which team (players and bots)
local function startMatch(members: { Member }, tutorial: boolean)
	local humans = {}
	local simMembers = {}
	local previousKind = nil
	for _, member in members do
		local player = member.player
		if player then
			table.insert(humans, player)
			previousKind = previousKind or info(player).lastKind
			table.insert(simMembers, { team = member.team, ownerId = player.UserId, name = player.DisplayName, isBot = false })
		else
			table.insert(simMembers, { team = member.team, ownerId = 0, name = member.botName or "Bot", isBot = true })
		end
	end

	local seed = rng:NextInteger(1, 2 ^ 30)
	local kind = MapData.pickKind(rng, previousKind)
	local match: Match = { sim = nil :: any, players = humans, snapshotTimer = 0, over = false }

	local function emit(name: string, ...)
		for _, player in match.players do
			MatchRemote:FireClient(player, name, ...)
		end
		if name == "turn" then
			local ant = match.sim.ants[(...)]
			if ant and ant.isBot then
				task.spawn(Bot.takeTurn, match.sim, ant)
			end
		elseif name == "over" then
			finishMatch(match)
		end
	end

	match.sim = Sim.new(seed, kind, simMembers, tutorial, emit)
	table.insert(matches, match)
	local startInfo = match.sim:startInfo()
	for _, player in humans do
		-- stop getting news from an old, finished match
		for _, old in matches do
			local index = if old ~= match then table.find(old.players, player) else nil
			if index then
				table.remove(old.players, index)
			end
		end
		local i = info(player)
		i.where, i.match, i.queueMode, i.lobby, i.lastKind = "match", match, nil, nil, kind
		MatchRemote:FireClient(player, "start", startInfo)
	end
end

local function leaveMatch(player: Player)
	local i = info(player)
	local match = i.match
	if match then
		match.sim:removeOwner(player.UserId)
		local index = table.find(match.players, player)
		if index then
			table.remove(match.players, index)
		end
		i.match = nil
	end
	i.where = "menu"
end

RunService.Heartbeat:Connect(function(dt)
	for _, match in matches do
		if not match.over then
			match.sim:step(dt)
		end
		match.snapshotTimer += dt
		if match.snapshotTimer >= SNAPSHOT_EVERY then
			match.snapshotTimer = 0
			local snapshot = match.sim:snapshot()
			for _, player in match.players do
				SnapshotRemote:FireClient(player, snapshot)
			end
		end
	end
	-- a match with nobody left watching is removed
	for index = #matches, 1, -1 do
		if #matches[index].players == 0 then
			table.remove(matches, index)
		end
	end
end)

---------------------------------------------------------------- quick match

local function sendQueue(mode: number)
	local queue = queues[mode]
	for _, player in queue do
		LobbyRemote:FireClient(player, "queue", mode, #queue, mode * 2)
	end
end

local function leaveQueue(player: Player)
	local i = info(player)
	local mode = i.queueMode
	if mode then
		local index = table.find(queues[mode], player)
		if index then
			table.remove(queues[mode], index)
		end
		i.queueMode = nil
		sendQueue(mode)
	end
end

local function joinQueue(player: Player, mode: number)
	local queue = queues[mode]
	table.insert(queue, player)
	local i = info(player)
	i.where, i.queueMode = "queue", mode
	if #queue >= mode * 2 then
		-- enough players: mix them and split into two teams
		local picked = {}
		for _ = 1, mode * 2 do
			table.insert(picked, table.remove(queue, 1))
		end
		for k = #picked, 2, -1 do
			local j = rng:NextInteger(1, k)
			picked[k], picked[j] = picked[j], picked[k]
		end
		local members = {}
		for k, p in picked do
			table.insert(members, { player = p, team = if k % 2 == 1 then 1 else 2 })
		end
		startMatch(members, false)
	end
	sendQueue(mode)
end

---------------------------------------------------------------- lobbies (Make Lobby)

local function lobbyList()
	local list = {}
	for _, lobby in lobbies do
		local hostName = "?"
		for _, member in lobby.members do
			if member.player and member.player.UserId == lobby.hostId then
				hostName = member.player.DisplayName
			end
		end
		table.insert(list, { id = lobby.id, host = hostName, count = #lobby.members, max = Config.MAX_LOBBY_PLAYERS })
	end
	table.sort(list, function(a, b)
		return a.id < b.id
	end)
	return list
end

local function broadcastLobbyList()
	local list = lobbyList()
	for player, i in infos do
		if i.where == "menu" then
			LobbyRemote:FireClient(player, "lobbyList", list)
		end
	end
end

local function sendLobby(lobby: Lobby)
	for _, member in lobby.members do
		local player = member.player
		if player then
			local members = {}
			for _, m in lobby.members do
				table.insert(members, {
					name = if m.player then m.player.DisplayName else (m.botName or "Bot"),
					team = m.team,
					isBot = m.player == nil,
					isMe = m.player == player,
					isHost = m.player ~= nil and m.player.UserId == lobby.hostId,
				})
			end
			LobbyRemote:FireClient(player, "lobby", {
				id = lobby.id,
				isHost = player.UserId == lobby.hostId,
				members = members,
				max = Config.MAX_LOBBY_PLAYERS,
			})
		end
	end
end

local function teamCounts(lobby: Lobby): (number, number)
	local a, b = 0, 0
	for _, member in lobby.members do
		if member.team == 1 then
			a += 1
		else
			b += 1
		end
	end
	return a, b
end

local function smallerTeam(lobby: Lobby): number
	local a, b = teamCounts(lobby)
	return if a <= b then 1 else 2
end

local function leaveLobby(player: Player)
	local i = info(player)
	local lobby = i.lobby
	if not lobby then
		return
	end
	i.lobby = nil
	for index, member in lobby.members do
		if member.player == player then
			table.remove(lobby.members, index)
			break
		end
	end
	-- the host left: the next player becomes the host; no players left: the lobby is gone
	local nextHost = nil
	for _, member in lobby.members do
		if member.player then
			nextHost = nextHost or member.player
		end
	end
	if not nextHost then
		lobbies[lobby.id] = nil
	else
		if lobby.hostId == player.UserId then
			lobby.hostId = nextHost.UserId
		end
		sendLobby(lobby)
	end
	broadcastLobbyList()
end

local function startLobby(player: Player, lobby: Lobby)
	if #lobby.members < 2 then
		notice(player, "Potrzeba co najmniej 2 graczy (możesz dodać bota)")
		return
	end
	-- nobody on one team: move someone over
	local a, b = teamCounts(lobby)
	if a == 0 or b == 0 then
		local from = if a == 0 then 2 else 1
		for _, member in lobby.members do
			if member.team == from then
				member.team = 3 - from
				break
			end
		end
	end
	lobbies[lobby.id] = nil
	startMatch(lobby.members, false)
	broadcastLobbyList()
end

---------------------------------------------------------------- menu actions

-- Leave whatever the player is doing now (queue, lobby, match).
local function leaveEverything(player: Player)
	leaveQueue(player)
	leaveLobby(player)
	leaveMatch(player)
end

LobbyRemote.OnServerEvent:Connect(function(player: Player, action: any, arg: any)
	local i = info(player)
	if type(action) ~= "string" then
		return
	end

	if action == "quick" then
		if typeof(arg) == "number" and table.find(Config.QUICK_MODES, arg) then
			leaveEverything(player)
			joinQueue(player, arg)
		end
	elseif action == "cancel" then
		leaveQueue(player)
		i.where = "menu"
	elseif action == "single" or action == "tutorial" then
		-- you alone vs N enemy bots (the tutorial is always vs 1 bot)
		local bots = 1
		if action == "single" and typeof(arg) == "number" and table.find(Config.SINGLE_BOTS, arg) then
			bots = arg
		end
		leaveEverything(player)
		local members: { Member } = { { player = player, team = 1 } }
		for b = 1, bots do
			table.insert(members, { team = 2, botName = if bots == 1 then "Bot" else "Bot " .. b })
		end
		startMatch(members, action == "tutorial")
	elseif action == "browse" then
		LobbyRemote:FireClient(player, "lobbyList", lobbyList())
	elseif action == "create" then
		leaveEverything(player)
		local lobby: Lobby = { id = nextLobbyId, hostId = player.UserId, members = { { player = player, team = 1 } } }
		nextLobbyId += 1
		lobbies[lobby.id] = lobby
		i.where, i.lobby = "lobby", lobby
		sendLobby(lobby)
		broadcastLobbyList()
	elseif action == "join" then
		local lobby = lobbies[arg]
		if not lobby then
			notice(player, "Tego lobby już nie ma")
			LobbyRemote:FireClient(player, "lobbyList", lobbyList())
		elseif #lobby.members >= Config.MAX_LOBBY_PLAYERS then
			notice(player, "Lobby jest pełne")
		elseif i.lobby ~= lobby then
			leaveEverything(player)
			table.insert(lobby.members, { player = player, team = smallerTeam(lobby) })
			i.where, i.lobby = "lobby", lobby
			sendLobby(lobby)
			broadcastLobbyList()
		end
	elseif action == "leave" then
		leaveLobby(player)
		i.where = "menu"
	elseif action == "team" then
		local lobby = i.lobby
		if lobby then
			for _, member in lobby.members do
				if member.player == player then
					member.team = 3 - member.team
				end
			end
			sendLobby(lobby)
		end
	elseif action == "addBot" or action == "removeBot" then
		local lobby = i.lobby
		if lobby and lobby.hostId == player.UserId then
			if action == "addBot" and #lobby.members < Config.MAX_LOBBY_PLAYERS then
				local bots = 0
				for _, member in lobby.members do
					if not member.player then
						bots += 1
					end
				end
				table.insert(lobby.members, { team = smallerTeam(lobby), botName = "Bot " .. (bots + 1) })
			elseif action == "removeBot" then
				for index = #lobby.members, 1, -1 do
					if not lobby.members[index].player then
						table.remove(lobby.members, index)
						break
					end
				end
			end
			sendLobby(lobby)
			broadcastLobbyList()
		end
	elseif action == "start" then
		local lobby = i.lobby
		if lobby and lobby.hostId == player.UserId then
			startLobby(player, lobby)
		end
	elseif action == "toMenu" then
		leaveEverything(player)
		LobbyRemote:FireClient(player, "lobbyList", lobbyList())
	end
end)

InputRemote.OnServerEvent:Connect(function(player: Player, action: any, a: any, b: any)
	local match = info(player).match
	if match and not match.over and type(action) == "string" then
		match.sim:input(player.UserId, action, a, b)
	end
end)

Players.PlayerAdded:Connect(function(player)
	info(player)
end)
for _, player in Players:GetPlayers() do
	info(player)
end

Players.PlayerRemoving:Connect(function(player)
	leaveEverything(player)
	for _, match in matches do
		local index = table.find(match.players, player)
		if index then
			table.remove(match.players, index)
		end
	end
	infos[player] = nil
end)
