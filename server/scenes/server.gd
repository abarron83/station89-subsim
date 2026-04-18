extends Node

var mqtt: Node
var contact_manager: Node

func _ready():
	mqtt = preload("res://scripts/mqtt_manager.gd").new()
	mqtt.name = "MQTT"
	mqtt.message_received.connect(_on_message_received)
	add_child(mqtt)
	await get_tree().create_timer(1.0).timeout
	print("Server: Online")
	mqtt.subscribe("submarine/captain/command")
	contact_manager = preload("res://scripts/contact_manager.gd").new()
	contact_manager.name = "ContactManager"
	add_child(contact_manager)
	contact_manager.init(mqtt)
	mqtt.publish("submarine/game/state", "patrol")
	print("Server: Listening for Captain orders")

func _on_message_received(topic: String, payload: String):
	if topic == "submarine/captain/command":
		print("Server: Captain order received -> ", payload)
		mqtt.publish("submarine/game/state", payload)
