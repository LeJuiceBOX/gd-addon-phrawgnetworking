class_name NetworkStatistics
extends RefCounted

## Rolling network statistics for diagnostics UI.
## Call record_in() / record_out() whenever bytes cross the wire,
## and tick(delta) once per frame (or _process).

# --- Per-second (last completed 1s window) ---
var bytes_in: int = 0
var bytes_out: int = 0
var packets_in: int = 0
var packets_out: int = 0

# --- Accumulators for the window currently being measured ---
var _acc_bytes_in: int = 0
var _acc_bytes_out: int = 0
var _acc_packets_in: int = 0
var _acc_packets_out: int = 0
var _window_time: float = 0.0

# --- All-time totals ---
var total_bytes_in: int = 0
var total_bytes_out: int = 0
var total_packets_in: int = 0
var total_packets_out: int = 0
var uptime: float = 0.0

# --- Min / max / peak (per-second rates) ---
var min_bytes_in: int = -1   ## -1 = no sample yet
var max_bytes_in: int = 0
var min_bytes_out: int = -1
var max_bytes_out: int = 0

# --- History ring buffer (for graphs) ---
const HISTORY_SIZE: int = 60
var history_in: PackedInt32Array = PackedInt32Array()
var history_out: PackedInt32Array = PackedInt32Array()

# --- Latency / connection quality ---
var ping_ms: float = 0.0
var min_ping_ms: float = -1.0
var max_ping_ms: float = 0.0
var avg_ping_ms: float = 0.0
var jitter_ms: float = 0.0
var _ping_samples: int = 0

# --- Packet loss ---
## Manual tally, only populated if you call record_loss() yourself. ENet does
## not expose packet counts, so these stay at 0 unless you feed them.
var packets_lost: int = 0
var packets_expected: int = 0

## Loss as a 0..1 ratio, read from ENet's own estimate in sample_peer().
## This is the figure to display; packets_lost/packets_expected are not.
var loss_ratio: float = 0.0
## Variance of the mean RTT, in milliseconds. ENet's own jitter estimate,
## independent of the smoothed jitter_ms computed in record_ping().
var rtt_variance_ms: float = 0.0

signal window_elapsed  ## Emitted each time a 1s window closes.


func _init() -> void:
	history_in.resize(HISTORY_SIZE)
	history_out.resize(HISTORY_SIZE)


# ---------------------------------------------------------------- recording

func record_in(byte_count: int, packet_count: int = 1) -> void:
	_acc_bytes_in += byte_count
	_acc_packets_in += packet_count
	total_bytes_in += byte_count
	total_packets_in += packet_count


func record_out(byte_count: int, packet_count: int = 1) -> void:
	_acc_bytes_out += byte_count
	_acc_packets_out += packet_count
	total_bytes_out += byte_count
	total_packets_out += packet_count


func record_ping(ms: float) -> void:
	var prev := ping_ms
	ping_ms = ms
	if _ping_samples > 0:
		jitter_ms = lerp(jitter_ms, absf(ms - prev), 0.1)
	_ping_samples += 1
	avg_ping_ms += (ms - avg_ping_ms) / float(_ping_samples)
	if min_ping_ms < 0.0 or ms < min_ping_ms:
		min_ping_ms = ms
	max_ping_ms = maxf(max_ping_ms, ms)


func record_loss(lost: int, expected: int) -> void:
	packets_lost += lost
	packets_expected += expected


## Pulls RTT and loss straight off an ENet peer. Called once per window by
## Network._physics_process, so no manual record_ping() needed.
## ENet reports RTT in whole milliseconds.
func sample_peer(peer: ENetPacketPeer) -> void:
	if peer == null:
		return
	record_ping(peer.get_statistic(ENetPacketPeer.PEER_ROUND_TRIP_TIME))

	# ENet exposes loss only as a ratio, not as packet counts. It's scaled by
	# PACKET_LOSS_SCALE and recomputed on ENet's own ~10s interval, so this is
	# a coarse gauge rather than a running tally.
	loss_ratio = peer.get_statistic(ENetPacketPeer.PEER_PACKET_LOSS) / float(ENetPacketPeer.PACKET_LOSS_SCALE)
	rtt_variance_ms = peer.get_statistic(ENetPacketPeer.PEER_ROUND_TRIP_TIME_VARIANCE)


# ---------------------------------------------------------------- per-type

## Payload bytes and counts broken down by packet type name, for spotting
## which packet is eating the bandwidth. Shape: { "CHAT": { "in_bytes": 0,
## "out_bytes": 0, "in_count": 0, "out_count": 0 }, ... }
var by_type: Dictionary = {}


func _type_entry(type_name: String) -> Dictionary:
	if not by_type.has(type_name):
		by_type[type_name] = {
			"in_bytes": 0, "out_bytes": 0, "in_count": 0, "out_count": 0,
		}
	return by_type[type_name]


func record_in_typed(type_name: String, byte_count: int) -> void:
	record_in(byte_count)
	var e := _type_entry(type_name)
	e["in_bytes"] += byte_count
	e["in_count"] += 1


func record_out_typed(type_name: String, byte_count: int) -> void:
	record_out(byte_count)
	var e := _type_entry(type_name)
	e["out_bytes"] += byte_count
	e["out_count"] += 1


# ---------------------------------------------------------------- ticking

func tick(delta: float) -> void:
	uptime += delta
	_window_time += delta
	if _window_time < 1.0:
		return
	_window_time -= 1.0
	_close_window()


func _close_window() -> void:
	bytes_in = _acc_bytes_in
	bytes_out = _acc_bytes_out
	packets_in = _acc_packets_in
	packets_out = _acc_packets_out

	if min_bytes_in < 0 or bytes_in < min_bytes_in:
		min_bytes_in = bytes_in
	if min_bytes_out < 0 or bytes_out < min_bytes_out:
		min_bytes_out = bytes_out
	max_bytes_in = maxi(max_bytes_in, bytes_in)
	max_bytes_out = maxi(max_bytes_out, bytes_out)

	_push_history(history_in, bytes_in)
	_push_history(history_out, bytes_out)

	_acc_bytes_in = 0
	_acc_bytes_out = 0
	_acc_packets_in = 0
	_acc_packets_out = 0

	window_elapsed.emit()


func _push_history(buf: PackedInt32Array, value: int) -> void:
	for i in range(HISTORY_SIZE - 1):
		buf[i] = buf[i + 1]
	buf[HISTORY_SIZE - 1] = value


# ---------------------------------------------------------------- derived

func avg_bytes_in() -> float:
	return total_bytes_in / maxf(uptime, 0.001)


func avg_bytes_out() -> float:
	return total_bytes_out / maxf(uptime, 0.001)


## Prefers ENet's own loss estimate. Falls back to the manual record_loss()
## tally only if you've been feeding it and ENet hasn't reported yet.
func loss_percent() -> float:
	if loss_ratio > 0.0:
		return 100.0 * loss_ratio
	if packets_expected == 0:
		return 0.0
	return 100.0 * packets_lost / float(packets_expected)


func total_bytes() -> int:
	return total_bytes_in + total_bytes_out


## HISTORY_SIZE is 60 and each entry is one 1-second window, so summing the
## ring buffer gives exactly the trailing minute. Windows that haven't been
## filled yet are 0, so this reads low for the first minute of uptime.
func bytes_in_last_min() -> int:
	var sum := 0
	for v in history_in:
		sum += v
	return sum


func bytes_out_last_min() -> int:
	var sum := 0
	for v in history_out:
		sum += v
	return sum


func bytes_last_min() -> int:
	return bytes_in_last_min() + bytes_out_last_min()


# ---------------------------------------------------------------- display

static func format_bytes(b: int) -> String:
	if b < 1024:
		return "%d B" % b
	if b < 1024 * 1024:
		return "%.1f KiB" % (b / 1024.0)
	if b < 1024 * 1024 * 1024:
		return "%.2f MiB" % (b / 1048576.0)
	return "%.2f GiB" % (b / 1073741824.0)


static func format_rate(bytes_per_sec: int) -> String:
	return format_bytes(bytes_per_sec) + "/s"


func reset() -> void:
	bytes_in = 0
	bytes_out = 0
	packets_in = 0
	packets_out = 0
	_acc_bytes_in = 0
	_acc_bytes_out = 0
	_acc_packets_in = 0
	_acc_packets_out = 0
	_window_time = 0.0
	total_bytes_in = 0
	total_bytes_out = 0
	total_packets_in = 0
	total_packets_out = 0
	uptime = 0.0
	min_bytes_in = -1
	max_bytes_in = 0
	min_bytes_out = -1
	max_bytes_out = 0
	history_in.fill(0)
	history_out.fill(0)
	ping_ms = 0.0
	min_ping_ms = -1.0
	max_ping_ms = 0.0
	avg_ping_ms = 0.0
	jitter_ms = 0.0
	_ping_samples = 0
	packets_lost = 0
	packets_expected = 0
	loss_ratio = 0.0
	rtt_variance_ms = 0.0
	by_type.clear()
