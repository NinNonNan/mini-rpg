class_name Game
extends Control

# --- Riferimenti ai Nodi dell'Interfaccia Utente (UI) ---
@onready var meteo_stats = $UI/VBC_Main/MC_Meteo/PC/HBC/MeteoText
@onready var enemy_stats_box = $UI/VBC_Main/MC_Enemy/PC
@onready var enemy_icon = $UI/VBC_Main/MC_Enemy/PC/HBC/Icon
@onready var enemy_stats = $UI/VBC_Main/MC_Enemy/PC/HBC/StatsText
@onready var text = $UI/VBC_Main/MC_Story/PC/HBC/StoryText
@onready var player_icon = $UI/VBC_Main/MC_Player/PC/HBC/Icon
@onready var player_stats = $UI/VBC_Main/MC_Player/PC/HBC/StatsText
@onready var b1 = $UI/VBC_Main/VBC_Button/MC1/Choice1
@onready var b2 = $UI/VBC_Main/VBC_Button/MC2/Choice2
@onready var b3 = $UI/VBC_Main/VBC_Button/MC3/Choice3

# --- QTE ---
@onready var qte = $QTE

# --- Manager di Sistema ---
@onready var combat_manager = $Manager/Combat as CombatManager
@onready var dialogue_manager = $Manager/Dialogue as DialogueManager
@onready var empathy_manager = $Manager/Empathy as EmpathyManager
@onready var item_manager = $Manager/Item as ItemManager
@onready var special_manager = $Manager/Special as SpecialManager
@onready var growth_manager = $Manager/Growth as GrowthManager
@onready var death_manager = $Manager/Death as DeathManager
@onready var meteo_manager = $Manager/Meteo as MeteoManager

# --- Stato del Gioco ---
var health: int = 10
var mana: int = 10
var max_health: int = 10
var max_mana: int = 10
var inventory: Array[String] = []
var current_entity_pronoun: String = ""
var current_victory_scene: String = ""
var current_entity_id: String = ""
var was_in_combat: bool = false # Aggiunto per tracciare la vittoria in combattimento

var qte_context: String = "" # Contesto per sapere perché è stato avviato il QTE
signal target_clicked(target_type)
var use_visual_health: bool = true

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

	# Impostazioni grafica
	#text.size_flags_vertical = Control.SIZE_EXPAND | Control.SIZE_FILL
	for btn in [b1, b2, b3]:
		btn.size_flags_horizontal = Control.SIZE_EXPAND | Control.SIZE_FILL

	# Caricamento dati e traduzioni
	_load_story()
	_load_translations()

	# Iniezione Game nei manager
	for mgr in [combat_manager, item_manager, dialogue_manager, empathy_manager, special_manager, growth_manager, death_manager, meteo_manager]:
		if mgr:
			mgr.game = self

	# Connessione DialogueManager
	if dialogue_manager:
		dialogue_manager.text_requested.connect(func(t): text.text = t)
		dialogue_manager.choices_requested.connect(_on_dialogue_choices_requested)
		dialogue_manager.stats_updated.connect(update_stats)
		dialogue_manager.dialogue_finished.connect(show_scene)
		dialogue_manager.dialogue_failed.connect(_start_prepared_combat)

	# Avvio scena iniziale
	show_scene(current_scene)

# --- Caricamento JSON ---
func _load_story():
	var json_data = StoryLoader.load_json_file("res://story.json")
	if json_data == null:
		text.text = tr("error_story_load_short")
		return
	story_data = json_data
	story = json_data.get("scenes", {})
	item_data = json_data.get("items", {})
	entity_data = json_data.get("entities", {})
	damage_types_data = json_data.get("damage_types", {})

	var player_data = json_data.get("player", {})
	if player_data.has("energy"):
		for stat in player_data["energy"]:
			if stat.get("type") == "life":
				max_health = int(stat.get("value", 10))
				health = max_health
			elif stat.get("type") == "magic":
				max_mana = int(stat.get("value", 10))
				mana = max_mana
	if player_icon and player_data.has("icon") and player_data["icon"] != "":
		player_icon.texture = load(player_data["icon"])

func _load_translations(lang_code: String = "it"):
	var file_path = "res://%s.json" % lang_code
	if not FileAccess.file_exists(file_path):
		push_error(tr("error_translation_file_not_found") % file_path)
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
	match type_id:
		"life": return health
		"magic": return mana
	return 0

func modify_player_energy(type_id: String, amount: int):
	match type_id:
		"life":
			health = clampi(health + amount, 0, max_health)
			if health <= 0: game_over()
		"magic":
			mana = clampi(mana + amount, 0, max_mana)
	update_stats()

func get_health_string(amount: int) -> String:
	return "❤️ %d" % amount if use_visual_health else str(amount) + " HP"

func get_mana_string(amount: int) -> String:
	return "💧 %d" % amount if use_visual_health else str(amount) + " MP"

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
	var show_enemy = false
	if combat_manager and combat_manager.current_entity_health > 0:
		show_enemy = true
		entity_text = tr("stats_enemy_hp") % get_health_string(combat_manager.current_entity_health)
	elif dialogue_manager and dialogue_manager.is_active:
		show_enemy = true
	elif current_entity_id != "" and empathy_manager and empathy_manager.is_known:
		show_enemy = true
		var entity = entity_data.get(current_entity_id, {})
		var hp = 0
		if entity.has("energy"):
			for stat in entity["energy"]:
				if stat.get("type") == "life":
					hp = int(stat.get("value", 0))
		entity_text = tr("stats_enemy_hp") % get_health_string(hp)
	if player_stats:
		player_stats.text = tr("stats_player") % [get_health_string(health), get_mana_string(mana), inv_str]
	if enemy_stats_box and enemy_stats:
		enemy_stats.text = entity_text
		if enemy_icon:
			var icon_path = entity_data.get(current_entity_id, {}).get("icon", "")
			if icon_path != "":
				enemy_icon.texture = load(icon_path)
			else:
				enemy_icon.texture = null
		enemy_stats_box.visible = true

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

# --- Game Over ---
func game_over():
	if death_manager:
		death_manager.record_player_death()
	text.text = tr("game_over_text")
	enable_choices()
	health = max_health
	mana = max_mana
	inventory.clear()
	if combat_manager: combat_manager.current_entity_health = 0
	if dialogue_manager: dialogue_manager.reset()
	b1.text = tr("game_over_choice")
	b1.show()
	_clear_signals(b1)
	b1.pressed.connect(show_scene.bind("start"))
	b2.hide()
	b3.hide()

func notify_entity_death(entity_id: String):
	if death_manager:
		death_manager.record_entity_death(entity_id)

func _clear_signals(button: Button):
	for conn in button.pressed.get_connections():
		button.pressed.disconnect(conn.callable)

# --- QTE ---
func start_qte_event(message_key: String = "qte_start_default", context: String = ""):
	disable_choices()
	text.text = tr(message_key)
	qte_context = context
	if qte: qte.start(b1) # Passa b1 per sovrapporre la barra al pulsante

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
	b1.text = "Player"
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
	var energy = 0
	if "available_energy" in growth_manager:
		energy = growth_manager.available_energy
	
	text.text = tr("growth_menu_title") % energy
	
	# Pulsante 1: Vita
	b1.text = tr("growth_btn_life") % max_health
	b1.show()
	_clear_signals(b1)
	b1.pressed.connect(func():
		if growth_manager.has_method("upgrade_stat") and growth_manager.upgrade_stat("life"):
			_update_growth_menu()
			update_stats()
	)
	
	# Pulsante 2: Magia
	b2.text = tr("growth_btn_magic") % max_mana
	b2.show()
	_clear_signals(b2)
	b2.pressed.connect(func():
		if growth_manager.has_method("upgrade_stat") and growth_manager.upgrade_stat("magic"):
			_update_growth_menu()
			update_stats()
	)
	
	# Pulsante 3: Continua
	b3.text = tr("growth_btn_continue")
	b3.show()
	_clear_signals(b3)
	b3.pressed.connect(show_scene.bind(current_victory_scene))
