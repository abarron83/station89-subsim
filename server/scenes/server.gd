extends Node

var mqtt: Node

func _ready():
	mqtt = preload("res://scripts/mqtt_manager.gd").new()
	mqtt.name = "MQTT"
	add_child(mqtt)
	await get_tree().create_timer(1.0).timeout
	print("Server: Online, publishing every 3 seconds...")
	var timer = Timer.new()
	timer.wait_time = 3.0
	timer.autostart = true
	timer.timeout.connect(_publish_state)
	add_child(timer)

func _publish_state():
	mqtt.publish("submarine/game/state", "patrol")
	print("Server: Published state -> patrol")
