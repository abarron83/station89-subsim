extends Node2D

var mqtt: Node
const CLIENT_ID = "station89_helm"
const MAX_DEPTH_FEET = 800

# Nav state
var heading: float = 0.0        # 0-359 degrees
var depth: float = 0.0          # 0.0 = surface, 1.0 = max depth
var throttle: float = 0.0       # 0.0 = stop, 1.0 = full ahead
var game_state: String = "patrol"

# Player position on nav chart
var player_world_pos: Vector2 = Vector2(0, 0)
var player_trail: Array = []
const MAX_TRAIL = 40

# Contacts from server
var contacts: Dictionary = {}
var contact_ages: Dictionary = {}
const CONTACT_TIMEOUT = 6.0

# Input state
var turning_left: bool = false
var turning_right: bool = false
var diving: bool = false
var ascending: bool = false

const TURN_SPEED = 45.0       # degrees per second
const DEPTH_SPEED = 0.15
const MOVE_SPEED = 40.0

var font: Font
var _publish_timer: float = 0.0
const PUBLISH_INTERVAL = 0.2

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
	print("Helm: Online")

func _process(delta):
	# Handle turning
	if turning_left:
		heading -= TURN_SPEED * delta
	if turning_right:
		heading += TURN_SPEED * delta
	heading = fmod(heading + 360.0, 360.0)

	# Handle depth
	if diving:
		depth = clamp(depth + DEPTH_SPEED * delta, 0.0, 1.0)
	if ascending:
		depth = clamp(depth - DEPTH_SPEED * delta, 0.0, 1.0)

	# Move player position based on heading and throttle
	if throttle > 0.0:
		var move_dir = Vector2(cos(deg_to_rad(heading)), sin(deg_to_rad(heading)))
		player_world_pos += move_dir * throttle * MOVE_SPEED * delta
		# Record trail
		if player_trail.size() == 0 or player_world_pos.distance_to(player_trail[player_trail.size()-1]) > 15:
			player_trail.append(player_world_pos)
			if player_trail.size() > MAX_TRAIL:
				player_trail.pop_front()
				
	# Age out stale contacts
	var to_remove = []
	for id in contact_ages:
		contact_ages[id] += delta
		if contact_ages[id] > CONTACT_TIMEOUT:
			to_remove.append(id)
	for id in to_remove:
		contacts.erase(id)
		contact_ages.erase(id)

	# Publish helm state
	_publish_timer += delta
	if _publish_timer >= PUBLISH_INTERVAL:
		_publish_timer = 0.0
		mqtt.publish("submarine/helm/heading", str(snappedf(heading, 0.1)))
		mqtt.publish("submarine/helm/depth", str(snappedf(depth, 0.01)))
		mqtt.publish("submarine/helm/throttle", str(snappedf(throttle, 0.01)))

	queue_redraw()

func _input(event):
	if event is InputEventKey:
		var pressed = event.pressed
		match event.keycode:
			KEY_LEFT, KEY_A:   turning_left  = pressed
			KEY_RIGHT, KEY_D:  turning_right = pressed
			KEY_UP, KEY_W:     ascending     = pressed
			KEY_DOWN, KEY_S:   diving        = pressed
			KEY_EQUAL, KEY_KP_ADD:
				if pressed:
					throttle = clamp(throttle + 0.1, 0.0, 1.0)
			KEY_MINUS, KEY_KP_SUBTRACT:
				if pressed:
					throttle = clamp(throttle - 0.1, 0.0, 1.0)
			KEY_X:
				if pressed:
					throttle = 0.0

func _draw():
	var W = get_viewport().size.x
	var H = get_viewport().size.y

	# Background
	draw_rect(Rect2(Vector2.ZERO, get_viewport().size), Color(0.03, 0.04, 0.06))

	# ── HEADER ──────────────────────────────────────────────
	draw_rect(Rect2(0, 0, W, 55), Color(0.06, 0.08, 0.14))
	draw_string(font, Vector2(20, 38), "HELM — NAVIGATION CONTROL", HORIZONTAL_ALIGNMENT_LEFT, -1, 26, Color(0.6, 0.8, 0.6))
	var state_col = _state_color(game_state)
	draw_string(font, Vector2(W - 280, 38), "STATE: " + game_state.to_upper(), HORIZONTAL_ALIGNMENT_LEFT, -1, 20, state_col)
	
	# ── NAV CHART (center) ───────────────────────────────────
	var chart_center = Vector2(W / 2.0, H / 2.0 + 20)
	var chart_radius = 280.0
	var chart_scale = chart_radius / 1000.0

	# Chart background
	draw_circle(chart_center, chart_radius, Color(0.02, 0.06, 0.04))
	draw_arc(chart_center, chart_radius, 0, TAU, 128, Color(0.0, 0.5, 0.2, 0.6), 2.0)

	# Grid rings
	for i in range(1, 4):
		draw_arc(chart_center, chart_radius * (i / 4.0), 0, TAU, 64, Color(0.0, 0.25, 0.1, 0.4), 1.0)

	# Grid lines
	draw_line(chart_center + Vector2(-chart_radius, 0), chart_center + Vector2(chart_radius, 0), Color(0.0, 0.25, 0.1, 0.3), 1.0)
	draw_line(chart_center + Vector2(0, -chart_radius), chart_center + Vector2(0, chart_radius), Color(0.0, 0.25, 0.1, 0.3), 1.0)

	# Cardinal labels
	draw_string(font, chart_center + Vector2(-5, -chart_radius - 8), "N", HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(0.0, 0.8, 0.3, 0.7))
	draw_string(font, chart_center + Vector2(chart_radius + 4, 6), "E", HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(0.0, 0.8, 0.3, 0.7))
	draw_string(font, chart_center + Vector2(-5, chart_radius + 16), "S", HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(0.0, 0.8, 0.3, 0.7))
	draw_string(font, chart_center + Vector2(-chart_radius - 14, 6), "W", HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(0.0, 0.8, 0.3, 0.7))

	# Player trail
	for i in range(player_trail.size()):
		var tp = chart_center + (player_trail[i] - player_world_pos) * chart_scale
		var alpha = float(i) / float(player_trail.size()) * 0.5
		draw_circle(tp, 2.0, Color(0.0, 0.8, 0.3, alpha))

	# Contacts on chart
	for id in contacts:
		var c = contacts[id]
		var contact_rad = deg_to_rad(c.bearing)
		var contact_chart_pos = chart_center + Vector2(cos(contact_rad), sin(contact_rad)) * chart_radius * c.distance
		var ctype_col = _contact_color(c.type)
		draw_circle(contact_chart_pos, 5.0, ctype_col)
		draw_arc(contact_chart_pos, 8.0, 0, TAU, 12, Color(ctype_col.r, ctype_col.g, ctype_col.b, 0.4), 1.0)

	# Player submarine (triangle pointing in heading direction)
	var heading_rad = deg_to_rad(heading)
	var sub_size = 10.0
	var sub_tip   = chart_center + Vector2(cos(heading_rad), sin(heading_rad)) * sub_size
	var sub_left  = chart_center + Vector2(cos(heading_rad + 2.4), sin(heading_rad + 2.4)) * sub_size * 0.6
	var sub_right = chart_center + Vector2(cos(heading_rad - 2.4), sin(heading_rad - 2.4)) * sub_size * 0.6
	draw_colored_polygon(PackedVector2Array([sub_tip, sub_left, sub_right]), Color(0.2, 1.0, 0.4))
	draw_polyline(PackedVector2Array([sub_tip, sub_left, sub_right, sub_tip]), Color(0.4, 1.0, 0.5), 1.5)

	# ── COMPASS ─────────────────────────────────────────────
	var compass_center = Vector2(120, H / 2.0)
	var compass_radius = 90.0
	draw_circle(compass_center, compass_radius, Color(0.04, 0.06, 0.04))
	draw_arc(compass_center, compass_radius, 0, TAU, 64, Color(0.0, 0.6, 0.2, 0.7), 2.0)

	# Tick marks
	for i in range(36):
		var tick_angle = deg_to_rad(i * 10.0)
		var tick_len = 12.0 if i % 9 == 0 else 6.0
		var inner = compass_center + Vector2(cos(tick_angle), sin(tick_angle)) * (compass_radius - tick_len)
		var outer = compass_center + Vector2(cos(tick_angle), sin(tick_angle)) * compass_radius
		draw_line(inner, outer, Color(0.0, 0.6, 0.2, 0.6), 1.0)

	# North indicator
	var north_angle = deg_to_rad(-heading - 90)
	var north_tip = compass_center + Vector2(cos(north_angle), sin(north_angle)) * (compass_radius - 10)
	draw_line(compass_center, north_tip, Color(1.0, 0.3, 0.3, 0.9), 2.0)
	draw_string(font, north_tip + Vector2(-4, -4), "N", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(1.0, 0.3, 0.3))

	# Heading needle
	var needle_angle = deg_to_rad(-90.0)
	var needle_tip = compass_center + Vector2(cos(needle_angle), sin(needle_angle)) * (compass_radius - 10)
	draw_line(compass_center, needle_tip, Color(0.2, 1.0, 0.4, 0.9), 2.0)

	# Heading readout
	draw_string(font, compass_center + Vector2(-24, 16), "%03d°" % int(heading), HORIZONTAL_ALIGNMENT_LEFT, -1, 20, Color(0.2, 1.0, 0.4))
	draw_string(font, compass_center + Vector2(-28, -compass_radius - 10), "HEADING", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(0.0, 0.6, 0.2))

	# ── DEPTH GAUGE ─────────────────────────────────────────
	var dg_x = W - 180.0
	var dg_y = 80.0
	var dg_h = H - 160.0
	var dg_w = 40.0
	draw_rect(Rect2(dg_x, dg_y, dg_w, dg_h), Color(0.02, 0.05, 0.02))
	draw_rect(Rect2(dg_x, dg_y, dg_w, dg_h), Color(0.0, 0.4, 0.2, 0.6), false, 1.5)
	# Fill
	var fill_h = dg_h * depth
	draw_rect(Rect2(dg_x, dg_y + dg_h - fill_h, dg_w, fill_h), Color(0.0, 0.3, 0.5, 0.7))
	# Depth label
	draw_string(font, Vector2(dg_x - 10, dg_y - 10), "DEPTH", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(0.0, 0.6, 0.4))
	draw_string(font, Vector2(dg_x, dg_y + dg_h + 20), "%d ft" % int(depth * MAX_DEPTH_FEET), HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(0.0, 0.8, 0.5))
	draw_string(font, Vector2(dg_x, dg_y + dg_h + 38), "%d m" % int(depth * MAX_DEPTH_FEET * 0.3048), HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(0.0, 0.6, 0.4))

	# ── THROTTLE ────────────────────────────────────────────
	var tg_x = W - 100.0
	var tg_y = 80.0
	var tg_h = H - 160.0
	var tg_w = 40.0
	draw_rect(Rect2(tg_x, tg_y, tg_w, tg_h), Color(0.03, 0.04, 0.02))
	draw_rect(Rect2(tg_x, tg_y, tg_w, tg_h), Color(0.3, 0.5, 0.0, 0.6), false, 1.5)
	var t_fill_h = tg_h * throttle
	var t_col = Color(0.2, 0.8, 0.0) if throttle < 0.7 else Color(1.0, 0.5, 0.0)
	draw_rect(Rect2(tg_x, tg_y + tg_h - t_fill_h, tg_w, t_fill_h), Color(t_col.r, t_col.g, t_col.b, 0.8))
	draw_string(font, Vector2(tg_x - 4, tg_y - 10), "SPEED", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(0.4, 0.6, 0.0))
	draw_string(font, Vector2(tg_x, tg_y + tg_h + 20), "%d%%" % int(throttle * 100), HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(0.4, 0.8, 0.0))

	# ── CONTROLS LEGEND ─────────────────────────────────────
	var ly = H - 110.0
	draw_rect(Rect2(10, ly, 380, 100), Color(0.04, 0.06, 0.04))
	draw_rect(Rect2(10, ly, 380, 100), Color(0.0, 0.3, 0.1, 0.6), false, 1.0)
	draw_string(font, Vector2(20, ly + 18), "CONTROLS", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(0.0, 0.6, 0.2))
	draw_string(font, Vector2(20, ly + 36), "A / D  or  ◄ ►  — Turn", HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(0.5, 0.8, 0.5))
	draw_string(font, Vector2(20, ly + 54), "W / S  or  ▲ ▼  — Ascend / Dive", HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(0.5, 0.8, 0.5))
	draw_string(font, Vector2(20, ly + 72), "+  /  -  — Throttle Up / Down", HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(0.5, 0.8, 0.5))
	draw_string(font, Vector2(20, ly + 90), "X  — All Stop", HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(0.5, 0.8, 0.5))

func _state_color(state: String) -> Color:
	match state:
		"patrol":          return Color(0.0, 0.8, 0.0)
		"combat":          return Color(1.0, 0.2, 0.2)
		"silent":          return Color(0.2, 0.4, 1.0)
		"battle_stations": return Color(1.0, 0.5, 0.0)
	return Color(0.8, 0.8, 0.8)

func _contact_color(type: String) -> Color:
	match type:
		"surface":     return Color(0.0, 1.0, 0.0)
		"submarine":   return Color(1.0, 0.8, 0.0)
		"patrol_boat": return Color(1.0, 0.4, 0.0)
	return Color(0.0, 1.0, 0.0)

func _on_message_received(topic: String, payload: String):
	if topic == "submarine/game/state":
		game_state = payload
	elif topic == "submarine/contacts/update":
		var data = JSON.parse_string(payload)
		if data == null:
			return
		contacts[data.id] = {
			"bearing": float(data.bearing),
			"distance": float(data.distance),
			"type": data.type
						
		}
		contact_ages[data.id] = 0.0
