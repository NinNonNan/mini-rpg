class_name Game
extends Control

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

# --- QTE ---
@onready var qte = $Manager/QTE

# --- Manager di Sistema ---
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

# --- Stato del Gioco ---
var player_energy: Dictionary = {}
var player_max_energy: Dictionary = {}

# --- Equipaggiamento ---
var equipment: Dictionary = {} # Mappa slot_id -> item_id
var equipment_slots: Array[String] = ["Mano Destra", "Mano Sinistra", "Corpo", "Testa", "Accessorio"]

# --- Compatibilità (Bridge) ---
# Queste proprietà permettono agli altri script di usare game.health 
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

var inventory: Array[String] = []
var current_entity_pronoun: String = ""
var current_victory_scene: String = ""
var current_entity_id: String = ""
var was_in_combat: bool = false # Aggiunto per tracciare la vittoria in combattimento
var qte_power_multiplier: float = 0.2 # Moltiplicatore per la velocità del QTE

var qte_context: String = "" # Contesto per sapere perché è stato avviato il QTE
signal target_clicked(target_type)
var use_visual_health: bool = true
var grayscale_material: ShaderMaterial
var death_overlay: ColorRect

# --- Database ---
var story: Dictionary = {}
var story_data: Dictionary = {}
var item_data: Dictionary = {}
var entity_data: Dictionary = {}
var damage_types_data: Dictionary = {}
var current_scene: String = "start"

func _ready():
	# QTE
	if qte:
		qte.qte_finished.connect(_on_qte_finished)
	
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
		push_error("ERRORE: Nodo RuneManager non trovato in $Manager/Rune")
	if not stats_manager:
		push_warning("ATTENZIONE: StatsManager non trovato in $Manager/Stats. Aggiungi il nodo per abilitare il menu.")

	# Impostazioni grafica
	#text.size_flags_vertical = Control.SIZE_EXPAND | Control.SIZE_FILL
	for btn in [b1, b2, b3]:
		btn.size_flags_horizontal = Control.SIZE_EXPAND | Control.SIZE_FILL

	# Caricamento dati e traduzioni
	_load_story()
	_load_translations()

	# Iniezione Game nei manager
	for mgr in [combat_manager, item_manager, dialogue_manager, empathy_manager, special_manager, growth_manager, death_manager, meteo_manager, stats_manager]:
		if mgr:
			mgr.game = self

	# Connessione RuneManager
	if rune_manager:
		rune_manager.request_target_selection.connect(_on_rune_data_received)
		rune_manager.combo_finished.connect(_on_rune_combo_finished)
		
		# Fix layout: Forza il posizionamento al centro dello schermo
		if rune_manager is Control:
			rune_manager.top_level = true
			rune_manager.set_anchors_and_offsets_preset(Control.PRESET_CENTER)

	# Connessione DialogueManager
	if dialogue_manager:
		dialogue_manager.text_requested.connect(func(t): text.text = t)
		dialogue_manager.choices_requested.connect(_on_dialogue_choices_requested)
		dialogue_manager.stats_updated.connect(update_stats)
		dialogue_manager.dialogue_finished.connect(show_scene)
		dialogue_manager.dialogue_failed.connect(_start_prepared_combat)

	# Inizializza effetti grafici per la morte
	# !!! NON RIMUOVERE !!! Serve per visualizzare la morte (grigio + overlay)
	_init_death_effects()

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
		# Uniamo le definizioni in story_data per mantenere la compatibilità
		story_data.merge(definitions_json, true)
		damage_types_data = definitions_json.get("damage_types", {})
	else:
		push_error(tr("error_definitions_load"))

	# Caricamento items separato
	var items_json = StoryLoader.load_json_file("res://data/items.json")
	if items_json != null:
		item_data = items_json
	
	var player_data = json_data.get("player", {})
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

# --- Stats ---
func get_player_energy_value(type_id: String) -> int:
	return player_energy.get(type_id, 0)

# Calcola la % di schivata basata sulle energie "fisiche" attuali.
# -------------------------------------------------------------------------
# MECCANICA DI SCHIVATA:
# La probabilità di evitare un attacco dipende dalla somma delle energie
# che hanno la proprietà "bonus": "evasion" definita in definitions.json.
# (Es. Life e Chakra).
#
# Formula: (Somma Energie Evasione Attuali) * 2%
# -------------------------------------------------------------------------
func get_player_evasion() -> int:
	var phys_sum = 0
	var energy_types_def = story_data.get("energy_types", {})
	
	for type_id in player_energy.keys():
		var def = energy_types_def.get(type_id, {})
		if def.get("bonus") == "evasion":
			phys_sum += get_player_energy_value(type_id)

	var evasion_chance = phys_sum * 2.0
	return int(min(evasion_chance, 75)) # Cap massimo al 75%

func modify_player_energy(type_id: String, amount: int):
	if not player_energy.has(type_id):
		return

	var current_value = player_energy[type_id]
	var max_value = player_max_energy.get(type_id, 0)
	var new_value = current_value + amount

	if type_id == "life":
		# La vita può scendere sotto lo 0 per mostrare il danno in eccesso
		player_energy[type_id] = int(min(new_value, max_value))
		if player_energy.get("life", 0) <= 0:
			game_over()
	else:
		# Le altre statistiche sono bloccate tra 0 e il loro massimo.
		player_energy[type_id] = clampi(new_value, 0, max_value)

	update_stats()

func equip_item(item_id: String, slot: String):
	# Se lo slot è occupato, rimuovi prima l'oggetto attuale
	if slot in equipment:
		unequip_item(slot)
	
	# Rimuovi dall'inventario e aggiungi all'equipaggiamento
	if item_id in inventory:
		inventory.erase(item_id) # Rimuove la prima occorrenza trovata
		equipment[slot] = item_id
		update_stats()

func unequip_item(slot: String):
	if slot in equipment:
		var item_id = equipment[slot]
		equipment.erase(slot)
		inventory.append(item_id)
		update_stats()

func get_energy_string(type_id: String, amount: int, max_amount: int = -1) -> String:
	var icon = ""
	var abbr = ""
	if story_data.has("energy_types") and story_data["energy_types"].has(type_id):
		var type_data = story_data["energy_types"][type_id]
		icon = type_data.get("icon", "")
		abbr = type_data.get("abbreviation", "")

	var value_str = str(amount)
	if max_amount >= 0:
		value_str = "%d/%d" % [amount, max_amount]
	
	if use_visual_health and icon:
		if abbr:
			return "%s: %s %s" % [abbr, icon, value_str]
		return "%s %s" % [icon, value_str]
	else:
		var label = abbr if abbr else tr(story_data.get("energy_types", {}).get(type_id, {}).get("name", type_id))
		return "%s: %s" % [label, value_str]

func get_damage_type_icon(type_id: String) -> String:
	if damage_types_data.has(type_id):
		return damage_types_data[type_id].get("icon", "")
	return ""

func update_stats():
	var inventory_names = []
	for item_id in inventory:
		var icon = item_manager.get_item_icon(item_id)
		var item_name = item_manager.get_item_name(item_id)
		inventory_names.append(icon if icon != "" else item_name)
	var inv_str = tr("inventory_empty")
	if inventory_names.size() > 0:
		inv_str = ", ".join(inventory_names)

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
			inv_line = "🎒 %s" % inv_str
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

# Funzione deprecata ma mantenuta per compatibilità interna
func get_health_string(amount: int) -> String:
	return get_energy_string("life", amount)

# --- Scene & Choices ---
func show_scene(scene_name):
	# Rileva la sconfitta di un'entità in combattimento.
	# Se stavamo combattendo e ora passiamo alla scena di vittoria, registra la morte.
	if was_in_combat and current_entity_id != "" and scene_name == current_victory_scene:
		notify_entity_death(current_entity_id)

	if scene_name != current_scene:
		current_entity_id = ""
		if empathy_manager: empathy_manager.reset()
	was_in_combat = false # Resetta il flag ad ogni cambio di scena
	current_scene = scene_name
	if combat_manager: combat_manager.current_entity_health = 0
	# Aggiorna il meteo al cambio di scena
	if meteo_manager: meteo_manager.roll_weather()
	
	if dialogue_manager: dialogue_manager.reset()
	var scene = story[scene_name]
	text.text = tr(scene["text"])
	update_stats()

	var buttons = [b1, b2, b3]
	var choices = scene.get("choices", [])
	for i in range(buttons.size()):
		if i < choices.size():
			buttons[i].text = tr(choices[i]["text"])
			buttons[i].show()
			_clear_signals(buttons[i])
			buttons[i].pressed.connect(func(): handle_choice(choices[i]))
		else:
			buttons[i].hide()

func handle_choice(choice):
	# Aggiunge un feedback aptico (vibrazione) alla pressione di un pulsante di scelta.
	Input.vibrate_handheld(50)

	if choice.has("action"):
		match choice["action"]:
			"pickup":
				var item = choice.get("item_id", "")
				if not item in inventory:
					inventory.append(item)
					var icon = item_manager.get_item_icon(item)
					var item_name = item_manager.get_item_name(item)
					var display_name = ("%s " % icon if icon and icon != "" else "") + item_name
					text.text = tr("item_picked_up") % display_name
					update_stats()
			"qte":
				start_qte_event()
			"combat":
				current_entity_id = choice.get("entity_id", "")
				current_victory_scene = choice.get("victory_scene", "")
				_start_prepared_combat()
			"dialogue":
				current_entity_id = choice.get("entity_id", "")
				current_victory_scene = choice.get("victory_scene", "")
				if entity_data.has(current_entity_id):
					current_entity_pronoun = entity_data[current_entity_id].get("pronoun", "")
				_start_prepared_dialogue()
			"runes":
				if rune_manager:
					rune_manager.start_rune_casting()
	if choice.has("next"):
		show_scene(choice["next"])

# --- Combattimento & Dialogo ---
func _start_prepared_combat():
	if combat_manager:
		was_in_combat = true
		combat_manager.start_combat(current_entity_id, current_victory_scene)

func _start_prepared_dialogue():
	if dialogue_manager:
		was_in_combat = false # Assicura che il dialogo non venga conteggiato come combattimento
		dialogue_manager.start_dialogue(current_entity_id, current_entity_pronoun, 0, current_victory_scene)

func _on_dialogue_choices_requested(choices):
	var buttons = [b1, b2, b3]
	for i in range(buttons.size()):
		if i < choices.size():
			buttons[i].text = tr(choices[i]["text"])
			buttons[i].show()
			_clear_signals(buttons[i])
			buttons[i].pressed.connect(func(): dialogue_manager.handle_choice(choices[i]["action"]))
		else:
			buttons[i].hide()

# --- Gestione Rune ---
func _on_rune_data_received(spell_data: Dictionary):
	var spell_id = spell_data.get("id", "rune_spell")
	var power = int(spell_data.get("power", 0))
	var cost = int(spell_data.get("cost", 0))
	var type = spell_data.get("type", "neutral")
	_on_spell_cast_success(spell_id, power, cost, type)

func _on_spell_cast_success(spell_id, power, cost, type):
	# FIX: Se siamo in combattimento, il CombatManager gestisce l'effetto della runa (danni, resistenze, ecc.)
	# Interrompiamo qui per evitare che Game.gd applichi danni "puri" ignorando le immunità del nemico.
	if was_in_combat:
		return
	
	# Consuma Mana (Solo se NON siamo in combattimento, altrimenti ci pensa il CombatManager)
	modify_player_energy("magic", -int(cost))

	var msg = ""
	if type == "sacro":
		# Cura il giocatore
		modify_player_energy("life", int(power))
		msg = tr("spell_cast_heal") % [tr(spell_id), int(power)]
	else:
		# Danno al nemico (se in combattimento o se c'è un'entità attiva)
		if combat_manager and combat_manager.current_entity_health > 0:
			combat_manager.current_entity_health -= int(power)
			msg = tr("spell_cast_damage") % [tr(spell_id), int(power)]
			
			# Controllo vittoria immediata
			if combat_manager.current_entity_health <= 0:
				msg += " " + tr("combat_victory")
				# Nota: Il CombatManager gestirà la transizione al prossimo click o update
		else:
			msg = tr("spell_cast_no_enemy")

	# Aggiorna il testo e le statistiche
	text.text += "\n" + msg
	update_stats()

func _on_rune_combo_finished(total_spells):
	if total_spells > 0:
		text.text += tr("rune_combo_end_msg") % total_spells

func _init_death_effects():
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
	death_overlay.color = Color(0.2, 0.2, 0.2, 0.5) # Grigio scuro semitrasparente
	death_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	death_overlay.hide()
	
	var player_mc = $UI/VBC_Main/MC_Player
	if player_mc:
		player_mc.add_child(death_overlay)

# --- Game Over ---
func game_over():
	if death_manager:
		death_manager.record_player_death()
	text.text = tr("game_over_text")
	enable_choices()
	if combat_manager: combat_manager.current_entity_health = 0
	if dialogue_manager: dialogue_manager.reset()
	b1.text = tr("game_over_choice")
	b1.show()
	_clear_signals(b1)
	b1.pressed.connect(_restart_game)
	b2.hide()
	b3.hide()

	# Applica effetti visivi morte
	# !!! NON RIMUOVERE QUESTE RIGHE !!! Gestiscono il feedback visivo di morte (icona grigia e overlay scuro).
	if player_icon: player_icon.material = grayscale_material
	if player_stats: player_stats.material = grayscale_material
	if death_overlay: death_overlay.show()

func _restart_game():
	health = max_health
	mana = max_mana
	mood = max_mood
	inventory.clear()

	# Rimuovi effetti visivi morte
	# !!! NON RIMUOVERE QUESTE RIGHE !!! Ripristinano la grafica normale al riavvio.
	if player_icon: player_icon.material = null
	if player_stats: player_stats.material = null
	if death_overlay: death_overlay.hide()

	show_scene("start")

func notify_entity_death(entity_id: String):
	if death_manager:
		death_manager.record_entity_death(entity_id)

func _trigger_haptic():
	# Feedback tattile universale (funziona solo su mobile)
	Input.vibrate_handheld(50)

func _clear_signals(button: Button):
	for conn in button.pressed.get_connections():
		button.pressed.disconnect(conn.callable)
	
	# Riconnette il feedback aptico ogni volta che il pulsante viene pulito/preparato
	if not button.pressed.is_connected(_trigger_haptic):
		button.pressed.connect(_trigger_haptic)

# --- QTE ---
func start_qte_event(message_key: String = "qte_start_default", context: String = ""):
	disable_choices()
	text.text = tr(message_key)
	qte_context = context
	
	var speed_factor: float = 1.0
	
	# Calcola la velocità in base alla potenza del mostro (totale energia)
	if current_entity_id != "" and entity_data.has(current_entity_id):
		var entity = entity_data[current_entity_id]
		var total_energy = 0.0
		if entity.has("energy"):
			for stat in entity["energy"]:
				total_energy += stat.get("value", 0)
		if total_energy > 0:
			speed_factor = total_energy * qte_power_multiplier

	if qte: qte.start(b1, speed_factor) # Passa b1 e la velocità calcolata

func _on_qte_finished(value):
	var result_text = tr("qte_result_miss")
	var multiplier = 0.0 # Un "MANCATO" non infligge danno
	if value > 0.45 and value < 0.55:
		result_text = tr("qte_result_perfect")
		multiplier = 2.0
	elif value > 0.3 and value < 0.7:
		result_text = tr("qte_result_good")
		multiplier = 1.2
	text.text = result_text
	
	# Aspetta un attimo per far leggere il risultato del QTE al giocatore
	await get_tree().create_timer(1.0).timeout
	
	# Gestisce il risultato del QTE in base al contesto
	if qte_context == "player_attack":
		if combat_manager:
			combat_manager.resolve_player_attack(multiplier)
	
	qte_context = "" # Resetta il contesto
	# I pulsanti verranno riattivati dal CombatManager al prossimo turno del giocatore

func enable_target_selection():
	enable_choices()
	text.text = tr("combat_select_target")
	
	# Opzione 1: Player
	b1.text = tr("target_player")
	b1.show()
	_clear_signals(b1)
	b1.pressed.connect(func(): target_clicked.emit("player"))
	
	# Opzione 2: Nemico
	if current_entity_id != "" and combat_manager and combat_manager.current_entity_health > 0:
		var e_data = entity_data.get(current_entity_id, {})
		var e_name = e_data.get("name", "Nemico")
		b2.text = tr(e_name)
		b2.show()
		_clear_signals(b2)
		b2.pressed.connect(func(): target_clicked.emit("enemy"))
	else:
		b2.hide()

	# Opzione 3: Indietro
	b3.text = tr("combat_back")
	b3.show()
	_clear_signals(b3)
	b3.pressed.connect(func(): target_clicked.emit("back"))

func disable_target_selection():
	for btn in [b1, b2, b3]:
		btn.hide()
		_clear_signals(btn)

func disable_choices():
	for btn in [b1, b2, b3]:
		btn.disabled = true

func enable_choices():
	for btn in [b1, b2, b3]:
		btn.disabled = false

# --- Menu Crescita ---
func start_growth_menu(next_scene: String):
	current_victory_scene = next_scene
	
	if not growth_manager:
		show_scene(next_scene)
		return
		
	enable_choices()
	_update_growth_menu()

func _update_growth_menu():
	if not growth_manager or not "available_energy" in growth_manager:
		return
	
	var energy = growth_manager.available_energy
	text.text = tr("growth_menu_title") % energy
	
	var buttons = [b1, b2, b3]
	for btn in buttons:
		btn.hide()
		_clear_signals(btn)

	var player_energy_types = story_data.get("player", {}).get("energy", [])
	var energy_type_definitions = story_data.get("energy_types", {})
	
	var button_index = 0
	for energy_stat in player_energy_types:
		if button_index >= buttons.size():
			break # Mostra al massimo 3 opzioni

		var stat_id = energy_stat.get("type")

		var stat_name_key = energy_type_definitions.get(stat_id, {}).get("name", stat_id)
		var stat_name = tr(stat_name_key)
		var current_value = player_max_energy.get(stat_id, 0)
		
		var btn = buttons[button_index]
		btn.text = tr("growth_btn_stat") % [stat_name, current_value]
		btn.show()
		btn.pressed.connect(growth_manager.upgrade_stat.bind(stat_id))
		
		button_index += 1
