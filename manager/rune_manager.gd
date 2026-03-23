extends Control

# NOTA IMPORTANTE:
# NON inserire stringhe di testo hardcoded (es. "Hai lanciato...") direttamente nel codice.
# Usa sempre tr("chiave_json") e definisci la chiave corrispondente nel file data/it.json.

# Segnali verso il sistema di gioco/combattimento
signal spell_cast_success(spell_id, final_power, cost, type)
signal spell_cast_failed(reason)
signal request_target_selection(spell_data)
signal combo_finished(total_spells)

# Configurazione Gameplay
const MAX_COMBO_CHAIN = 7
const PERFECT_TIME_THRESHOLD_MS = 2500 # Sotto i 2.5s è "Perfetto" -> Combo
const MAX_TIME_FOR_MULTIPLIER_MS = 5000 # Sopra i 5s il moltiplicatore è 1.0x
# const COST_SCALING_FACTOR = 1.5 # Il costo aumenta del 50% per ogni spell nella catena
const COST_SCALING_FACTOR = 0.75 # Il costo diminuisce del 25% per ogni spell nella catena

# Variabili di Stato
var rune_data = {}
var damage_types_data = {}
var current_sequence = []
var current_icons = []
var start_time_ms = 0
var current_combo_index = 0
var is_active = false
var accumulated_spells = []

# Riferimenti UI (Assicurati che i nomi dei nodi nella scena corrispondano)
@onready var feedback_label = $Panel/CenterContainer/VBoxContainer/FeedbackLabel
@onready var rune_display_label = $Panel/CenterContainer/VBoxContainer/RuneDisplayLabel
@onready var grid_container = $Panel/CenterContainer/VBoxContainer/RuneGrid


func _ready():
	_load_rune_data()
	hide()
	# Configurazione font:
	# 1. FeedbackLabel: Messaggi di gioco (dimensione normale per leggere il testo)
	feedback_label.add_theme_font_size_override("font_size", 24)
	# Abilita il ritorno a capo intelligente e imposta un'altezza minima per nomi lunghi
	feedback_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	feedback_label.custom_minimum_size.y = 80
	feedback_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER # Centra anche il testo descrittivo

	# 2. RuneDisplayLabel: Simboli delle rune (dimensione grande per vedere le icone)
	rune_display_label.add_theme_font_size_override("font_size", 50)
	# Centra le rune visualizzate orizzontalmente
	rune_display_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	# Riserva spazio verticale fisso per evitare spostamenti quando si scrive la prima runa
	rune_display_label.custom_minimum_size.y = 80
	rune_display_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER

func _load_rune_data():
	# ATTENZIONE: I percorsi dei file JSON sono fissi in res://data/.
	# NON MODIFICARE questi percorsi a meno di una specifica richiesta.
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
	
	var story_file = FileAccess.open("res://data/story.json", FileAccess.READ)
	if story_file:
		var json = JSON.new()
		var error = json.parse(story_file.get_as_text())
		if error == OK:
			damage_types_data = json.data.get("damage_types", {})
	else:
		push_error(tr("error_story_file_not_found_rune"))

# Metodo pubblico per avviare il manager
func start_rune_casting():
	# Soluzione pulita per il posizionamento:
	# 1. Rendi il pannello "top_level" per sganciarlo dal layout del genitore.
	#    Questo fa sì che si posizioni rispetto all'intera finestra di gioco.
	top_level = true
	# 2. Applica il preset per centrarlo (ancore e offset) ogni volta che viene aperto.
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	# 3. Assicuriamoci che anche i contenitori interni si espandano per riempire lo schermo.
	#    Se il Panel o il CenterContainer rimangono piccoli in alto a sinistra, la griglia non sarà centrata.
	$Panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	$Panel/CenterContainer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	show()
	is_active = true
	current_combo_index = 0
	accumulated_spells.clear()
	_prepare_round(tr("rune_prompt_start"))

func _prepare_round(prompt_text: String) -> void:
	current_sequence.clear()
	current_icons.clear()
	start_time_ms = 0 # Il timer partirà al primo click
	feedback_label.text = prompt_text
	rune_display_label.text = "" # Pulisce la visualizzazione delle rune
	
	# Nascondiamo temporaneamente la griglia per evitare che il layout si "restringa"
	# visibilmente mentre la svuotiamo e la riempiamo di nuovo.
	grid_container.hide()
	
	# Pulisci griglia precedente
	for child in grid_container.get_children():
		child.queue_free()
	
	# queue_free() elimina i nodi alla fine del frame. Attendiamo il frame successivo
	# per essere sicuri che la griglia sia vuota prima di aggiungere nuovi elementi.
	await get_tree().process_frame
	
	# Mischia le rune (Logica: ordine diverso ad ogni apertura/round)
	var deck = rune_data.get("runes", []).duplicate()
	deck.shuffle()
	
	# Genera pulsanti
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
		_process_success(found_spell, time_taken)
	else:
		# Fallimento
		feedback_label.text = tr("rune_fizzle")
		# Se un incantesimo fallisce, l'intera catena si spezza e si perde.
		# Svuotiamo gli incantesimi accumulati per terminare la sessione senza lanciare nulla.
		accumulated_spells.clear()
		await get_tree().create_timer(1.0).timeout
		_end_session()

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

		# 2. Gestisci gli opposti: si annullano a vicenda
		# Es. Se ho Fuoco (10) e Ghiaccio (6), il risultato è Fuoco (4).
		# I tipi opposti sono definiti in story.json -> damage_types.
		var processed_types = [] # Per non processare una coppia due volte
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

		# 3. Calcola potenza totale e determina il tipo dominante
		# Il tipo con la potenza residua maggiore determina l'elemento finale dell'attacco.
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

		# 4. Crea l'incantesimo aggregato
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
		# Emettiamo combo_finished solo se non ci sono spell da lanciare (fallimento)
		# Altrimenti lasciamo il controllo alla selezione bersaglio
		combo_finished.emit(current_combo_index)

# Debug veloce
func _input(event):
	if OS.is_debug_build() and event.is_action_pressed("ui_focus_next"):
		if not is_active:
			start_rune_casting()
