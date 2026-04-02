# =========================================================
# SLEEP MANAGER
# =========================================================
# Gestisce il minigioco del riposo per recuperare energie e ridurre lo stress.
#
# Funzionalità principali:
# - Esecuzione di un minigioco di riflessi (salto della pecora).
# - Calcolo dell'efficienza del riposo basato sui tentativi.
# - Recupero dinamico di HP, Mana e riduzione dello Stress.
# - Interfaccia UI dedicata sovrapposta al gioco.

## Gestisce la meccanica del sonno tramite un minigioco "conta le pecore".
class_name SleepManager
extends Node

## Riferimento al gioco principale.
var game: Game

## Indica se il minigioco è attualmente in esecuzione.
var is_active: bool = false

## Punteggio necessario per completare il riposo.
var points_needed: int = 5
## Punti accumulati nella sessione corrente.
var current_points: int = 0
## Numero totale di tentativi effettuati (usato per l'efficienza).
var total_attempts: int = 0
## Velocità di movimento orizzontale della pecora.
var sheep_speed: float = 450.0
## Velocità iniziale per i reset.
var base_speed: float = 450.0
## Flag che indica se la pecora si trova nell'area di salto valida.
var is_jumping: bool = false

## Nodi UI per l'interfaccia del minigioco.
var overlay: ColorRect
var sheep: TextureRect
var fence: TextureRect
var score_label: Label

## Avvia il minigioco, inizializza lo stato e crea l'interfaccia.
func start_minigame():
	if is_active: return
	is_active = true
	current_points = 0
	total_attempts = 0
	sheep_speed = base_speed
	
	_create_ui()
	set_process(true)

## Crea dinamicamente i nodi UI necessari per il minigioco.
func _create_ui():
	# Sfondo nero trasparente (simile alla morte)
	overlay = game.ui_manager.create_full_screen_overlay(Color.BLACK, true)
	game.add_child(overlay)
	
	# Intercettazione input a pieno schermo (aggiunto per primo per stare sullo sfondo)
	var input_btn = Button.new()
	input_btn.flat = true
	input_btn.name = "SheepInputBtn"
	input_btn.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	input_btn.pressed.connect(_on_screen_tapped)
	overlay.add_child(input_btn)
	
	# Istruzioni e Score
	score_label = Label.new()
	score_label.text = tr("sleep_score") % [0, points_needed]
	score_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	score_label.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	score_label.position.y = 100
	score_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	overlay.add_child(score_label)
	
	# Roccia (Posizionata manualmente al centro)
	var screen_size = game.get_viewport_rect().size
	fence = TextureRect.new()
	fence.texture = load("res://art/rock.svg")
	fence.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	fence.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	fence.custom_minimum_size = Vector2(96, 96)
	fence.size = Vector2(96, 96)
	# Centra la roccia basandosi sulla dimensione effettiva dello schermo
	fence.position = Vector2(screen_size.x / 2 - 48, screen_size.y / 2 - 48)
	fence.mouse_filter = Control.MOUSE_FILTER_IGNORE
	overlay.add_child(fence)
	
	# Pecora (SVG)
	sheep = TextureRect.new()
	sheep.name = "Sheep"
	sheep.texture = load("res://art/sheep.svg")
	sheep.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	sheep.size = Vector2(92, 92)
	sheep.pivot_offset = Vector2(46, 46) # Centro per rotazione e scala
	sheep.flip_h = true
	sheep.mouse_filter = Control.MOUSE_FILTER_IGNORE
	overlay.add_child(sheep)
	_reset_sheep()

## Riposiziona la pecora all'inizio (lato sinistro) e resetta lo stato di salto.
func _reset_sheep():
	var screen_size = game.get_viewport_rect().size
	sheep.position = Vector2(-100, screen_size.y / 2 - 46)
	sheep.rotation = 0
	is_jumping = false

## Gestisce il movimento della pecora e l'arco di salto visivo.
func _process(delta):
	if not is_active: return
	
	# Movimento pecora
	sheep.position.x += sheep_speed * delta
	
	var screen_size = game.get_viewport_rect().size
	# Logica Salto Automatico (visivo)
	var center_x = screen_size.x / 2
	var distance_from_fence = abs(sheep.position.x - center_x)
	if distance_from_fence < 100:
		is_jumping = true
		var jump_percent = cos(distance_from_fence / 100.0 * (PI/2))
		# Arco di salto
		sheep.position.y = (screen_size.y / 2 - 46) - (jump_percent * 120.0)
		# Rotazione dinamica durante il salto
		var rot_direction = -1.0 if sheep.position.x < center_x else 1.0
		sheep.rotation = lerp(0.0, deg_to_rad(20.0 * rot_direction), jump_percent)
	else:
		is_jumping = false
		sheep.position.y = screen_size.y / 2 - 46

	# Se esce dallo schermo a destra senza essere stata intercettata
	if sheep.position.x > screen_size.x:
		# Fallimento per mancata intercettazione
		current_points = 0
		sheep_speed = base_speed # Reset velocità
		total_attempts += 1 # Penalità per l'efficienza
		score_label.text = tr("sleep_fail") % points_needed
		
		# Feedback visivo/aptico del fallimento
		Input.vibrate_handheld(200)
		_reset_sheep()

## Gestisce l'input del giocatore per contare la pecora.
func _on_screen_tapped():
	total_attempts += 1
	
	# Se la pecora è nell'arco del salto
	if is_jumping:
		current_points += 1
		score_label.text = tr("sleep_score") % [current_points, points_needed]
		sheep_speed += 40.0 # Aumenta la difficoltà
		Input.vibrate_handheld(50)
		
		# Effetto feedback positivo
		var tween = create_tween()
		tween.tween_property(sheep, "modulate", Color.GREEN, 0.1)
		tween.tween_property(sheep, "modulate", Color.WHITE, 0.1)
		
		if current_points >= points_needed:
			_finish_sleep()
		else:
			_reset_sheep()
	else:
		# Perde la concentrazione
		current_points = 0
		sheep_speed = base_speed # Reset velocità
		score_label.text = tr("sleep_fail") % points_needed
		Input.vibrate_handheld(200)
		
		# Effetto feedback negativo
		var tween = create_tween()
		tween.tween_property(sheep, "modulate", Color.RED, 0.1)
		tween.tween_property(sheep, "modulate", Color.WHITE, 0.1)
		_reset_sheep()

## Conclude il minigioco, calcola l'efficienza e applica i bonus.
func _finish_sleep():
	is_active = false
	set_process(false)
	
	# Disabilita l'input e nasconde i componenti del minigioco per la fase di sonno
	var btn = overlay.get_node_or_null("SheepInputBtn")
	if btn: btn.disabled = true
	
	sheep.hide()
	fence.hide()
	score_label.hide()
	
	# Crea l'animazione del sonno profondo (Zzz...)
	var zzz_label = Label.new()
	zzz_label.text = "Z"
	zzz_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	zzz_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	zzz_label.add_theme_font_size_override("font_size", 60)
	zzz_label.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	# Assicura che la label si espanda dal centro verso l'esterno
	zzz_label.grow_horizontal = Control.GROW_DIRECTION_BOTH
	zzz_label.grow_vertical = Control.GROW_DIRECTION_BOTH
	overlay.add_child(zzz_label)
	
	# Animazione di "respiro" per i Zzz (pulsazione opacità)
	zzz_label.modulate.a = 0.2 # Parte leggero
	var z_tween = create_tween().set_loops()
	z_tween.tween_property(zzz_label, "modulate:a", 1.0, 1.5).set_trans(Tween.TRANS_SINE) # Sale al picco
	z_tween.tween_property(zzz_label, "modulate:a", 0.2, 1.5).set_trans(Tween.TRANS_SINE) # Torna giù
	
	# Animazione di "galleggiamento" (Zzz fluttuano)
	var float_tween = create_tween().set_loops()
	var original_y = zzz_label.position.y
	float_tween.tween_property(zzz_label, "position:y", original_y - 20, 1.5).set_trans(Tween.TRANS_SINE)
	float_tween.tween_property(zzz_label, "position:y", original_y + 10, 1.5).set_trans(Tween.TRANS_SINE)
	
	_run_zzz_text_animation(zzz_label)
	_run_haptic_breath(zzz_label)
	
	# Tempo di sonno profondo (10 secondi)
	await game.get_tree().create_timer(10.0).timeout
	z_tween.kill()
	
	# Calcolo efficienza (inversamente proporzionale ai tentativi)
	var efficiency = float(points_needed) / float(max(points_needed, total_attempts))
	
	# Dissolvenza finale verso il gioco (ritorno alla realtà)
	var fade_tween = create_tween()
	fade_tween.tween_property(overlay, "modulate:a", 0.0, 2.0)
	await fade_tween.finished
	
	# Applichiamo i benefici del riposo solo al risveglio completo
	_apply_recovery(efficiency)
	
	overlay.queue_free()
	
	if game.stats_manager:
		game.stats_manager.close_config_menu()

## Gestisce il cambiamento ciclico del testo dei Zzz.
func _run_zzz_text_animation(label: Label):
	var frames = ["Z", "Zz", "Zzz", "Zzzz.", "Zzzz..", "Zzzz..."]
	var i = 0
	while is_instance_valid(label) and label.is_visible_in_tree():
		label.text = frames[i]
		i = (i + 1) % frames.size()
		# 0.5s x 6 frame = 3s (esattamente la durata di un ciclo completo del tween)
		await game.get_tree().create_timer(0.5).timeout

## Gestisce il loop della vibrazione "respirata" basata sull'opacità dei Zzz.
func _run_haptic_breath(label: Label):
	while is_instance_valid(label) and label.is_visible_in_tree():
		# Campioniamo l'opacità attuale (0.2 -> 1.0)
		var intensity = label.modulate.a
		# Trasformiamo l'intensità in durata (es: da 20ms a 120ms)
		var duration = int(intensity * 120)
		
		Input.vibrate_handheld(duration)
		# Aspettiamo un breve intervallo prima del prossimo "campione"
		await game.get_tree().create_timer(0.2).timeout

## Applica i benefici del riposo scalati in base all'efficienza.
## Recupera le energie (HP/MP) e riduce lo stress in base a quanto è stato preciso il giocatore.
func _apply_recovery(efficiency: float):
	if not game.stats_manager: return
	
	# Recupero Base: 30% del max per energia, -20 Stress
	# Scalato per efficienza
	for type_id in game.stats_manager.player_max_energy.keys():
		var max_val = game.stats_manager.player_max_energy[type_id]
		
		if type_id == "stress":
			# Lo stress cala
			var reduction = -int(20.0 * efficiency)
			game.modify_player_energy("stress", reduction)
		else:
			# Le altre energie recuperano
			var amount = int((max_val * 0.3) * efficiency)
			game.modify_player_energy(type_id, amount)
	
	game.text.text = tr("sleep_recovery_msg")
	game.update_stats()
