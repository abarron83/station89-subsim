extends Node2D

var mqtt: Node
const CLIENT_ID = "station89_sonar"
var game_state: String = "patrol"

# Sonar sweep
var sweep_angle: float = 0.0
var sweep_speed: float = 60.0

# Contacts - keyed by ID
var contacts: Dictionary = {}

# Display
var center: Vector2
var radius: float

# Track previous positions for movement trails
var contact_history: Dictionary = {}
const MAX_HISTORY = 4

# Contact colors by type
const TYPE_COLORS = {
	"surface": Color(0.0, 1.0, 0.0),
	"submarine": Color(1.0, 0.8, 0.0),
	"patrol_boat": Color(1.0, 0.4, 0.0)
}

func _ready():
	center = Vector2(get_viewport().size) / 2
	radius = min(center.x, center.y) * 0.85
	mqtt = preload("res://scripts/mqtt_manager.gd").new()
	mqtt.name = "MQTT"
	mqtt.CLIENT_ID = CLIENT_ID
	mqtt.message_received.connect(_on_message_received)
	add_child(mqtt)
	await get_tree().create_timer(1.0).timeout
	mqtt.subscribe("submarine/game/state")
	mqtt.subscribe("submarine/contacts/update")
	print("Sonar: Online")

func _process(delta):
	sweep_angle += sweep_speed * delta
	if sweep_angle >= 360.0:
		sweep_angle -= 360.0
		# Full sweep complete - age all contacts
		for id in contacts:
			contacts[id].age += 1
		# Remove contacts not seen in 3 sweeps
		var to_remove = []
		for id in contacts:
			if contacts[id].age > 3:
				to_remove.append(id)
		for id in to_remove:
			contacts.erase(id)
		for id in to_remove:
			contacts.erase(id)
			contact_history.erase(id)

	# Light up contacts as sweep passes over them
	for id in contacts:
		var c = contacts[id]
		var diff = abs(sweep_angle - c.bearing)
		if diff > 180:
			diff = 360 - diff
		if diff < 3.0:
			c.lit = true
			c.lit_timer = 0.0
		if c.lit:
			c.lit_timer += delta
			if c.lit_timer > 2.0:
				c.lit = false

	queue_redraw()

func _draw():
	# Background
	draw_rect(Rect2(Vector2.ZERO, get_viewport().size), Color(0.02, 0.05, 0.02))

	# Range rings
	for i in range(1, 5):
		var r = radius * (i / 4.0)
		draw_arc(center, r, 0, TAU, 64, Color(0.0, 0.3, 0.0, 0.4), 1.0)
		# Range labels
		draw_string(ThemeDB.fallback_font, center + Vector2(4, -r + 4),
			"%d%%" % (i * 25), HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(0.0, 0.5, 0.0, 0.6))

	# Crosshairs
	draw_line(center + Vector2(-radius, 0), center + Vector2(radius, 0), Color(0.0, 0.3, 0.0, 0.4), 1.0)
	draw_line(center + Vector2(0, -radius), center + Vector2(0, radius), Color(0.0, 0.3, 0.0, 0.4), 1.0)

	# Sweep trail
	for i in range(60):
		var trail_angle = deg_to_rad(sweep_angle - i * 1.2)
		var alpha = (1.0 - i / 60.0) * 0.18
		var end = center + Vector2(cos(trail_angle), sin(trail_angle)) * radius
		draw_line(center, end, Color(0.0, 1.0, 0.0, alpha), 2.0)

	# Sweep line
	var sweep_rad = deg_to_rad(sweep_angle)
	var sweep_end = center + Vector2(cos(sweep_rad), sin(sweep_rad)) * radius
	draw_line(center, sweep_end, Color(0.0, 1.0, 0.2, 0.9), 2.0)

	# Contact trails and dots
	for id in contacts:
		var c = contacts[id]
		var base_color = TYPE_COLORS.get(c.type, Color(0.0, 1.0, 0.0))
		var contact_rad = deg_to_rad(c.bearing)
		var contact_pos = center + Vector2(cos(contact_rad), sin(contact_rad)) * radius * c.distance

		# Draw movement trail
		if contact_history.has(id) and contact_history[id].size() > 0:
			var history = contact_history[id]
			for i in range(history.size()):
				var h = history[i]
				var h_rad = deg_to_rad(h.bearing)
				var h_pos = center + Vector2(cos(h_rad), sin(h_rad)) * radius * h.distance
				var fade = (float(i + 1) / float(history.size())) * 0.4
				draw_circle(h_pos, 2.5, Color(base_color.r, base_color.g, base_color.b, fade))
			# Draw line connecting trail to current pos
			var last = history[history.size() - 1]
			var last_rad = deg_to_rad(last.bearing)
			var last_pos = center + Vector2(cos(last_rad), sin(last_rad)) * radius * last.distance
			draw_line(last_pos, contact_pos, Color(base_color.r, base_color.g, base_color.b, 0.2), 1.0)

		if c.lit:
			var fade = clamp(1.0 - (c.lit_timer / 2.0), 0.1, 1.0)
			# Outer glow
			draw_circle(contact_pos, 10.0 * c.strength, Color(base_color.r, base_color.g, base_color.b, fade * 0.3))
			# Core dot
			draw_circle(contact_pos, 5.0, Color(base_color.r, base_color.g, base_color.b, fade))
			# Type indicator ring for submarines
			if c.type == "submarine":
				draw_arc(contact_pos, 9.0, 0, TAU, 16, Color(base_color.r, base_color.g, base_color.b, fade * 0.6), 1.0)
		else:
			draw_circle(contact_pos, 3.0, Color(base_color.r, base_color.g, base_color.b, 0.15))

	# Outer ring
	draw_arc(center, radius, 0, TAU, 128, Color(0.0, 0.8, 0.0, 0.8), 2.0)

	# HUD text
	var state_color = Color(0.0, 1.0, 0.0) if game_state == "patrol" else Color(1.0, 0.2, 0.2)
	draw_string(ThemeDB.fallback_font, Vector2(10, 20),
		"STATE: " + game_state.to_upper(), HORIZONTAL_ALIGNMENT_LEFT, -1, 14, state_color)
	draw_string(ThemeDB.fallback_font, Vector2(10, 40),
		"CONTACTS: %d" % contacts.size(), HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(0.0, 1.0, 0.0, 0.8))
	draw_string(ThemeDB.fallback_font, center + Vector2(0, -radius - 16),
		"BRG: %03d" % int(sweep_angle), HORIZONTAL_ALIGNMENT_CENTER, -1, 14, Color(0.0, 1.0, 0.0, 0.8))

	# Legend
	var legend_x = get_viewport().size.x - 160
	draw_string(ThemeDB.fallback_font, Vector2(legend_x, 20), "LEGEND", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(0.0, 0.8, 0.0))
	draw_circle(Vector2(legend_x + 6, 35), 4.0, TYPE_COLORS["surface"])
	draw_string(ThemeDB.fallback_font, Vector2(legend_x + 16, 40), "SURFACE", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(0.0, 0.8, 0.0))
	draw_circle(Vector2(legend_x + 6, 52), 4.0, TYPE_COLORS["submarine"])
	draw_string(ThemeDB.fallback_font, Vector2(legend_x + 16, 57), "SUBMARINE", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(0.8, 0.7, 0.0))
	draw_circle(Vector2(legend_x + 6, 69), 4.0, TYPE_COLORS["patrol_boat"])
	draw_string(ThemeDB.fallback_font, Vector2(legend_x + 16, 74), "PATROL BOAT", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(0.8, 0.4, 0.0))

func _on_message_received(topic: String, payload: String):
	if topic == "submarine/game/state":
		game_state = payload

	elif topic == "submarine/contacts/update":
		var data = JSON.parse_string(payload)
		if data == null:
			return
		var id = data.id
		var new_bearing = float(data.bearing)
		var new_distance = float(data.distance)

		if not contact_history.has(id):
			contact_history[id] = []

		if contacts.has(id):
			var old = contacts[id]
			if abs(old.bearing - new_bearing) > 0.5 or abs(old.distance - new_distance) > 0.005:
				contact_history[id].append({"bearing": old.bearing, "distance": old.distance})
				if contact_history[id].size() > MAX_HISTORY:
					contact_history[id].pop_front()

		if not contacts.has(id):
			contacts[id] = {"age": 0, "lit": false, "lit_timer": 0.0}

		contacts[id].bearing = new_bearing
		contacts[id].distance = new_distance
		contacts[id].strength = float(data.strength)
		contacts[id].type = data.type
		contacts[id].age = 0
