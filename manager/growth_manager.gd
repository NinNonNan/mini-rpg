# =========================================================
# GROWTH MANAGER
# =========================================================
# Gestisce la crescita e il potenziamento del personaggio.
#
# Funzionalità principali:
# - Calcola l'energia (XP) ottenuta dai nemici sconfitti.
# - Gestisce un pool di "Energia disponibile" da spendere.
# - Permette di aumentare permanentemente le statistiche massime (HP, MP, ecc.).
#
# Scopo narrativo: Rappresenta l'evoluzione del potere del giocatore 
# attraverso l'assorbimento dell'essenza dei nemici.

class_name GrowthManager
extends Node

# --- Segnali ---
# Emesso alla chiusura del menu per informare il gioco di riattivare l'HUD.
signal growth_finished

# --- Riferimenti Esterni ---
# Riferimento al gioco principale (Game.gd). Iniettato in _ready().
var game

# --- Riferimenti UI e Cache ---
var growth_overlay: Control = null
var _current_story_data: Dictionary = {}
var _player_energy_ref: Dictionary = {}
var _player_max_energy_ref: Dictionary = {}

# --- Stato della Crescita ---
# Energia accumulata pronta per essere distribuita.
var available_energy: int = 0
# Valore iniziale dell'energia a inizio sessione (per permettere il reset).
var initial_available_energy: int = 0
# Mappa temporanea delle modifiche durante la sessione UI (stat_id -> punti aggiunti).
var temp_changes: Dictionary = {} 

## Calcola quanta energia rilascia un nemico sconfitto.
## La ricompensa è basata sulla somma delle statistiche del nemico (es. Vita + Magia).
## Input: entity_id (String) - L'identificatore dell'entità sconfitta.
## Output: int - L'ammontare di energia calcolata (33% della forza totale).
func calculate_reward(entity_id: String) -> int:
	var entity = game.entity_data.get(entity_id)
	
	if entity == null:
		push_warning(tr("warn_growth_entity_not_found") % entity_id)
		return 0
	
	# Calcola il valore totale delle statistiche del nemico
	var reward_base = 0.0 # Usiamo float per i calcoli intermedi
	
	if entity.has("energy"):
		for stat in entity["energy"]:
			# Sommiamo i valori positivi (es. vita), convertendo a float per sicurezza
			var val = float(stat.get("value", 0.0))
			if val > 0:
				reward_base += val
	elif entity.has("health"): # Supporto per la vecchia struttura dati
		reward_base += float(entity.get("health", 0.0))
	
	if reward_base <= 0:
		push_warning(tr("warn_growth_reward_zero") % entity_id)

	# Il reward è una frazione della forza totale (es. 50%), arrotondato per eccesso
	# Diciamo invece che l'energia rilasciata è un terzo di quella forza.
	var final_reward = ceili(reward_base * 0.33)
	return int(final_reward)

## Aggiunge energia al pool del giocatore.
## Input: amount (int) - Quantità di energia da aggiungere.
## Output: Nessuno.
func add_energy(amount: int):
	available_energy += amount

## Inizializza la sessione di crescita e apre il menu UI.
## Input: 
## - story_data (Dictionary): Dati della storia per le definizioni stats.
## - player_energy (Dictionary): Riferimento alle energie attuali.
## - player_max_energy (Dictionary): Riferimento ai massimali.
## Output: Nessuno.
func open_growth_menu(story_data: Dictionary, player_energy: Dictionary, player_max_energy: Dictionary):
	_current_story_data = story_data
	_player_energy_ref = player_energy
	_player_max_energy_ref = player_max_energy
	
	# Salva lo stato iniziale per permettere il reset ("Riassegna")
	start_growth_session()
	# Costruisce l'interfaccia da zero
	_create_growth_overlay()

## Crea programmaticamente l'overlay del menu di crescita.
## Input: Nessuno.
## Output: Nessuno.
func _create_growth_overlay():
	if growth_overlay:
		growth_overlay.queue_free()
	
	# Sfondo oscurato che blocca l'input agli elementi sottostanti
	growth_overlay = game.ui_manager.create_full_screen_overlay(Color(0, 0, 0, 0.9))
	
	# Contenitore per centrare il menu
	var center_container = CenterContainer.new()
	center_container.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	growth_overlay.add_child(center_container)
	
	var vbox = VBoxContainer.new()
	# Spaziatura verticale tra i vari blocchi (Titolo, Lista Stats, Bottoni)
	vbox.add_theme_constant_override("separation", 20)
	center_container.add_child(vbox)
	
	var custom_font = load("res://fonts/freecam v2.ttf")
	var font_size = 20
	
	var title_label = Label.new()
	title_label.name = "TitleLabel" # Usato per trovare il nodo durante il refresh
	title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title_label.add_theme_font_override("font", custom_font)
	title_label.add_theme_font_size_override("font_size", font_size + 4)
	vbox.add_child(title_label)
	
	# Container per le righe delle statistiche
	var stats_container = VBoxContainer.new()
	stats_container.name = "StatsContainer"
	stats_container.add_theme_constant_override("separation", 10)
	vbox.add_child(stats_container)
	
	# Recupera quali statistiche il giocatore possiede dal database
	var player_energy_types = _current_story_data.get("player", {}).get("energy", [])
	# Recupera i nomi localizzati delle statistiche
	var energy_type_definitions = _current_story_data.get("energy_types", {})
	
	for energy_stat in player_energy_types:
		var stat_id = energy_stat.get("type")
		
		# Lo stress non può essere modificato durante l'avanzamento
		if stat_id == "stress": continue
		
		var stat_name_key = energy_type_definitions.get(stat_id, {}).get("name", stat_id)
		
		var row = HBoxContainer.new()
		row.name = "Row_" + stat_id
		row.alignment = BoxContainer.ALIGNMENT_CENTER
		
		# Bottone per diminuire (restituisce il punto al pool disponibile)
		var btn_minus = Button.new()
		btn_minus.text = "➖"
		btn_minus.custom_minimum_size = Vector2(40, 40)
		btn_minus.pressed.connect(func(): 
			if try_decrease_stat(stat_id):
				_refresh_growth_ui()
		)
		row.add_child(btn_minus)
		
		# Nome della statistica
		var lbl_name = Label.new()
		lbl_name.name = "LabelName"
		lbl_name.custom_minimum_size = Vector2(160, 0) 
		lbl_name.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		lbl_name.add_theme_font_override("font", custom_font)
		lbl_name.add_theme_font_size_override("font_size", font_size)
		lbl_name.text = tr(stat_name_key)
		row.add_child(lbl_name)

		# Valore numerico (Base + Modifiche Temporanee)
		var lbl_val = Label.new()
		lbl_val.name = "LabelValue"
		lbl_val.custom_minimum_size = Vector2(120, 0) 
		lbl_val.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		lbl_val.add_theme_font_override("font", custom_font)
		lbl_val.add_theme_font_size_override("font_size", font_size)
		row.add_child(lbl_val)
		
		# Bottone per aumentare (consuma un punto dal pool)
		var btn_plus = Button.new()
		btn_plus.text = "➕"
		btn_plus.custom_minimum_size = Vector2(40, 40)
		btn_plus.pressed.connect(func():
			if try_increase_stat(stat_id):
				_refresh_growth_ui()
		)
		row.add_child(btn_plus)
		stats_container.add_child(row)

	# Bottoni di azione in fondo al menu
	var actions_row = HBoxContainer.new()
	actions_row.alignment = BoxContainer.ALIGNMENT_CENTER
	actions_row.add_theme_constant_override("separation", 20)
	vbox.add_child(actions_row)
	
	# Reset: Annulla tutto ciò che è stato fatto in questa sessione
	var btn_reset = Button.new()
	btn_reset.text = tr("growth_btn_reset")
	btn_reset.pressed.connect(func():
		reset_changes()
		_refresh_growth_ui()
	)
	actions_row.add_child(btn_reset)
	
	# Confirm: Applica permanentemente i punti al player
	var btn_confirm = Button.new()
	btn_confirm.text = tr("growth_btn_confirm")
	btn_confirm.pressed.connect(func():
		confirm_changes()
		growth_overlay.queue_free()
		growth_overlay = null
		growth_finished.emit() # Segnala a Game.gd di tornare alla normalità
	)
	actions_row.add_child(btn_confirm)
	
	# Aggiunge l'interfaccia come figlio del gioco principale per renderla visibile
	game.add_child(growth_overlay)
	_refresh_growth_ui() # Primo aggiornamento dei valori

## Aggiorna i testi e i valori numerici all'interno dell'overlay UI.
## Input: Nessuno.
## Output: Nessuno.
func _refresh_growth_ui():
	if not growth_overlay: return
	
	var title_lbl = growth_overlay.find_child("TitleLabel", true, false)
	if title_lbl:
		title_lbl.text = tr("growth_menu_title") % available_energy
	
	var stats_container = growth_overlay.find_child("StatsContainer", true, false)
	if stats_container:
		for child in stats_container.get_children():
			var stat_id = child.name.replace("Row_", "")
			var lbl_val = child.get_node_or_null("LabelValue") # Cerca la label numerica della riga
			if lbl_val:
				# Somma il valore attuale del giocatore ai punti "in sospeso" in questo menu
				var base_val = _player_max_energy_ref.get(stat_id, 0)
				var added_val = temp_changes.get(stat_id, 0)
				lbl_val.text = str(base_val + added_val)

## Inizializza i dati per una nuova sessione di distribuzione punti.
## Input: Nessuno.
## Output: Nessuno.
func start_growth_session():
	initial_available_energy = available_energy
	temp_changes.clear()

## Tenta di aggiungere un punto a una statistica (modifica temporanea).
## Input: stat_type (String) - L'ID della statistica da incrementare.
## Output: bool - true se l'operazione ha avuto successo (energia disponibile > 0).
func try_increase_stat(stat_type: String) -> bool:
	if available_energy > 0:
		available_energy -= 1
		temp_changes[stat_type] = temp_changes.get(stat_type, 0) + 1
		return true
	return false

## Tenta di rimuovere un punto assegnato durante la sessione attuale.
## Input: stat_type (String) - L'ID della statistica da decrementare.
## Output: bool - true se c'erano punti temporanei da rimuovere.
func try_decrease_stat(stat_type: String) -> bool:
	if temp_changes.get(stat_type, 0) > 0:
		temp_changes[stat_type] -= 1
		available_energy += 1
		return true
	return false

## Annulla tutte le modifiche fatte nella sessione UI corrente.
## Input: Nessuno.
## Output: Nessuno.
func reset_changes():
	available_energy = initial_available_energy
	temp_changes.clear()

## Applica permanentemente le modifiche al giocatore e chiude la sessione.
## Input: Nessuno.
## Output: Nessuno.
func confirm_changes():
	if temp_changes.is_empty():
		# Nessuna modifica fatta, esce solo
		game.show_scene(game.current_victory_scene)
		return

	for stat_type in temp_changes:
		var amount = temp_changes[stat_type]
		if amount > 0:
			# 1. Aumenta il valore MASSIMO della statistica
			var current_max = _player_max_energy_ref.get(stat_type, 0)
			_player_max_energy_ref[stat_type] = current_max + amount
			
			# 2. Aumenta anche il valore ATTUALE (cura/ripristino parziale)
			game.modify_player_energy(stat_type, amount)
	
	# Pulisce i dati temporanei
	temp_changes.clear()
	initial_available_energy = available_energy
	
	game.update_stats() # Aggiorna le statistiche del giocatore (HP/MP)
	game.show_scene(game.current_victory_scene)
