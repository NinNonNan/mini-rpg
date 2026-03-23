# =========================================================
# STATS MANAGER
# =========================================================
# Gestisce il menu di configurazione del personaggio.
#
# Funzionalità principali:
# - Visualizzazione e ordinamento delle statistiche (UI dinamica).
# - Navigazione dell'inventario.
# - Gestione dell'equipaggiamento (spostamento oggetti Zaino <-> Slot).
#
# Questo manager crea e distrugge la propria interfaccia (popup) su richiesta.

class_name StatsManager
extends Control

# Riferimento al gioco principale.
var game: Game

# Riferimenti ai nodi UI generati dinamicamente
var config_panel: PanelContainer
var items_container: VBoxContainer

func _ready():
	# Si nasconde e occupa tutto lo schermo per bloccare i click sotto quando aperto
	visible = false
	z_index = 100 # Assicura che sia sopra a tutto
	
	# Forza il rendering sopra tutto e a schermo intero (indipendente dalla gerarchia)
	top_level = true
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

# Apre il menu di configurazione e mette in pausa le interazioni di gioco.
func open_config_menu():
	if not game: return
	
	_build_ui()
	visible = true
	# Disabilita le scelte nel gioco mentre il menu è aperto
	game.disable_choices()

# Chiude il menu, distrugge l'interfaccia e riprende il gioco.
func close_config_menu():
	visible = false
	if config_panel:
		config_panel.queue_free()
		config_panel = null
	
	# Aggiorna la UI principale con il nuovo ordine
	game.update_stats()
	
	# Se il gioco ha un riferimento al player o alla UI stats, lo forziamo ad aggiornarsi
	# (game.update_stats() lo fa già, ma utile per sicurezza)
	game.enable_choices()

# Costruisce l'intera interfaccia utente via codice.
func _build_ui():
	# Pulisce eventuale UI precedente
	if config_panel: config_panel.queue_free()
	
	# Sfondo scuro semi-trasparente
	var bg = ColorRect.new()
	bg.color = Color(0, 0, 0, 0.8)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	
	# Pannello principale
	config_panel = PanelContainer.new()
	# Centra il pannello nello schermo
	config_panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	config_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	config_panel.custom_minimum_size = Vector2(400, 500) # Dimensione minima per stare comodi
	config_panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	add_child(config_panel)
	
	var main_vbox = VBoxContainer.new()
	config_panel.add_child(main_vbox)

	# Titolo del pannello generale
	var main_title = Label.new()
	main_title.text = tr("stats_menu_title")
	main_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_apply_font(main_title, 24)
	main_vbox.add_child(main_title)
	
	# --- TAB CONTAINER ---
	var tabs = TabContainer.new()
	tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_apply_font(tabs, 20)
	main_vbox.add_child(tabs)
	
	# -- TAB 1: Statistiche --
	var stats_page = VBoxContainer.new()
	stats_page.name = tr("stats_tab_stats")
	items_container = VBoxContainer.new() # Assegna al container globale per _refresh_list
	stats_page.add_child(items_container)
	tabs.add_child(stats_page)
	
	_refresh_stats_list()
	
	# -- TAB 2: Inventario --
	var inv_page = VBoxContainer.new()
	inv_page.name = tr("stats_tab_inventory")
	tabs.add_child(inv_page)
	_build_inventory_tab(inv_page)
	
	# Pulsante Chiudi
	var close_btn = Button.new()
	close_btn.text = tr("stats_btn_close")
	_apply_font(close_btn, 20)
	close_btn.pressed.connect(close_config_menu)
	main_vbox.add_child(close_btn)

# Applica il font globale e la dimensione specificata a un controllo.
func _apply_font(node: Control, font_size: int):
	var font = load("res://fonts/freecam v2.ttf")
	if font:
		node.add_theme_font_override("font", font)
	node.add_theme_font_size_override("font_size", font_size)

# Aggiorna la lista delle statistiche nel primo tab.
# Permette di riordinare le stat visualizzate nell'HUD principale.
func _refresh_stats_list():
	if not items_container: return
	for child in items_container.get_children():
		child.queue_free()
	
	var hint = Label.new()
	hint.text = tr("stats_order_hint")
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_apply_font(hint, 20)
	items_container.add_child(hint)
	items_container.add_child(HSeparator.new())
		
	# Recupera la lista delle energie dal gioco. Se game non esiste, usa array vuoto.
	var energy_defs: Array = game.story_data.get("player", {}).get("energy", []) if game else []
	
	# Ordina basandosi sull'ordine attuale
	energy_defs.sort_custom(func(a, b): return a.get("display_order", 99) < b.get("display_order", 99))
	
	for i in range(energy_defs.size()):
		var def = energy_defs[i]
		var type_id = def.get("type")
		var type_data = game.story_data.get("energy_types", {}).get(type_id, {})
		var icon = type_data.get("icon", "")
		var name_key = type_data.get("name", type_id)
		
		var row = HBoxContainer.new()
		items_container.add_child(row)
		
		# Label info
		var lbl = Label.new()
		lbl.text = "%s %s" % [icon, tr(name_key)]
		lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_apply_font(lbl, 20)
		# Evidenzia i primi 3 (quelli che verranno mostrati)
		if i < 3:
			lbl.modulate = Color.GREEN
		else:
			lbl.modulate = Color(1, 1, 1, 0.5)
			
		row.add_child(lbl)
		
		# Pulsante SU
		var btn_up = Button.new()
		btn_up.text = "▲"
		_apply_font(btn_up, 20)
		btn_up.disabled = (i == 0)
		btn_up.pressed.connect(_move_item.bind(i, -1))
		row.add_child(btn_up)
		
		# Pulsante GIU
		var btn_down = Button.new()
		btn_down.text = "▼"
		_apply_font(btn_down, 20)
		btn_down.disabled = (i == energy_defs.size() - 1)
		btn_down.pressed.connect(_move_item.bind(i, 1))
		row.add_child(btn_down)

# Gestisce lo spostamento su/giù di una statistica nella lista.
func _move_item(index: int, direction: int):
	var energy_defs: Array = game.story_data.get("player", {}).get("energy", [])
	
	# Poiché l'array potrebbe non essere ordinato in memoria come lo vediamo a schermo,
	# prima lo ordiniamo per essere sicuri di scambiare gli elementi giusti.
	energy_defs.sort_custom(func(a, b): return a.get("display_order", 99) < b.get("display_order", 99))
	
	var target_index = index + direction
	if target_index < 0 or target_index >= energy_defs.size():
		return
		
	# Scambia i valori di display_order
	var item_a = energy_defs[index]
	var item_b = energy_defs[target_index]
	
	var order_a = item_a.get("display_order", 99)
	var order_b = item_b.get("display_order", 99)
	
	item_a["display_order"] = order_b
	item_b["display_order"] = order_a
	
	# Ridisegna la lista
	_refresh_stats_list()

# =========================================================
# --- GESTIONE INVENTARIO UI ---
# =========================================================

# Costruisce il contenuto del tab Inventario/Equipaggiamento.
func _build_inventory_tab(container: VBoxContainer):
	# Pulisce contenuto
	for c in container.get_children():
		c.queue_free()
	
	# 1. Sezione EQUIPAGGIAMENTO
	var lbl_equip = Label.new()
	lbl_equip.text = tr("stats_equip_title")
	lbl_equip.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_apply_font(lbl_equip, 20)
	container.add_child(lbl_equip)
	
	var slots_grid = GridContainer.new()
	slots_grid.columns = 1
	slots_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	container.add_child(slots_grid)
	
	for slot_id in game.equipment_slots:
		var btn = Button.new()
		btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
		var item_id = game.equipment.get(slot_id)
		
		if item_id:
			var item_name = game.item_manager.get_item_name(item_id) if game.item_manager else item_id
			var item_icon = game.item_manager.get_item_icon(item_id) if game.item_manager else ""
			btn.text = tr("stats_equip_slot_filled") % [slot_id, item_icon, item_name]
			# Click -> Rimuovi
			btn.pressed.connect(func():
				game.unequip_item(slot_id)
				_build_inventory_tab(container) # Ricarica UI
			)
			btn.modulate = Color(0.8, 1, 0.8) # Verdino se equipaggiato
		else:
			btn.text = tr("stats_equip_slot_empty") % slot_id
			btn.disabled = true # Disabilita click su slot vuoti (l'equip si fa dall'inventario)
			btn.modulate = Color(1, 1, 1, 0.5)
		
		_apply_font(btn, 20)
		slots_grid.add_child(btn)
	
	container.add_child(HSeparator.new())
	
	# 2. Sezione ZAINO
	var lbl_bag = Label.new()
	lbl_bag.text = tr("stats_bag_title") % game.inventory.size()
	lbl_bag.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_apply_font(lbl_bag, 20)
	container.add_child(lbl_bag)
	
	var scroll = ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	container.add_child(scroll)
	
	var bag_vbox = VBoxContainer.new()
	bag_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(bag_vbox)
	
	if game.inventory.is_empty():
		var lbl_empty = Label.new()
		lbl_empty.text = tr("stats_bag_empty")
		lbl_empty.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_apply_font(lbl_empty, 20)
		bag_vbox.add_child(lbl_empty)
	else:
		for i in range(game.inventory.size()):
			var item_id = game.inventory[i]
			var item_name = game.item_manager.get_item_name(item_id) if game.item_manager else item_id
			var item_icon = game.item_manager.get_item_icon(item_id) if game.item_manager else ""
			
			# Recupera info mani
			var hands_str = ""
			if game.item_data.has(item_id) and game.item_data[item_id].has("hands"):
				hands_str = " (%dH)" % int(game.item_data[item_id]["hands"])

			var row = HBoxContainer.new()
			bag_vbox.add_child(row)
			
			var lbl = Label.new()
			lbl.text = "%s %s%s" % [item_icon, item_name, hands_str]
			lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			_apply_font(lbl, 20)
			row.add_child(lbl)
			
			var btn_equip = Button.new()
			btn_equip.text = tr("stats_btn_equip")
			_apply_font(btn_equip, 20)
			# Click -> Mostra popup per scegliere slot
			btn_equip.pressed.connect(_show_slot_selection.bind(item_id, container))
			row.add_child(btn_equip)

# Mostra la schermata di selezione dello slot dove equipaggiare l'oggetto.
func _show_slot_selection(item_id: String, container: VBoxContainer):
	# Svuota il container per mostrare solo la selezione slot
	for c in container.get_children():
		c.queue_free()
		
	var lbl = Label.new()
	lbl.text = tr("stats_equip_prompt") % item_id
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_apply_font(lbl, 20)
	container.add_child(lbl)
	
	for slot in game.equipment_slots:
		var btn = Button.new()
		btn.text = slot
		_apply_font(btn, 20)
		btn.pressed.connect(func():
			game.equip_item(item_id, slot)
			_build_inventory_tab(container) # Torna alla lista
		)
		container.add_child(btn)
		
	container.add_child(HSeparator.new())
	
	var btn_cancel = Button.new()
	btn_cancel.text = tr("stats_btn_cancel")
	_apply_font(btn_cancel, 20)
	btn_cancel.pressed.connect(func(): _build_inventory_tab(container))
	container.add_child(btn_cancel)