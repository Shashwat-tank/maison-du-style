# Obby Race

Everyone races the same obstacle course at the same time. The twist: **the course
is randomly generated every race**, so nobody can just memorise it.

## How a race works
1. Players wait in the lobby; after a 15 second intermission everyone is lined up
   behind a glass gate on the start pad.
2. 3, 2, 1, **GO** — the gate drops.
3. The course is 8 stages, getting harder toward the finish. Each stage ends in a
   green checkpoint pad. Falling off or touching anything glowing red sends you
   back to your last checkpoint instantly — no death screen.
4. When the first player finishes, everyone else has 30 seconds left.
5. Results: coins for 1st/2nd/3rd (50/30/20), 10 for finishing, 1 per checkpoint
   for anyone who didn't. A **Win** counts when you beat at least one other racer.

## Stage types
| Stage | What you do |
| --- | --- |
| Jumps | Hop across floating platforms (always the opening stage) |
| Lava Floor | Step across stones over glowing lava |
| Spinners | Jump over rotating red bars; later ones become crosses |
| Vanishing Tiles | Glass tiles fade in and out in a wave — keep moving with it |
| Tightrope | Zig-zag along narrow beams |
| Laser Hall | Laser walls switch on and off — time your run |
| Tower Climb | Climb two trusses — a breather before the next hard stage |

Gaps, platform sizes, spin speeds and beam widths all scale with how far into the
course a stage is.

## Play it in Studio
See [`../../tools/README.md`](../../tools/README.md). One player is enough — press
**Play** and a solo race starts after the intermission. To race others: **Test** →
**Clients and Servers** → Players: 2+.

With Rojo instead: run `rojo serve` in this folder and click **Connect** in the
Rojo plugin.

## How it's built
```
src/shared/   Config, Remotes                         -> ReplicatedStorage.Shared
src/server/   RaceManager (loop), CourseBuilder (stages),
              PlayerStats, NoPlayerCollisions, RoundState -> ServerScriptService.Server
src/client/   HUD, ObstacleAnimator, HazardWatcher    -> StarterPlayerScripts.Client
```
- **Server-authoritative progress.** The server checks each racer's position
  against their *next* checkpoint only, so checkpoints count in order and the
  finish can't be skipped to. Clients never report progress.
- **Smooth obstacles.** Spinners, tiles and lasers are animated on each client
  from the shared server clock, so they look smooth and line up for everyone.
- **Hazards are checked on the client**, which is safe: the only thing a client
  can do with that is send itself backwards.
- Players pass through each other, so nobody can block a beam or shove you off.

All tuning values live in `src/shared/Config.lua`; stage geometry is in
`src/server/CourseBuilder.lua`.

## Roadmap
- Save Wins and Coins between sessions (DataStore)
- Shop: trails, character effects, finish celebrations — cosmetic only
- Daily course, best-time leaderboard
- Spectate the leader after you finish
