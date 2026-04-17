extends Node

var mqtt: Node
var contact_manager: Node

func _ready():
	mqtt = preload("res://scripts/mqtt_manager.gd").new()
	mqtt.name = "MQTT"
	add_child(mqtt)
	await get_tree().create_timer(1.0).timeout
	print("Server: Online")
	# Start contact manager
	contact_manager = preload("res://scripts/contact_manager.gd").new()
	contact_manager.name = "ContactManager"
	add_child(contact_manager)
	contact_manager.init(mqtt)
	# Publish initial game state
	mqtt.publish("submarine/game/state", "patrol")
