# =========================================================
# RUNE MANAGER
# =========================================================
# Gestisce il sistema di magia basato sulle rune.
#
# Funzionalità principali:
# - Minigioco di input sequenziale (Quick Time Event mnemonico).
# - Gestione delle combo: più incantesimi lanciati in sequenza rapida.
# - Calcolo avanzato del danno: somma potenze dello stesso tipo e annulla opposti.
# - Integrazione con l'interfaccia utente dedicata (sovrapposta).
#
# Scopo narrativo: Rappresenta la manipolazione delle energie 
# primordiali attraverso il linguaggio dei segni antichi.

extends Control

# --- Segnali ---
## Emesso per richiedere la selezione di un bersaglio per l'incantesimo generato.
signal request_target_selection(spell_data)
## Emesso al termine della sessione di rune se non sono stati generati incantesimi.
signal combo_finished(total_spells)

# --- Riferimenti Esterni ---
## Riferimento al gioco principale (Game.gd). Iniettato in Game._ready().
var game

# --- Configurazione Gameplay ---
const MAX_COMBO_CHAIN = 7
const PERFECT_TIME_THRESHOLD_MS = 2500 # Sotto i 2.5s è "Perfetto" -> Combo
const MAX_TIME_FOR_MULTIPLIER_MS = 5000 # Sopra i 5s il moltiplicatore è 1.0x
## Fattore di riduzione del costo mana per ogni incantesimo in combo (25% di sconto).
const COST_SCALING_FACTOR = 0.75 

# --- Stato del Manager ---
var rune_data = {}
var damage_types_data = {}
var current_sequence = []
var current_icons = []
var start_time_ms = 0
var current_combo_index = 0
var is_active = false
var accumulated_spells = []

# --- Riferimenti UI ---
@onready var feedback_label = $Panel/CenterContainer/VBoxContainer/FeedbackLabel
@onready var rune_display_label = $Panel/CenterContainer/VBoxContainer/RuneDisplayLabel
@onready var grid_container = $Panel/CenterContainer/VBoxContainer/RuneGrid

## Configurazione iniziale del layout e caricamento dati.
## Input: Nessuno.
## Output: Nessuno.
func _ready():
	if self is Control:
		top_level = true
		set_anchors_and_offsets_preset(Control.PRESET_CENTER)

	_load_rune_data()
	hide()
	
	feedback_label.add_theme_font_size_override("font_size", 24)
	feedback_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	feedback_label.custom_minimum_size.y = 80
	feedback_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER

	rune_display_label.add_theme_font_size_override("font_size", 50)
	rune_display_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	rune_display_label.custom_minimum_size.y = 80
	rune_display_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER

## Carica le definizioni delle rune e dei tipi di danno dai file JSON.
## Input: Nessuno.
## Output: Nessuno (popola variabili locali).
func _load_rune_data():
	var runes_file = FileAccess.open("res://data/runes.json", FileAccess.READ)
	if runes_file:
		var json = JSON.new()
		var error = json.parse(runes_file.get_as_text())
		if error == OK:
			rune_data = json.data
		else:
			push_error(tr("error_rune_parse"))
	else:
		push_error(tr("error_rune_file_not_found"))
	
	var defs_file = FileAccess.open("res://data/definitions.json", FileAccess.READ)
	if defs_file:
		var json = JSON.new()
		var error = json.parse(defs_file.get_as_text())
		if error == OK:
			damage_types_data = json.data.get("damage_types", {})
	else:
		push_error(tr("error_definitions_file_not_found_rune"))

## Inizializza e mostra l'interfaccia per il lancio delle rune.
## Input: Nessuno.
## Output: Nessuno.
func start_rune_casting():
	top_level = true
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	$Panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	$Panel/CenterContainer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	show()
	is_active = true
	current_combo_index = 0
	accumulated_spells.clear()
	_prepare_round(tr("rune_prompt_start"))

## Prepara un nuovo round di input (resetta sequenza e rimescola pulsanti).
## Input: prompt_text (String) - Messaggio da visualizzare nel feedback.
## Output: Nessuno.
func _prepare_round(prompt_text: String) -> void:
	current_sequence.clear()
	current_icons.clear()
	start_time_ms = 0
	feedback_label.text = prompt_text
	rune_display_label.text = ""
	
	grid_container.hide()
	
	for child in grid_container.get_children():
		child.queue_free()
	
	await get_tree().process_frame
	
	var deck = rune_data.get("runes", []).duplicate()
	deck.shuffle()
	
	for rune in deck:
		var btn := Button.new()
		btn.text = rune.get("icon", "?")
		btn.custom_minimum_size = Vector2(90, 90)
		btn.size_flags_horizontal = Control.SIZE_EXPAND | Control.SIZE_FILL
		btn.size_flags_vertical = Control.SIZE_EXPAND | Control.SIZE_FILL
		btn.tooltip_text = rune["name"]
		btn.add_theme_font_size_override("font_size", 48)
		# Connettiamo l'evento passando l'ID della runa e il riferimento al bottone
		btn.pressed.connect(_on_rune_pressed.bind(rune.get("id", "unknown_rune"), btn))
		grid_container.add_child(btn)

	# Ora che la griglia è di nuovo piena, la rendiamo di nuovo visibile.
	grid_container.show()

# Callback attivata alla pressione di un pulsante runa
func _on_rune_pressed(rune_id: String, btn_ref: Button):
	# Aggiunge un feedback aptico (vibrazione) al tocco.
	Input.vibrate_handheld(50) # 50 millisecondi è una vibrazione breve e netta.

	if not is_active: return
	
	# Specifica: "clicca in sequenza tre rune diverse"
	if rune_id in current_sequence:
		feedback_label.text = tr("rune_error_duplicate")
		return

	# Avvia timer al primo tocco della sequenza attuale
	if current_sequence.size() == 0:
		start_time_ms = Time.get_ticks_msec()

	current_sequence.append(rune_id)
	current_icons.append(btn_ref.text)
	btn_ref.disabled = true # Feedback visivo: runa usata
	
	# Aggiorna SOLO la label delle rune (quella con il font grande)
	rune_display_label.text = " ᛫ ".join(current_icons)

	# Controllo fine sequenza
	if current_sequence.size() == 3:
		_evaluate_spell_attempt()

# Valuta se la sequenza inserita corrisponde a un incantesimo valido
func _evaluate_spell_attempt():
	var end_time = Time.get_ticks_msec()
	var time_taken = end_time - start_time_ms
	
	var found_spell = null
	var spells_list = rune_data.get("spells", [])
	
	for spell in spells_list:
		# L'ordine è importante: array devono essere identici
		if spell["sequence"] == current_sequence:
			found_spell = spell
			break
	
	if found_spell:
		# Successo! Calcola bonus e verifica combo
		_process_success(found_spell, time_taken)
	else:
		# Fallimento
		feedback_label.text = tr("rune_fizzle")
		# Se un incantesimo fallisce, l'intera catena si spezza e si perde.
		# Svuotiamo gli incantesimi accumulati per terminare la sessione senza lanciare nulla.
		accumulated_spells.clear()
		await get_tree().create_timer(1.0).timeout
		_end_session()

# Elabora un incantesimo lanciato con successo
func _process_success(spell, time_taken_ms):
	# 1. Calcolo Moltiplicatore Velocità
	# Più veloce = più potenza.
	var speed_mult = 1.0
	if time_taken_ms < MAX_TIME_FOR_MULTIPLIER_MS:
		# Formula lineare inversa: 0ms -> 2.0x, 5000ms -> 1.0x (esempio)
		var factor = 1.0 - (float(time_taken_ms) / float(MAX_TIME_FOR_MULTIPLIER_MS))
		speed_mult = 1.0 + factor 
	
	# 2. Calcolo Costo Scalare per Combo
	var scaled_cost = spell.get("cost", 0) * pow(COST_SCALING_FACTOR, current_combo_index)
	
	# Accumula l'incantesimo nella lista
	accumulated_spells.append({
		"id": spell.get("id", "unknown_spell"),
		"name": spell.get("name", "spell_unknown"),
		"power": spell.get("base_power", 0) * speed_mult,
		"speed_mult": speed_mult,
		"cost": scaled_cost,
		"type": spell.get("type", "neutral")
	})

	# 3. Gestione Combo / Concatenazione
	# Se l'esecuzione è "perfetta" (tempo minimo) e non abbiamo raggiunto il limite
	if time_taken_ms <= PERFECT_TIME_THRESHOLD_MS and current_combo_index < MAX_COMBO_CHAIN:
		current_combo_index += 1
		feedback_label.text = tr("rune_perfect_chain") + (tr("rune_chain_multiplier") % current_combo_index)
		
		# Breve pausa per mostrare il feedback positivo
		await get_tree().create_timer(0.6).timeout
		
		# Riavvia il round con rune rimescolate
		await _prepare_round(tr("rune_prompt_start"))
	else:
		feedback_label.text = tr("rune_cast_msg") % tr(spell.get("name", "spell_unknown"))
		await get_tree().create_timer(1.0).timeout
		_end_session()

# Termina la sessione di lancio e calcola il risultato finale aggregato
# Questa funzione è il cuore del sistema di calcolo danni magico.
# Unisce tutti gli incantesimi lanciati nella combo in un unico "super-spell".
func _end_session():
	is_active = false
	hide()
	if accumulated_spells.size() > 0:
		# 1. Raggruppa potenza per tipo e calcola costo totale
		# Somma la potenza base di tutte le spell lanciate nella combo, divise per tipo elementale.
		var power_by_type = {}
		var total_cost = 0.0
		for spell in accumulated_spells:
			var spell_type = spell.get("type", "neutral")
			var spell_power = spell.get("power", 0.0)
			
			if not power_by_type.has(spell_type):
				power_by_type[spell_type] = 0.0
			power_by_type[spell_type] += spell_power
			
			total_cost += spell.get("cost", 0.0)

		if OS.is_debug_build():
			print("\n" + tr("debug_rune_calc_start"))
			print(tr("debug_rune_raw_power") % str(power_by_type))

		var processed_types = [] 
		for type1 in power_by_type.keys():
			if type1 in processed_types: continue

			var type1_data = damage_types_data.get(type1, {})
			var opposite_type = type1_data.get("opposite")

			if opposite_type and power_by_type.has(opposite_type):
				var power1 = power_by_type[type1]
				var power2 = power_by_type[opposite_type]
				
				if OS.is_debug_build():
					print(tr("debug_rune_conflict") % [type1, power1, opposite_type, power2])
				
				if power1 >= power2:
					power_by_type[type1] = power1 - power2
					power_by_type[opposite_type] = 0.0
				else:
					power_by_type[opposite_type] = power2 - power1
					power_by_type[type1] = 0.0
				
				processed_types.append(type1)
				processed_types.append(opposite_type)

		var total_power = 0.0
		var main_type = "neutral"
		var max_power = 0.0
		
		for type in power_by_type.keys():
			var power = power_by_type[type]
			total_power += power
			if power > max_power:
				max_power = power
				main_type = type
		
		if total_power <= 0:
			main_type = "neutral"
			total_power = 0

		if OS.is_debug_build():
			print(tr("debug_rune_final_power") % str(power_by_type))
			print(tr("debug_rune_result") % [main_type, total_power])
			print(tr("debug_rune_separator"))

		var aggregated_spell = {
			"id": "rune_combo",
			"name": "spell_combo_runic",
			"power": total_power,
			"cost": total_cost,
			"type": main_type
		}

		if OS.is_debug_build():
			print(tr("debug_rune_request_target") % str(aggregated_spell))
		request_target_selection.emit(aggregated_spell)
	else:
		combo_finished.emit(current_combo_index)

## Risolve l'effetto di un incantesimo quando lanciato fuori dal combattimento.
## Gestisce la meccanica di assorbimento (Affinità = Cura) e il danno ambientale.
## Input: spell_data (Dictionary) - Dati della magia (id, power, cost, type).
func resolve_world_spell(spell_data: Dictionary):
	if not game: return

	var spell_id = spell_data.get("id", "rune_spell")
	var power = int(spell_data.get("power", 0))
	var cost = int(spell_data.get("cost", 0))
	var type = spell_data.get("type", "neutral")
	
	# Consumo risorse (Mana/Chakra)
	game.modify_player_energy("magic", -cost)

	var msg = ""
	
	# --- Meccanica di Assorbimento Energetico ---
	# 1. Non esiste una "magia di cura" pura.
	# 2. L'affinità elementale inverte il danno in rigenerazione vitale.
	# 3. In assenza di affinità, l'energia colpisce l'eventuale nemico.
	
	var player_affinities = game.story_data.get("player", {}).get("affinity", [])

	if type in player_affinities:
		# Il giocatore assorbe l'elemento: trasforma la potenza in salute
		game.modify_player_energy("life", power)
		msg = tr("spell_cast_heal") % [tr(spell_id), power]
	else:
		# L'energia viene proiettata all'esterno (Danno)
		if game.combat_manager and game.combat_manager.current_entity_health > 0:
			game.combat_manager.current_entity_health -= power
			msg = tr("spell_cast_damage") % [tr(spell_id), power]
			
			# Check vittoria fuori dal CombatManager (es. attacco preventivo)
			if game.combat_manager.current_entity_health <= 0:
				msg += " " + tr("combat_victory")
		else:
			msg = tr("spell_cast_no_enemy")

	# Aggiornamento log e UI
	if game.text:
		game.text.text += "\n" + msg
	game.update_stats()

# Debug veloce
func _input(event):
	if OS.is_debug_build() and event.is_action_pressed("ui_focus_next"):
		if not is_active:
			start_rune_casting()
