# War in Grass — notes for Claude

Tymek's (12) own Roblox game, separate from LIF. Talk to him in Polish, simply (skill `tymek-bezpiecznie`
applies here too). Code and comments in English; in-game text is Polish for now.

## The game
- Turn-based artillery game in the style of Worms, but our own: **black ants vs red ants** in the grass,
  they throw **acorns** (żołędzie). Not a copy of Worms (no worms, names or look from it).
- **True 2D** inside a ScreenGui. Map 1024x576 pixels, the whole map is always on screen (Tymek chose
  this over a scrolling camera). 1024 is the EditableImage limit per side.
- 4 map kinds, random each match, never the same twice in a row: Łąka (meadow), Wyspy (islands, bigger
  jump there), Mrowisko (anthill, tunnels), Ogród (garden, mushrooms + root arches).
  Grass blades are decoration (not solid). Ants spawn only on flat dry spots.
- Menu: Quick Match (1v1/2v2/3v3/5v5 queue), Make Lobby (list, create, join, switch team, host adds bots,
  Start), Single Player (vs bot), Tutorial (7 steps vs bot, no damage, then a normal game).
- Multiplayer works **inside one server** only. Matchmaking across servers (MemoryStore + teleports)
  and the server player limit (5v5 = 10 players) need dad: game settings / publishing.
- Controls: A/D walk, W jump, mouse aims, hold Space = charge, release = throw, Enter skips tutorial,
  1/2/3 = weapon.
- Weapons (numbers in Config): 1 Żołądź (acorn), 2 Kasztan (explodes, then SEED_COUNT seeds jump out and
  explode), 3 Deszcz kasztanów (click a spot: RAIN_COUNT chestnuts fall from the sky one by one, wind blows
  them; RAIN_PER_ANT uses per ant per match, free in the tutorial). The bot uses all three.

## How it works (since 11.11.2026)
- The **server simulates** every match (`Sim`); players only send input on their own turn.
- Map: server sends only seed + kind; everyone builds the same map with `MapData.new(seed, kind)`.
  Explosions are sent as whole-number (x, y, r) so everyone cuts the same hole.
- Snapshots (buffer, ~20/s, UnreliableRemoteEvent) carry ant positions/HP/flags, all flying projectiles
  (`sim.projectiles`), turn, wind, power, current weapon + rains left. Layout is documented above
  `Sim.snapshot`; `Game.snapshot` must read it the same way.
  Events (RemoteEvent `Match`): start, turn, explode, damage, kill, splash, land, throw, practiceDone,
  tutorialEnd, over. Client slides drawn ants toward snapshot positions.

## Files
- `src/shared/Config.luau`: every number of the game (Tymek can tweak these himself). → ReplicatedStorage.WarInGrassShared
- `src/shared/MapData.luau`: map materials grid, 4 generators, `isSolid`, `surfaceY`, `explode`.
- `src/server/Main.server.luau`: remotes (`ReplicatedStorage.WarInGrassNet`: Lobby, Match, Input, Snapshot),
  menu actions, quick-match queues, lobbies, running matches.
- `src/server/Sim.luau`: one match: ants, physics, acorn, turns, tutorial mode, snapshot packing.
- `src/server/Bot.luau`: bot turn: tries ~800 throws with `sim:simulateShot`, adds error (Config.BOT_*).
- `src/server/Setup.server.luau`: `CharacterAutoLoads = false`.
- `src/client/init.client.luau`: builds the ScreenGui, wires remotes to Menu and Game.
- `src/client/Menu.luau`, `Game.luau` (match screen, HUD, wind meter + streaks, tutorial, results),
  `AntView.luau` (pixel ant 12x8 cells of 2 map px), `Map.luau` (colors the map into EditableImages in
  2x2 "big pixels", retro palette, darker bands with depth).
- `src/client/Sound.luau`: `Sound.play(name)` plays sounds from `Config.SOUNDS` (built-in rbxasset sounds for
  now; Tymek can swap in Toolbox audio ids). Hooked to button clicks and match events.
- `src/client/Music.luau`: looping background music (`Config.MUSIC_MENU` / `MUSIC_GAME`, Toolbox ids Tymek
  picked; now both "World Map Overworld"), fades between songs, ♪ ON/OFF button top right + M key.
- `src/client/Retro.luau`: the retro (old console) look of menu AND match: Press Start 2P pixel font with
  own text fitting (`Retro.fit`, TextScaled does not work well with it), square buttons that press down,
  dialog panels, pixel clouds, `vignette` (dark corners), `tvLines`, menu pixel scene. `Ui.luau` is no longer used.
- `default.project.json`: Rojo, port **34900** (LIF uses 34872/34873, keep them apart).
- `WarInGrass.rbxl`: Tymek's place file from Studio. Never overwrite it with a build.

## Running and testing
- `rojo serve default.project.json` (Rojo 7.7.1 via `aftman.toml`), then in Studio: Rojo plugin → port 34900 → Connect → Play.
- Multiplayer test in Studio: Test tab → Clients and Servers → 2+ players.
- Offline checks: `luau-compile --null` and `luau-analyze` from `C:\Projekty\LIF\repo\LIF-repo\.tools\luau\`
  (analyze shows Roblox-global noise), `rojo build default.project.json -o <scratchpad>/wig.rbxlx`.
- Offline bot-vs-bot match test: load Config/MapData/Sim/Bot sources into luau.exe with mocked
  `game`, `Random`, `task`, `os.clock` (see the 11.11 session; scripts were in the scratchpad).

## Watch out
- `EditableImage` may need "Allow Mesh / Image APIs" and an ID-verified 13+ account for a **published** game.
  Publishing only with dad (Maciej). Never "Publish to Roblox" on your own.
- Saving player data (e.g. "tutorial already seen") = DataStore → only with dad.
- No git repo yet. Making one / pushing to GitHub: ask first; GitHub together with dad.

## Next steps
1. Test the multiplayer version in Studio (Play + Clients and Servers), fix errors from Output.
2. Then Tymek's ideas, one small thing at a time (more weapons, sounds, bot levels...).
