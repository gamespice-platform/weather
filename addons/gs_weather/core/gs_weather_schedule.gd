class_name GSWeatherSchedule
extends RefCounted

## Lightning, thunder and wind as pure functions of (the document's seed, a time).
##
## [b]Why this is how lightning stays in sync without a packet.[/b] The obvious design is a server
## that decides "lightning now" and tells every client. That costs a message per strike, arrives
## at a different moment for each client, is lost for a client that joins mid-storm, and does
## nothing for a replay or a spectator who seeks. Here nothing is ever sent: the strike list is a
## function of the document's seed and a clock every client already shares (the match time a
## game feeds in), so each client works out for itself that "there is a strike at 41.37 s, 312 m
## north-east of the centre". Two clients that agree on the time agree on the storm, a client that
## joins late sees the same storm from its first frame, and seeking a replay is just a different
## [param t].
##
## [b]Time is cut into slots[/b] of [member GSWeatherDoc.thunder_interval] seconds. Slot [code]n[/code]
## holds at most one strike, present with probability [member GSWeatherDoc.thunder_chance], placed
## between 25% and 75% of the way through its slot. A stateful countdown ("wait a random time, strike,
## repeat") cannot be asked about the middle of a match without simulating all of it, and its
## failure mode is the latch (one missed tick and it never fires again). A slot has no state to
## lose. The placement also bounds the pace: two strikes are always at least half an interval apart
## (1.5 s at the shortest), which is the guarantee that a flash, with its double flicker, never
## exceeds the three a second the accessibility guidance allows.
##
## [b]The strike has a place in the world, not on the screen[/b]: an angle and a distance from the
## document's centre, drawn from the same seed. So it is the same strike for everyone and each
## client sees it from where it stands: [method thunder_delay] differs per listener, and a player
## near the strike hears the thunder first.
##
## All draws are indexed ([method GSRandomStream.unit_at]), so asking about slot 900 does not
## need slots 0 to 899, and asking twice gives the same answer.

# Indices within a slot's block of draws. A block is 8 wide so a slot's draws never collide.
const _BLOCK := 8
const _PRESENT := 0
const _OFFSET := 1
const _ANGLE := 2
const _DISTANCE := 3
const _POWER := 4
const _SOUND := 5

## Where in its slot a strike falls, as fractions: the bound on how close two can be.
const EARLIEST := 0.25
const LATEST := 0.75


## The slot number that contains [param t].
static func slot_of(doc: GSWeatherDoc, t: float) -> int:
	return floori(t / doc.thunder_interval)


## The strike of slot [param n], or an empty dictionary when that slot has none.
##
## [code]{"slot", "time", "position": Vector3, "distance": float (from the centre),
## "power": 0.5 to 1, "sound": StringName}[/code]. [code]sound[/code] is one of the document's
## thunder sound ids, picked by the same seed, or empty.
static func strike(doc: GSWeatherDoc, n: int) -> Dictionary:
	var time := strike_time(doc, n)
	if time < 0.0:
		return {}
	var s := doc.stream()
	var base := n * _BLOCK
	var sound: StringName = &""
	if not doc.ambience_thunder.is_empty():
		sound = doc.ambience_thunder[s.range_i_at(base + _SOUND, 0, doc.ambience_thunder.size() - 1)]
	var pos := strike_position(doc, n)
	return {  # perf-lint: allow alloc one per strike, built only for slots that strike in the window
		"slot": n,
		"time": time,
		"position": pos,
		"distance": _strike_dist(doc, n),
		"power": strike_power(doc, n),
		"sound": sound,
	}


## When slot [param n] strikes, or -1 when it has no strike. Allocates nothing, so per-frame
## scans test slots with this and build [method strike] only for the ones that hit.
static func strike_time(doc: GSWeatherDoc, n: int) -> float:
	if not doc.has_thunder or n < 0:
		return -1.0
	var s := doc.stream()
	var base := n * _BLOCK
	if not s.chance_at(base + _PRESENT, doc.thunder_chance):
		return -1.0
	return (float(n) + EARLIEST + s.unit_at(base + _OFFSET) * (LATEST - EARLIEST)) * doc.thunder_interval


## Where slot [param n] strikes (only meaningful when [method strike_time] is not -1).
static func strike_position(doc: GSWeatherDoc, n: int) -> Vector3:
	var s := doc.stream()
	var base := n * _BLOCK
	var angle := s.unit_at(base + _ANGLE) * TAU
	var dist := _strike_dist(doc, n)
	return doc.thunder_centre + Vector3(cos(angle) * dist, 0.0, sin(angle) * dist)


static func _strike_dist(doc: GSWeatherDoc, n: int) -> float:
	# Square root so strikes spread over the ring's area, not crowd the inner edge.
	var u := doc.stream().unit_at(n * _BLOCK + _DISTANCE)
	var lo2 := doc.thunder_min_distance * doc.thunder_min_distance
	var hi2 := doc.thunder_max_distance * doc.thunder_max_distance
	return sqrt(lo2 + u * (hi2 - lo2))


static func strike_power(doc: GSWeatherDoc, n: int) -> float:
	return 0.5 + 0.5 * doc.stream().unit_at(n * _BLOCK + _POWER)


## Every strike whose time is in ([param t0], [param t1]], in order.
static func strikes_between(doc: GSWeatherDoc, t0: float, t1: float) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if not doc.has_thunder or t1 <= t0:
		return out
	var n := maxi(slot_of(doc, t0), 0)
	var last := slot_of(doc, t1)
	while n <= last:
		var tm := strike_time(doc, n)
		if tm > t0 and tm <= t1:
			out.append(strike(doc, n))
		n += 1
	return out


## Seconds from a flash until its thunder reaches [param listener].
static func thunder_delay(doc: GSWeatherDoc, st: Dictionary, listener: Vector3) -> float:
	return listener.distance_to(st["position"]) / doc.speed_of_sound


## The longest a thunder can lag its flash for any listener within the document's range of the
## centre plus [param reach] metres, for sizing the look-back window of [method thunders_between].
static func max_delay(doc: GSWeatherDoc, reach: float = 2000.0) -> float:
	return (doc.thunder_max_distance + reach + doc.thunder_height) / doc.speed_of_sound


## Strikes whose thunder reaches [param listener] in ([param t0], [param t1]]: the flash was
## earlier, by the distance over the speed of sound. Each is the strike dictionary plus
## [code]"delay"[/code] and [code]"listener_distance"[/code].
static func thunders_between(doc: GSWeatherDoc, listener: Vector3, t0: float, t1: float) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if not doc.has_thunder or t1 <= t0:
		return out
	var t_lo := t0 - max_delay(doc)
	var n := maxi(slot_of(doc, t_lo), 0)
	var last := slot_of(doc, t1)
	while n <= last:
		var tm := strike_time(doc, n)
		n += 1
		if tm <= t_lo or tm > t1:
			continue
		var metres := listener.distance_to(strike_position(doc, n - 1))
		var delay := metres / doc.speed_of_sound
		var arrives := tm + delay
		if arrives > t0 and arrives <= t1:
			var item := strike(doc, n - 1)
			item["delay"] = delay
			item["listener_distance"] = metres
			out.append(item)
	return out


## How bright the flash of [param st] is at time [param t], 0 to 1 (times the strike's power):
## a sharp rise, a fall, and a second weaker flicker 0.14 s later, which is what lightning
## looks like and what a single smooth pulse does not. Zero outside the flash.
static func flash_envelope(doc: GSWeatherDoc, st: Dictionary, t: float) -> float:
	return _envelope(doc, t - float(st["time"]), float(st["power"]))


static func _envelope(doc: GSWeatherDoc, d: float, power: float) -> float:
	if d < 0.0 or d > doc.flash_duration:
		return 0.0
	var k := doc.flash_duration * 0.2
	var main := smoothstep(0.0, 0.02, d) * exp(-d / k)
	var d2 := d - 0.14
	var flicker := 0.6 * smoothstep(0.0, 0.02, d2) * exp(-d2 / k) if d2 > 0.0 else 0.0
	return clampf(main + flicker, 0.0, 1.0) * power


## The strongest flash at time [param t] among all strikes, 0 to 1, and the strike behind it.
## [param listener] dims strikes far from it (a flash far off lights the sky less); leave it
## [constant Vector3.INF] for the same brightness for everyone.
## Returns [code]{"level": float, "strike": Dictionary}[/code].
static func flash_at(doc: GSWeatherDoc, t: float, listener: Vector3 = Vector3.INF) -> Dictionary:
	var n := brightest_slot(doc, t, listener)
	if n < 0:
		return {"level": 0.0, "strike": {}}
	return {"level": slot_level(doc, n, t, listener), "strike": strike(doc, n)}


## The slot of the strongest flash at [param t] ([method flash_at] without allocating), or -1.
static func brightest_slot(doc: GSWeatherDoc, t: float, listener: Vector3 = Vector3.INF) -> int:
	if not doc.has_thunder:
		return -1
	var t0 := t - doc.flash_duration - 0.001
	var n := maxi(slot_of(doc, t0), 0)
	var last := slot_of(doc, t)
	var best := -1
	var best_level := 0.0
	while n <= last:
		var tm := strike_time(doc, n)
		if tm > t0 and tm <= t:
			var level := slot_level(doc, n, t, listener)
			if level > best_level:
				best_level = level
				best = n
		n += 1
	return best


## Flash brightness of slot [param n] at [param t], dimmed by distance from [param listener].
static func slot_level(doc: GSWeatherDoc, n: int, t: float, listener: Vector3 = Vector3.INF) -> float:
	var tm := strike_time(doc, n)
	if tm < 0.0:
		return 0.0
	var level := _envelope(doc, t - tm, strike_power(doc, n))
	if listener != Vector3.INF:
		level *= distance_dim(doc, listener.distance_to(strike_position(doc, n)))
	return level


## Brightness and loudness factor for a strike [param metres] away: 1 close, down to 0.2 far.
static func distance_dim(doc: GSWeatherDoc, metres: float) -> float:
	return clampf(1.0 - metres / (doc.thunder_max_distance * 1.5), 0.2, 1.0)


## The wind at time [param t]: the document's vector times one plus the gust. A gust is the
## positive part of two slow sines beating against each other, so gusts come and go unevenly
## and are never negative. A function of time and seed, so every client's trees lean together.
static func wind_at(doc: GSWeatherDoc, t: float) -> Vector3:
	if not doc.has_wind:
		return Vector3.ZERO
	var phase := doc.stream().unit_at(1 << 40) * TAU
	var p := doc.gust_period
	var gust := maxf(sin(TAU * t / p + phase) * sin(TAU * t / (p * 0.43) + 1.3), 0.0)
	return doc.wind_vector * (1.0 + doc.gust_strength * gust)
