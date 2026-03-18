class_name QTE
extends Control

signal qte_finished(value)

@onready var bar = ColorRect.new()
@onready var cursor = Panel.new()

var active = false
var speed = 500.0
var direction = 1
var time: float = 0.0

func _ready():
	# Imposta la barra
	bar.size = Vector2(400, 50)
	bar.position = Vector2(200, 200)
	# Abilita la ricezione degli input del mouse sulla barra
	bar.mouse_filter = Control.MOUSE_FILTER_STOP
	bar.gui_input.connect(_on_bar_gui_input)
	add_child(bar)

	# Imposta il cursore con bordo e sfondo trasparente
	var stylebox = StyleBoxFlat.new()
	stylebox.bg_color = Color(0, 0, 0, 0) # Sfondo trasparente
	stylebox.border_width_top = 2
	stylebox.border_width_bottom = 2
	stylebox.border_width_left = 2
	stylebox.border_width_right = 2
	stylebox.border_color = Color(0.1, 0.1, 0.1, 1) # Colore bordo quasi nero
	cursor.add_theme_stylebox_override("panel", stylebox)
	cursor.size = Vector2(10, bar.size.y)
	cursor.position = Vector2(bar.position.x, bar.position.y)
	cursor.mouse_filter = Control.MOUSE_FILTER_IGNORE # Il cursore non deve bloccare il click sulla barra
	add_child(cursor)

	hide() # QTE nascosto di default

func start(target_control: Control = null):
	if target_control:
		# Sgancia il QTE da eventuali layout automatici o ancore del genitore
		set_anchors_preset(Control.PRESET_TOP_LEFT)
		custom_minimum_size = Vector2.ZERO
		
		# Sovrappone il QTE al controllo target (es. il bottone)
		global_position = target_control.global_position
		size = target_control.size
		# Assicura che il QTE sia disegnato sopra il bottone e l'interfaccia
		z_index = 10
		
		# Adatta la barra e il cursore alle nuove dimensioni
		bar.position = Vector2.ZERO
		bar.size = size
		cursor.size.y = size.y
		cursor.position.y = 0
	else:
		z_index = 0 # Ripristina lo z-index normale se non c'è un target specifico

	active = true
	show()
	# Reset cursore all'inizio della barra (sin(-PI/2) = -1)
	time = -PI / 2
	cursor.position.x = bar.position.x

func stop():
	active = false
	hide()

func _process(delta):
	if not active:
		return
	
	var max_dist = bar.size.x - cursor.size.x
	var amplitude = max_dist / 2.0
	var center_x = bar.position.x + amplitude
	
	# Calcola la velocità angolare affinché la velocità massima (al centro) sia pari a 'speed'
	var angular_speed = speed / amplitude if amplitude > 0 else 0.0
	
	time += delta * angular_speed
	cursor.position.x = center_x + amplitude * sin(time)

	# Aggiorna il colore della barra: Rosso (Mancato) -> Giallo (Colpito) -> Verde (Perfetto)
	var progress = get_qte_value()
	var dist_from_center = abs(progress - 0.5) # 0.0 al centro, 0.5 agli estremi

	# Le soglie corrispondono a quelle in Game.gd per i risultati del QTE
	var perfect_threshold = 0.05 # (0.5 - 0.45)
	var good_threshold = 0.2 # (0.5 - 0.3)

	if dist_from_center < perfect_threshold:
		# Zona "Perfetto": Interpola da Giallo a Verde
		var weight = 1.0 - (dist_from_center / perfect_threshold)
		bar.color = Color.YELLOW.lerp(Color.GREEN, weight)
	elif dist_from_center < good_threshold:
		# Zona "Buono": Interpola da Rosso a Giallo
		var range_size = good_threshold - perfect_threshold
		var value_in_range = dist_from_center - perfect_threshold
		var weight = 1.0 - (value_in_range / range_size)
		bar.color = Color.RED.lerp(Color.YELLOW, weight)
	else:
		# Zona "Mancato": Rosso pieno
		bar.color = Color.RED

func _input(event):
	if not active:
		return

	if event.is_action_pressed("ui_accept"):
		confirm_hit()

# Gestisce il click del mouse sulla barra
func _on_bar_gui_input(event):
	if not active:
		return
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		confirm_hit()

func confirm_hit():
	var value = get_qte_value()
	qte_finished.emit(value)
	stop()

func get_qte_value() -> float:
	var min_x = bar.position.x
	var max_x = bar.position.x + bar.size.x - cursor.size.x
	return clamp((cursor.position.x - min_x) / (max_x - min_x), 0.0, 1.0)
