# Maison du Style — Roblox games

Each game lives in its own folder under `games/`, with its own source, Rojo
project, and ready-made Studio install files.

| Game | Status | Folder |
| --- | --- | --- |
| **Obby Race** — race through a new random obstacle course every round | Playable | [`games/obby-race`](games/obby-race) |
| Murder Mystery — roles, knife and revolver, clue system | Shelved | [`games/murder-mystery`](games/murder-mystery) |

Planned next: Sky Wars (platform PvP) and Zombie Horde (team survival).

## Installing a game into Studio

See [`tools/README.md`](tools/README.md). Short version: open
`games/<game>/install/`, and either paste `StudioInstaller.luau` into Studio's
Command Bar, or insert the three `.rbxmx` files.

After changing any game's code, regenerate its install files:

```
python3 tools/build_installer.py              # every game
python3 tools/build_installer.py obby-race    # just one
```
