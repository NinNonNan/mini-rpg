# =========================================================
# COMBAT MANAGER
# =========================================================
# Gestisce la logica dei combattimenti a turni.
#
# Funzionalità principali:
# - Gestione turni (Giocatore <-> Nemico).
# - Calcolo danni (Fisici, Magici, Runici) e resistenze/debolezze.
# - Integrazione con QTE per attacchi fisici e RuneManager per la magia.
# - Gestione della selezione bersaglio e feedback visivo.
# - Risoluzione degli scontri (Vittoria/Fuga/Sconfitta).
#
# Scopo narrativo: Tradurre le interazioni ostili in una sfida tattica 
# basata sulle energie e sulle affinità elementali.

class_name CombatManager
extends Node

# --- Segnali ---
## Emesso quando un bersaglio viene selezionato durante una fase di puntamento.
signal target_selected(target_type)

# --- Riferimenti Esterni ---
## Riferimento al gioco principale (Game.gd). Iniettato in Game._ready().
var game

# --- Stato del Combattimento ---
## ID dell'entità attualmente in combattimento.
var current_entity_id: String = ""
## Salute attuale del nemico.
var current_entity_health: int = 0
## Dati del danno del nemico (int o Array di dizionari).
var current_entity_damage_data = null
## ID della scena da caricare in caso di vittoria.
var current_victory_scene: String = ""

# --- Cache Temporanea Azioni ---
## ID della magia selezionata in attesa di selezione bersaglio.
var pending_spell_id: String = ""
## Dati della combo runica calcolata in attesa di selezione bersaglio.
var pending_rune_data: Dictionary = {}
## Memorizza i tween attivi per la selezione bersaglio per poterli fermare.
var _target_tweens: Array[Tween] = []

## Avvia un nuovo scontro inizializzando i dati del nemico e la UI.
## Input: 
## - entity_id (String): L'ID del nemico nel database.
## - victory_scene (String): La scena successiva in caso di successo.
## Output: Nessuno.
func start_combat(entity_id: String, victory_scene: String):
	current_entity_id = entity_id
	current_victory_scene = victory_scene

	# 1. CARICAMENTO DATI
	# -------------------
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

## Modifica la salute del nemico attuale.
## Input: type_id (String) - Tipo di energia; amount (int) - Valore da aggiungere/sottrarre.
## Output: Nessuno.
func modify_current_entity_energy(type_id: String, amount: int):
	# Per ora i nemici hanno solo "life", quindi applichiamo tutto alla salute
	if type_id == "life":
		current_entity_health += amount

## Calcola la probabilità di schivata del giocatore basata sulle energie fisiche.
## La schivata è limitata a un massimo del 75%.
## Input: Nessuno.
## Output: int - Percentuale di schivata (0-75).
func get_player_evasion() -> int:
	var phys_sum = 0
	var energy_types_def = game.story_data.get("energy_types", {})
	
	if not game.stats_manager:
		return 0
		
	for type_id in game.stats_manager.player_energy.keys():
		var def = energy_types_def.get(type_id, {})
		if def.get("bonus") == "evasion":
			phys_sum += game.get_player_energy_value(type_id)

	var evasion_chance = phys_sum * 2.0
	# Cap massimo al 75% per evitare invulnerabilità totale
	return int(min(evasion_chance, 75))

## Configura e mostra i pulsanti principali per le azioni di combattimento.
## Viene chiamata all'inizio di ogni turno del giocatore.
## Input: Nessuno.
## Output: Nessuno.
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

## Apre il sottomenu delle abilità speciali (magie).
## Popola dinamicamente i pulsanti in base alle magie caricate nello SpecialManager.
## Input: Nessuno.
## Output: Nessuno.
func open_special_menu():
	# Controllo di sicurezza: se il manager non è caricato, interrompi per evitare crash
	if not game.special_manager:
		push_error(game.tr("error_special_manager_missing"))
		return

	var all_spells = game.special_manager.spells
	var spell_keys = all_spells.keys()
	var buttons = [game.b1, game.b2] # Array di pulsanti per le magie, facilmente estendibile

	# 1. POPOLAMENTO DINAMICO
	# -----------------------
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

## Verifica i costi e prepara l'interfaccia per il lancio di una magia.
## Input: spell_id (String) - ID dell'incantesimo da lanciare.
## Output: Nessuno.
func prepare_spell_cast(spell_id: String):
	# Controllo Mana preventivo
	if not game.special_manager.has_enough_mana(spell_id):
		var cost = game.special_manager.spells[spell_id].cost
		game.text.text = game.tr("spell_cost_low") % cost
		await get_tree().create_timer(1.0).timeout
		open_special_menu()
		return

	pending_spell_id = spell_id
	var spell_type = game.special_manager.spells[spell_id].get("type", "")
	
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
	enable_target_selection(spell_type)
	target_selected.connect(_on_target_chosen, CONNECT_ONE_SHOT)

## Annulla la fase di puntamento di una magia e torna al menu abilità.
## Input: Nessuno.
## Output: Nessuno.
func cancel_spell_selection():
	disable_target_selection()
	# Disconnette il segnale se era attivo (per evitare doppie chiamate future)
	if target_selected.is_connected(_on_target_chosen):
		target_selected.disconnect(_on_target_chosen)
	open_special_menu()

## Callback invocata quando l'utente seleziona un bersaglio (Player o Nemico).
## Input: target_type (String) - "player" o "enemy".
## Output: Nessuno.
func _on_target_chosen(target_type: String):
	disable_target_selection()
	
	# Determina l'ID del bersaglio
	var target_id = ""
	if target_type == "player":
		# Target "player" è una keyword speciale riconosciuta dallo SpecialManager
		target_id = "player"
	elif target_type == "enemy":
		target_id = current_entity_id
	
	if target_id != "":
		await execute_spell(pending_spell_id, target_id)

## Esegue l'effetto di una magia sul bersaglio selezionato e passa il turno.
## Input: spell_id (String) - ID incantesimo; target_id (String) - ID del bersaglio.
## Output: Nessuno.
func execute_spell(spell_id: String, target_id: String):
	if OS.is_debug_build():
		print(game.tr("debug_special_use") % [spell_id, target_id])
		
	# Delega l'esecuzione effettiva (calcolo danni/cure/costi) allo SpecialManager.
	# Lo SpecialManager restituisce una stringa descrittiva dell'effetto.
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

## Analizza il nemico per rivelare le sue statistiche e passa il turno.
## Utilizza l'EmpathyManager per la logica di analisi.
## Input: Nessuno.
## Output: Nessuno.
func analyze_turn():
	# Delega la logica all'EmpathyManager
	game.text.text = game.empathy_manager.analyze(current_entity_id)

	game.update_stats()

	await get_tree().create_timer(1.5).timeout

	# Dopo l'analisi il nemico reagisce
	entity_turn()

## Utilizza un oggetto consumabile durante il proprio turno.
## Input: item_id (String) - ID dell'oggetto da usare.
## Output: Nessuno.
func use_item_turn(item_id):
	# La logica dell'oggetto è gestita dall'ItemManager
	game.text.text = game.item_manager.use_item(item_id)

	game.update_stats()

	await get_tree().create_timer(1.5).timeout

	# Il nemico reagisce
	entity_turn()

## Avvia la sequenza di casting tramite RuneManager.
## Connette i segnali necessari per gestire l'esito della combo.
## Input: Nessuno.
## Output: Nessuno.
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
		push_error(game.tr("error_rune_manager_missing"))
		# Fallback: passa il turno se qualcosa va storto
		entity_turn()

## Callback: Il RuneManager ha calcolato la combo e richiede un bersaglio.
## Input: spell_data (Dictionary) - Dati dell'incantesimo aggregato {power, type, cost, name}.
## Output: Nessuno.
func _on_rune_target_requested(spell_data: Dictionary):
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
	enable_target_selection(spell_data.get("type", "neutral"))
	target_selected.connect(_on_rune_target_chosen, CONNECT_ONE_SHOT)

## Annulla la selezione del bersaglio per le rune (comporta la perdita del turno).
## Input: Nessuno.
## Output: Nessuno.
func cancel_rune_selection():
	disable_target_selection()
	if target_selected.is_connected(_on_rune_target_chosen):
		target_selected.disconnect(_on_rune_target_chosen)
	# Se annulli dopo aver castato le rune, torni al menu principale ma hai perso l'occasione di lanciare.
	show_combat_buttons()

## Callback invocata alla selezione del bersaglio per la combo runica.
## Input: target_type (String) - ID del tipo di bersaglio ("player", "enemy", "back").
## Output: Nessuno.
func _on_rune_target_chosen(target_type: String):
	disable_target_selection()
	
	var target_id = ""
	if target_type == "player": target_id = "player"
	elif target_type == "enemy": target_id = current_entity_id
	elif target_type == "back":
		cancel_rune_selection()
		return
	
	if target_id != "":
		_execute_rune_combo(target_id)

## Applica gli effetti della combo runica al bersaglio.
## Gestisce il consumo di mana e il calcolo dei moltiplicatori elementali.
## Input: target_id (String) - ID del bersaglio ("player" o ID nemico).
## Output: Nessuno.
@warning_ignore("shadowed_variable")
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
			msg = game.tr("combat_self_damage") % [spell_name, damage] + msg_extra
	
	elif target_id == current_entity_id:
		# Applica danno al nemico
		current_entity_health -= damage
		if current_entity_health < 0: current_entity_health = 0
		
		if damage < 0:
			msg = game.tr("combat_enemy_absorb") % type
		else:
			msg = game.tr("spell_cast_damage") % [spell_name, damage] + msg_extra

	game.text.text = msg
	game.update_stats()

	await get_tree().create_timer(1.5).timeout

	if await _check_victory():
		return
	
	entity_turn()

## Callback invocata quando la sequenza di rune termina senza produrre incantesimi.
## Input: _total_spells (int) - Numero di incantesimi generati (0 in questo caso).
## Output: Nessuno.
func _on_rune_sequence_finished(_total_spells):
	entity_turn()

## Avvia l'evento QTE per l'attacco fisico del giocatore.
## Input: Nessuno.
## Output: Nessuno.
func initiate_attack_qte():
	# Avvia l'evento QTE per l'attacco del giocatore.
	# Il contesto "player_attack" dirà a Game.gd come gestire il risultato.
	game.start_qte_event("qte_start_attack", "player_attack")

## Calcola e applica il danno dell'attacco fisico dopo il QTE.
## Input: qte_multiplier (float) - Il moltiplicatore ottenuto dal QTE.
## Output: Nessuno.
func resolve_player_attack(qte_multiplier: float):
	if not game.item_manager: return
	
	# Calcolo del danno tramite ItemManager
	# ItemManager controlla l'equipaggiamento e restituisce il danno base + bonus.
	var damage_result = game.item_manager.get_player_damage()

	var total_damage = damage_result[0]
	var damage_die = damage_result[1]
	var quality = damage_result[2]
	var damage_type = damage_result[3]
	# weapon_name serve per il log (es. "Spada" o "Pugni")
	var weapon_name = damage_result[4]
	
	# Applica il moltiplicatore del QTE al danno base
	total_damage = int(total_damage * qte_multiplier)

	# Recuperiamo i dati sulle resistenze del nemico corrente
	var entity_def = game.entity_data.get(current_entity_id, {})
	var weaknesses = entity_def.get("weaknesses", [])
	var immunities = entity_def.get("immunities", [])
	var affinities = entity_def.get("affinity", [])
	
	var multiplier_msg = ""

	# CALCOLO MOLTIPLICATORI ELEMENTALI
	# ---------------------------------
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

	print(game.tr("log_combat_player_attack") % [weapon_name, current_entity_id, damage_type, total_damage, hp_before, current_entity_health])

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


## Gestisce il turno dell'IA nemica: calcolo danno, check evasione e applicazione effetti.
## Input: Nessuno.
## Output: Nessuno.
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

	# --- CONTROLLO SCHIVATA ---
	var evasion_chance = get_player_evasion()
	# Genera un numero tra 0.0 e 100.0
	if randf() * 100.0 < float(evasion_chance):
		game.text.text = game.tr("combat_enemy_miss") % evasion_chance
		print(game.tr("log_combat_miss") % evasion_chance)
		await get_tree().create_timer(1.5).timeout
		show_combat_buttons()
		return
	else:
		print(game.tr("log_combat_hit") % evasion_chance)
	# --------------------------

	var hp_before = game.health
	game.health -= damage
	print(game.tr("log_combat_enemy_attack") % [current_entity_id, attack_type, damage, hp_before, game.health])
	game.update_stats()

	if game.health <= 0:
		# La morte è già gestita dal setter di game.health -> StatsManager -> DeathManager
		return

	else:

		if attack_type != "":
			game.text.text = game.tr("combat_enemy_attack_type") % [attack_type, max_damage, damage]
		else:
			game.text.text = game.tr("combat_enemy_attack") % [max_damage, damage]

		await get_tree().create_timer(1.5).timeout

		# Torna il turno del giocatore
		show_combat_buttons()

## Abilita le aree cliccabili (Giocatore/Nemico) per la selezione del bersaglio.
## Cambia il modulate delle box per riflettere se l'azione è benefica o ostile.
## Input: action_type (String) - Il tipo elementale dell'azione.
## Output: Nessuno.
func enable_target_selection(action_type: String = ""):
	# Pulisce eventuali animazioni residue
	for tw in _target_tweens: if tw: tw.kill()
	_target_tweens.clear()

	# Rendi i contenitori della UI intercettatori di click per la selezione bersaglio
	if game.player_box_container:
		var target_color = _get_color_for_effect("player", action_type)
		game.player_box_container.mouse_filter = Control.MOUSE_FILTER_STOP
		if not game.player_box_container.gui_input.is_connected(_on_player_target_input):
			game.player_box_container.gui_input.connect(_on_player_target_input)
		
		# Disabilitiamo il pulsante config stats affinché non blocchi il click del target
		var cfg_btn = game.player_box_container.find_child("StatsConfigButton", true, false)
		if cfg_btn: cfg_btn.mouse_filter = Control.MOUSE_FILTER_PASS
		
		# Crea l'animazione pulsante
		var tw = create_tween().set_loops()
		tw.tween_property(game.player_box_container, "modulate", target_color, 0.7).set_trans(Tween.TRANS_SINE)
		tw.tween_property(game.player_box_container, "modulate", Color.WHITE, 0.7).set_trans(Tween.TRANS_SINE)
		_target_tweens.append(tw)
	
	if game.enemy_stats_box:
		var target_color = _get_color_for_effect("enemy", action_type)
		game.enemy_stats_box.mouse_filter = Control.MOUSE_FILTER_STOP
		if not game.enemy_stats_box.gui_input.is_connected(_on_enemy_target_input):
			game.enemy_stats_box.gui_input.connect(_on_enemy_target_input)

		# Crea l'animazione pulsante
		var tw = create_tween().set_loops()
		tw.tween_property(game.enemy_stats_box, "modulate", target_color, 0.7).set_trans(Tween.TRANS_SINE)
		tw.tween_property(game.enemy_stats_box, "modulate", Color.WHITE, 0.7).set_trans(Tween.TRANS_SINE)
		_target_tweens.append(tw)

## Disabilita il puntamento UI e ripristina l'aspetto normale dei contenitori.
## Input: Nessuno.
## Output: Nessuno.
func disable_target_selection():
	# Ferma e rimuove tutte le animazioni attive
	for tw in _target_tweens: if tw: tw.kill()
	_target_tweens.clear()

	if game.player_box_container:
		game.player_box_container.modulate = Color.WHITE
		game.player_box_container.mouse_filter = Control.MOUSE_FILTER_PASS
		if game.player_box_container.gui_input.is_connected(_on_player_target_input):
			game.player_box_container.gui_input.disconnect(_on_player_target_input)
		
		# Ripristiniamo il pulsante config stats
		var cfg_btn = game.player_box_container.find_child("StatsConfigButton", true, false)
		if cfg_btn: cfg_btn.mouse_filter = Control.MOUSE_FILTER_STOP
	
	if game.enemy_stats_box:
		game.enemy_stats_box.modulate = Color.WHITE
		game.enemy_stats_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
		if game.enemy_stats_box.gui_input.is_connected(_on_enemy_target_input):
			game.enemy_stats_box.gui_input.disconnect(_on_enemy_target_input)

## Gestisce l'input del mouse sul contenitore del giocatore.
## Input: event (InputEvent) - L'evento di input catturato.
## Output: Nessuno.
func _on_player_target_input(event: InputEvent):
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		target_selected.emit("player")

## Gestisce l'input del mouse sul contenitore del nemico.
## Input: event (InputEvent) - L'evento di input catturato.
## Output: Nessuno.
func _on_enemy_target_input(event: InputEvent):
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		target_selected.emit("enemy")

## Calcola il colore di feedback (Rosso/Verde) in base all'affinità del bersaglio con l'azione.
## Input: target_type (String) - "player" o "enemy"; action_type (String) - Tipo di energia.
## Output: Color - Il colore da applicare al modulate.
@warning_ignore("shadowed_variable")
func _get_color_for_effect(target_type: String, action_type: String) -> Color:
	var affinities = []
	if target_type == "player":
		affinities = game.story_data.get("player", {}).get("affinity", [])
	else:
		# Recupera le affinità dell'entità corrente
		var entity_def = game.entity_data.get(current_entity_id, {})
		affinities = entity_def.get("affinity", [])
	
	if action_type != "" and action_type in affinities:
		return Color(0.8, 1.2, 0.8) # Verde (Cura/Affinità)
	return Color(1.2, 0.8, 0.8) # Rosso (Danno/Ostilità)

## Verifica se il nemico è stato sconfitto e assegna le ricompense di crescita.
## Input: Nessuno.
## Output: bool - true se il nemico è morto e lo scontro è terminato.
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
