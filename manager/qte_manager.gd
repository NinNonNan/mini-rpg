extends Node

signal qte_finished(value)

var game 
var is_active: bool = false
var current_value: float = 0.0
var speed: float = 1.0
var target_btn: Button = null
var context: String = ""
var power_multiplier: float = 0.2
var elapsed_time: float = 0.0

# Riferimenti agli elementi grafici della barra
var bar_container: Button = null
var cursor_sprite: TextureRect = null

func _ready():
	set_process(false)

func start_event(message_key: String = "qte_start_default", ctx: String = ""):
	# 1. Prepara la UI del gioco tramite il riferimento 'game'
	game.disable_choices()
	game.text.text = tr(message_key)
	context = ctx
	
	# 2. Avvia il calcolo della velocità e il loop interattivo
	start_for_entity(game.b1, game.current_entity_id, game.entity_data, power_multiplier)

func start_for_entity(target_button: Button, entity_id: String, entity_data: Dictionary, p_multiplier: float):
	var calculated_speed: float = 1.0
	
	if entity_id != "" and entity_data.has(entity_id):
		var entity = entity_data[entity_id]
		var total_energy = 0.0
		if entity.has("energy"):
			for stat in entity["energy"]:
				total_energy += float(stat.get("value", 0))
		if total_energy > 0:
			calculated_speed = total_energy * p_multiplier

	# Avviamo il QTE interattivo
	start(target_button, calculated_speed)

func start(button: Button, speed_val: float):
	if is_active: return
	
	target_btn = button
	# Clamp della velocità per evitare che il QTE sia impossibile o troppo lento
	speed = clamp(speed_val, 0.5, 4.0) 
	current_value = 0.0
	elapsed_time = 0.0
	is_active = true
	
	# Prepariamo il pulsante: deve essere attivo per ricevere il click del QTE
	if target_btn:
		target_btn.disabled = false
		# Pulizia connessioni precedenti per evitare conflitti con la logica di Game.gd
		for connection in target_btn.pressed.get_connections():
			target_btn.pressed.disconnect(connection.callable)
		
		# Colleghiamo il click alla nostra logica di intercettazione
		target_btn.pressed.connect(_on_button_pressed)
		# Creiamo la barra visiva sopra il pulsante
		_create_visual_bar()
	
	set_process(true)
	print("[QTEManager] Interazione avviata. Obiettivo: 0.5. Velocità: ", speed)

func _process(delta):
	if not is_active: return
	
	elapsed_time += delta * speed
	
	# Funzione sinusoidale: oscilla tra 0 e 1. 
	# La velocità è massima a 0.5 e minima a 0 e 1.
	current_value = (sin(elapsed_time) + 1.0) / 2.0
	
	# Calcolo fattore accuratezza (1.0 al centro, 0.0 ai bordi)
	var accuracy_factor = 1.0 - (abs(current_value - 0.5) * 2.0)
	
	# Nuova palette morbida: Estremi (#5a1f1f) -> Medio (#6b6b2a) -> Centro (#d4c48a)
	var color_ext = Color("#5a1f1f")
	var color_mid = Color("#6b6b2a")
	var color_ctr = Color("#d4c48a")
	var dynamic_color: Color
	if accuracy_factor < 0.5:
		dynamic_color = color_ext.lerp(color_mid, accuracy_factor * 2.0)
	else:
		dynamic_color = color_mid.lerp(color_ctr, (accuracy_factor - 0.5) * 2.0)
	
	# Applichiamo il colore allo sfondo della barra
	if bar_container:
		# Accediamo allo StyleBox sovrascritto. Non usiamo .duplicate() per 
		# modificare direttamente la risorsa condivisa tra gli stati (normal, hover, pressed).
		var sb = bar_container.get_theme_stylebox("normal") as StyleBoxFlat
		if sb:
			sb.bg_color = dynamic_color
	
	# Aggiorna la posizione visiva del cursore
	if cursor_sprite and bar_container:
		var bar_width = bar_container.size.x
		var cursor_width = cursor_sprite.size.x
		# Calcoliamo lo spazio utile affinché il cursore resti sempre dentro i bordi
		cursor_sprite.position.x = current_value * (bar_width - cursor_width)

func _on_button_pressed():
	if is_active:
		_end_qte(current_value)

func _create_visual_bar():
	# Creiamo un pulsante trasparente che copre esattamente il tasto originale
	bar_container = Button.new()
	target_btn.add_child(bar_container)
	bar_container.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	
	# Stile della barra (sfondo scuro)
	var sb = StyleBoxFlat.new()
	sb.bg_color = Color(0.15, 0.15, 0.15, 1.0)
	sb.set_border_width_all(2)
	sb.border_color = Color.DIM_GRAY
	bar_container.add_theme_stylebox_override("normal", sb)
	bar_container.add_theme_stylebox_override("hover", sb)
	bar_container.add_theme_stylebox_override("pressed", sb)
	
	bar_container.pressed.connect(_on_button_pressed)
	
	# Cursore SVG
	cursor_sprite = TextureRect.new()
	bar_container.add_child(cursor_sprite)
	
	# Determina l'icona: usa l'arma equipaggiata se disponibile, altrimenti il cursore di default
	var icon_path = "res://art/cursor.svg"
	if game.item_manager:
		var weapon_id = game.item_manager.get_equipped_weapon_id()
		if weapon_id != "":
			var svg_path = game.item_manager.get_item_svg(weapon_id)
			if svg_path != "" and FileAccess.file_exists(svg_path):
				icon_path = svg_path
	
	cursor_sprite.texture = load(icon_path)
	cursor_sprite.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	cursor_sprite.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	
	# Adattiamo la larghezza del cursore basandoci sull'altezza del pulsante.
	# Questo lo rende alto quanto la barra e proporzionale.
	var bar_h = target_btn.size.y
	cursor_sprite.custom_minimum_size = Vector2(bar_h, bar_h)

	cursor_sprite.set_anchors_and_offsets_preset(Control.PRESET_LEFT_WIDE)
	cursor_sprite.mouse_filter = Control.MOUSE_FILTER_IGNORE

func _end_qte(final_value: float):
	is_active = false
	set_process(false)
	
	if bar_container:
		bar_container.queue_free()
		bar_container = null
	
	# --- Risoluzione Risultato ---
	# Calcoliamo la distanza assoluta dal centro (0.5)
	var distance = abs(final_value - 0.5)
	
	var result_text = tr("qte_result_miss")
	var multiplier = 0.0
	
	if distance < 0.05: # Molto vicino al centro
		result_text = tr("qte_result_perfect")
		multiplier = 2.0
	elif distance < 0.2: # Abbastanza vicino
		result_text = tr("qte_result_good")
		multiplier = 1.2
	
	game.text.text = result_text
	
	# Breve pausa per mostrare il risultato (Perfect/Good/Miss)
	await get_tree().create_timer(1.0).timeout
	
	# Risoluzione della conseguenza del QTE
	if context == "player_attack":
		if game.combat_manager:
			game.combat_manager.resolve_player_attack(multiplier)
	
	context = ""
	qte_finished.emit(final_value)
