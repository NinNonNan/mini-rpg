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

signal retry_requested

var game: Game

var grayscale_material: ShaderMaterial
var death_overlay: ColorRect

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

func init_ui_effects():
	# 1. Shader Grayscale per l'icona
	var shader = Shader.new()
	shader.code = """
		shader_type canvas_item;
		void fragment() {
			vec4 tex_color = texture(TEXTURE, UV);
			float gray = dot(tex_color.rgb, vec3(0.299, 0.587, 0.114));
			COLOR = vec4(vec3(gray), tex_color.a);
		}
	"""
	grayscale_material = ShaderMaterial.new()
	grayscale_material.shader = shader

	# 2. Overlay semitrasparente per il box giocatore
	death_overlay = ColorRect.new()
	death_overlay.color = Color(0, 0, 0, 0.85) # Sfondo scuro
	death_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	death_overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	death_overlay.gui_input.connect(func(event):
		if event is InputEventMouseButton and event.pressed:
			retry_requested.emit()
	)
	death_overlay.hide()
	
	var label = Label.new()
	label.name = "DeathLabel"
	label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.add_theme_color_override("font_color", Color.RED)
	label.add_theme_font_size_override("font_size", 64)

	if game and game.custom_font:
		label.add_theme_font_override("font", game.custom_font)

	death_overlay.add_child(label)
	game.add_child(death_overlay)

func handle_game_over():
	record_player_death()
	game.text.text = tr("game_over_text")
	game.enable_choices()
	if game.combat_manager: game.combat_manager.current_entity_health = 0
	if game.dialogue_manager: game.dialogue_manager.reset()
	
	game.b1.text = tr("game_over_choice")
	game.b1.show()
	game._clear_signals(game.b1)
	game.b1.pressed.connect(func(): retry_requested.emit())
	game.b2.hide()
	game.b3.hide()

	if game.player_icon: game.player_icon.material = grayscale_material
	if game.player_stats: game.player_stats.material = grayscale_material
	if death_overlay:
		death_overlay.get_node("DeathLabel").text = tr("game_over_text")
		death_overlay.modulate.a = 0.0
		death_overlay.show()
		var tween = game.create_tween()
		tween.tween_property(death_overlay, "modulate:a", 1.0, 2.0)

func clear_death_effects():
	if game.player_icon: game.player_icon.material = null
	if game.player_stats: game.player_stats.material = null
	if death_overlay: death_overlay.hide()

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
