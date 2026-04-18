extends Node2D

var mqtt: Node
const CLIENT_ID = "station89_captain"

# Current sim info
var game_state: String = "patrol"
var contact_count: int = 0
var contacts: Dictionary = {}
var order_log: Array = []
const MAX_LOG = 8

# Button definitions [{label, command, color}]
var buttons = [
	{"label": "PATROL",         "command": "patrol",         "color": Color(0.0, 0.6, 0.0),  "rect": Rect2()},
	{"label": "COMBAT",         "command": "combat",         "color": Color(0.7, 0.0, 0.0),  "rect": Rect2()},
	{"label": "SILENT RUNNING", "command": "silent",         "color": Color(0.0, 0.3, 0.6),  "rect": Rect2()},
	{"label": "BATTLE STATIONS","command": "battle_stations","color": Color(0.8, 0.3, 0.0),  "rect": Rect2()},
	{"label": "SURFACE",        "command": "surface",        "color": Color(0.3, 0.3, 0.6),  "rect": Rect2()},
	{"label": "DIVE",           "command": "dive",           "color": Color(0.0, 0.4, 0.5),  "rect": Rect2()},
]

var hovered_button: int = -1
var font: Font

func _ready():
	font = ThemeDB.fallback_font
	mqtt = preload("res://scripts/mqtt_manager.gd").new()
	mqtt.name = "MQTT"
	mqtt.CLIENT_ID = CLIENT_ID
	mqtt.message_received.connect(_on_message_received)
	add_child(mqtt)
	await get_tree().create_timer(1.0).timeout
	mqtt.subscribe("submarine/game/state")
	mqtt.subscribe("submarine/contacts/update")
	print("Captain: Online")
	_log_order("Captain station online")

func _process(_delta):
	queue_redraw()

func _draw():
	var W = get_viewport().size.x
	var H = get_viewport().size.y

	# Background
	draw_rect(Rect2(Vector2.ZERO, get_viewport().size), Color(0.04, 0.04, 0.08))

	# ── HEADER ──────────────────────────────────────────────
	draw_rect(Rect2(0, 0, W, 60), Color(0.08, 0.1, 0.18))
	draw_string(font, Vector2(20, 42), "STATION 89 — COMMAND", HORIZONTAL_ALIGNMENT_LEFT, -1, 28, Color(0.8, 0.85, 1.0))
	# State indicator top right
	var state_col = _state_color(game_state)
	draw_rect(Rect2(W - 260, 10, 240, 40), Color(state_col.r, state_col.g, state_col.b, 0.2))
	draw_rect(Rect2(W - 260, 10, 240, 40), state_col, false)
	draw_string(font, Vector2(W - 250, 38), "STATE: " + game_state.to_upper(), HORIZONTAL_ALIGNMENT_LEFT, -1, 20, state_col)

	# ── LEFT PANEL: ORDER BUTTONS ────────────────────────────
	draw_string(font, Vector2(30, 90), "ISSUE ORDER", HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color(0.5, 0.6, 0.8))
	_draw_divider(20, 98, 420)

	var btn_w = 380
	var btn_h = 64
	var btn_x = 30
	var btn_start_y = 110
	var btn_gap = 14

	for i in range(buttons.size()):
		var btn = buttons[i]
		var btn_y = btn_start_y + i * (btn_h + btn_gap)
		var rect = Rect2(btn_x, btn_y, btn_w, btn_h)
		buttons[i].rect = rect

		var is_active = game_state == btn.command
		var is_hovered = hovered_button == i
		var col = btn.color

		# Button bg
		var bg_alpha = 0.5 if is_active else (0.25 if is_hovered else 0.12)
		draw_rect(rect, Color(col.r, col.g, col.b, bg_alpha))
		# Border
		var border_alpha = 1.0 if is_active else (0.7 if is_hovered else 0.4)
		draw_rect(rect, Color(col.r, col.g, col.b, border_alpha), false, 2.0)
		# Active indicator bar
		if is_active:
			draw_rect(Rect2(btn_x, btn_y, 6, btn_h), col)
		# Label
		draw_string(font, Vector2(btn_x + 20, btn_y + btn_h / 2 + 8), btn.label,
			HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Color(1.0, 1.0, 1.0, 0.9 if is_active else 0.7))

	# ── CENTER PANEL: CONTACT SUMMARY ───────────────────────
	var cx = 460
	draw_string(font, Vector2(cx, 90), "CONTACT SUMMARY", HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color(0.5, 0.6, 0.8))
	_draw_divider(cx, 98, 500)

	draw_string(font, Vector2(cx, 130), "TOTAL CONTACTS: %d" % contacts.size(),
		HORIZONTAL_ALIGNMENT_LEFT, -1, 22, Color(0.0, 1.0, 0.0))

	# Contact type breakdown
	var surface_count = 0
	var sub_count = 0
	var patrol_count = 0
	for id in contacts:
		match contacts[id].type:
			"surface": surface_count += 1
			"submarine": sub_count += 1
			"patrol_boat": patrol_count += 1

	var summary_y = 165
	_draw_contact_row(cx, summary_y,       "SURFACE VESSELS", surface_count, Color(0.0, 1.0, 0.0))
	_draw_contact_row(cx, summary_y + 40,  "SUBMARINES",      sub_count,     Color(1.0, 0.8, 0.0))
	_draw_contact_row(cx, summary_y + 80,  "PATROL BOATS",    patrol_count,  Color(1.0, 0.4, 0.0))

	# Closest contact
	var closest = _get_closest_contact()
	if closest != null:
		draw_string(font, Vector2(cx, summary_y + 140), "NEAREST CONTACT",
			HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(0.5, 0.6, 0.8))
		draw_string(font, Vector2(cx, summary_y + 162),
			"BRG: %03d  DIST: %d%%  TYPE: %s" % [int(closest.bearing), int(closest.distance * 100), closest.type.to_upper()],
			HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color(1.0, 0.8, 0.2))

	# Threat level
	var threat = _get_threat_level()
	var threat_col = Color(0.0, 1.0, 0.0) if threat == "LOW" else (Color(1.0, 0.8, 0.0) if threat == "MEDIUM" else Color(1.0, 0.2, 0.2))
	draw_string(font, Vector2(cx, summary_y + 210), "THREAT LEVEL",
		HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(0.5, 0.6, 0.8))
	draw_rect(Rect2(cx, summary_y + 220, 200, 36), Color(threat_col.r, threat_col.g, threat_col.b, 0.2))
	draw_rect(Rect2(cx, summary_y + 220, 200, 36), threat_col, false, 1.5)
	draw_string(font, Vector2(cx + 10, summary_y + 245), threat,
		HORIZONTAL_ALIGNMENT_LEFT, -1, 20, threat_col)

	# ── RIGHT PANEL: ORDER LOG ───────────────────────────────
	var rx = 1000
	draw_string(font, Vector2(rx, 90), "ORDER LOG", HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color(0.5, 0.6, 0.8))
	_draw_divider(rx, 98, W - rx - 20)

	for i in range(order_log.size()):
		var entry = order_log[order_log.size() - 1 - i]
		var log_y = 120 + i * 28
		var log_alpha = 1.0 - (i * 0.1)
		draw_string(font, Vector2(rx, log_y), entry,
			HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(0.7, 0.8, 0.7, log_alpha))

	# ── FOOTER ──────────────────────────────────────────────
	draw_rect(Rect2(0, H - 40, W, 40), Color(0.08, 0.1, 0.18))
	draw_string(font, Vector2(20, H - 12), "STATION 89 SUBMARINE SIMULATOR  |  CAPTAIN'S CONSOLE  |  MIT LICENSE  |  github.com/abarron83/station89-subsim",
		HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(0.3, 0.35, 0.5))

func _draw_contact_row(x, y, label, count, color):
	draw_circle(Vector2(x + 8, y - 5), 5.0, color)
	draw_string(font, Vector2(x + 22, y), "%s: %d" % [label, count],
		HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color(color.r, color.g, color.b, 0.9))

func _draw_divider(x, y, width):
	draw_line(Vector2(x, y), Vector2(x + width, y), Color(0.2, 0.25, 0.4), 1.0)

func _state_color(state: String) -> Color:
	match state:
		"patrol":         return Color(0.0, 0.8, 0.0)
		"combat":         return Color(1.0, 0.2, 0.2)
		"silent":         return Color(0.2, 0.4, 1.0)
		"battle_stations":return Color(1.0, 0.5, 0.0)
		"surface":        return Color(0.4, 0.6, 1.0)
		"dive":           return Color(0.0, 0.5, 0.6)
	return Color(0.8, 0.8, 0.8)

func _get_closest_contact():
	var closest = null
	var closest_dist = 999.0
	for id in contacts:
		var c = contacts[id]
		if c.distance < closest_dist:
			closest_dist = c.distance
			closest = c
	return closest

func _get_threat_level() -> String:
	if contacts.size() == 0:
		return "LOW"
	var closest = _get_closest_contact()
	if closest == null:
		return "LOW"
	if closest.distance < 0.3 or contacts.size() >= 4:
		return "HIGH"
	elif closest.distance < 0.6 or contacts.size() >= 2:
		return "MEDIUM"
	return "LOW"

func _log_order(text: String):
	var timestamp = Time.get_time_string_from_system().substr(0, 5)
	order_log.append("[%s] %s" % [timestamp, text])
	if order_log.size() > MAX_LOG:
		order_log.pop_front()

func _input(event):
	if event is InputEventMouseMotion:
		hovered_button = -1
		for i in range(buttons.size()):
			if buttons[i].rect.has_point(event.position):
				hovered_button = i
				break

	if event is InputEventMouseButton:
		if event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			for i in range(buttons.size()):
				if buttons[i].rect.has_point(event.position):
					_issue_order(buttons[i].command, buttons[i].label)
					break

func _issue_order(command: String, label: String):
	print("Captain: Issuing order -> ", command)
	mqtt.publish("submarine/captain/command", command)
	_log_order("ORDER: " + label)

func _on_message_received(topic: String, payload: String):
	if topic == "submarine/game/state":
		game_state = payload
		_log_order("STATE: " + payload.to_upper())

	elif topic == "submarine/contacts/update":
		var data = JSON.parse_string(payload)
		if data == null:
			return
		contacts[data.id] = {
			"bearing": float(data.bearing),
			"distance": float(data.distance),
			"strength": float(data.strength),
			"type": data.type
		}
