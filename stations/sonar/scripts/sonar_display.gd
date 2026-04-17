extends Node2D

var mqtt: Node

const BROKER_HOST = "127.0.0.1"
const BROKER_PORT = 1883
const CLIENT_ID = "station89_sonar"
const SUBSCRIBE_TOPIC = "submarine/game/state"

func _ready():
	mqtt = preload("res://scripts/mqtt_manager.gd").new()
	mqtt.name = "MQTT"
	mqtt.CLIENT_ID = CLIENT_ID
	mqtt.message_received.connect(_on_message_received)
	add_child(mqtt)
	await get_tree().create_timer(1.0).timeout
	print("Sonar: Connected, subscribing to game state...")
	_subscribe(SUBSCRIBE_TOPIC)

func _on_message_received(topic: String, payload: String):
	print("Sonar: Message received -> ", topic, " : ", payload)
	_on_game_state(payload)

func _subscribe(topic: String):
	var t = topic.to_utf8_buffer()
	var packet = PackedByteArray()
	# SUBSCRIBE fixed header
	packet.append(0x82)
	# Remaining length
	packet.append(2 + 2 + t.size() + 1)
	# Packet ID
	packet.append_array([0x00, 0x01])
	# Topic length + topic
	packet.append(0x00)
	packet.append(t.size())
	packet.append_array(t)
	# QoS 0
	packet.append(0x00)
	mqtt.socket.put_data(packet)
	print("Sonar: Subscribed to ", topic)

func _on_game_state(state: String):
	print("Sonar: Game state received -> ", state)
	# This is where we'll update the display
	queue_redraw()
