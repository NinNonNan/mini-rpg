class_name Game
extends Control

# --- Riferimenti ai Nodi dell'Interfaccia Utente (UI) ---
@onready var text = $UI/VBC_Main/PC_Text/StoryText
@onready var player_stats = $UI/VBC_Main/PC_Player/StatsText # Riferimento al box statistiche giocatore
@onready var enemy_stats_box = $UI/VBC_Main/PC_Enemy         # Riferimento al CONTENITORE nemico
@onready var enemy_stats_text = $UI/VBC_Main/PC_Enemy/StatsText # Riferimento al TESTO nemico
@onready var b1 = $UI/VBC_Main/VBC_Button/Choice1
@onready var b2 = $UI/VBC_Main/VBC_Button/Choice2
@onready var b3 = $UI/VBC_Main/VBC_Button/Choice3

# --- Manager di Sistema ---
@onready var combat_manager = $Manager/CombatManager as CombatManager
@onready var dialogue_manager = $Manager/DialogueManager as DialogueManager
@onready var empathy_manager = $Manager/EmpathyManager as EmpathyManager
@onready var item_manager = $Manager/ItemManager as ItemManager

# --- Variabili di Stato del Gioco ---
# Salute del giocatore
var health: int = 10
# Inventario del giocatore (contiene gli ID degli oggetti)
var inventory: Array[String] = []
# Pronome dell'entità corrente (es: "il", "la")
var current_entity_pronoun: String = ""
# Scena da mostrare in caso di vittoria
var current_victory_scene: String = ""
# ID dell'entità corrente (per combattimento o dialogo)
var current_entity_id: String = ""

# Opzione grafica: Se true, mostra cuori (❤️) invece dei numeri.
var use_visual_health: bool = true

# --- Database di Gioco (caricati da JSON) ---
# Contiene tutte le scene narrative del gioco
var story: Dictionary = {}
# Database degli oggetti (armi, pozioni, ecc.)
var item_data: Dictionary = {}
# Database delle entità (nemici, NPC, ecc.)
var entity_data: Dictionary = {}
# Database dei tipi di danno (taglio, fuoco, ecc.)
var damage_types_data: Dictionary = {}

# Nome della scena attualmente mostrata
var current_scene: String = "start"

# Funzione chiamata da Godot quando il nodo è pronto e aggiunto alla scena.
func _ready():
	# DEBUG: Verifica che i nodi essenziali siano stati trovati
	if not text:
		push_error("ERRORE CRITICO: Nodo 'StoryText' non trovato. Verifica il percorso nella scena.")
	if not player_stats:
		push_error("ERRORE CRITICO: Nodo 'StatsText' (Player) non trovato. Verifica il percorso '$UI/VBC_Main/PC_Player/StatsText'.")
	if not enemy_stats_box:
		# FALLBACK: Se non trova "PC_Enemy", prova a cercare "PC_enemy" (minuscolo)
		if $UI/VBC_Main.has_node("PC_enemy"):
			enemy_stats_box = $UI/VBC_Main.get_node("PC_enemy")
			# Se abbiamo recuperato il box, cerchiamo di recuperare anche il testo interno
			if enemy_stats_box.has_node("StatsText"):
				enemy_stats_text = enemy_stats_box.get_node("StatsText")
		else:
			push_error("ATTENZIONE: Nodo 'PC_Enemy' (o 'PC_enemy') non trovato in '$UI/VBC_Main'.")

	# Impostazioni grafiche per l'interfaccia
	text.size_flags_vertical = Control.SIZE_EXPAND | Control.SIZE_FILL
	b1.size_flags_horizontal = Control.SIZE_EXPAND | Control.SIZE_FILL
	b2.size_flags_horizontal = Control.SIZE_EXPAND | Control.SIZE_FILL
	b3.size_flags_horizontal = Control.SIZE_EXPAND | Control.SIZE_FILL
	
	# Caricamento dati e traduzioni
	_load_story()
	_load_translations()
	
	# Inietta il riferimento a 'Game' in tutti i manager per dare accesso allo stato globale
	if combat_manager: combat_manager.game = self
	if item_manager: item_manager.game = self
	if dialogue_manager: dialogue_manager.game = self
	if empathy_manager: empathy_manager.game = self
	
	# Collega i segnali del DialogueManager per gestire l'interfaccia durante i dialoghi
	if dialogue_manager:
		dialogue_manager.text_requested.connect(func(t): text.text = t)
		dialogue_manager.choices_requested.connect(_on_dialogue_choices_requested)
		dialogue_manager.stats_updated.connect(update_stats)
		dialogue_manager.dialogue_finished.connect(show_scene)
		dialogue_manager.dialogue_failed.connect(_start_prepared_combat)
	
	# Avvia il gioco mostrando la prima scena
	show_scene(current_scene)

# Carica i dati della storia dal file story.json
func _load_story():
	# Usiamo la classe StoryLoader per caricare e validare il file JSON
	var json_data = StoryLoader.load_json_file("res://story.json")
	
	if json_data == null:
		text.text = tr("error_story_load")
		return

	# Popoliamo i dizionari di gioco con i dati caricati
	story = json_data.get("scenes", {})
	item_data = json_data.get("items", {})
	entity_data = json_data.get("entities", {})
	damage_types_data = json_data.get("damage_types", {})

# Carica il file di traduzione e lo registra nel TranslationServer
func _load_translations(lang_code: String = "it"):
	var file_path = "res://%s.json" % lang_code
	if not FileAccess.file_exists(file_path):
		push_error("File di traduzione non trovato: %s" % file_path)
		text.text = tr("error_translation_file_not_found") % lang_code
		return

	var file = FileAccess.open(file_path, FileAccess.READ)
	var content = file.get_as_text()
	file.close()

	var json_data = JSON.parse_string(content)

	if json_data == null:
		push_error("Errore nel parsing del JSON di traduzione: %s" % file_path)
		text.text = tr("error_translation_file_parse") % lang_code
		return

	# Creiamo una nuova traduzione e aggiungiamo ogni stringa al server
	var translation = Translation.new()
	for key in json_data:
		translation.add_message(key, json_data[key])

	TranslationServer.add_translation(translation)

# Genera una stringa visiva per la salute (es. "❤️❤️❤️" o "3 HP")
func get_health_string(amount: int) -> String:
	if use_visual_health:
		return "❤️".repeat(amount)
	else:
		return str(amount) + " HP"

# Recupera l'icona associata a un tipo di danno (es. "fuoco" -> "🔥")
func get_damage_type_icon(type_id: String) -> String:
	if damage_types_data.has(type_id):
		return damage_types_data[type_id].get("icon", "")
	return ""

# Aggiorna il testo delle statistiche del giocatore e del nemico.
func update_stats():
	# Costruisce la stringa dell'inventario
	var inventory_names = []
	for item_id in inventory:
		var item_name = item_manager.get_item_name(item_id)
		var icon = item_manager.get_item_icon(item_id)
		
		# Se l'icona esiste, usiamo QUELLA per l'inventario. Altrimenti il nome.
		if icon != "":
			inventory_names.append(icon)
		else:
			inventory_names.append(item_name)
			
	var inventory_string = tr("inventory_empty")
	if not inventory_names.is_empty():
		inventory_string = ", ".join(inventory_names)
	
	# Costruisce la stringa delle statistiche dell'entità (nemico o NPC)
	var entity_text = ""
	var show_enemy_stats = false
	
	if combat_manager and combat_manager.current_entity_health > 0: # In combattimento
		show_enemy_stats = true
		if empathy_manager and empathy_manager.is_known:
			entity_text = tr("stats_enemy_hp") % get_health_string(combat_manager.current_entity_health)
			entity_text += "\n" + tr("stats_mood") % empathy_manager.current_mood
			entity_text += empathy_manager.get_weakness_immunity_text(current_entity_id)
		else:
			entity_text = tr("stats_enemy_hp_unknown")
			entity_text += "\n" + tr("stats_mood_unknown")
	elif dialogue_manager and dialogue_manager.is_active: # In dialogo
		show_enemy_stats = true
		if empathy_manager and empathy_manager.is_known:
			entity_text = tr("stats_mood") % dialogue_manager.current_mood
			entity_text += empathy_manager.get_weakness_immunity_text(current_entity_id)
		else:
			entity_text = tr("stats_mood_unknown")
	# Caso 3: Analisi passiva (es. pulsante "Esamina" nella storia)
	elif current_entity_id != "" and empathy_manager and empathy_manager.is_known:
		show_enemy_stats = true
		# Recuperiamo i dati dall'archivio entità
		var entity = entity_data.get(current_entity_id, {})
		var hp = int(entity.get("health", 0))
		entity_text = tr("stats_enemy_hp") % get_health_string(hp)
		entity_text += "\n" + tr("stats_mood") % empathy_manager.current_mood
		entity_text += empathy_manager.get_weakness_immunity_text(current_entity_id)
			
	# Aggiorna il box del giocatore
	if player_stats:
		player_stats.text = tr("stats_player") % [get_health_string(health), inventory_string]
	
	# Aggiorna e gestisce la visibilità del box del nemico
	if enemy_stats_box and enemy_stats_text:
		enemy_stats_text.text = entity_text
		enemy_stats_box.visible = true

# Mostra una scena specifica basata sul suo nome.
func show_scene(scene_name):
	# Imposta la scena corrente e resetta lo stato dei manager
	# Se stiamo cambiando scena vera e propria (non ricaricando la stessa per aggiornare il testo),
	# resettiamo i dati del nemico corrente per evitare "fantasmi" (es. stats del drago nella foresta).
	if scene_name != current_scene:
		current_entity_id = ""
		if empathy_manager:
			empathy_manager.reset()

	# Imposta la scena corrente
	current_scene = scene_name
	
	if combat_manager:
		combat_manager.current_entity_health = 0
	if dialogue_manager:
		dialogue_manager.reset()
		
	var scene = story[scene_name]
	text.text = tr(scene["text"])
	update_stats()
	
	# Configura i pulsanti in base alle scelte disponibili nella scena
	var choices = scene["choices"]
	var buttons = [b1, b2, b3]
	for i in range(buttons.size()):
		if i < choices.size():
			buttons[i].text = tr(choices[i]["text"])
			buttons[i].show()
			var choice = choices[i]
			_clear_signals(buttons[i])
			buttons[i].pressed.connect(func(): handle_choice(choice))
		else:
			buttons[i].hide()

# Gestisce la logica quando un pulsante di scelta viene premuto.
func handle_choice(choice):
	# 1. Gestione Azioni Speciali (definite nel JSON)
	if choice.has("action"):
		match choice["action"]:
			"pickup":
				var item = choice.get("item_id", "oggetto")
				if not item in inventory:
					inventory.append(item)
					var item_name = item_manager.get_item_name(item)
					var icon = item_manager.get_item_icon(item)
					
					# Messaggio di raccolta con icona se disponibile
					if icon != "":
						text.text = tr("pickup_success") % (icon + " " + item_name)
					else:
						text.text = tr("pickup_success") % item_name
						
					update_stats()
					await get_tree().create_timer(1.0).timeout
			"combat":
				# Prepara i dati per l'incontro (combattimento o dialogo)
				var next_entity_id = choice.get("entity_id", "")
				current_victory_scene = choice.get("victory_scene", "start")
				var entity = entity_data.get(next_entity_id, {})
				current_entity_pronoun = entity.get("pronoun", "")
				
				# Resettiamo la conoscenza SOLO se stiamo affrontando un nuovo nemico
				if empathy_manager and current_entity_id != next_entity_id:
					empathy_manager.reset()
				
				current_entity_id = next_entity_id
				var mood = entity.get("mood", -1) # Default a ostile

				if mood >= 0:
					# L'entità non è ostile, offri la scelta tra dialogo e attacco
					var entity_name_key = entity.get("name", current_entity_id)
					var entity_name = tr(entity_name_key)
					text.text = tr("encounter_neutral") % entity_name
					
					b1.text = tr("choice_attack")
					b1.show()
					_clear_signals(b1)
					b1.pressed.connect(_start_prepared_combat)
					
					b2.text = tr("choice_dialogue")
					b2.show()
					_clear_signals(b2)
					b2.pressed.connect(_start_prepared_dialogue)
					
					b3.hide()
				else:
					# L'entità è ostile, inizia subito il combattimento
					_start_prepared_combat()
				return # Il flusso viene gestito dall'incontro, non dal cambio scena
			"restart":
				health = 10
				inventory.clear()
				show_scene("start")
				return
			"analyze":
				var entity_id = choice.get("entity_id", "")
				current_entity_id = entity_id # Salviamo chi stiamo analizzando!
				
				var analysis_text = ""
				if empathy_manager:
					analysis_text = empathy_manager.analyze(entity_id)
				text.text = analysis_text
				update_stats()
				await get_tree().create_timer(2.0).timeout

	# 2. Cambio Scena Normale
	if choice.has("next"):
		show_scene(choice["next"])

# --- Funzioni di Incontro (Combattimento e Dialogo) ---

func _start_prepared_combat():
	if combat_manager:
		combat_manager.start_combat(current_entity_id, current_victory_scene)

func _start_prepared_dialogue():
	var entity = entity_data.get(current_entity_id, {})
	var mood = entity.get("mood", 0)
	if dialogue_manager:
		dialogue_manager.start_dialogue(current_entity_id, current_entity_pronoun, mood, current_victory_scene)

# --- Logica del Dialogo ---

func _on_dialogue_choices_requested(choices):
	var buttons = [b1, b2, b3]
	for i in range(buttons.size()):
		if i < choices.size():
			var choice = choices[i]
			buttons[i].text = tr(choice["text"])
			buttons[i].show()
			_clear_signals(buttons[i])
			# Collega il pulsante per chiamare handle_choice nel DialogueManager
			buttons[i].pressed.connect(func(): dialogue_manager.handle_choice(choice["action"]))
		else:
			buttons[i].hide()

func game_over():
	text.text = tr("game_over_text")
	health = 10
	inventory.clear()
	
	# Resetta lo stato dei manager
	if combat_manager: combat_manager.current_entity_health = 0
	if dialogue_manager: dialogue_manager.reset()
	
	b1.text = tr("game_over_choice")
	b1.show()
	_clear_signals(b1)
	b1.pressed.connect(show_scene.bind("start"))
	b2.hide()
	b3.hide()

# Funzione helper per rimuovere tutti i collegamenti di un segnale di un pulsante
func _clear_signals(button: Button) -> void:
	for conn in button.pressed.get_connections():
		button.pressed.disconnect(conn.callable)
		
