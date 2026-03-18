class_name DeathManager
extends Node

var game: Game

# -------------------------------------------------------------------
# !!! IMPORTANTE !!!
# SOSTITUISCI QUESTO URL con l'endpoint della tua API online.
# Per testare, puoi usare un servizio come https://webhook.site/
# e incollare qui l'URL unico che ti viene fornito.
var api_url = "https://webhook.site/adf018ca-d0e3-4068-82ca-9259f5b9336a"
# -------------------------------------------------------------------

@onready var http_request = HTTPRequest.new()

func _ready():
	print("[DeathManager] Inizializzato. Invio dati a: ", api_url)
	add_child(http_request)
	http_request.request_completed.connect(_on_request_completed)

# Registra la morte del giocatore
func record_player_death():
	var data = {
		"type": "player_death",
		"timestamp": Time.get_unix_time_from_system()
	}
	_send_request(data)
	print(tr("death_manager_log_player"))

# Registra la morte di un'entità
func record_entity_death(entity_id: String):
	if entity_id.is_empty():
		return
	var data = {
		"type": "entity_death",
		"entity_id": entity_id,
		"timestamp": Time.get_unix_time_from_system()
	}
	_send_request(data)
	print(tr("death_manager_log_entity") % entity_id)

func _send_request(data: Dictionary):
	var headers: PackedStringArray = ["Content-Type: application/json"]
	var body = JSON.stringify(data)
	var error = http_request.request(api_url, headers, HTTPClient.METHOD_POST, body)
	if error != OK:
		push_error(tr("death_manager_http_error"))

func _on_request_completed(_result, response_code, _headers, body):
	if response_code == 200 or response_code == 201:
		print(tr("death_manager_success"))
	else:
		var response_body = body.get_string_from_utf8()
		push_warning(tr("death_manager_fail") % [response_code, response_body])
