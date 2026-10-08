# Installing into Studio without Rojo

Both bundles here are generated from `src/` by `build_installer.py`, so they always
match the real game code. **Regenerate them after changing anything under `src/`:**

```
python3 tools/build_installer.py
```

Pick one of the two methods below. They produce exactly the same result.

---

## Method A — one paste (fastest)

1. Open Roblox Studio and create a new **Baseplate** place.
2. **View** tab → **Command Bar**. Also open **View** → **Output**, so you can see errors.
3. Open [`StudioInstaller.luau`](StudioInstaller.luau), select all, copy.
4. Paste into the Command Bar and press **Enter**.
5. It prints the 14 instances it created.

If the paste collapses into a single line, the Command Bar has stripped the newlines
and this method will not work — use Method B instead. (Studio's Command Bar was
historically single-line; multi-line support is a newer beta.)

Re-running it is safe: it replaces its own previous install, and never touches
`Workspace`, so a map you built yourself is left alone.

## Method B — insert three model files (always works)

Download the three files in [`rbxmx/`](rbxmx), then in Studio's **Explorer**
right-click each service below and choose **Insert from File...**:

| Right-click this service | Insert this file |
| --- | --- |
| `ReplicatedStorage` | `Shared.rbxmx` |
| `ServerScriptService` | `Server.rbxmx` |
| `StarterPlayer` → `StarterPlayerScripts` | `Client.rbxmx` |

Inserting into the wrong service is the only thing that can go wrong here — the
scripts find each other by path, so the names and locations must match the table.

---

## Then play it

**Test** tab → **Clients and Servers** → Players: **2** → **Start**.

Studio needs only 2 players; a live server needs 3 (a Detective only appears with
3+). See `MinPlayers` in `src/shared/Config.lua`.

If something breaks, copy the red text from the **Output** window — that is what is
needed to diagnose it.

## Resulting hierarchy

```
ReplicatedStorage/Shared          (Folder)
  Config, Remotes, Util           (ModuleScript)
ServerScriptService/Server        (Script)
  ClueService, CombatService, MapService,
  RoleService, RoundManager, RoundState   (ModuleScript)
StarterPlayer/StarterPlayerScripts/Client (LocalScript)
  GunController, HUD              (ModuleScript)
```

This mirrors `default.project.json`, so you can switch to Rojo later without
changing any code. Delete these three containers first if you do, or you will
end up with two copies.
