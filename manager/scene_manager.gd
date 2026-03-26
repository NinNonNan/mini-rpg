# =========================================================
# SCENE MANAGER
# =========================================================
# Gestisce la navigazione tra scene e la logica delle scelte:
# - Transizioni di scena
# - Gestione delle scelte del giocatore
# - Preparazione combattimenti e dialoghi
# - Integrazione con QTE e sistemi di rune

class_name SceneManager
extends Node

# Riferimento al game principale
var game

# Stato corrente
var current_scene: String = "start"
var was_in_combat: bool = false
var current_entity_id: String = ""
var current_victory_scene: String = ""
var current_entity_pronoun: String = ""

# Riferimenti UI per i pulsanti (inizializzati nel _ready)
var b1
var b2
var b3

func _ready():
	_init_ui_references()

func show_scene(scene_name: String):
	# Carica e visualizza una nuova scena
	# Rileva la sconfitta di un'entità in combattimento
	if was_in_combat and current_entity_id != "" and scene_name == current_victory_scene:
		_notify_entity_death(current_entity_id)

	if scene_name != current_scene:
		current_entity_id = ""
		if game.empathy_manager:
			game.empathy_manager.reset()
	was_in_combat = false # Resetta il flag ad ogni cambio di scena
	current_scene = scene_name

	if game.combat_manager:
		game.combat_manager.current_entity_health = 0

	# Aggiorna il meteo al cambio di scena
	if game.meteo_manager:
		game.meteo_manager.roll_weather()

	# Auto-save
	if game.save_manager:
		game.save_manager.save_game()

	if game.dialogue_manager:
		game.dialogue_manager.reset()

	var scene = game.data_manager.get_story_scene(scene_name)
	if not scene:
		push_error("Scena non trovata: " + scene_name)
		return

	# Imposta il testo principale usando le traduzioni
	game.ui_manager.text.text = tr(scene["text"])
	game.ui_manager.update_stats()

	# Configura i pulsanti per le scelte
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

func handle_choice(choice: Dictionary):
	# Esegue la logica associata a una scelta del giocatore
	# Feedback aptico
	Input.vibrate_handheld(50)

	if choice.has("action"):
		match choice["action"]:
			"pickup":
				_handle_item_pickup(choice)
			"qte":
				_start_qte()
			"combat":
				_prepare_combat(choice)
			"dialogue":
				_prepare_dialogue(choice)
			"runes":
				_start_rune_casting()

	if choice.has("next"):
		show_scene(choice["next"])

func _handle_item_pickup(choice: Dictionary):
	# Gestisce il pickup di un item
	var item_id = choice.get("item_id", "")
	if not game.player_manager.has_item(item_id):
		game.player_manager.add_item(item_id)
		var icon = game.item_manager.get_item_icon(item_id)
		var item_name = game.item_manager.get_item_name(item_id)
		var display_name = ("%s " % icon if icon and icon != "" else "") + item_name
		game.ui_manager.text.text = tr("item_picked_up") % [display_name]
		game.ui_manager.update_stats()

func _start_qte():
	# Avvia un Quick Time Event
	if game and game.has_method("start_qte_event"):
		game.start_qte_event()

func _prepare_combat(choice: Dictionary):
	# Prepara e avvia il combattimento
	current_entity_id = choice.get("entity_id", "")
	current_victory_scene = choice.get("victory_scene", "")
	_start_prepared_combat()

func _prepare_dialogue(choice: Dictionary):
	# Prepara e avvia il dialogo
	current_entity_id = choice.get("entity_id", "")
	current_victory_scene = choice.get("victory_scene", "")
	var entity_data = game.data_manager.get_entity_data(current_entity_id)
	current_entity_pronoun = entity_data.get("pronoun", "")
	_start_prepared_dialogue()

func _start_rune_casting():
	# Avvia il minigioco delle rune
	if game.rune_manager:
		game.rune_manager.start_rune_casting()

func _start_prepared_combat():
	# Avvia il combattimento con l'entità preparata
	if game.combat_manager:
		was_in_combat = true
		game.combat_manager.start_combat(current_entity_id, current_victory_scene)

func _start_prepared_dialogue():
	# Avvia il dialogo con l'entità preparata
	if game.dialogue_manager:
		was_in_combat = false
		game.dialogue_manager.start_dialogue(current_entity_id, current_entity_pronoun, 0, current_victory_scene)

func _notify_entity_death(entity_id: String):
	# Notifica la morte di un'entità (da implementare secondo la logica di gioco)
	# Questa funzione dovrebbe essere implementata secondo le esigenze specifiche del gioco
	pass

func _clear_signals(button: Button):
	# Rimuove tutti i segnali connessi a un pulsante
	var connections = button.pressed.get_connections()
	for connection in connections:
		button.pressed.disconnect(connection["callable"])

func _init_ui_references():
	# Inizializza i riferimenti ai nodi UI
	if not game:
		push_error("SceneManager: game reference not set!")
		return
	
	b1 = game.get_node("UI/VBC_Main/VBC_Button/MC1/Choice1")
	b2 = game.get_node("UI/VBC_Main/VBC_Button/MC2/Choice2")
	b3 = game.get_node("UI/VBC_Main/VBC_Button/MC3/Choice3")
