extends Control

const TEMPLATE = "[color=ORANGE]{SEND_OR_RECIEVE}[/color] - [color=LIGHTBLUE]{PACKET_TYPE}[/color] - [color=YELLOW]{PACKET_DATA}[/color]"

## Separator drawn between paired values. Defined once here so the colour is
## consistent everywhere; the .tscn writes {PIPE} rather than a literal "|".
const PIPE = "[color=#5a5a5a]|[/color]"

## Each label's text in the .tscn is used as its own template. They're captured
## on _ready before the first substitution, so re-filling them every window
## doesn't consume the placeholders.
@onready var _stats_left: RichTextLabel = %StatsLeft
@onready var _stats_right: RichTextLabel = %StatsRight
@onready var _by_type_label: RichTextLabel = %ByType
var _left_template: String = ""
var _right_template: String = ""
var _by_type_template: String = ""

func log_packet(packet,outgoing = false):
	var log = TEMPLATE
	if outgoing:
		log = log.replace("{SEND_OR_RECIEVE}","OUT")
	else:
		log = log.replace("{SEND_OR_RECIEVE}","IN")
	log = log.replace("{PACKET_TYPE}",packet.type)

	if packet.data.size() == 0:
		log = log.replace(" - [color=YELLOW]{PACKET_DATA}[/color]","")
	else:
		log = log.replace("{PACKET_DATA}",str(packet.data))

	log += "\n"
	%PacketLog.text += log


## min_bytes_* use -1 to mean "no window has closed yet". Printing that as a
## byte count would be nonsense, so show a dash until there's a real sample.
func _fmt_min(v: int) -> String:
	if v < 0:
		return "-"
	return NetworkStatistics.format_rate(v)


## Same idea for min_ping_ms, which starts at -1.0.
func _fmt_ms(v: float) -> String:
	if v < 0.0:
		return "-"
	return "%.0f ms" % v


func _fmt_uptime(seconds: float) -> String:
	var total := int(seconds)
	if total < 60:
		return "%ds" % total
	if total < 3600:
		return "%dm %ds" % [total / 60, total % 60]
	return "%dh %dm" % [total / 3600, (total % 3600) / 60]


## One line per packet type seen, sorted heaviest-first by total bytes so the
## bandwidth hog is always at the top.
func _fmt_by_type(by_type: Dictionary) -> String:
	if by_type.is_empty():
		return "  [color=GRAY]no packets yet[/color]"
	var names := by_type.keys()
	names.sort_custom(func(a, b):
		var ea: Dictionary = by_type[a]
		var eb: Dictionary = by_type[b]
		return (ea["in_bytes"] + ea["out_bytes"]) > (eb["in_bytes"] + eb["out_bytes"])
	)
	var lines: Array[String] = []
	for n in names:
		var e: Dictionary = by_type[n]
		lines.append("  [color=LIGHTBLUE]%s[/color] UP %s (%d) %s DN %s (%d)" % [
			n,
			NetworkStatistics.format_bytes(e["out_bytes"]), e["out_count"],
			PIPE,
			NetworkStatistics.format_bytes(e["in_bytes"]), e["in_count"],
		])
	return "\n".join(lines)


## Applies every substitution to one template. Values are shared across the
## labels, so which placeholders a given template actually uses is up to the
## .tscn; unused entries are simply no-ops.
func _fill(template: String, values: Dictionary) -> String:
	var text := template
	for key in values:
		text = text.replace("{%s}" % key, values[key])
	return text


## Redraws the readout. Driven by NetworkStatistics.window_elapsed, so it
## updates once per second rather than every frame.
func refresh_stats() -> void:
	var s := Network.statistics
	var v := {}

	v["PIPE"] = PIPE

	# Per-second rates for the last closed window.
	v["BYTES_UP"] = NetworkStatistics.format_rate(s.bytes_out)
	v["BYTES_DN"] = NetworkStatistics.format_rate(s.bytes_in)
	v["BYTES_TRANSFERRED_MIN"] = NetworkStatistics.format_bytes(s.bytes_last_min())
	v["PACKETS_UP"] = str(s.packets_out)
	v["PACKETS_DN"] = str(s.packets_in)

	# Extremes and averages across all closed windows.
	v["PEAK_UP"] = NetworkStatistics.format_rate(s.max_bytes_out)
	v["PEAK_DN"] = NetworkStatistics.format_rate(s.max_bytes_in)
	v["MIN_UP"] = _fmt_min(s.min_bytes_out)
	v["MIN_DN"] = _fmt_min(s.min_bytes_in)
	v["AVG_UP"] = NetworkStatistics.format_rate(int(s.avg_bytes_out()))
	v["AVG_DN"] = NetworkStatistics.format_rate(int(s.avg_bytes_in()))

	# All-time totals.
	v["TOTAL_UP"] = NetworkStatistics.format_bytes(s.total_bytes_out)
	v["TOTAL_DN"] = NetworkStatistics.format_bytes(s.total_bytes_in)
	v["TOTAL_PACKETS_UP"] = str(s.total_packets_out)
	v["TOTAL_PACKETS_DN"] = str(s.total_packets_in)

	# Latency is sampled from the server peer, which only exists client-side.
	# Showing "0 ms" on the server would look like a real measurement, so say
	# plainly that it isn't one.
	if Network.is_server:
		v["PING"] = "[color=GRAY]n/a (server)[/color]"
		v["PING_MIN"] = "-"
		v["PING_AVG"] = "-"
		v["PING_MAX"] = "-"
		v["JITTER"] = "-"
		v["LOSS"] = "[color=GRAY]n/a (server)[/color]"
	else:
		v["PING"] = _fmt_ms(s.ping_ms)
		v["PING_MIN"] = _fmt_ms(s.min_ping_ms)
		v["PING_AVG"] = _fmt_ms(s.avg_ping_ms)
		v["PING_MAX"] = _fmt_ms(s.max_ping_ms)
		# jitter_ms is our own smoothed estimate; rtt_variance_ms is ENet's.
		v["JITTER"] = "%.1f ms (ENet var %.1f)" % [s.jitter_ms, s.rtt_variance_ms]
		# ENet recomputes loss on its own ~10s interval, so this lags and is a
		# health indicator rather than a precise per-second figure.
		v["LOSS"] = "%.1f%%" % s.loss_percent()

	v["UPTIME"] = _fmt_uptime(s.uptime)
	v["BY_TYPE"] = _fmt_by_type(s.by_type)

	_stats_left.text = _fill(_left_template, v)
	_stats_right.text = _fill(_right_template, v)
	_by_type_label.text = _fill(_by_type_template, v)


func _ready() -> void:
	# Capture each label's authored text as its template before the first
	# substitution, otherwise refilling would have no placeholders to find.
	_left_template = _stats_left.text
	_right_template = _stats_right.text
	_by_type_template = _by_type_label.text

	refresh_stats()
	Network.statistics.window_elapsed.connect(refresh_stats)

	Network.on_packet_received.connect(func(packet:Packet):
		log_packet(packet,false)
	)
	Network.on_packet_sent.connect(func(packet:Packet):
		log_packet(packet,true)
	)
