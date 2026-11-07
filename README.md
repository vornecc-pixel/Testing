# ESP Suite

A single-file ESP for Roblox (**players / NPCs / nodes**) with a full in-game
menu: per-feature toggles, distance-limit sliders, and an independent colour
picker for every feature on every category.

```
ESP.lua        the script — paste it into your executor and hit execute
loader.lua     fetch-and-run wrapper that pulls ESP.lua from this repo
tests/         headless test harness (mock Roblox API), not needed at runtime
```

## Quick start

**Option A — one-liner from GitHub:**

```lua
loadstring(game:HttpGet("https://raw.githubusercontent.com/vornecc-pixel/Testing/e834f10ad75ce60393a5bbe69cf62f5a180f4bfb/ESP.lua"))()
```

That URL is pinned to a commit, so it always loads the exact version that was
tested. For whatever is on the branch head right now, swap the SHA for the
branch name:

```lua
loadstring(game:HttpGet("https://raw.githubusercontent.com/vornecc-pixel/Testing/arena/bc2a72bc-testing/ESP.lua"))()
```

**Option B — the loader script** (recommended if Option A is misbehaving):

```lua
loadstring(game:HttpGet("https://raw.githubusercontent.com/vornecc-pixel/Testing/e834f10ad75ce60393a5bbe69cf62f5a180f4bfb/loader.lua"))()
```

The loader tries the pinned commit, the branch head, and a jsDelivr mirror in
that order, and reports exactly what each one did instead of failing silently —
it detects a missing HTTP API, `HttpEnabled = false`, empty responses, HTTP error
statuses, and HTML-instead-of-Lua. If it can't fetch, paste `ESP.lua` directly.

**Option C —** paste the whole of `ESP.lua` in directly.

Then:

1. Execute. The menu opens automatically.
2. **RightShift** toggles the menu (or click the small `ESP` pill).
   `RightControl` / `Delete` closes it.

Re-executing unloads the previous copy first, so it never stacks.

## What's on screen

| Feature | Players | NPCs | Nodes |
|---|---|---|---|
| Chams (Highlight) incl. through-wall | ✅ | ✅ | ✅ |
| Box — corner accents or full frame | ✅ | ✅ | ✅ |
| Box fill | ✅ | ✅ | ✅ |
| R15 skeleton (auto R6 fallback) | ✅ | ✅ | — |
| Health bar + health number | ✅ | ✅ | — |
| Name | ✅ | ✅ | ✅ |
| Distance | ✅ | ✅ | ✅ |
| Equipped weapon | ✅ | ✅ | — |
| Head dot | ✅ | ✅ | — |
| Tracer to screen edge | ✅ | ✅ | ✅ |

Every row above has its **own toggle and its own colour** — the players' box
colour, the players' cham colour, the players' name colour and so on are all
independent, and the same settings exist separately for NPCs and nodes.

## Distance limit

Each category (Players / NPCs / Nodes) has a **Max distance** slider, in studs:

* range `10 – 3000`, step `10`
* applied every frame, so dragging it updates instantly
* **Unlimited distance** toggle overrides it
* distance reading can be shown in **studs or metres** (`Studs per metre` is in
  Settings, default `3.571`)

## Colours

Click any colour row to open the picker:

* **Hue strip** + **saturation/value square**, live preview swatch
* **Hex field** — type `#RRGGBB` (or `#RGB`) and press Enter
* Changes apply on the next frame, no re-execution needed

## Toggles that are *not* per-category

**Filters** tab:

* NPC filter mode — `Whitelist` / `Blacklist` / `All`, with an editable name list
* Node filter mode — `Whitelist` / `Blacklist`, with an editable name list
* `*` works as a wildcard, e.g. `*Node`, `Guard*`
* Ignore dead, team check, show yourself, max tracked nodes

**Settings** tab:

* Studs per metre, box scale, render budget, rescan interval
* Show/hide the pill button
* Save / load settings to `esp_suite_config.json` (when the executor has
  `writefile`/`readfile`), reset everything
* Live status line (drawing library availability + tracked counts)

## Scripting API

```lua
local ESP = _G.ESP_Suite          -- exposed globally

ESP.config                        -- live config table (every feature lives here)
ESP.config.players.maxDistance = 250
ESP.config.players.chams.color = { 255, 0, 0 }
ESP.config.npcs.box.mode = "Full"

ESP.setDistance("nodes", 800)            -- clamped to 10..3000
ESP.setColor("players", "box", 255, 0, 0)
ESP.exportConfig()                       -- JSON string (also copies to clipboard)
ESP.importConfig(json)                   -- merge a config back in
ESP.saveConfig() / ESP.loadConfig()      -- file persistence
ESP.rescan()                             -- re-apply filters, rescan the world
ESP.toggleMenu() / ESP.setMenuOpen(true)
ESP.counts()                             -- { player = n, npc = n, node = n }
ESP.unload()                             -- full teardown
_G.EspUnload()                           -- same thing, legacy alias
```

## Config layout

```lua
CFG.players = {
    enabled = true,
    maxDistance = 400,      -- studs, driven by the slider
    unlimited = false,

    chams     = { on = true, color = {120,200,255}, fill = 35, outline = 100, throughWalls = true },
    box       = { on = true, color = {120,200,255}, mode = "Corners", corner = 25, thickness = 1, alpha = 100 },
    fill      = { on = false, color = {120,200,255}, alpha = 12 },
    skeleton  = { on = true, color = {120,200,255}, alpha = 100, thickness = 1, healthTint = false },
    healthBar = { on = true, color = {80,220,140},  alpha = 100, width = 3, tint = false },
    healthText= { on = false, color = {80,220,140}, alpha = 100, tint = false },
    name      = { on = true, color = {255,255,255}, alpha = 100, size = 14, healthTint = false },
    distance  = { on = true, color = {200,200,200}, alpha = 100, meters = false },
    weapon    = { on = true, color = {255,220,80},  alpha = 100, hideUnarmed = false },
    headDot   = { on = false, color = {255,255,255}, alpha = 100, size = 4 },
    tracer    = { on = false, color = {167,139,250}, alpha = 100, thickness = 1, origin = "Bottom" },
}
```

`alpha` is **opacity** (`100` = solid, `0` = invisible), `color` is `{r,g,b}`
in `0–255`. Values are sanitised on load, so a hand-edited config can't break
the script.

## Notes

* Needs an executor with the `Drawing` library for the 2-D overlay. Without it
  the script still runs — the Highlight-based chams keep working and the status
  line reports `drawing: unavailable`.
* Works with R15 rigs out of the box; R6 characters fall back to the reduced
  9-bone skeleton automatically.
* The render budget (`Settings → Render budget`) caps how many targets are drawn
  per frame, nearest first, so big servers stay smooth.
* Node detection only tracks `BasePart`/`Model` children of `Workspace`, so
  character limbs never get picked up as nodes.

## Tests

The script was developed against a headless mock of the Roblox API:

```bash
pip install lupa
python3 tests/run.py
```

(anything with a Lua 5.4+ interpreter can run `lua tests/run_tests.lua` directly)

69 assertions cover tracking, filters, chams colouring, box rendering, the
distance slider, skeletons, health/text, colour picking, dropdowns, config
persistence, lifecycle hooks and full unload.
