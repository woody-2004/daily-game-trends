#!/usr/bin/env python3
"""Rebuild NightShift.rbxlx from the .lua sources.

Run after editing GameManager.server.lua or ClientUI.client.lua:
    python3 build_rbxlx.py

NOTE: the Roblox Open Cloud place-publish endpoint rejects files with any
bytes after the closing </roblox> tag ("Invalid Content stream"), so this
script deliberately writes the file WITHOUT a trailing newline.
"""
import os
from xml.sax.saxutils import escape

HERE = os.path.dirname(os.path.abspath(__file__))


def read_source(name: str) -> str:
    with open(os.path.join(HERE, name), encoding="utf-8") as f:
        return escape(f.read().rstrip("\n"))


game_manager = read_source("GameManager.server.lua")
client_ui = read_source("ClientUI.client.lua")

# Lighting defaults match setNight() in GameManager: DbD midnight fog.
# The script drives Lighting at runtime; these are the pre-match defaults.
rbxlx = f"""<roblox xmlns:xmime="http://www.w3.org/2005/05/xmlmime" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" xsi:noNamespaceSchemaLocation="http://www.roblox.com/roblox.xsd" version="4">
\t<Item class="Workspace" referent="RBX0">
\t\t<Properties>
\t\t\t<string name="Name">Workspace</string>
\t\t</Properties>
\t</Item>
\t<Item class="ServerScriptService" referent="RBX1">
\t\t<Properties>
\t\t\t<string name="Name">ServerScriptService</string>
\t\t</Properties>
\t\t<Item class="Script" referent="RBX2">
\t\t\t<Properties>
\t\t\t\t<string name="Name">GameManager</string>
\t\t\t\t<token name="RunContext">0</token>
\t\t\t\t<bool name="Disabled">false</bool>
\t\t\t\t<ProtectedString name="Source">{game_manager}</ProtectedString>
\t\t\t</Properties>
\t\t</Item>
\t</Item>
\t<Item class="StarterPlayer" referent="RBX3">
\t\t<Properties>
\t\t\t<string name="Name">StarterPlayer</string>
\t\t</Properties>
\t\t<Item class="StarterPlayerScripts" referent="RBX4">
\t\t\t<Properties>
\t\t\t\t<string name="Name">StarterPlayerScripts</string>
\t\t\t</Properties>
\t\t\t<Item class="LocalScript" referent="RBX5">
\t\t\t\t<Properties>
\t\t\t\t\t<string name="Name">ClientUI</string>
\t\t\t\t\t<bool name="Disabled">false</bool>
\t\t\t\t\t<ProtectedString name="Source">{client_ui}</ProtectedString>
\t\t\t\t</Properties>
\t\t\t</Item>
\t\t</Item>
\t</Item>
\t<Item class="Lighting" referent="RBX6">
\t\t<Properties>
\t\t\t<string name="Name">Lighting</string>
\t\t\t<token name="Technology">4</token>
\t\t\t<bool name="GlobalShadows">true</bool>
\t\t\t<float name="Brightness">3</float>
\t\t\t<float name="ShadowSoftness">0.2</float>
\t\t\t<float name="EnvironmentDiffuseScale">1</float>
\t\t\t<float name="EnvironmentSpecularScale">1</float>
\t\t\t<Color3 name="Ambient"><R>0</R><G>0</G><B>0</B></Color3>
\t\t\t<Color3 name="OutdoorAmbient"><R>0.0588235</R><G>0.0588235</G><B>0.0784314</B></Color3>
\t\t\t<string name="TimeOfDay">00:00:00</string>
\t\t</Properties>
\t</Item>
</roblox>"""

out = os.path.join(HERE, "NightShift.rbxlx")
with open(out, "w", encoding="utf-8", newline="\n") as f:
    f.write(rbxlx)  # no trailing newline — see note above
print(f"wrote {out} ({len(rbxlx)} bytes)")
