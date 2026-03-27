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
# Riferimento al gestore degli oggetti (senza tipo statico per permettere duck-typing).
var item_manager

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
	
	# Recupera l'ItemManager se non è già associato (seguendo il pattern $Manager/Item)
	if not item_manager:
		item_manager = game.get_node_or_null("Manager/Item")
	
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
	
	# Verifica di sicurezza: se item_manager non è disponibile, usciamo
	if not item_manager:
		return

	# Accesso sicuro alle proprietà del Manager tramite get() (1 solo argomento)
	var equipment = item_manager.get("equipment")
	if equipment == null: equipment = {}
	var equipment_slots = item_manager.get("equipment_slots")
	if equipment_slots == null: equipment_slots = []

	for slot_id in (equipment_slots as Array):
		var btn = Button.new()
		btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
		var item_id = equipment.get(slot_id)
		
		if item_id:
			var item_name = item_manager.get_item_name(item_id)
			var item_icon = item_manager.get_item_icon(item_id)
			btn.text = tr("stats_equip_slot_filled") % [tr(slot_id), item_icon, item_name]
			# Click -> Rimuovi
			btn.pressed.connect(func():
				item_manager.unequip_item(slot_id)
				_build_inventory_tab(container) # Ricarica UI
			)
			btn.modulate = Color(0.8, 1, 0.8) # Verdino se equipaggiato
		else:
			btn.text = tr("stats_equip_slot_empty") % tr(slot_id)
			btn.disabled = true # Disabilita click su slot vuoti (l'equip si fa dall'inventario)
			btn.modulate = Color(1, 1, 1, 0.5)
		
		_apply_font(btn, 20)
		slots_grid.add_child(btn)
	
	container.add_child(HSeparator.new())
	
	# 2. Sezione ZAINO
	var inventory = item_manager.get("inventory")
	if inventory == null: inventory = []
	var item_data = item_manager.get("item_data")
	if item_data == null: item_data = {}

	var lbl_bag = Label.new()
	lbl_bag.text = tr("stats_bag_title") % (inventory as Array).size()
	lbl_bag.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_apply_font(lbl_bag, 20)
	container.add_child(lbl_bag)
	
	var scroll = ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	container.add_child(scroll)
	
	var bag_vbox = VBoxContainer.new()
	bag_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(bag_vbox)
	
	if inventory.is_empty():
		var lbl_empty = Label.new()
		lbl_empty.text = tr("stats_bag_empty")
		lbl_empty.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_apply_font(lbl_empty, 20)
		bag_vbox.add_child(lbl_empty)
	else:
		for i in range(inventory.size()):
			var item_id = inventory[i]
			var item_name = item_manager.get_item_name(item_id)
			var item_icon = item_manager.get_item_icon(item_id)
			
			# Recupera info mani
			var hands_str = ""
			if item_data.has(item_id) and item_data[item_id].has("hands"):
				hands_str = " (%dH)" % int(item_data[item_id]["hands"])

			var row = HBoxContainer.new()
			bag_vbox.add_child(row)
			
			var lbl = Label.new()
			lbl.text = "%s %s%s" % [item_icon, item_name, hands_str]
			lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			_apply_font(lbl, 20)
			row.add_child(lbl)
			
			# Recupera i dati dell'oggetto per determinarne il tipo (Consumabile o Equipaggiamento)
			var item_props = item_data.get(item_id, {})
			
			if item_props.has("heal") or item_props.has("restore"):
				# MECCANICA CONSUMABILI: Se l'oggetto ha dati di ripristino ("restore"), mostriamo "Usa"
				var btn_use = Button.new()
				btn_use.text = tr("stats_btn_use")
				_apply_font(btn_use, 20)
				# Connette all'azione di utilizzo passando l'ID oggetto e il container per aggiornare la lista
				btn_use.pressed.connect(_use_item.bind(item_id, container))
				row.add_child(btn_use)
			else:
				# MECCANICA EQUIPAGGIAMENTO: Comportamento standard se non è un consumabile
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
	var display_name = item_manager.get_item_name(item_id)
	lbl.text = tr("stats_equip_prompt") % display_name
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_apply_font(lbl, 20)
	container.add_child(lbl)
	
	var slots = item_manager.get("equipment_slots")
	if slots == null: slots = []

	for slot in (slots as Array):
		var btn = Button.new()
		btn.text = tr(slot)
		_apply_font(btn, 20)
		btn.pressed.connect(func():
			item_manager.equip_item(item_id, slot)
			_build_inventory_tab(container) # Torna alla lista
		)
		container.add_child(btn)
		
	container.add_child(HSeparator.new())
	
	var btn_cancel = Button.new()
	btn_cancel.text = tr("stats_btn_cancel")
	_apply_font(btn_cancel, 20)
	btn_cancel.pressed.connect(func(): _build_inventory_tab(container))
	container.add_child(btn_cancel)

# Gestisce l'utilizzo di un oggetto consumabile (es. Pozione)
func _use_item(item_id: String, container: VBoxContainer):
	if not game or not item_manager: return
	
	# Delega la logica all'ItemManager e ottiene il messaggio di feedback
	var feedback = item_manager.use_item(item_id)
	
	if game.text:
		game.text.text += "\n" + feedback
	
	# Ricarica la UI
	_build_inventory_tab(container)
