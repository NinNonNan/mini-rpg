# Registriamo la classe globalmente con il nome CombatManager
# Questo permette di usare "CombatManager" come tipo in altri script
class_name CombatManager
extends Node  # Estende Node perché non deve essere visibile in scena come Control

# --- Riferimento al nodo principale del gioco ---
# Contiene tutte le informazioni principali: UI, inventario, nemici, ecc.
var game: Game


# --- Stato del combattimento ---
var current_entity_id: String = ""        # ID dell'entità che stiamo combattendo
var current_entity_health = 0             # HP dell'entità in combattimento
var current_entity_damage = 0             # Danno che il nemico infligge al giocatore
var current_victory_scene = ""            # Scena da mostrare quando il nemico viene sconfitto


# --- Funzione principale: inizia il combattimento ---
func start_combat(entity_id: String, victory_scene: String):
	current_entity_id = entity_id
	current_victory_scene = victory_scene

	# Prendiamo le statistiche dell'entità dal database globale
	var entity_def = game.entity_data.get(entity_id, {})
	current_entity_health = entity_def.get("health", 5)   # Default 5 HP se non definito
	current_entity_damage = entity_def.get("damage", 2)  # Default 2 danni se non definito

	# Resettiamo le informazioni sul nemico (ad esempio se lo abbiamo già analizzato)
	if game.empathy_manager:
		game.empathy_manager.reset()

	# Aggiorniamo la UI delle statistiche (HP, inventario, ecc.)
	game.update_stats()

	# Mostriamo un messaggio iniziale, con traduzione tramite tr()
	game.text.text = game.tr("combat_start") % current_entity_health

	# Mostriamo i pulsanti per il combattimento
	show_combat_buttons()


# --- Configura i pulsanti durante il combattimento ---
func show_combat_buttons():
	# --- Pulsante 1: ATTACCA ---
	game.b1.text = game.tr("choice_attack")
	game.b1.show()
	game._clear_signals(game.b1)             # Rimuove eventuali vecchi collegamenti
	game.b1.pressed.connect(attack_entity, CONNECT_ONE_SHOT)

	# --- Pulsante 2: FUGGI ---
	game.b2.text = game.tr("combat_choice_flee")
	game.b2.show()
	game._clear_signals(game.b2)
	game.b2.pressed.connect(flee_combat, CONNECT_ONE_SHOT)

	# --- Pulsante 3: ANALIZZA o USA OGGETTO ---
	game.b3.hide()  # Default: nascosto

	# Se il nemico non è ancora conosciuto, permetti di analizzarlo
	if game.empathy_manager and not game.empathy_manager.is_known:
		game.b3.text = game.tr("combat_choice_analyze")
		game.b3.show()
		game._clear_signals(game.b3)
		game.b3.pressed.connect(analyze_turn, CONNECT_ONE_SHOT)
	else:
		# Se conosciamo il nemico, vediamo se possiamo usare un oggetto curativo
		for item_id in game.inventory:
			if game.item_data.has(item_id) and game.item_data[item_id].has("heal"):
				var item_name_key = game.item_data.get(item_id, {}).get("name", item_id)
				var translated_item_name = game.tr(item_name_key)
				game.b3.text = game.tr("combat_choice_use_item") % translated_item_name
				game.b3.show()
				game._clear_signals(game.b3)
				game.b3.pressed.connect(func(): use_item(item_id), CONNECT_ONE_SHOT)
				break  # Usabile solo il primo oggetto curativo trovato


# --- Azioni durante il combattimento ---

# Analizza il nemico per scoprirne punti deboli
func analyze_turn():
	var entity_data = game.entity_data.get(current_entity_id, {})
	var mood = entity_data.get("mood", 0)
	
	game.empathy_manager.analyze(mood)  # Aggiorna lo stato del nemico

	var analysis_text = game.tr("combat_analysis_success")  # Testo standard
	if mood < -10:
		analysis_text = game.tr("combat_analysis_hostile")  # Se il nemico è molto ostile

	game.text.text = analysis_text
	game.update_stats()
	await get_tree().create_timer(1.5).timeout  # Piccola pausa visiva
	entity_turn()  # Il nemico reagisce dopo l'analisi


# Usa un oggetto dall'inventario
func use_item(item_id):
	var item_props = game.item_data[item_id]
	var heal_amount = item_props.get("heal", 0)
	var item_name_key = game.item_data.get(item_id, {}).get("name", item_id)
	var translated_item_name = game.tr(item_name_key)

	game.health = min(game.health + heal_amount, 10)  # Non superare 10 HP
	game.text.text = game.tr("combat_item_used") % [translated_item_name, heal_amount]

	# Se l'oggetto è consumabile, rimuovilo dall'inventario
	if item_props.get("consumable", false):
		game.inventory.erase(item_id)

	game.update_stats()
	await get_tree().create_timer(1.5).timeout
	entity_turn()  # Il nemico reagisce dopo l'uso dell'oggetto


# Attacco del giocatore
func attack_entity():
	var damage_die = 2  # Danno base
	for item_id in game.inventory:
		if game.item_data.has(item_id):
			var item_stats = game.item_data[item_id]
			damage_die = max(damage_die, item_stats.get("damage", 0))  # Usa l'arma più potente

	var damage = randi_range(1, damage_die)  # Dado: 1..damage_die
	current_entity_health -= damage

	game.text.text = game.tr("combat_player_attack") % [damage_die, damage]
	game.update_stats()
	await get_tree().create_timer(1.0).timeout

	# Controllo vittoria
	if current_entity_health <= 0:
		current_entity_health = 0
		game.text.text = game.tr("combat_victory")
		game.update_stats()
		await get_tree().create_timer(1.5).timeout
		game.show_scene(current_victory_scene)
		return

	entity_turn()  # Il nemico reagisce


# Tentativo di fuga
func flee_combat():
	game.text.text = game.tr("combat_flee_attempt")
	await get_tree().create_timer(1.0).timeout

	if randf() < 0.5:
		# Fuga riuscita
		game.text.text = game.tr("combat_flee_success")
		await get_tree().create_timer(1.5).timeout
		game.show_scene("start")
	else:
		# Fuga fallita
		game.text.text = game.tr("combat_flee_fail")
		await get_tree().create_timer(1.5).timeout
		entity_turn()  # Nemico attacca


# Turno del nemico
func entity_turn():
	var damage = randi_range(1, current_entity_damage)  # Danno casuale fino al massimo
	game.health -= damage
	game.update_stats()

	if game.health <= 0:
		game.game_over()  # Il giocatore muore
	else:
		game.text.text = game.tr("combat_enemy_attack") % [current_entity_damage, damage]
		await get_tree().create_timer(1.5).timeout
		show_combat_buttons()  # Torna il turno del giocatore