# GameSpice Weather

The family's everyday-weather layer: snow, rain, thunderstorms, wind and fog, described per map as a document, so any game gets them by adding a node. Intense events (a tornado, a flood) stay in [natural-disasters](../natural-disasters), which may later build on this.

Read the family [CLAUDE.md](../../CLAUDE.md) first.

**The distributable is `addons/gs_weather/`.** It requires [GameSpice Core](../gs-core) and nothing else. [GameSpice FX](../gs-fx) (draws the precipitation) and [GameSpice Lighting](../gs-lighting) (writes the fog) are **optional**: a build with neither still parses documents, runs the lightning schedule, answers `wind()` and emits `lightning` and `thunder`. For local development link all three, gitignored (`ln -s ../../gs-core/addons/gs_core addons/gs_core`, and the same for `gs_fx` and `gs_lighting`).

## Read before

| Read | Before |
| --- | --- |
| [docs/design.md](docs/design.md) | changing anything: why lightning needs no packets, the optional-addon rule, what fog is not allowed to be, the flash-rate guarantee, what is deliberately not here |

## Layout

| Path | What |
| --- | --- |
| `core/gs_weather_doc.gd` | `GSWeatherDoc`: the document; `parse() -> GSResult` (unknown keys refused at every level), `to_dict()`, `precipitation_dict()`, `describe()` |
| `core/gs_weather_schedule.gd` | `GSWeatherSchedule`: pure functions of (seed, time): `strike`, `strikes_between`, `thunders_between`, `flash_at`, `wind_at` |
| `core/gs_weather_config.gd` | `GSWeatherConfig`: quality, density scale, `allow_flashes`, `flash_scale` (a `GSConfig`) |
| `runtime/gs_weather.gd` | `GSWeather`: the node; `apply`, `setup`, `clear`, `advance`, `wind`, `describe`; signals `lightning`, `thunder`, `ambience_changed`, `ambience_inside_changed` |
| `runtime/gs_weather_bolt.gd` | `GSWeatherBolt`: the bolt's polyline and ribbon mesh (pure geometry) |
| `gs_weather_api.gd` | the API level (`GSAddonApi` rule) |
| `examples/weather_selftest.tscn` | the suite |
| `examples/weather_demo.tscn` | snow, rain with lightning, fog, and a held flash (`--mode`, `--shot`) |

Paths except `examples/` are in `addons/gs_weather/`.

## Running and testing

The family's two steps ([family CLAUDE.md](../../CLAUDE.md#validating-anything)), then `timeout 120 godot --headless --path . res://examples/weather_selftest.tscn`. The suite counts sections and checks, and the checks that need an optional addon are counted only when it is installed (the same suite passes in a project that has neither: link only gs-core into a scratch project and run it). The last section is the armed one: it makes deliberately wrong claims and asserts the harness caught them. The suite cannot see whether anything looks right: after changing anything that draws, render the demo under xvfb (`--mode snow|rain|fog|flash --shot file.png`) and look.

## Rules that bite

- **Never name a `GSFx*` or `GSLight*` class in a script here.** A named class from an absent addon is a parse error in the whole file. They are reached by path (`load(...)`, `.new()`, `Object.call`) behind `fx_available()` and `lighting_available()` (API levels 5 and 6). [design](docs/design.md#optional-addons-by-path-and-level)
- **Lightning is never sent.** It is a pure function of the document's seed and the shared match time a game passes to `advance()`. Anything that adds state to the schedule (a countdown, a random stream that advances) breaks late join, seeking and agreement. [design](docs/design.md#lightning-in-sync-without-networking)
- **Fog is written onto the existing `Environment` through `GSLightRig.apply_fog`, never a second `WorldEnvironment`**, and the map's own fog is put back by `clear()`. [design](docs/design.md#fog-belongs-to-the-lighting)
- **The shortest storm is 3 s per interval by default** (`GSWeatherConfig.min_thunder_interval`, overridable, 0 = no floor, lowering it logs a warning) and a strike sits in the middle half of its slot, so two are at least 1.5 s apart: the three-flashes-a-second guarantee lives in the document's range check and the schedule's placement, and a test counts it. [design](docs/design.md#the-flash-rate-is-guaranteed-by-construction)
- **A flash changes the sky and ambient energy by a bump over a captured base and restores it exactly**; it never accumulates from frame to frame, and `allow_flashes`/`flash_scale` reach zero.
- Call `advance()` yourself; nothing runs in `_process`.
- A newly created node gets an auto name like `@WorldEnvironment@3`, so a `GSNodeRef` path to it needs `name` set first (the suite hit this).

## Open items

- Two games carry their own per-zone weather (a tick-driven draw of sky, wind, storm and fog for gameplay grip); that is prior art this does not replace: they decide *what the weather is* in a zone (simulation), this draws *a* weather. Folding them in means a game converting its zone draw into a `GSWeatherDoc` per zone; the steps, with mg-dangerous-delivery as the worked example, are in docs/design.md ("Adopting it in a game with its own weather"); nightly item `weather-adopt` covers the remaining game.
- Gusts reach GameSpice FX as a lean: `advance` hands `gust()` (wind minus the steady wind) to `GSFxWeather.set_gust` every frame.
