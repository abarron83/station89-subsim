extends Node

# Player submarine world position (center of the world for now)
var player_pos: Vector2 = Vector2(0, 0)
var max_sonar_range: float = 1000.0

var contacts: Dictionary = {}
var _spawn_timer: float = 0.0
const SPAWN_INTERVAL = 8.0
var _update_timer: float = 0.0
const UPDATE_INTERVAL = 0.5

var mqtt: Node

func init(mqtt_node: Node):
	mqtt = mqtt_node
	# Spawn two contacts immediately for testing
	_spawn_contact()
	_spawn_contact()

func _process(delta):
	_spawn_timer += delta
	if _spawn_timer >= SPAWN_INTERVAL:
		_spawn_timer = 0.0
		if contacts.size() < 5:
			_spawn_contact()

	# Move all contacts
	for id in contacts:
		var c = contacts[id]
		var heading_rad = deg_to_rad(c.heading)
		c.x += cos(heading_rad) * c.speed * delta
		c.y += sin(heading_rad) * c.speed * delta
		# Remove if out of range
		var dist = Vector2(c.x, c.y).distance_to(player_pos)
		if dist > max_sonar_range * 1.5:
			contacts.erase(id)
			print("Server: Contact lost - ", id)
			return

	# Publish updates
	_update_timer += delta
	if _update_timer >= UPDATE_INTERVAL:
		_update_timer = 0.0
		_publish_contacts()

func _spawn_contact():
	var id = "contact_%03d" % randi_range(1, 999)
	# Spawn at random position within sonar range
	var angle = randf() * TAU
	var distance = randf_range(300.0, 900.0)
	var types = ["surface", "surface", "surface", "submarine", "patrol_boat"]
	var type = types[randi() % types.size()]
	contacts[id] = {
		"id": id,
		"x": cos(angle) * distance,
		"y": sin(angle) * distance,
		"heading": randf() * 360.0,
		"speed": randf_range(5.0, 25.0),
		"type": type,
		"noise": randf_range(0.3, 1.0) if type != "submarine" else randf_range(0.1, 0.4)
	}
	print("Server: Contact spawned - ", id, " type:", type)

func _publish_contacts():
	for id in contacts:
		var c = contacts[id]
		# Calculate bearing and distance relative to player
		var relative = Vector2(c.x, c.y) - player_pos
		var bearing = fmod(rad_to_deg(atan2(relative.y, relative.x)) + 360.0, 360.0)
		var distance = relative.length() / max_sonar_range
		var strength = clamp(c.noise * (1.0 - distance), 0.0, 1.0)
		# Only publish if within sonar range
		if distance <= 1.0:
			var payload = JSON.stringify({
				"id": id,
				"bearing": snappedf(bearing, 0.1),
				"distance": snappedf(distance, 0.01),
				"strength": snappedf(strength, 0.01),
				"type": c.type
			})
			mqtt.publish("submarine/contacts/update", payload)
