extends Node2D

var mqtt: Node
const CLIENT_ID = "station89_sonar"
const SUBSCRIBE_TOPIC = "submarine/game/state"

# Sonar sweep state
var sweep_angle: float = 0.0
var sweep_speed: float = 90.0  # degrees per second
var contacts: Array = []        # [{angle, distance, age}]
var game_state: String = "patrol"

# Display settings
var center: Vector2
var radius: float

func _ready():
	center = Vector2(get_viewport().size) / 2
	radius = min(center.x, center.y) * 0.85
	mqtt = preload("res://scripts/mqtt_manager.gd").new()
	mqtt.name = "MQTT"
	mqtt.CLIENT_ID = CLIENT_ID
	mqtt.message_received.connect(_on_message_received)
	add_child(mqtt)
	await get_tree().create_timer(1.0).timeout
	print("Sonar: Online")
	_subscribe(SUBSCRIBE_TOPIC)
	# Spawn a fake contact for testing
	contacts.append({"angle": 45.0, "distance": 0.6, "age": 0.0})
	contacts.append({"angle": 210.0, "distance": 0.35, "age": 0.0})

func _process(delta):
	sweep_angle += sweep_speed * delta
	if sweep_angle >= 360.0:
		sweep_angle -= 360.0
	# Age out contacts older than 4 seconds
	for c in contacts:
		c.age += delta
	contacts = contacts.filter(func(c): return c.age < 4.0)
	queue_redraw()

func _draw():
	# Background
	draw_rect(Rect2(Vector2.ZERO, get_viewport().size), Color(0.02, 0.05, 0.02))
	# Range rings
	for i in range(1, 5):
		var r = radius * (i / 4.0)
		draw_arc(center, r, 0, TAU, 64, Color(0.0, 0.3, 0.0, 0.5), 1.0)
	# Crosshairs
	draw_line(center + Vector2(-radius, 0), center + Vector2(radius, 0), Color(0.0, 0.3, 0.0, 0.4), 1.0)
	draw_line(center + Vector2(0, -radius), center + Vector2(0, radius), Color(0.0, 0.3, 0.0, 0.4), 1.0)
	# Sweep fill (trailing glow)
	for i in range(60):
		var trail_angle = deg_to_rad(sweep_angle - i * 1.2)
		var alpha = (1.0 - i / 60.0) * 0.18
		var end = center + Vector2(cos(trail_angle), sin(trail_angle)) * radius
		draw_line(center, end, Color(0.0, 1.0, 0.0, alpha), 2.0)
	# Sweep line
	var sweep_rad = deg_to_rad(sweep_angle)
	var sweep_end = center + Vector2(cos(sweep_rad), sin(sweep_rad)) * radius
	draw_line(center, sweep_end, Color(0.0, 1.0, 0.2, 0.9), 2.0)
	# Contacts
	for c in contacts:
		var contact_rad = deg_to_rad(c.angle)
		var contact_pos = center + Vector2(cos(contact_rad), sin(contact_rad)) * radius * c.distance
		var fade = 1.0 - (c.age / 4.0)
		draw_circle(contact_pos, 5.0, Color(0.0, 1.0, 0.0, fade))
		draw_arc(contact_pos, 8.0, 0, TAU, 16, Color(0.0, 1.0, 0.0, fade * 0.5), 1.0)
	# Outer ring
	draw_arc(center, radius, 0, TAU, 128, Color(0.0, 0.8, 0.0, 0.8), 2.0)
	# Bearing label
	draw_string(ThemeDB.fallback_font, center + Vector2(0, -radius - 16), 
		"BRG: %03d" % int(sweep_angle), HORIZONTAL_ALIGNMENT_CENTER, -1, 14, Color(0.0, 1.0, 0.0, 0.8))
	# Game state indicator
	var state_color = Color(0.0, 1.0, 0.0) if game_state == "patrol" else Color(1.0, 0.2, 0.2)
	draw_string(ThemeDB.fallback_font, Vector2(10, 20), 
		"STATE: " + game_state.to_upper(), HORIZONTAL_ALIGNMENT_LEFT, -1, 14, state_color)

func _on_message_received(topic: String, payload: String):
	if topic == "submarine/game/state":
		game_state = payload
		print("Sonar: Game state -> ", game_state)

func _subscribe(topic: String):
	var t = topic.to_utf8_buffer()
	var packet = PackedByteArray()
	packet.append(0x82)
	packet.append(2 + 2 + t.size() + 1)
	packet.append_array([0x00, 0x01])
	packet.append(0x00)
	packet.append(t.size())
	packet.append_array(t)
	packet.append(0x00)
	mqtt.socket.put_data(packet)
	print("Sonar: Subscribed to ", topic)
