@tool
class_name GSWeatherConfig
extends GSConfig

## What a player and an operator get to say about weather.
##
## [member allow_flashes] and [member flash_scale] are accessibility settings, not preferences:
## lightning is a full-screen brightness change, and a player who asked for none must get none.
## Fog is deliberately not here: it is the world's atmosphere and part of how far anyone can see,
## so letting one player turn it off would be an advantage (see docs/design.md).

@export_group("Quality")

## 0 off (no precipitation, no flashes, no bolt; the schedule, wind and signals still run), 1 low
## (a third of the flakes, no bolt), 2 high.
@export_range(0, 2, 1) var quality: int = 2

## Multiplies the thickness of precipitation, 0 to 2. A player's slider.
@export_range(0.0, 2.0, 0.05) var density_scale: float = 1.0

@export_group("Accessibility")

## Whether lightning brightens the sky and ambient light at all. Thunder still arrives.
@export var allow_flashes: bool = true

## Multiplies the flash brightness, 0 to 1. Zero is the same as [member allow_flashes] off.
@export_range(0.0, 1.0, 0.05) var flash_scale: float = 1.0

## The shortest thunder [code]mean_interval[/code] a weather document may ask for, in seconds.
## Default 3 (no more than three flashes a second, the photosensitivity guidance); any value, 0 is
## no floor. Lowering it is logged as a warning each time a faster storm is applied.
@export_range(0.0, 10.0, 0.1, "or_greater") var min_thunder_interval: float = GSWeatherDoc.MIN_INTERVAL


func env_prefix() -> String:
	return "GS_WEATHER_"


func cli_prefix() -> String:
	return "--weather-"


func validate() -> GSResult:
	if quality < 0 or quality > 2:
		return GSResult.fail(GSError.CODE_INVALID, "quality is a tier from 0 to 2")
	if not is_finite(min_thunder_interval) or min_thunder_interval < 0.0:
		return GSResult.fail(GSError.CODE_INVALID, "min_thunder_interval must be 0 or more seconds")
	return GSResult.success(null)
