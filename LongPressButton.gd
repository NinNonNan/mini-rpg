# d:\___SVILUPPO\mini-rpg\LongPressButton.gd
class_name LongPressButton
extends Button

signal long_pressed

@export var duration: float = 0.8 # Tempo in secondi per attivare il long press

var _is_pressing: bool = false
var _timer: float = 0.0
var _touch_position: Vector2 = Vector2.ZERO

func _ready():
	# Rende lo sfondo del pulsante trasparente usando StyleBoxEmpty
	# NOTA: self_modulate.a = 0.0 renderebbe invisibile anche il _draw(), quindi usiamo gli stili.
	var empty_style = StyleBoxEmpty.new()
	add_theme_stylebox_override("normal", empty_style)
	add_theme_stylebox_override("pressed", empty_style)
	add_theme_stylebox_override("hover", empty_style)
	add_theme_stylebox_override("focus", empty_style)
	add_theme_stylebox_override("disabled", empty_style)
	
	# Rimuove il testo di default se presente
	text = ""
	
	# Assicura che l'animazione sia disegnata sopra gli altri elementi nel contenitore
	z_index = 10
	
	# Connessione segnali base del pulsante
	button_down.connect(_on_button_down)
	button_up.connect(_on_button_up)
	# Se il mouse/dito esce dall'area, annulla la pressione
	mouse_exited.connect(_on_button_up)

func _process(delta):
	if _is_pressing:
		_timer += delta
		queue_redraw() # Forza il ridisegno per l'animazione
		if _timer >= duration:
			_trigger_long_press()

func _on_button_down():
	_is_pressing = true
	_timer = 0.0
	_touch_position = get_local_mouse_position() # Memorizza il punto esatto del tocco
	queue_redraw()

func _on_button_up():
	_is_pressing = false
	_timer = 0.0
	queue_redraw()

func _trigger_long_press():
	_is_pressing = false # Resetta per evitare trigger multipli
	_timer = 0.0
	queue_redraw()
	long_pressed.emit()

func _draw():
	if _is_pressing:
		var center = _touch_position
		var radius = 50.0
		var thickness = 8.0
		var progress = clamp(_timer / duration, 0.0, 1.0)
		
		# 1. Sfondo scuro (Outline) per contrasto su qualsiasi sfondo
		draw_arc(center, radius, 0, TAU, 64, Color(0, 0, 0, 0.5), thickness + 4.0, true)
		
		# 2. Base dell'anello (Grigio chiaro/Bianco trasparente)
		draw_arc(center, radius, 0, TAU, 64, Color(1, 1, 1, 0.3), thickness, true)
		
		# 3. Progresso (Bianco pieno e visibile)
		# Disegna l'arco solo se c'è progresso per evitare glitch grafici a 0
		if progress > 0.0:
			var color = Color.WHITE
			# Diventa verde quando è completo
			if progress >= 1.0:
				color = Color.GREEN
			draw_arc(center, radius, -PI / 2, -PI / 2 + (progress * TAU), 64, color, thickness, true)
