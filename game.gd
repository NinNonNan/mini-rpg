class_name Game
extends Control

# ==============================================================================
# CORE CONTROLLER DEL GIOCO
# Gestisce il loop principale, la UI, lo stato del giocatore e i manager.
# ==============================================================================

# --- Riferimenti ai Nodi dell'Interfaccia Utente (UI) ---
@onready var meteo_stats = $UI/VBC_Main/MC_Meteo/PC/HBC/MeteoText
@onready var enemy_stats_box = $UI/VBC_Main/MC_Enemy/PC
@onready var enemy_icon = $UI/VBC_Main/MC_Enemy/PC/HBC/Icon
@onready var enemy_stats = $UI/VBC_Main/MC_Enemy/PC/HBC/StatsText
@onready var text = $UI/VBC_Main/MC_Story/PC/HBC/StoryText
@onready var player_icon = $UI/VBC_Main/MC_Player/PC/HBC/Icon
@onready var player_box_container = $UI/VBC_Main/MC_Player
@onready var player_stats = $UI/VBC_Main/MC_Player/PC/HBC/StatsText
@onready var b1 = $UI/VBC_Main/VBC_Button/MC1/Choice1
@onready var b2 = $UI/VBC_Main/VBC_Button/MC2/Choice2
@onready var b3 = $UI/VBC_Main/VBC_Button/MC3/Choice3

# --- Quick Time Event (QTE) ---
@onready var qte = $Manager/QTE

# --- Manager di Sistema ---
# Riferimenti ai sottosistemi logici (Combattimento, Dialogo, Oggetti, ecc.)
@onready var combat_manager = $Manager/Combat as CombatManager
@onready var dialogue_manager = $Manager/Dialogue as DialogueManager
@onready var empathy_manager = $Manager/Empathy as EmpathyManager
@onready var item_manager = $Manager/Item
@onready var special_manager = $Manager/Special as SpecialManager
@onready var growth_manager = $Manager/Growth as GrowthManager
@onready var death_manager = $Manager/Death as DeathManager
@onready var meteo_manager = $Manager/Meteo as MeteoManager
@onready var rune_manager = $Manager/Rune
@onready var stats_manager = $Manager/Stats # Richiede script StatsManager
@onready var save_manager = $Manager/Save as SaveManager

# --- Stato del Gioco ---
var player_energy: Dictionary = {}
var player_max_energy: Dictionary = {}

# --- Accessori di Propriet├á (Getter/Setter) ---
# --- Compatibilit├á (Bridge) ---
# Queste propriet├á permettono agli altri script di usare game.health 
# mentre noi usiamo il sistema dinamico player_energy sotto il cofano.
var health: int:
	get: return player_energy.get("life", 0)
	set(value): modify_player_energy("life", value - player_energy.get("life", 0))
var max_health: int:
	get: return player_max_energy.get("life", 0)
	set(value): player_max_energy["life"] = value

var mana: int:
	get: return player_energy.get("magic", 0)
	set(value): modify_player_energy("magic", value - player_energy.get("magic", 0))
var max_mana: int:
	get: return player_max_energy.get("magic", 0)
	set(value): player_max_energy["magic"] = value

var mood: int:
	get: return player_energy.get("mood", 0)
	set(value): modify_player_energy("mood", value - player_energy.get("mood", 0))
var max_mood: int:
	get: return player_max_energy.get("mood", 0)
	set(value): player_max_energy["mood"] = value

# --- Variabili di Flusso ---
var current_entity_pronoun: String = ""
var current_victory_scene: String = ""
var current_entity_id: String = ""
var was_in_combat: bool = false
var use_visual_health: bool = true

# --- Database ---
var story: Dictionary = {}
var story_data: Dictionary = {}
var entity_data: Dictionary = {}
var damage_types_data: Dictionary = {}
var current_scene: String = "start"

# --- Risorse Condivise ---
var custom_font = load("res://fonts/freecam v2.ttf")

# --- Inizializzazione ---
func _ready():
	# Setup Pulsante Long Press per Configurazione (Sopra le stat del player)
	if player_box_container:
		var stats_btn = LongPressButton.new()
		stats_btn.name = "StatsConfigButton"
		stats_btn.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		stats_btn.focus_mode = Control.FOCUS_NONE
		stats_btn.mouse_filter = Control.MOUSE_FILTER_STOP
		stats_btn.long_pressed.connect(func():
			Input.vibrate_handheld(100)
			if stats_manager:
				stats_manager.open_config_menu()
		)
		player_box_container.add_child(stats_btn)

	# Controlli nodi
	if not text:
		push_error(tr("error_node_storytext_not_found"))
	if not player_stats:
		push_error(tr("error_node_playerstats_not_found"))
	if not enemy_stats_box:
		push_warning(tr("warning_node_enemybox_not_found"))
	if not special_manager:
		push_error(tr("error_node_special_not_found"))
	if not growth_manager:
		push_error(tr("error_node_growth_not_found"))
	if not death_manager:
		push_error(tr("error_node_death_not_found"))
	if not meteo_manager:
		push_error(tr("error_node_meteo_not_found"))
	if not rune_manager:
		push_error(tr("error_rune_manager_node_missing"))
	if not stats_manager:
		push_warning(tr("warn_stats_manager_missing"))
	if not save_manager:
		push_warning("SaveManager non trovato in $Manager/Save")

	# Impostazioni grafica
	#text.size_flags_vertical = Control.SIZE_EXPAND | Control.SIZE_FILL
	for btn in [b1, b2, b3]:
		btn.size_flags_horizontal = Control.SIZE_EXPAND | Control.SIZE_FILL
		# Assicura che i pulsanti si espandano correttamente nel layout

	# Caricamento dati JSON (storia, oggetti) e localizzazione
	_load_story()
	_load_translations()

	# Iniezione Game nei manager
	# Fornisce ai manager un riferimento a questo script principale per callback e accesso ai dati
	for mgr in [qte, combat_manager, item_manager, dialogue_manager, empathy_manager, special_manager, growth_manager, death_manager, meteo_manager, stats_manager, save_manager, rune_manager]:
		if mgr:
			mgr.game = self
	
	# Debug check per item_manager
	if not item_manager:
		push_error("ERRORE CRITICO: ItemManager non è stato inizializzato correttamente in Game.gd!")

	# Connessione RuneManager
	if rune_manager:
		rune_manager.request_target_selection.connect(_on_rune_data_received)
		rune_manager.combo_finished.connect(_on_rune_combo_finished)

	# Connessione DialogueManager
	if dialogue_manager:
		dialogue_manager.text_requested.connect(func(t): text.text = t)
		dialogue_manager.choices_requested.connect(_on_dialogue_choices_requested)
		# Aggiorna le statistiche quando cambiano durante un dialogo (es. Umore)
		dialogue_manager.stats_updated.connect(update_stats)
		dialogue_manager.dialogue_finished.connect(show_scene)
		dialogue_manager.dialogue_failed.connect(_start_prepared_combat)

	# Inizializzazione DeathManager
	if death_manager:
		death_manager.init_ui_effects()
		death_manager.retry_requested.connect(_restart_game)
	
	# Tentativo di caricamento partita
	if save_manager:
		save_manager.load_game()

	
	# Avvio scena iniziale
	show_scene(current_scene)

# --- Caricamento JSON ---
func _load_story():
	# ATTENZIONE: I percorsi dei file JSON sono fissi in res://data/.
	# NON MODIFICARE questi percorsi a meno di una specifica richiesta.
	var json_data = StoryLoader.load_json_file("res://data/story.json")
	if json_data == null:
		text.text = tr("error_story_load_short")
		return
	story_data = json_data
	story = json_data.get("scenes", {})
	entity_data = json_data.get("entities", {})
	
	# Caricamento definizioni (energy_types, damage_types, weather, spells)
	# ATTENZIONE: Percorso fisso in res://data/. NON MODIFICARE.
	var definitions_json = StoryLoader.load_json_file("res://data/definitions.json")
	if definitions_json != null:
		# Uniamo le definizioni in story_data per mantenere la compatibilit├á
		story_data.merge(definitions_json, true)
		damage_types_data = definitions_json.get("damage_types", {})
	else:
		push_error(tr("error_definitions_load"))

	if item_manager:
		item_manager.load_items()
	
	# Carica dati entit├á (player e nemici) da file separato
	var entities_json = StoryLoader.load_json_file("res://data/entities.json")
	var player_data = {}

	if entities_json != null:
		entity_data = entities_json.get("entities", {})
		if entities_json.has("player"):
			player_data = entities_json.get("player", {})
			# Aggiorna story_data con i dati del player per la UI
			story_data["player"] = player_data
	else:
		push_error("Errore caricamento entities.json!")
		return

	if player_data.is_empty():
		player_data = json_data.get("player", {})

	if player_data.has("energy"):
		player_energy.clear()
		player_max_energy.clear()
		for stat in player_data.get("energy", []):
			var type_id = stat.get("type")
			if type_id:
				var value = int(stat.get("value", 0))
				player_max_energy[type_id] = value
				player_energy[type_id] = value
	if player_icon and player_data.has("icon") and player_data["icon"] != "":
		player_icon.texture = load(player_data["icon"])

func _load_translations(lang_code: String = "it"):
	# ATTENZIONE: Percorso fisso per le traduzioni in res://data/. NON MODIFICARE.
	var file_path = "res://data/%s.json" % lang_code
	if not FileAccess.file_exists(file_path):
		# Usa concatenazione per evitare crash se tr() fallisce (restituendo la chiave senza %s)
		push_error(tr("error_translation_file_not_found") + ": " + file_path)
		return
	var file = FileAccess.open(file_path, FileAccess.READ)
	var content = file.get_as_text()
	file.close()
	var json_data = JSON.parse_string(content)
	if json_data != null:
		var translation = Translation.new()
		translation.locale = lang_code
		for key in json_data:
			translation.add_message(key, json_data[key])
		TranslationServer.add_translation(translation)
		TranslationServer.set_locale(lang_code)

# --- Gestione Statistiche Giocatore ---
func get_player_energy_value(type_id: String) -> int:
	# Restituisce il valore corrente di una statistica (es. "life", "magic")
	return player_energy.get(type_id, 0)

func modify_player_energy(type_id: String, amount: int):
	# Modifica una statistica del giocatore e gestisce i limiti (min/max).
	if not player_energy.has(type_id):
		return

	var current_value = player_energy[type_id]
	var max_value = player_max_energy.get(type_id, 0)
	var new_value = current_value + amount

	if type_id == "life":
		# La vita pu├▓ scendere sotto lo 0 per mostrare il danno in eccesso
		# Se scende a 0 o meno, attiva il Game Over.
		player_energy[type_id] = int(min(new_value, max_value))
		if player_energy.get("life", 0) <= 0:
			if death_manager: death_manager.handle_game_over()
	else:
		# Le altre statistiche sono bloccate tra 0 e il loro massimo.
		player_energy[type_id] = clampi(new_value, 0, max_value)

	update_stats()

func get_energy_string(type_id: String, amount: int, max_amount: int = -1) -> String:
	# Formatta una stringa per visualizzare una statistica (Icona + Valore).
	var icon = ""
	var abbr = ""
	if story_data.has("energy_types") and story_data["energy_types"].has(type_id):
		var type_data = story_data["energy_types"][type_id]
		icon = type_data.get("icon", "")
		abbr = type_data.get("abbreviation", "")

	var value_str = str(amount)
	if max_amount >= 0:
		value_str = "%d/%d" % [amount, max_amount]
	
	# Usa la rappresentazione visiva (icona) se abilitata, altrimenti testo.
	if use_visual_health and icon:
		if abbr:
			return "%s: %s %s" % [abbr, icon, value_str]
		return "%s %s" % [icon, value_str]
	else:
		var label = abbr if abbr else tr(story_data.get("energy_types", {}).get(type_id, {}).get("name", type_id))
		return "%s: %s" % [label, value_str]

func get_damage_type_icon(type_id: String) -> String:
	# Recupera l'icona associata a un tipo di danno (es. Fuoco, Ghiaccio).
	if damage_types_data.has(type_id):
		return damage_types_data[type_id].get("icon", "")
	return ""

func disable_choices():
	for btn in [b1, b2, b3]:
		btn.disabled = true

func enable_choices():
	for btn in [b1, b2, b3]:
		btn.disabled = false

func update_stats():
	# Aggiorna tutte le etichette dell'interfaccia utente (UI) con i valori correnti.
	var inventory_names = []
	if item_manager:
		for item_id in item_manager.inventory:
			inventory_names.append(item_manager.get_display_name(item_id))
	var inv_str = tr("inventory_empty")
	if inventory_names.size() > 0:
		inv_str = ", ".join(inventory_names)

	# Aggiorna UI nemico
	var entity_text = ""
	if combat_manager and combat_manager.current_entity_health > 0:
		entity_text = tr("stats_enemy_hp") % get_health_string(combat_manager.current_entity_health)
	elif dialogue_manager and dialogue_manager.is_active:
		pass
	elif current_entity_id != "" and empathy_manager and empathy_manager.is_known:
		var entity = entity_data.get(current_entity_id, {})
		var hp = 0
		if entity.has("energy"):
			for stat in entity["energy"]:
				if stat.get("type") == "life":
					hp = int(stat.get("value", 0))
		entity_text = tr("stats_enemy_hp") % get_health_string(hp)
	
	# Aggiorna UI giocatore
	if player_stats:
		var stats_lines: Array[String] = []
		var player_energy_definitions: Array = story_data.get("player", {}).get("energy", [])

		# Ordina le statistiche in base a 'display_order'
		player_energy_definitions.sort_custom(func(a, b): return a.get("display_order", 99) < b.get("display_order", 99))

		# Prendi solo le prime 3 da visualizzare
		var stats_to_display = player_energy_definitions.slice(0, 3)

		for stat_def in stats_to_display:
			var type_id = stat_def.get("type")
			if type_id:
				var current_value = get_player_energy_value(type_id)
				var max_value = player_max_energy.get(type_id, 0)
				stats_lines.append(get_energy_string(type_id, current_value, max_value))
		
		# Aggiungi l'inventario
		var inv_line: String
		if use_visual_health:
			inv_line = "­ƒÄÆ %s" % inv_str
		else:
			inv_line = "%s %s" % [tr("stats_inventory_prefix"), inv_str]
		stats_lines.append(inv_line)

		player_stats.text = "\n".join(stats_lines)

	if enemy_stats_box and enemy_stats:
		enemy_stats.text = entity_text
		if enemy_icon:
			var icon_path = entity_data.get(current_entity_id, {}).get("icon", "")
			if icon_path != "":
				enemy_icon.texture = load(icon_path)
			else:
				enemy_icon.texture = null
		enemy_stats_box.visible = true

# Funzione deprecata ma mantenuta per compatibilit├á interna
func get_health_string(amount: int) -> String:
	return get_energy_string("life", amount)

# --- Gestione Scene e Scelte ---
func show_scene(scene_name):
	# Carica e visualizza una nuova scena dal dizionario 'story'.
	# Rileva la sconfitta di un'entit├á in combattimento.
	# Se stavamo combattendo e ora passiamo alla scena di vittoria, registra la morte.
	if was_in_combat and current_entity_id != "" and scene_name == current_victory_scene:
		if death_manager: death_manager.record_entity_death(current_entity_id)

	if scene_name != current_scene:
		current_entity_id = ""
		if empathy_manager: empathy_manager.reset()
	was_in_combat = false # Resetta il flag ad ogni cambio di scena
	current_scene = scene_name
	if combat_manager: combat_manager.current_entity_health = 0
	# Aggiorna il meteo al cambio di scena
	if meteo_manager: meteo_manager.roll_weather()
	
	# Auto-save
	if save_manager:
		save_manager.save_game()
	
	if dialogue_manager: dialogue_manager.reset()
	var scene = story[scene_name]
	# Imposta il testo principale usando le traduzioni
	text.text = tr(scene["text"])
	update_stats()

	var buttons = [b1, b2, b3]
	var choices = scene.get("choices", [])
	for i in range(buttons.size()):
		if i < choices.size():
			# Configura il pulsante per la scelta
			buttons[i].text = tr(choices[i]["text"])
			buttons[i].show()
			_clear_signals(buttons[i])
			buttons[i].pressed.connect(func(): handle_choice(choices[i]))
		else:
			buttons[i].hide()

func handle_choice(choice):
	# Esegue la logica associata a una scelta del giocatore.
	# Aggiunge un feedback aptico (vibrazione) alla pressione di un pulsante di scelta.
	Input.vibrate_handheld(50)

	if choice.has("action"):
		match choice["action"]:
			"pickup":
				# Raccoglie un oggetto
				var item_id = choice.get("item_id", "")
				if item_manager and item_manager.add_item(item_id):
					text.text = tr("item_picked_up") % [item_manager.get_display_name(item_id)]
					update_stats()
			"qte":
				# Avvia un Quick Time Event
				start_qte_event()
			"combat":
				# Prepara e avvia il combattimento
				current_entity_id = choice.get("entity_id", "")
				current_victory_scene = choice.get("victory_scene", "")
				_start_prepared_combat()
			"dialogue":
				# Prepara e avvia il dialogo
				current_entity_id = choice.get("entity_id", "")
				current_victory_scene = choice.get("victory_scene", "")
				if entity_data.has(current_entity_id):
					current_entity_pronoun = entity_data[current_entity_id].get("pronoun", "")
				_start_prepared_dialogue()
			"runes":
				# Avvia il minigioco delle rune
				if rune_manager:
					rune_manager.start_rune_casting()
	if choice.has("next"):
		show_scene(choice["next"])

func start_qte_event(message_key: String = "qte_start_default", context: String = ""):
	# Avvia l'interfaccia del QTE tramite il relativo manager
	if qte:
		qte.start_event(message_key, context)

func start_growth_menu(victory_scene: String):
	# Aggiorna la scena di destinazione e delega l'apertura al GrowthManager
	current_victory_scene = victory_scene
	if growth_manager:
		growth_manager.open_growth_menu(story_data, player_energy, player_max_energy)

# --- Preparazione Combattimento & Dialogo ---
func _start_prepared_combat():
	if combat_manager:
		was_in_combat = true
		combat_manager.start_combat(current_entity_id, current_victory_scene)

func _start_prepared_dialogue():
	if dialogue_manager:
		was_in_combat = false # Assicura che il dialogo non venga conteggiato come combattimento
		dialogue_manager.start_dialogue(current_entity_id, current_entity_pronoun, 0, current_victory_scene)

func _on_dialogue_choices_requested(choices):
	# Callback dal DialogueManager per visualizzare le opzioni di dialogo sui pulsanti principali.
	var buttons = [b1, b2, b3]
	for i in range(buttons.size()):
		if i < choices.size():
			buttons[i].text = tr(choices[i]["text"])
			buttons[i].show()
			_clear_signals(buttons[i])
			buttons[i].pressed.connect(func(): dialogue_manager.handle_choice(choices[i]["action"]))
		else:
			buttons[i].hide()

# --- Gestione Sistema Rune ---
func _on_rune_data_received(spell_data: Dictionary):
	if was_in_combat:
		return
	
	if rune_manager:
		rune_manager.resolve_world_spell(spell_data)

func _on_rune_combo_finished(total_spells):
	if total_spells > 0:
		text.text += tr("rune_combo_end_msg") % total_spells

func _restart_game():
	# Ripristina lo stato del giocatore per una nuova partita.
	if item_manager:
		item_manager.reset()
	
	# Ricarica i dati originali dal JSON per assicurare un reset pulito delle stats
	_load_story()

	# Rimuovi effetti visivi morte
	if death_manager: death_manager.clear_death_effects()

	if growth_manager and growth_manager.growth_overlay:
		growth_manager.growth_overlay.queue_free()
		growth_manager.growth_overlay = null

	show_scene("start")
func _trigger_haptic():
	# Feedback tattile universale (funziona solo su mobile)
	Input.vibrate_handheld(50)

func _clear_signals(button: Button):
	# Rimuove tutte le connessioni esistenti dai pulsanti per evitare doppi click o azioni errate.
	for conn in button.pressed.get_connections():
		button.pressed.disconnect(conn.callable)
	
	# Riconnette il feedback aptico ogni volta che il pulsante viene pulito/preparato
	if not button.pressed.is_connected(_trigger_haptic):
		button.pressed.connect(_trigger_haptic)
