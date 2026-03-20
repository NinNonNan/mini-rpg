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
var game


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

# Variabile temporanea per la magia selezionata in attesa di bersaglio
var pending_spell_id: String = ""

# Variabile temporanea per i dati della combo runica in attesa di bersaglio
var pending_rune_data: Dictionary = {}


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
	current_entity_health = 5 # Valore di default se non specificato
	if entity_def.has("energy"):
		# Cerca la statistica "life" nell'array energy in modo funzionale
		var life_stats = entity_def["energy"].filter(func(stat): return stat.get("type") == "life")
		if not life_stats.is_empty():
			current_entity_health = int(life_stats[0].get("value", 5))
	elif entity_def.has("health"): # Fallback per vecchia struttura
		current_entity_health = int(entity_def.get("health", 5))

	current_entity_damage_data = entity_def.get("damage", 2)

	# Aggiorna la UI delle statistiche
	game.update_stats()

	# Messaggio iniziale di combattimento
	game.text.text = game.tr("combat_start") % current_entity_health

	# Mostra i pulsanti di combattimento
	show_combat_buttons()

# Modifica l'energia dell'entità corrente (Chiamato da SpecialManager per infliggere danni)
func modify_current_entity_energy(type_id: String, amount: int):
	# Per ora i nemici hanno solo "life", quindi applichiamo tutto alla salute
	if type_id == "life":
		current_entity_health += amount

# =========================================================
# CONFIGURAZIONE PULSANTI COMBATTIMENTO
# =========================================================
# Imposta i pulsanti disponibili nel turno del giocatore.

func show_combat_buttons():
	# Riabilita i pulsanti (nel caso fossero disabilitati da QTE o altro)
	game.enable_choices()

	# -----------------------------------------------------
	# PULSANTE 1 : ATTACCO
	# -----------------------------------------------------
	game.b1.text = game.tr("choice_attack")
	game.b1.show()

	game._clear_signals(game.b1)
	game.b1.pressed.connect(initiate_attack_qte, CONNECT_ONE_SHOT)

	# -----------------------------------------------------
	# PULSANTE 2 : ABILITÀ / SPECIAL
	# -----------------------------------------------------
	
	game.b2.text = game.tr("combat_choice_special")
	game.b2.show()

	game._clear_signals(game.b2)
	game.b2.pressed.connect(open_special_menu)

	# -----------------------------------------------------
	# PULSANTE 3 : FUGA O RUNE
	# -----------------------------------------------------

	# Flag interno per decidere quale meccanica visualizzare (come richiesto)
	var use_runes_system = true

	if use_runes_system:
		game.b3.text = game.tr("combat_choice_runes")
		game.b3.show()
		game._clear_signals(game.b3)
		game.b3.pressed.connect(start_rune_combat, CONNECT_ONE_SHOT)
	else:
		game.b3.text = game.tr("combat_choice_flee")
		game.b3.show()
		game._clear_signals(game.b3)
		game.b3.pressed.connect(flee_combat, CONNECT_ONE_SHOT)


# =========================================================
# MENU ABILITÀ
# =========================================================

func open_special_menu():
	# Controllo di sicurezza: se il manager non è caricato, interrompi per evitare crash
	if not game.special_manager:
		push_error("SpecialManager non trovato! Impossibile aprire il menu abilità.")
		return

	var all_spells = game.special_manager.spells
	var spell_keys = all_spells.keys()
	var buttons = [game.b1, game.b2] # Array di pulsanti per le magie, facilmente estendibile

	# Popola dinamicamente i pulsanti con le magie disponibili
	for i in range(buttons.size()):
		var button = buttons[i]
		game._clear_signals(button) # Pulisce segnali precedenti

		if i < spell_keys.size():
			# C'è una magia da assegnare a questo pulsante
			var spell_id = spell_keys[i]
			var spell_data = all_spells[spell_id]
			var icon = game.get_damage_type_icon(spell_data.get("type", ""))

			button.text = "%s %s (%d MP)" % [icon, game.tr(spell_data.name), spell_data.cost]
			# Usiamo .bind() per passare l'ID della magia in modo sicuro ed evitare problemi di scope
			button.pressed.connect(prepare_spell_cast.bind(spell_id))
			button.show()
		else:
			# Non ci sono più magie, nascondi i pulsanti rimanenti
			button.hide()

	# Indietro (Button 3)
	game.b3.text = game.tr("combat_back")
	game.b3.show()
	game._clear_signals(game.b3)
	game.b3.pressed.connect(show_combat_buttons) # Ritorna al menu di combattimento principale

# Fase 1: Preparazione e Selezione Bersaglio
func prepare_spell_cast(spell_id: String):
	# Controllo Mana preventivo
	if not game.special_manager.has_enough_mana(spell_id):
		var cost = game.special_manager.spells[spell_id].cost
		game.text.text = game.tr("spell_cost_low") % cost
		await get_tree().create_timer(1.0).timeout
		open_special_menu()
		return

	pending_spell_id = spell_id
	
	# Cambia UI per chiedere il bersaglio
	game.text.text = game.tr("combat_select_target")
	
	# Nasconde i pulsanti delle magie
	game.b1.hide()
	game.b2.hide()
	
	# Pulsante Indietro diventa Annulla
	game.b3.text = game.tr("combat_back")
	game.b3.show()
	game._clear_signals(game.b3)
	game.b3.pressed.connect(cancel_spell_selection)
	
	# Attiva le icone cliccabili
	game.enable_target_selection()
	game.target_clicked.connect(_on_target_chosen, CONNECT_ONE_SHOT)

func cancel_spell_selection():
	game.disable_target_selection()
	# Disconnette il segnale se era attivo (per evitare doppie chiamate future)
	if game.target_clicked.is_connected(_on_target_chosen):
		game.target_clicked.disconnect(_on_target_chosen)
	open_special_menu()

# Fase 2: Bersaglio Selezionato ed Esecuzione
func _on_target_chosen(target_type: String):
	game.disable_target_selection()
	
	# Determina l'ID del bersaglio
	var target_id = ""
	if target_type == "player":
		target_id = "player"
	elif target_type == "enemy":
		target_id = current_entity_id
	
	if target_id != "":
		await execute_spell(pending_spell_id, target_id)

func execute_spell(spell_id: String, target_id: String):
		
	# Esegue la magia
	game.text.text = game.special_manager.use_spell(spell_id, target_id)
	game.update_stats()
	
	await get_tree().create_timer(1.5).timeout
	
	# Controllo vittoria immediato o Turno nemico
	if not await _check_victory():
		entity_turn()
	

# -- Vecchie funzioni rimosse o sostituite dalla nuova UI --

# (La funzione analyze_turn e use_item_turn sono momentaneamente rimosse dall'UI 
# per fare spazio alle abilità, ma la logica rimane nel codice se volessi ripristinarle in sottomenu)


#	# Codice precedente per referenza (B3 items/analyze)
#	# Se il nemico non è ancora conosciuto
#	if game.empathy_manager and not game.empathy_manager.is_known:
#		game.b3.text = game.tr("combat_choice_analyze")
#		game.b3.show()
#		game._clear_signals(game.b3)
#		game.b3.pressed.connect(analyze_turn, CONNECT_ONE_SHOT)
#	else:
#		# Se il nemico è già analizzato possiamo usare oggetti
#		var consumable_id = game.item_manager.get_first_consumable()
#		if consumable_id != "":
#			var item_name_key = game.item_data.get(consumable_id, {}).get("name", consumable_id)
#			game.b3.text = game.tr("combat_choice_use_item") % game.tr(item_name_key)
#			game.b3.show()
#			game._clear_signals(game.b3)
#			game.b3.pressed.connect(func(): use_item_turn(consumable_id), CONNECT_ONE_SHOT)

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
# SISTEMA RUNE
# =========================================================

func start_rune_combat():
	# Verifica che il RuneManager esista nel Game
	if "rune_manager" in game and game.rune_manager:
		# Connettiamo il segnale per la richiesta bersaglio (NUOVO)
		if not game.rune_manager.request_target_selection.is_connected(_on_rune_target_requested):
			game.rune_manager.request_target_selection.connect(_on_rune_target_requested)
		
		# Connettiamo il segnale di fine combo (per gestire fallimenti/fizzle)
		if not game.rune_manager.combo_finished.is_connected(_on_rune_sequence_finished):
			game.rune_manager.combo_finished.connect(_on_rune_sequence_finished)
			
		game.rune_manager.start_rune_casting()
	else:
		push_error("RuneManager non trovato! Impossibile avviare la sequenza rune.")
		# Fallback: passa il turno se qualcosa va storto
		entity_turn()

func _on_rune_target_requested(spell_data):
	pending_rune_data = spell_data
	
	# Configura la UI per la selezione bersaglio
	game.text.text = game.tr("combat_select_target")
	
	# Nasconde i pulsanti di combattimento
	game.b1.hide()
	game.b2.hide()
	
	# Pulsante Indietro (Annulla selezione ma perde il turno/runa)
	game.b3.text = game.tr("combat_back")
	game.b3.show()
	game._clear_signals(game.b3)
	game.b3.pressed.connect(cancel_rune_selection)
	
	# Attiva le icone cliccabili sui bersagli
	game.enable_target_selection()
	game.target_clicked.connect(_on_rune_target_chosen, CONNECT_ONE_SHOT)

func cancel_rune_selection():
	game.disable_target_selection()
	if game.target_clicked.is_connected(_on_rune_target_chosen):
		game.target_clicked.disconnect(_on_rune_target_chosen)
	# Se annulli dopo aver castato le rune, torni al menu principale ma hai perso l'occasione di lanciare.
	show_combat_buttons()

func _on_rune_target_chosen(target_type):
	game.disable_target_selection()
	
	var target_id = ""
	if target_type == "player": target_id = "player"
	elif target_type == "enemy": target_id = current_entity_id
	elif target_type == "back":
		cancel_rune_selection()
		return
	
	if target_id != "":
		_execute_rune_combo(target_id)

func _execute_rune_combo(target_id):
	var data = pending_rune_data
	var power = int(data.get("power", 0))
	var cost = int(data.get("cost", 0))
	var type = data.get("type", "neutral")
	var spell_name = data.get("name", "Combo Runica")

	# Consuma Mana
	game.modify_player_energy("magic", -cost)
	
	# Recupera dati del bersaglio per resistenze/affinità
	var affinities = []
	var immunities = []
	var weaknesses = []
	
	if target_id == "player":
		var p_data = game.story_data.get("player", {})
		affinities = p_data.get("affinity", [])
		weaknesses = p_data.get("weaknesses", [])
		immunities = p_data.get("immunities", [])
	else:
		var e_data = game.entity_data.get(current_entity_id, {})
		affinities = e_data.get("affinity", [])
		weaknesses = e_data.get("weaknesses", [])
		immunities = e_data.get("immunities", [])

	var damage = power
	var msg = ""
	var msg_extra = ""
	
	# ========================================================================================
	# SISTEMA DI CURA BASATO SU AFFINITÀ (IMPORTANTE: NON MODIFICARE)
	# Non esiste un tipo "Cura" dedicato. La cura avviene quando il bersaglio viene colpito
	# da un tipo di energia per cui possiede un'affinità.
	# Se type è in affinities -> Il danno diventa negativo (ovvero cura).
	# ========================================================================================
	if type in affinities:
		damage *= -1 # Affinità inverte il danno (Cura)
		msg_extra = game.tr("combat_damage_affinity") % type
	elif type in immunities:
		damage = 0
		msg_extra = game.tr("combat_damage_immunity") % type
	elif type in weaknesses:
		damage *= 2
		msg_extra = game.tr("combat_damage_weakness")
	
	# Applica Danno/Cura
	if target_id == "player":
		# Controlliamo se questo danno sarà letale PRIMA di applicarlo.
		# Se il giocatore muore, modify_player_energy resetta le variabili globali (Game Over),
		# quindi dobbiamo interrompere l'esecuzione qui per non attivare erroneamente la vittoria.
		var is_lethal = damage > 0 and (game.health - damage) <= 0

		# modify_player_energy: +amount = cura, -amount = danno
		# Se 'damage' è negativo (cura), -damage diventa positivo.
		game.modify_player_energy("life", -damage)
		
		if is_lethal:
			return

		if damage < 0:
			msg = game.tr("spell_cast_heal") % [spell_name, abs(damage)]
		else:
			msg = "Ti sei colpito con %s per %d danni!" % [spell_name, damage] + msg_extra
	
	elif target_id == current_entity_id:
		current_entity_health -= damage
		if current_entity_health < 0: current_entity_health = 0
		
		if damage < 0:
			msg = "Il nemico assorbe %s e si cura!" % type
		else:
			msg = game.tr("spell_cast_damage") % [spell_name, damage] + msg_extra

	game.text.text = msg
	game.update_stats()

	await get_tree().create_timer(1.5).timeout

	if await _check_victory():
		return
	
	entity_turn()

func _on_rune_sequence_finished(_total_spells):
	# Viene chiamato solo se la combo fallisce (0 spells)
	# Passa il turno al nemico (punizione per il fallimento)
	entity_turn()

# =========================================================
# ATTACCO DEL GIOCATORE
# =========================================================

func initiate_attack_qte():
	# Avvia l'evento QTE per l'attacco del giocatore.
	# Il contesto "player_attack" dirà a Game.gd come gestire il risultato.
	game.start_qte_event("qte_start_attack", "player_attack")

# Viene chiamata da Game.gd al termine del QTE di attacco.
func resolve_player_attack(qte_multiplier: float):
	
	# Calcolo del danno tramite ItemManager
	var damage_result = game.item_manager.get_player_damage()

	var total_damage = damage_result[0]
	var damage_die = damage_result[1]
	var quality = damage_result[2]
	var damage_type = damage_result[3]
	
	# Applica il moltiplicatore del QTE al danno base
	total_damage = int(total_damage * qte_multiplier)

	# Recuperiamo i dati sulle resistenze del nemico corrente
	var entity_def = game.entity_data.get(current_entity_id, {})
	var weaknesses = entity_def.get("weaknesses", [])
	var immunities = entity_def.get("immunities", [])
	var affinities = entity_def.get("affinity", [])
	
	var multiplier_msg = ""

	# Controllo Debolezze e Immunità
	if damage_type != "":
		# Controlla prima l'affinità, che inverte il danno in cura
		if damage_type in affinities:
			total_damage *= -1 # Inverte il danno in cura
			multiplier_msg = game.tr("combat_damage_affinity") % damage_type
		# Poi controlla immunità
		elif damage_type in immunities:
			total_damage = 0
			multiplier_msg = game.tr("combat_damage_immunity") % damage_type
		
		# Infine controlla debolezze
		elif damage_type in weaknesses:
			total_damage *= 2
			multiplier_msg = game.tr("combat_damage_weakness")

	# Applichiamo il danno (che potrebbe essere stato azzerato o raddoppiato)
	var hp_before = current_entity_health
	current_entity_health -= total_damage
	print("[COMBAT LOG] Player Attack -> %s | Type: %s | DMG: %d | HP: %d -> %d" % [current_entity_id, damage_type, total_damage, hp_before, current_entity_health])

	# Il testo del risultato del QTE (es. "PERFECT!") è già stato mostrato da Game.gd.
	# Aggiungiamo una nuova riga con i dettagli del danno.
	var damage_details_text: String
	if quality > 0:
		if damage_type != "":
			damage_details_text = game.tr("combat_player_attack_bonus_type") % [damage_type, damage_die, quality, total_damage]
		else:
			damage_details_text = game.tr("combat_player_attack_bonus") % [damage_die, quality, total_damage]
	else:
		if damage_type != "":
			damage_details_text = game.tr("combat_player_attack_type") % [damage_type, damage_die, total_damage]
		else:
			damage_details_text = game.tr("combat_player_attack") % [damage_die, total_damage]
	
	game.text.text += "\n" + damage_details_text

	# Aggiungiamo il messaggio di feedback sull'efficacia
	game.text.text += multiplier_msg

	game.update_stats()

	# -----------------------------------------------------
	# CONTROLLO VITTORIA
	# -----------------------------------------------------

	if await _check_victory():
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

	var hp_before = game.health
	game.health -= damage
	print("[COMBAT LOG] Enemy Attack (%s) -> Player | Type: %s | DMG: %d | HP: %d -> %d" % [current_entity_id, attack_type, damage, hp_before, game.health])

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

# Funzione centralizzata per gestire la vittoria e le ricompense
func _check_victory() -> bool:
	if current_entity_health <= 0:
		current_entity_health = 0
		game.text.text = game.tr("combat_victory")
		
		# Calcolo Ricompense Energia
		if game.growth_manager:
			var reward = game.growth_manager.calculate_reward(current_entity_id)
			if reward > 0:
				game.growth_manager.add_energy(reward)
				game.text.text += "\n" + game.tr("growth_energy_gained") % reward
		
		game.update_stats()
		await get_tree().create_timer(2.0).timeout
		
		# Invece di andare alla scena, apriamo il menu di crescita
		game.start_growth_menu(current_victory_scene)
		return true
		
	return false
