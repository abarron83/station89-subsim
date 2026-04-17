extends Node

signal message_received(topic: String, payload: String)

var mqtt_client: TCPServer
var socket: StreamPeerTCP
var connected := false

const BROKER_HOST = "127.0.0.1"
const BROKER_PORT = 1883
var CLIENT_ID = "station89_server"

func _ready():
	connect_to_broker()

func connect_to_broker():
	socket = StreamPeerTCP.new()
	var err = socket.connect_to_host(BROKER_HOST, BROKER_PORT)
	if err == OK:
		print("MQTT: Connecting to broker...")
		await get_tree().create_timer(0.5).timeout
		socket.poll()
		_send_connect_packet()
	else:
		print("MQTT: Failed to connect - ", err)

func _send_connect_packet():
	var client_id = CLIENT_ID.to_utf8_buffer()
	var packet = PackedByteArray()
	# CONNECT fixed header
	packet.append(0x10)
	# Remaining length
	var remaining = 10 + 2 + client_id.size()
	packet.append(remaining)
	# Protocol name
	packet.append_array([0x00, 0x04, 0x4D, 0x51, 0x54, 0x54])
	# Protocol level (3.1.1)
	packet.append(0x04)
	# Connect flags (clean session)
	packet.append(0x02)
	# Keep alive (60s)
	packet.append_array([0x00, 0x3C])
	# Client ID
	packet.append(0x00)
	packet.append(client_id.size())
	packet.append_array(client_id)
	socket.put_data(packet)
	connected = true
	print("MQTT: Connected to broker")

func publish(topic: String, payload: String):
	if not connected:
		print("MQTT: Not connected")
		return
	var t = topic.to_utf8_buffer()
	var p = payload.to_utf8_buffer()
	var packet = PackedByteArray()
	# PUBLISH fixed header
	packet.append(0x30)
	# Remaining length
	packet.append(2 + t.size() + p.size())
	# Topic length + topic
	packet.append(0x00)
	packet.append(t.size())
	packet.append_array(t)
	# Payload
	packet.append_array(p)
	socket.put_data(packet)

func _process(_delta):
	if not connected:
		return
	socket.poll()
	if socket.get_status() != StreamPeerTCP.STATUS_CONNECTED:
		return
	var available = socket.get_available_bytes()
	if available > 0:
		print("MQTT: ", available, " bytes incoming")
		var data = socket.get_data(available)
		if data[0] == OK:
			_parse_incoming(data[1])
		else:
			print("MQTT: Read error - ", data[0])

func _parse_incoming(data: PackedByteArray):
	if data.size() == 0:
		return
	var msg_type = (data[0] & 0xF0) >> 4
	if msg_type == 3:
		# Parse topic length
		var topic_len = (data[2] << 8) | data[3]
		var topic = data.slice(4, 4 + topic_len).get_string_from_utf8()
		var payload = data.slice(4 + topic_len).get_string_from_utf8()
		print("MQTT: Received -> ", topic, " : ", payload)
		emit_signal("message_received", topic, payload)
