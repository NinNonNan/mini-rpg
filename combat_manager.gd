# =========================================================
# COMBAT MANAGER
# =========================================================
# Gestisce tutta la logica del combattimento:
# - inizializzazione dello scontro
# - turni giocatore / nemico
# - analisi del nemico
# - uso oggetti
# - fuga
# - vittoria o sconfitta
#
# La UI e lo stato globale rimangono gestiti da Game.
# Questo manager si occupa solo della logica di combattimento.

class_name CombatManager
extends Node  # Non è un elemento visivo, quindi basta Node


# =========================================================
# RIFERIMENTO AL GAME
# =========================================================
# Permette al CombatManager di accedere a:
# - UI (text, pulsanti)
# - dati globali (entity_data, inventory)
# - altri manager (ItemManager, EmpathyManager)
#
# Questo riferimento viene assegnato in Game._ready():
#
# combat_manager.game = self
#
var game: Game


# =========================================================
# STATO DEL COMBATTIMENTO
# =========================================================

# ID dell'entità che stiamo combattendo
var current_entity_id: String = ""

# Salute attuale dell'entità
var current_entity_health = 0

# Dati del danno dell'entità (può essere un int o un Array di dizionari)
var current_entity_damage_data = null

# Scena da caricare dopo la vittoria
var current_victory_scene = ""


# =========================================================
# INIZIO COMBATTIMENTO
# =========================================================
# Viene chiamata dal Game quando un incontro diventa
# ostile oppure quando il dialogo fallisce.

func start_combat(entity_id: String, victory_scene: String):

	current_entity_id = entity_id
	current_victory_scene = victory_scene

	# Recuperiamo le statistiche dell'entità dal database
	var entity_def = game.entity_data.get(entity_id, {})

	# Se il JSON non definisce i valori usiamo default
	current_entity_health = int(entity_def.get("health", 5))
	current_entity_damage_data = entity_def.get("damage", 2)

	# Aggiorna la UI delle statistiche
	game.update_stats()

	# Messaggio iniziale di combattimento
	game.text.text = game.tr("combat_start") % current_entity_health

	# Mostra i pulsanti di combattimento
	show_combat_buttons()


# =========================================================
# CONFIGURAZIONE PULSANTI COMBATTIMENTO
# =========================================================
# Imposta i pulsanti disponibili nel turno del giocatore.

func show_combat_buttons():

	# -----------------------------------------------------
	# PULSANTE 1 : ATTACCO
	# -----------------------------------------------------
	game.b1.text = game.tr("choice_attack")
	game.b1.show()

	game._clear_signals(game.b1)
	game.b1.pressed.connect(attack_entity, CONNECT_ONE_SHOT)

	# -----------------------------------------------------
	# PULSANTE 2 : FUGA
	# -----------------------------------------------------
	game.b2.text = game.tr("combat_choice_flee")
	game.b2.show()

	game._clear_signals(game.b2)
	game.b2.pressed.connect(flee_combat, CONNECT_ONE_SHOT)

	# -----------------------------------------------------
	# PULSANTE 3 : ANALISI O OGGETTO
	# -----------------------------------------------------

	game.b3.hide()

	# Se il nemico non è ancora conosciuto
	if game.empathy_manager and not game.empathy_manager.is_known:

		game.b3.text = game.tr("combat_choice_analyze")
		game.b3.show()

		game._clear_signals(game.b3)
		game.b3.pressed.connect(analyze_turn, CONNECT_ONE_SHOT)

	else:

		# Se il nemico è già analizzato possiamo usare oggetti
		var consumable_id = game.item_manager.get_first_consumable()

		if consumable_id != "":

			var item_name_key = game.item_data.get(consumable_id, {}).get("name", consumable_id)

			game.b3.text = game.tr("combat_choice_use_item") % game.tr(item_name_key)
			game.b3.show()

			game._clear_signals(game.b3)
			game.b3.pressed.connect(func(): use_item_turn(consumable_id), CONNECT_ONE_SHOT)


# =========================================================
# ANALISI DEL NEMICO
# =========================================================
# Permette al giocatore di scoprire informazioni sull'entità.
# Utilizza l'EmpathyManager per determinare il comportamento.

func analyze_turn():

	# Delega la logica all'EmpathyManager
	game.text.text = game.empathy_manager.analyze(current_entity_id)

	game.update_stats()

	await get_tree().create_timer(1.5).timeout

	# Dopo l'analisi il nemico reagisce
	entity_turn()


# =========================================================
# USO OGGETTO
# =========================================================
# Usa un oggetto consumabile durante il combattimento.

func use_item_turn(item_id):

	# La logica dell'oggetto è gestita dall'ItemManager
	game.text.text = game.item_manager.use_item(item_id)

	game.update_stats()

	await get_tree().create_timer(1.5).timeout

	# Il nemico reagisce
	entity_turn()


# =========================================================
# ATTACCO DEL GIOCATORE
# =========================================================

func attack_entity():

	# Calcolo del danno tramite ItemManager
	var damage_result = game.item_manager.get_player_damage()

	var total_damage = damage_result[0]
	var damage_die = damage_result[1]
	var quality = damage_result[2]
	var damage_type = damage_result[3]

	# Recuperiamo i dati sulle resistenze del nemico corrente
	var entity_def = game.entity_data.get(current_entity_id, {})
	var weaknesses = entity_def.get("weaknesses", [])
	var immunities = entity_def.get("immunities", [])
	
	var multiplier_msg = ""

	# Controllo Debolezze e Immunità
	if damage_type != "":
		# Controlla immunità (ora array di stringhe)
		if damage_type in immunities:
			total_damage = 0
			multiplier_msg = game.tr("combat_damage_immunity") % damage_type
		
		# Controlla debolezze (se non è già immune e non è stato azzerato)
		elif damage_type in weaknesses:
			total_damage *= 2
			multiplier_msg = game.tr("combat_damage_weakness")

	# Applichiamo il danno (che potrebbe essere stato azzerato o raddoppiato)
	current_entity_health -= total_damage

	if quality > 0:
		if damage_type != "":
			game.text.text = game.tr("combat_player_attack_bonus_type") % [damage_type, damage_die, quality, total_damage]
		else:
			game.text.text = game.tr("combat_player_attack_bonus") % [damage_die, quality, total_damage]
	else:
		if damage_type != "":
			game.text.text = game.tr("combat_player_attack_type") % [damage_type, damage_die, total_damage]
		else:
			game.text.text = game.tr("combat_player_attack") % [damage_die, total_damage]

	# Aggiungiamo il messaggio di feedback sull'efficacia
	game.text.text += multiplier_msg

	game.update_stats()

	await get_tree().create_timer(1.0).timeout


	# -----------------------------------------------------
	# CONTROLLO VITTORIA
	# -----------------------------------------------------

	if current_entity_health <= 0:

		current_entity_health = 0

		game.text.text = game.tr("combat_victory")

		game.update_stats()

		await get_tree().create_timer(1.5).timeout

		game.show_scene(current_victory_scene)

		return


	# Se il nemico è vivo
	entity_turn()


# =========================================================
# TENTATIVO DI FUGA
# =========================================================

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

		entity_turn()


# =========================================================
# TURNO DEL NEMICO
# =========================================================
# Dopo l'azione del giocatore il nemico attacca.

func entity_turn():

	var max_damage = 2 # Valore di fallback
	var attack_type = ""
	
	# Logica di selezione del danno
	# Caso 1: Array di attacchi (es. Drago)
	if typeof(current_entity_damage_data) == TYPE_ARRAY and not current_entity_damage_data.is_empty():
		# Sceglie un attacco a caso dalla lista
		var attack = current_entity_damage_data.pick_random()
		# Gestisce sia array di oggetti {"amount": 5} che array di numeri [2, 5]
		if typeof(attack) == TYPE_DICTIONARY:
			max_damage = int(attack.get("amount", 2))
			attack_type = str(attack.get("type", ""))
		else:
			max_damage = int(attack)
			
	# Caso 2: Danno semplice intero (es. Lupo)
	elif typeof(current_entity_damage_data) == TYPE_INT or typeof(current_entity_damage_data) == TYPE_FLOAT:
		max_damage = int(current_entity_damage_data)

	var damage = randi_range(1, max_damage)

	game.health -= damage

	game.update_stats()

	if game.health <= 0:

		game.game_over()

	else:

		if attack_type != "":
			game.text.text = game.tr("combat_enemy_attack_type") % [attack_type, max_damage, damage]
		else:
			game.text.text = game.tr("combat_enemy_attack") % [max_damage, damage]

		await get_tree().create_timer(1.5).timeout

		# Torna il turno del giocatore
		show_combat_buttons()
