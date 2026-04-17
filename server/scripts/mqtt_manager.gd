extends Node

signal message_received(topic: String, payload: String)

var socket: StreamPeerTCP
var connected := false
var subscriptions: Array = []

var CLIENT_ID = "station89_client"
const BROKER_HOST = "127.0.0.1"
const BROKER_PORT = 1883

var _reconnect_timer: float = 0.0
const RECONNECT_INTERVAL = 3.0
var _ping_timer: float = 0.0
const PING_INTERVAL = 10.0

func _ready():
	_connect()

func _connect():
	socket = StreamPeerTCP.new()
	connected = false
	var err = socket.connect_to_host(BROKER_HOST, BROKER_PORT)
	if err != OK:
		print("MQTT: Connection error - ", err)
		return
	print("MQTT: Connecting to broker...")

func _process(delta):
	if socket == null:
		return

	socket.poll()
	var status = socket.get_status()

	if not connected:
		if status == StreamPeerTCP.STATUS_CONNECTED:
			_send_connect_packet()
		elif status == StreamPeerTCP.STATUS_ERROR or status == StreamPeerTCP.STATUS_NONE:
			_reconnect_timer += delta
			if _reconnect_timer >= RECONNECT_INTERVAL:
				_reconnect_timer = 0.0
				print("MQTT: Reconnecting...")
				_connect()
		return

	# Check for dropped connection
	if status != StreamPeerTCP.STATUS_CONNECTED:
		print("MQTT: Connection lost, reconnecting...")
		connected = false
		_connect()
		return

	# Keepalive ping
	_ping_timer += delta
	if _ping_timer >= PING_INTERVAL:
		_ping_timer = 0.0
		_send_ping()

	# Read incoming data
	var available = socket.get_available_bytes()
	if available > 0:
		var data = socket.get_data(available)
		if data[0] == OK:
			_parse_incoming(data[1])

func _send_connect_packet():
	var client_id = CLIENT_ID.to_utf8_buffer()
	var packet = PackedByteArray()
	packet.append(0x10)
	var remaining = 10 + 2 + client_id.size()
	packet.append(remaining)
	packet.append_array([0x00, 0x04, 0x4D, 0x51, 0x54, 0x54])
	packet.append(0x04)
	packet.append(0x02)
	packet.append_array([0x00, 0x3C])
	packet.append(0x00)
	packet.append(client_id.size())
	packet.append_array(client_id)
	socket.put_data(packet)
	print("MQTT: Connected as ", CLIENT_ID)
	connected = true
	# Resubscribe to all topics after connect
	for topic in subscriptions:
		_send_subscribe(topic)

func _send_ping():
	socket.put_data(PackedByteArray([0xC0, 0x00]))

func publish(topic: String, payload: String):
	if not connected:
		print("MQTT: Not connected, cannot publish")
		return
	var t = topic.to_utf8_buffer()
	var p = payload.to_utf8_buffer()
	var packet = PackedByteArray()
	packet.append(0x30)
	packet.append(2 + t.size() + p.size())
	packet.append(0x00)
	packet.append(t.size())
	packet.append_array(t)
	packet.append_array(p)
	socket.put_data(packet)

func subscribe(topic: String):
	if not subscriptions.has(topic):
		subscriptions.append(topic)
	if connected:
		_send_subscribe(topic)

func _send_subscribe(topic: String):
	var t = topic.to_utf8_buffer()
	var packet = PackedByteArray()
	packet.append(0x82)
	packet.append(2 + 2 + t.size() + 1)
	packet.append_array([0x00, 0x01])
	packet.append(0x00)
	packet.append(t.size())
	packet.append_array(t)
	packet.append(0x00)
	socket.put_data(packet)
	print("MQTT: Subscribed to ", topic)

func _parse_incoming(data: PackedByteArray):
	if data.size() == 0:
		return
	var msg_type = (data[0] & 0xF0) >> 4
	# CONNACK
	if msg_type == 2:
		print("MQTT: CONNACK received")
	# PUBLISH
	elif msg_type == 3:
		var topic_len = (data[2] << 8) | data[3]
		var topic = data.slice(4, 4 + topic_len).get_string_from_utf8()
		var payload = data.slice(4 + topic_len).get_string_from_utf8()
		print("MQTT: Received -> ", topic, " : ", payload)
		emit_signal("message_received", topic, payload)
	# PINGRESP
	elif msg_type == 13:
		print("MQTT: Ping OK")
