# Installing a game into Studio without Rojo

Every game has an `install/` folder (for example
[`games/obby-race/install`](../games/obby-race/install)) generated from its `src/`
by `build_installer.py`, so the install files always match the real game code.
**Regenerate them after changing any code:**

```
python3 tools/build_installer.py              # every game
python3 tools/build_installer.py obby-race    # just one
```

Pick one of the two methods below. They produce exactly the same result.

---

## Method A — one paste (fastest)

1. Open Roblox Studio and create a new **Baseplate** place.
2. **View** tab → **Command Bar**. Also open **View** → **Output**, so you can see errors.
3. Open the game's `install/StudioInstaller.luau`, select all, copy.
4. Paste into the Command Bar and press **Enter**. It prints what it created.

If the paste collapses into a single line, the Command Bar has stripped the newlines
and this method will not work — use Method B instead.

Re-running it is safe: it replaces its own previous install, and never touches
`Workspace`.

## Method B — insert three model files (always works)

Download the three `.rbxmx` files from the game's `install/` folder, then in
Studio's **Explorer** right-click each service below and choose **Insert from File...**:

| Right-click this service | Insert this file |
| --- | --- |
| `ReplicatedStorage` | `Shared.rbxmx` |
| `ServerScriptService` | `Server.rbxmx` |
| `StarterPlayer` → `StarterPlayerScripts` | `Client.rbxmx` |

Inserting into the wrong service is the only thing that can go wrong here — the
scripts find each other by path, so the names and locations must match the table.

**Switching games in the same place?** Delete the old `Shared`, `Server` and
`Client` first. Better: use a fresh Baseplate place per game.

---

## Then play it

- **Obby Race:** just press **Play** — one player is enough. To race others:
  **Test** → **Clients and Servers** → Players: 2+ → **Start**.
- **Murder Mystery:** **Test** → **Clients and Servers** → Players: **2** → **Start**.

If something breaks, copy the red text from the **Output** window — that is what is
needed to diagnose it.

## Resulting hierarchy

```
ReplicatedStorage/Shared                  (Folder of ModuleScripts)
ServerScriptService/Server                (Script, with ModuleScript children)
StarterPlayer/StarterPlayerScripts/Client (LocalScript, with ModuleScript children)
```

This mirrors each game's `default.project.json`, so you can switch to Rojo later
without changing any code. Delete these three containers first if you do, or you
will end up with two copies.
