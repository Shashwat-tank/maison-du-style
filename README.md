# Maison du Style — Murder Mystery (Roblox)

A round-based murder mystery for Roblox with an original twist: a **clue system**.

## How a round works
1. Players wait in the lobby until `MinPlayers` have joined, then an intermission counts down.
2. Everyone is teleported into the arena and secretly assigned a role:
   - **Murderer** — has a knife (click to stab). Wins by eliminating everyone else.
   - **Detective** — has a revolver (click to shoot where you aim). Shooting an innocent kills the detective too.
   - **Innocent** — no weapon. Wins by surviving until the timer ends or the murderer dies.
3. **Clues** (glowing orbs) are scattered around the map. Each clue an innocent examines reveals one more
   letter of the murderer's display name to *everyone* (`_ a _ _ o _`). The murderer can examine clues too,
   but that destroys them without revealing anything.
4. When the round ends, the murderer is revealed and winners earn coins.

## Run it in Studio
1. Install [Rojo](https://rojo.space) (the VS Code extension or the CLI) and the Rojo plugin for Studio.
2. In this folder run `rojo serve`.
3. Open a new **Baseplate** place in Studio, click **Connect** in the Rojo plugin.
4. To test multiplayer: **Test** tab → **Clients and Servers** → Players: 2 (or 3), then **Start**.
   In Studio the minimum is 2 players; in a live server it is 3 (see `src/shared/Config.lua`).

A placeholder lobby and arena are generated automatically. To use your own map, add a `Map` folder to
`Workspace` containing a `Spawns` folder and a `ClueSpots` folder of Parts (positions are what matter).

## Layout
```
default.project.json     Rojo project
src/shared/              Config, Remotes, Util   -> ReplicatedStorage.Shared
src/server/              Round loop, roles, combat, clues, map  -> ServerScriptService.Server
src/client/              HUD and gun aiming      -> StarterPlayerScripts.Client
```
All tuning values (timers, ranges, rewards) live in `src/shared/Config.lua`.

## Design rules
- The server is authoritative: roles, kills, cooldowns, and clue reveals are all decided server-side.
  The client only sends "I clicked" (and an aim point, which is validated).
- Each client is told only its own role.

## Roadmap (not built yet)
- Persistent coins and inventory (DataStore)
- Cosmetic shop: knife/revolver skins, emotes, death effects
- Multiple maps with a vote, spectator camera, detective gun drop on death
- Monetization: cosmetic-only. **No pay-to-win** (nothing that changes who wins a round).
  If adding paid random crates, check Roblox's current policy: odds must be disclosed, and
  paid random items are restricted for some users/regions.
