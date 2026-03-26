# =========================================================
# UI MANAGER
# =========================================================
# Gestisce tutti gli aggiornamenti dell'interfaccia utente:
# - Aggiornamento statistiche giocatore e nemico
# - Overlay di crescita
# - Effetti di morte (grayscale, overlay)
# - Gestione pulsanti e testi

class_name UIManager
extends Node

# Riferimento al game principale
var game

# Riferimenti UI (inizializzati nel _ready)
var meteo_stats
var enemy_stats_box
var enemy_icon
var enemy_stats
var text
var player_icon
var player_box_container
var player_stats

# Effetti grafici
var grayscale_material: ShaderMaterial
var death_overlay: ColorRect
var growth_overlay: Control = null

func _ready():
	# L'inizializzazione viene chiamata esplicitamente da game.gd
	pass

func set_story_text(val: String):
	if text: text.text = val

func add_story_text(val: String):
	if text: text.text += "\n" + val

func setup_choices(choices: Array, callback: Callable):
	var buttons = [game.scene_manager.b1, game.scene_manager.b2, game.scene_manager.b3]
	for i in range(buttons.size()):
		if i < choices.size():
			buttons[i].text = tr(choices[i]["text"])
			buttons[i].show()
			_clear_btn_signals(buttons[i])
			var action = choices[i]["action"]
			buttons[i].pressed.connect(func(): callback.call(action))
		else:
			buttons[i].hide()

func setup_target_selection(entity_id: String, target_signal: Signal):
	enable_choices()
	set_story_text(tr("combat_select_target"))
	var btns = [game.scene_manager.b1, game.scene_manager.b2, game.scene_manager.b3]
	
	btns[0].text = tr("target_player")
	btns[0].show()
	_clear_btn_signals(btns[0])
	btns[0].pressed.connect(func(): target_signal.emit("player"))
	
	if entity_id != "" and game.combat_manager and game.combat_manager.current_entity_health > 0:
		var e_name = tr(game.data_manager.entity_data.get(entity_id, {}).get("name", "enemy"))
		btns[1].text = e_name
		btns[1].show()
		_clear_btn_signals(btns[1])
		btns[1].pressed.connect(func(): target_signal.emit("enemy"))
	else:
		btns[1].hide()

	btns[2].text = tr("combat_back")
	btns[2].show()
	_clear_btn_signals(btns[2])
	btns[2].pressed.connect(func(): target_signal.emit("back"))

func clear_choices():
	for btn in [game.scene_manager.b1, game.scene_manager.b2, game.scene_manager.b3]:
		btn.hide()
		_clear_btn_signals(btn)

func disable_choices():
	for btn in [game.scene_manager.b1, game.scene_manager.b2, game.scene_manager.b3]:
		if btn: btn.disabled = true

func enable_choices():
	for btn in [game.scene_manager.b1, game.scene_manager.b2, game.scene_manager.b3]:
		if btn: btn.disabled = false

func show_game_over(restart_callback: Callable):
	set_story_text(tr("game_over_text"))
	enable_choices()
	var b1 = game.scene_manager.b1
	b1.text = tr("game_over_choice")
	b1.show()
	_clear_btn_signals(b1)
	b1.pressed.connect(restart_callback)
	game.scene_manager.b2.hide()
	game.scene_manager.b3.hide()

func wait(seconds: float):
	await game.get_tree().create_timer(seconds).timeout

func _clear_btn_signals(button: Button):
	for conn in button.pressed.get_connections():
		button.pressed.disconnect(conn.callable)
	if OS.has_feature("mobile"):
		button.pressed.connect(func(): Input.vibrate_handheld(50))

func update_stats():
	# Aggiorna tutte le statistiche visualizzate nell'UI
	_update_player_stats()
	_update_enemy_stats()

func _update_player_stats():
	# Aggiorna le statistiche del giocatore
	if not player_stats:
		return

	var stats_text = ""
	var player_energy_types = game.data_manager.story_data.get("player", {}).get("energy", [])

	for energy_stat in player_energy_types:
		var stat_id = energy_stat.get("type")
		var current_value = game.player_manager.get_energy_value(stat_id)
		var max_value = game.player_manager.get_max_energy_value(stat_id)
		stats_text += game.player_manager.get_energy_string(stat_id, current_value, max_value) + "\n"

	player_stats.text = stats_text.strip_edges()

	# Aggiorna icona giocatore
	if player_icon and game.player_manager.player_icon_texture:
		player_icon.texture = game.player_manager.player_icon_texture

func _update_enemy_stats():
	# Aggiorna le statistiche del nemico se in combattimento
	if not enemy_stats_box or not enemy_icon or not enemy_stats:
		return

	if game.combat_manager and game.combat_manager.current_entity_health > 0:
		enemy_stats_box.show()

		var entity_data = game.data_manager.get_entity_data(game.combat_manager.current_entity_id)
		if entity_data.has("icon") and entity_data["icon"] != "":
			enemy_icon.texture = load(entity_data["icon"])

		var health_text = get_health_string(game.combat_manager.current_entity_health)
		enemy_stats.text = health_text
	else:
		enemy_stats_box.hide()

func get_health_string(amount: int) -> String:
	# Formatta una stringa di salute per la UI
	return "❤️ Vita: %d" % amount

func show_death_effects():
	# Applica gli effetti visivi di morte
	if player_icon and grayscale_material:
		player_icon.material = grayscale_material

	_create_death_overlay()
	game.add_child(death_overlay)
	
	var label = death_overlay.get_node("DeathLabel")
	if label:
		label.text = tr("game_over_title")

func hide_death_effects():
	# Rimuove gli effetti visivi di morte
	if player_icon:
		player_icon.material = null

	if death_overlay:
		death_overlay.queue_free()
		death_overlay = null

func _init_ui_references():
	# Inizializza i riferimenti ai nodi UI
	if not game:
		push_error("UIManager: game reference not set!")
		return
	
	meteo_stats = game.get_node("UI/VBC_Main/MC_Meteo/PC/HBC/MeteoText")
	enemy_stats_box = game.get_node("UI/VBC_Main/MC_Enemy/PC")
	enemy_icon = game.get_node("UI/VBC_Main/MC_Enemy/PC/HBC/Icon")
	enemy_stats = game.get_node("UI/VBC_Main/MC_Enemy/PC/HBC/StatsText")
	text = game.get_node("UI/VBC_Main/MC_Story/PC/HBC/StoryText")
	player_icon = game.get_node("UI/VBC_Main/MC_Player/PC/HBC/Icon")
	player_box_container = game.get_node("UI/VBC_Main/MC_Player")
	player_stats = game.get_node("UI/VBC_Main/MC_Player/PC/HBC/StatsText")
	# Inizializza gli shader e materiali per gli effetti di morte
	# Shader grayscale per l'icona
	var shader = Shader.new()
	shader.code = """
		shader_type canvas_item;
		void fragment() {
			vec4 tex_color = texture(TEXTURE, UV);
			float gray = dot(tex_color.rgb, vec3(0.299, 0.587, 0.114));
			COLOR = vec4(vec3(gray), tex_color.a);
		}
	"""
	grayscale_material = ShaderMaterial.new()
	grayscale_material.shader = shader

func _create_death_overlay():
	# Crea l'overlay scuro per la morte
	if death_overlay: return
	
	death_overlay = ColorRect.new()
	death_overlay.color = Color(0, 0, 0, 0.85)
	death_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	death_overlay.mouse_filter = Control.MOUSE_FILTER_STOP

	var label = Label.new()
	label.name = "DeathLabel"
	label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.add_theme_color_override("font_color", Color.RED)
	label.add_theme_font_size_override("font_size", 64)
	if game.data_manager.custom_font:
		label.add_theme_font_override("font", game.data_manager.custom_font)
	death_overlay.add_child(label)

func show_growth_overlay():
	# Mostra l'overlay di crescita statistiche
	if not growth_overlay:
		_create_growth_overlay()
	game.add_child(growth_overlay)
	_refresh_growth_ui()

func hide_growth_overlay():
	# Nasconde l'overlay di crescita
	if growth_overlay:
		growth_overlay.queue_free()
		growth_overlay = null

func _create_growth_overlay():
	# Crea l'interfaccia di crescita delle statistiche
	# Se esiste già, rimuovilo per ricrearlo pulito
	if growth_overlay:
		growth_overlay.queue_free()

	# 1. Background scuro
	growth_overlay = ColorRect.new()
	growth_overlay.color = Color(0, 0, 0, 0.9)
	growth_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	growth_overlay.mouse_filter = Control.MOUSE_FILTER_STOP # Blocca i click sotto

	# 2. Contenitore Centrale
	var center_container = CenterContainer.new()
	center_container.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	growth_overlay.add_child(center_container)

	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 20)
	center_container.add_child(vbox)

	# Carica il font e imposta la dimensione standard per questo menu
	var custom_font = game.data_manager.custom_font
	var font_size = 20

	# 3. Titolo e Punti Disponibili
	var title_label = Label.new()
	title_label.name = "TitleLabel"
	title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title_label.add_theme_font_override("font", custom_font)
	title_label.add_theme_font_size_override("font_size", font_size + 4)
	vbox.add_child(title_label)

	# 4. Lista Statistiche
	var stats_container = VBoxContainer.new()
	stats_container.name = "StatsContainer"
	stats_container.add_theme_constant_override("separation", 10)
	vbox.add_child(stats_container)

func _refresh_growth_ui():
	# Aggiorna l'interfaccia di crescita con i valori attuali
	if not growth_overlay:
		return

	var title_label = growth_overlay.get_node("CenterContainer/VBoxContainer/TitleLabel")
	var stats_container = growth_overlay.get_node("CenterContainer/VBoxContainer/StatsContainer")

	if not title_label or not stats_container:
		return

	# Aggiorna titolo con punti disponibili
	var available_points = game.growth_manager.available_points if game.growth_manager else 0
	title_label.text = tr("growth_title") % available_points

	# Svuota il contenitore delle statistiche
	for child in stats_container.get_children():
		child.queue_free()

	# Popola la lista delle statistiche
	var player_energy_types = game.data_manager.story_data.get("player", {}).get("energy", [])
	var energy_type_definitions = game.data_manager.story_data.get("energy_types", {})

	var custom_font = game.data_manager.custom_font
	var font_size = 20

	for energy_stat in player_energy_types:
		var stat_id = energy_stat.get("type")
		var stat_name_key = energy_type_definitions.get(stat_id, {}).get("name", stat_id)
		var stat_name = tr(stat_name_key)
		var current_value = game.player_manager.get_energy_value(stat_id)

		var row = HBoxContainer.new()
		row.name = "Row_" + stat_id
		row.alignment = BoxContainer.ALIGNMENT_CENTER

		# Bottone Meno
		var btn_minus = Button.new()
		btn_minus.text = "➖"
		btn_minus.custom_minimum_size = Vector2(40, 40)
		btn_minus.add_theme_font_override("font", custom_font)
		btn_minus.add_theme_font_size_override("font_size", font_size)
		btn_minus.pressed.connect(func():
			if game.growth_manager.try_decrease_stat(stat_id):
				_refresh_growth_ui()
		)
		row.add_child(btn_minus)

		# Label Nome Statistica
		var lbl_name = Label.new()
		lbl_name.name = "LabelName"
		lbl_name.text = "%s: %d" % [stat_name, current_value]
		lbl_name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		lbl_name.custom_minimum_size = Vector2(160, 0)
		lbl_name.add_theme_font_override("font", custom_font)
		lbl_name.add_theme_font_size_override("font_size", font_size)
		row.add_child(lbl_name)

		# Bottone Più
		var btn_plus = Button.new()
		btn_plus.text = "➕"
		btn_plus.custom_minimum_size = Vector2(40, 40)
		btn_plus.add_theme_font_override("font", custom_font)
		btn_plus.add_theme_font_size_override("font_size", font_size)
		btn_plus.pressed.connect(func():
			if game.growth_manager.try_increase_stat(stat_id):
				_refresh_growth_ui()
		)
		row.add_child(btn_plus)

		stats_container.add_child(row)
