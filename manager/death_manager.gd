# =========================================================
# DEATH MANAGER
# =========================================================
# Gestisce la telemetria delle morti nel gioco (Analytics).
#
# Funzionalità principali:
# - Registra quando il giocatore muore.
# - Registra quando un nemico/entità muore.
# - Invia questi dati a un server remoto (API) tramite HTTP POST.
#
# SCOPO NARRATIVO:
# Dare l'impressione che le entità abbiano una coscienza persistente.
# TODO: Implementare in futuro creature che "ricordano" di essere state uccise in partite precedenti.

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
	# Configurazione iniziale
	# Aggiunge il nodo HTTPRequest alla scena per poter effettuare chiamate di rete.
	# Senza add_child(), il nodo non processerebbe la richiesta.
	
	# Fallback di sicurezza: se la traduzione manca (la chiave non ha %s), usiamo la concatenazione
	var msg = tr("death_manager_init")
	if "%s" in msg:
		print(msg % api_url)
	else:
		print(msg + ": " + api_url)
	add_child(http_request)
	http_request.request_completed.connect(_on_request_completed)

# =========================================================
# REGISTRAZIONE EVENTI
# =========================================================

func record_player_death():
	# Crea il payload JSON per la morte del giocatore
	var data = {
		"type": "player_death",
		"timestamp": Time.get_unix_time_from_system()
	}
	_send_request(data)
	print(tr("death_manager_log_player"))

func record_entity_death(entity_id: String):
	# Crea il payload JSON per la morte di un nemico
	if entity_id.is_empty():
		return
	var data = {
		"type": "entity_death",
		"entity_id": entity_id,
		"timestamp": Time.get_unix_time_from_system()
	}
	_send_request(data)
	print(tr("death_manager_log_entity") % entity_id)

# =========================================================
# GESTIONE HTTP
# =========================================================

func _send_request(data: Dictionary):
	# Prepara la richiesta POST
	var headers: PackedStringArray = ["Content-Type: application/json"]
	var body = JSON.stringify(data)
	
	# Invia la richiesta asincrona
	var error = http_request.request(api_url, headers, HTTPClient.METHOD_POST, body)
	if error != OK:
		push_error(tr("death_manager_http_error"))

# Callback chiamata quando il server risponde (o la richiesta va in timeout)
func _on_request_completed(_result, response_code, _headers, body):
	# Gestione della risposta
	# 200 = OK, 201 = Created (successo standard per POST)
	if response_code == 200 or response_code == 201:
		print(tr("death_manager_success"))
	else:
		var response_body = body.get_string_from_utf8()
		push_warning(tr("death_manager_fail") % [response_code, response_body])
