class_name Game
extends Control

# --- Riferimenti ai Nodi dell'Interfaccia Utente (UI) ---
@onready var text = $UI/VBC_Main/PC_Text/StoryText
@onready var stats = $UI/VBC_Main/PC_Stats/StatsText
@onready var b1 = $UI/VBC_Main/VBC_Button/Choice1
@onready var b2 = $UI/VBC_Main/VBC_Button/Choice2
@onready var b3 = $UI/VBC_Main/VBC_Button/Choice3

@onready var combat_manager = $Manager/CombatManager as CombatManager
@onready var dialogue_manager = $Manager/DialogueManager as DialogueManager
@onready var empathy_manager = $Manager/EmpathyManager as EmpathyManager

# --- Variabili di Gioco ---
# Salute del giocatore
var health: int = 10
# Inventario del giocatore
var inventory: Array[String] = []
# Pronome dell'entita
var current_entity_pronoun: String = "" 
# Scena da mostrare in caso di vittoria nel combattimento corrente
var current_victory_scene: String = ""
# ID dell'entità corrente per combattimento o dialogo
var current_entity_id: String = ""

# Dizionario che conterrà la storia del gioco, caricata da un file JSON.
var story: Dictionary = {}
# Dizionario che conterrà i dati degli oggetti (es. danni armi)
var item_data: Dictionary = {}
# Dizionario che conterrà i dati dei nemici
var entity_data: Dictionary = {}

# Tiene traccia della scena corrente
var current_scene: String = "start"

# Funzione chiamata da Godot quando il nodo è pronto e aggiunto alla scena.
func _ready():
	# DEBUG: Verifica che il nodo text sia stato trovato correttamente prima di usarlo
	if not text:
		push_error("ERRORE CRITICO: Il nodo 'StoryText' non è stato trovato. Verifica che il percorso '$UI/VBC_Main/PC_Text/StoryText' corrisponda alla tua scena.")
		return

	# Fa in modo che l'etichetta del testo si espanda per riempire lo spazio verticale,
	# mantenendo i pulsanti fissi in basso.
	text.size_flags_vertical = Control.SIZE_EXPAND | Control.SIZE_FILL

	# Fa in modo che i pulsanti si espandano orizzontalmente per riempire il contenitore.
	# Questo dà loro una larghezza uniforme e impedisce all'interfaccia di "saltare"
	# quando il testo dei pulsanti cambia.
	b1.size_flags_horizontal = Control.SIZE_EXPAND | Control.SIZE_FILL
	b2.size_flags_horizontal = Control.SIZE_EXPAND | Control.SIZE_FILL
	b3.size_flags_horizontal = Control.SIZE_EXPAND | Control.SIZE_FILL
	
	_load_story()
	_load_translations()
	
	# Passa il riferimento al nodo Game ai manager
	if combat_manager:
		combat_manager.game = self
	# (Potresti voler fare lo stesso per dialogue_manager e empathy_manager se hanno bisogno di un riferimento a Game)
	
	# Collega i segnali del DialogueManager
	if dialogue_manager:
		dialogue_manager.text_requested.connect(func(t): text.text = t)
		dialogue_manager.choices_requested.connect(_on_dialogue_choices_requested)
		dialogue_manager.stats_updated.connect(update_stats)
		dialogue_manager.dialogue_finished.connect(show_scene)
		dialogue_manager.dialogue_failed.connect(_start_prepared_combat)
		

	show_scene(current_scene)

# Carica i dati della storia dal file story.json
func _load_story():
	# Usiamo la nostra nuova classe dedicata per caricare i dati
	var json_data = StoryLoader.load_json_file("res://story.json")
	
	if json_data == null:
		text.text = tr("error_story_load")
		return

	story = json_data.get("scenes", {})
	item_data = json_data.get("items", {})
	entity_data = json_data.get("entities", {})

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

	# Creiamo una nuova traduzione e aggiungiamo ogni stringa
	var translation = Translation.new()
	for key in json_data:
		translation.add_message(key, json_data[key])

	TranslationServer.add_translation(translation)

# Aggiorna il testo delle statistiche del giocatore e del nemico.
func update_stats():
	var inventory_names = []
	for item_id in inventory:
		var item_name_key = item_data.get(item_id, {}).get("name", item_id)
		inventory_names.append(tr(item_name_key))
	var inventory_string = tr("inventory_empty")
	if not inventory_names.is_empty():
		inventory_string = ", ".join(inventory_names)
	
	var entity_text = ""
	# Chiediamo al CombatManager se siamo in combattimento e qual è la vita del nemico
	if combat_manager and combat_manager.current_entity_health > 0: # In combattimento
		if empathy_manager and empathy_manager.is_known:
			entity_text = tr("stats_enemy_hp") % combat_manager.current_entity_health
		else:
			entity_text = tr("stats_enemy_hp_unknown")
	elif dialogue_manager and dialogue_manager.is_active: # In dialogo
		if empathy_manager and empathy_manager.is_known:
			entity_text = tr("stats_mood") % dialogue_manager.current_mood
		else:
			entity_text = tr("stats_mood_unknown")
			
	stats.text = tr("stats_player") % [health, inventory_string, entity_text]

# Mostra una scena specifica basata sul suo nome.
func show_scene(scene_name):
	# Imposta la scena corrente e resetta la salute del nemico (non siamo in combattimento)
	current_scene = scene_name
	if combat_manager:
		combat_manager.current_entity_health = 0
	if dialogue_manager:
		dialogue_manager.reset()
	var scene = story[scene_name]
	text.text = tr(scene["text"])
	update_stats()
	var choices = scene["choices"]
	var buttons = [b1, b2, b3]

	# Configura i pulsanti in base alle scelte disponibili nella scena
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
	# 1. Gestione Azioni Generiche (basate sui dati del JSON)
	if choice.has("action"):
		match choice["action"]:
			"pickup":
				# Legge quale oggetto prendere dal JSON
				var item = choice.get("item_id", "oggetto")
				if not item in inventory:
					inventory.append(item)
					var item_name_key = item_data.get(item, {}).get("name", item)
					var item_name = tr(item_name_key)
					text.text = tr("pickup_success") % item_name
					update_stats()
					await get_tree().create_timer(1.0).timeout
			"combat":
				# Prepara l'incontro
				current_entity_id = choice.get("entity_id", "")
				current_victory_scene = choice.get("victory_scene", "start")
				var entity = entity_data.get(current_entity_id, {})
				current_entity_pronoun = entity.get("pronoun", "") # Carica il pronome
				
				# Nuovo nemico, resettiamo la conoscenza
				if empathy_manager: empathy_manager.reset()
				
				var mood = entity.get("mood", -1) # Default a ostile se non specificato

				if mood >= 0:
					# L'entità è neutrale o amichevole, offri la scelta
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
					
					b3.hide() # Nascondiamo il terzo pulsante per questa scelta
				else:
					# L'entità è ostile, inizia subito il combattimento
					_start_prepared_combat()
				return # L'incontro gestisce il flusso, usciamo dalla funzione
			"restart":
				health = 10
				inventory.clear()
				show_scene("start")
				return

	# 2. Cambio Scena (se definito nel JSON)
	if choice.has("next"):
		show_scene(choice["next"])

# --- Funzioni di Incontro (Combattimento e Dialogo) ---

func _start_prepared_combat():
	# Deleghiamo l'inizio del combattimento al CombatManager
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
			# Colleghiamo il pulsante per chiamare handle_choice nel DialogueManager
			buttons[i].pressed.connect(func(): dialogue_manager.handle_choice(choice["action"]))
		else:
			buttons[i].hide()

func game_over():
	text.text = tr("game_over_text")
	health = 10
	inventory.clear()
	# Resetta anche lo stato del combat manager
	if combat_manager:
		combat_manager.current_entity_health = 0
	if dialogue_manager:
		dialogue_manager.reset()
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
		
