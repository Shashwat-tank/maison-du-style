#!/usr/bin/env python3
"""Generate Studio install bundles for each game under games/.

Two outputs per game, both built from the same source so they cannot drift apart:

  games/<game>/install/StudioInstaller.luau   one script for the Studio Command Bar
  games/<game>/install/*.rbxmx                model files for Explorer -> Insert from File

Regenerate after changing anything under a game's src/:
    python3 tools/build_installer.py              # every game
    python3 tools/build_installer.py obby-race    # just one
"""

import pathlib
import sys
from xml.sax.saxutils import escape

ROOT = pathlib.Path(__file__).resolve().parent.parent
GAMES_DIR = ROOT / "games"

# Per-game text for the installer header and its closing message.
GAMES = {
    "murder-mystery": {
        "title": "Murder Mystery",
        "play": "Test tab -> Clients and Servers -> Players: 2 -> Start",
    },
    "obby-race": {
        "title": "Obby Race",
        "play": "Test tab -> Play (solo works; Clients and Servers -> Players: 2+ to race others)",
    },
}

# Mirrors default.project.json: each source directory maps onto the Studio
# instance Rojo would create for it. A directory with an `init` entry point
# becomes that script, with its sibling modules as children.
GROUPS = [
    {"dir": "shared", "root": "ReplicatedStorage", "name": "Shared",
     "class": "Folder", "init": None},
    {"dir": "server", "root": "ServerScriptService", "name": "Server",
     "class": "Script", "init": "init.server.lua"},
    {"dir": "client", "root": "StarterPlayerScripts", "name": "Client",
     "class": "LocalScript", "init": "init.client.lua"},
]


def collect(src):
    groups = []
    for group in GROUPS:
        directory = src / group["dir"]
        if not directory.is_dir():
            sys.exit("missing source directory: %s" % directory)

        source = None
        if group["init"]:
            init_path = directory / group["init"]
            if not init_path.is_file():
                sys.exit("missing entry point: %s" % init_path)
            source = init_path.read_text()

        modules = sorted(p for p in directory.glob("*.lua")
                         if p.name != group["init"])
        if not modules:
            sys.exit("no modules found in %s" % directory)

        groups.append({
            "root": group["root"], "name": group["name"],
            "class": group["class"], "source": source,
            "modules": [{"name": p.stem, "source": p.read_text()}
                        for p in modules],
        })
    return groups


# ---------------------------------------------------------------- Command Bar

def long_string(text):
    """Wrap text in a Luau long string, picking a delimiter that cannot collide."""
    level = 2
    while "]%s]" % ("=" * level) in text or "[%s[" % ("=" * level) in text:
        level += 1
    eq = "=" * level
    # Luau drops a newline immediately after the opening delimiter, so add one
    # deliberately; the remaining text is then preserved byte for byte.
    return "[%s[\n%s]%s]" % (eq, text, eq)


LUAU_HEADER = '''--!nocheck
-- Maison du Style - %(title)s: one-paste Studio installer.
--
-- GENERATED FILE - do not edit by hand.
-- Regenerate with: python3 tools/build_installer.py
--
-- HOW TO USE
--   1. Open Roblox Studio and create a new Baseplate place.
--   2. View tab -> Command Bar. Also open View -> Output to see errors later.
--   3. Paste this whole file into the Command Bar and press Enter.
--   4. %(play)s.
--
-- If the paste collapses into one line, the Command Bar has stripped the
-- newlines and this will not work. Use the .rbxmx files next to this one instead.
--
-- Re-running this is safe: it replaces its own previous install. It never
-- touches Workspace, so a map you built yourself is left alone.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local StarterPlayer = game:GetService("StarterPlayer")

local ROOTS = {
\tReplicatedStorage = ReplicatedStorage,
\tServerScriptService = ServerScriptService,
\tStarterPlayerScripts = StarterPlayer:FindFirstChildOfClass("StarterPlayerScripts")
\t\tor StarterPlayer:WaitForChild("StarterPlayerScripts"),
}
'''

LUAU_FOOTER = '''
-- Replace any previous install so re-running this script is idempotent.
for _, entry in ipairs(ENTRIES) do
\tif not entry.parent then
\t\tlocal existing = ROOTS[entry.root]:FindFirstChild(entry.name)
\t\tif existing then
\t\t\texisting:Destroy()
\t\tend
\tend
end

local containers = {}
local created = {}

for _, entry in ipairs(ENTRIES) do
\tlocal parent = ROOTS[entry.root]
\tif entry.parent then
\t\tparent = containers[entry.root .. "/" .. entry.parent]
\t\tif not parent then
\t\t\terror("installer: container missing for " .. entry.name)
\t\tend
\tend

\tlocal instance = Instance.new(entry.class)
\tinstance.Name = entry.name
\tif entry.source then
\t\t-- Writable from the Command Bar, which runs at plugin permission level.
\t\tinstance.Source = entry.source
\tend
\tinstance.Parent = parent

\tif not entry.parent then
\t\tcontainers[entry.root .. "/" .. entry.name] = instance
\tend

\tlocal prefix = entry.parent and (entry.parent .. ".") or ""
\ttable.insert(created, entry.root .. "." .. prefix .. entry.name)
end

print(string.format("%(title)s installed - %%d instances created:", #created))
for _, path in ipairs(created) do
\tprint("   " .. path)
end
print("Next: %(play)s")
'''


def render_luau(groups, game):
    out = [LUAU_HEADER % game, "\nlocal ENTRIES = {"]

    def emit(root, parent, name, cls, source):
        out.append("\t{")
        out.append('\t\troot = "%s",' % root)
        if parent:
            out.append('\t\tparent = "%s",' % parent)
        out.append('\t\tname = "%s",' % name)
        out.append('\t\tclass = "%s",' % cls)
        if source is not None:
            out.append("\t\tsource = %s," % long_string(source))
        out.append("\t},")

    for group in groups:
        emit(group["root"], None, group["name"], group["class"], group["source"])
        for module in group["modules"]:
            emit(group["root"], group["name"], module["name"],
                 "ModuleScript", module["source"])

    out.append("}")
    out.append(LUAU_FOOTER % game)
    return "\n".join(out)


# --------------------------------------------------------------------- rbxmx

RBXMX_OPEN = (
    '<roblox xmlns:xmime="http://www.w3.org/2005/05/xmlmime"'
    ' xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"'
    ' xsi:noNamespaceSchemaLocation="http://www.roblox.com/roblox.xsd"'
    ' version="4">\n'
)


def render_rbxmx(group):
    counter = [0]

    def item(cls, name, source, indent, children=()):
        counter[0] += 1
        pad = "  " * indent
        lines = ['%s<Item class="%s" referent="RBX%d">' % (pad, cls, counter[0]),
                 "%s  <Properties>" % pad,
                 '%s    <string name="Name">%s</string>' % (pad, escape(name))]
        if source is not None:
            if "]]>" in source:
                sys.exit("CDATA collision in %s" % name)
            lines.append('%s    <ProtectedString name="Source"><![CDATA[%s]]>'
                         "</ProtectedString>" % (pad, source))
        lines.append("%s  </Properties>" % pad)
        lines.extend(children)
        lines.append("%s</Item>" % pad)
        return lines

    kids = []
    for module in group["modules"]:
        kids.extend(item("ModuleScript", module["name"], module["source"], 2))

    body = item(group["class"], group["name"], group["source"], 1, kids)
    return RBXMX_OPEN + "\n".join(body) + "\n</roblox>\n"


def build(name):
    game = GAMES[name]
    base = GAMES_DIR / name
    out = base / "install"
    groups = collect(base / "src")
    out.mkdir(parents=True, exist_ok=True)

    luau = out / "StudioInstaller.luau"
    luau.write_text(render_luau(groups, game))
    total = sum(1 + len(g["modules"]) for g in groups)
    print("wrote %s (%d instances, %d bytes)"
          % (luau.relative_to(ROOT), total, luau.stat().st_size))

    for group in groups:
        path = out / ("%s.rbxmx" % group["name"])
        path.write_text(render_rbxmx(group))
        print("wrote %s (-> %s, %d instances, %d bytes)"
              % (path.relative_to(ROOT), group["root"],
                 1 + len(group["modules"]), path.stat().st_size))


if __name__ == "__main__":
    names = sys.argv[1:] or sorted(GAMES)
    for name in names:
        if name not in GAMES:
            sys.exit("unknown game %r; known: %s" % (name, ", ".join(sorted(GAMES))))
        build(name)
