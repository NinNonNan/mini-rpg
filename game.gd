extends Control

# --- Riferimenti ai Nodi dell'Interfaccia Utente (UI) ---
@onready var text = $CenterContainer/VBoxContainer/StoryText
@onready var stats = $CenterContainer/VBoxContainer/StatsText
@onready var b1 = $CenterContainer/VBoxContainer/Choice1
@onready var b2 = $CenterContainer/VBoxContainer/Choice2
@onready var b3 = $CenterContainer/VBoxContainer/Choice3

# --- Variabili di Gioco ---
# Salute del giocatore
var health = 10
# Inventario del giocatore
var inventory = []
# Salute del nemico corrente (0 se non si è in combattimento)
var current_enemy_health = 0
# Danno del nemico corrente
var current_enemy_damage = 0
# Scena da mostrare in caso di vittoria nel combattimento corrente
var current_victory_scene = ""

# Dizionario che conterrà la storia del gioco, caricata da un file JSON.
var story = {}
# Dizionario che conterrà i dati degli oggetti (es. danni armi)
var item_data = {}

# Tiene traccia della scena corrente
var current_scene = "start"

# Funzione chiamata da Godot quando il nodo è pronto e aggiunto alla scena.
func _ready():
	# Fa in modo che l'etichetta del testo si espanda per riempire lo spazio verticale,
	# mantenendo i pulsanti fissi in basso.
	text.size_flags_vertical = Control.SIZE_EXPAND | Control.SIZE_FILL

	# Fa in modo che i pulsanti si espandano orizzontalmente per riempire il contenitore.
	# Questo dà loro una larghezza uniforme e impedisce all'interfaccia di "saltare"
	# quando il testo dei pulsanti cambia.
	b1.size_flags_horizontal = Control.SIZE_EXPAND | Control.SIZE_FILL
	b2.size_flags_horizontal = Control.SIZE_EXPAND | Control.SIZE_FILL
	b3.size_flags_horizontal = Control.SIZE_EXPAND | Control.SIZE_FILL
	
	_load_story()
	show_scene(current_scene)

# Carica i dati della storia dal file story.json
func _load_story():
	var file_path = "res://story.json"
	
	if not FileAccess.file_exists(file_path):
		text.text = "ERRORE: File della storia non trovato!\nAssicurati che 'story.json' sia nella cartella del progetto."
		push_error("File della storia non trovato in: " + file_path)
		return

	var file = FileAccess.open(file_path, FileAccess.READ)
	var json_data = JSON.parse_string(file.get_as_text())
	
	if json_data and typeof(json_data) == TYPE_DICTIONARY:
		story = json_data.get("scenes", {})
		item_data = json_data.get("items", {})
	else:
		text.text = "ERRORE: Il file della storia ('story.json') è corrotto o malformato."
		push_error("Errore nel parsing del file JSON della storia.")

# Aggiorna il testo delle statistiche del giocatore e del nemico.
func update_stats():
	var enemy_text = ""
	if current_enemy_health > 0:
		enemy_text = " | Nemico: %d HP" % current_enemy_health
	stats.text = "Vita: %d | Inventario: %s%s" % [health, inventory, enemy_text]

# Mostra una scena specifica basata sul suo nome.
func show_scene(name):
	# Imposta la scena corrente e resetta la salute del nemico (non siamo in combattimento)
	current_scene = name
	current_enemy_health = 0
	var scene = story[name]
	text.text = scene["text"]
	update_stats()
	var choices = scene["choices"]
	var buttons = [b1, b2, b3]

	# Configura i pulsanti in base alle scelte disponibili nella scena
	for i in range(buttons.size()):
		if i < choices.size():
			buttons[i].text = choices[i]["text"]
			buttons[i].show()
			var choice = choices[i]
			_clear_signals(buttons[i])
			buttons[i].pressed.connect(func(): handle_choice(choice), CONNECT_ONE_SHOT)
		else:
			buttons[i].hide()

# Gestisce la logica quando un pulsante di scelta viene premuto.
func handle_choice(choice):
	# 1. Gestione Azioni Generiche (basate sui dati del JSON)
	if choice.has("action"):
		match choice["action"]:
			"pickup":
				# Legge quale oggetto prendere dal JSON
				var item = choice.get("item_id", "oggetto")
				if not item in inventory:
					inventory.append(item)
					text.text = "Hai preso: " + item
					update_stats()
					await get_tree().create_timer(1.0).timeout
			"combat":
				# Legge la vita del nemico e la scena di vittoria dal JSON
				var hp = choice.get("enemy_health", 5)
				var dmg = choice.get("enemy_damage", 2)
				var victory = choice.get("victory_scene", "start")
				start_combat(hp, dmg, victory)
				return # Il combattimento gestisce il flusso, usciamo dalla funzione
			"restart":
				health = 10
				inventory.clear()
				show_scene("start")
				return

	# 2. Cambio Scena (se definito nel JSON)
	if choice.has("next"):
		show_scene(choice["next"])

func start_combat(enemy_health, enemy_damage, victory_scene):
	current_enemy_health = enemy_health
	current_enemy_damage = enemy_damage
	current_victory_scene = victory_scene
	update_stats()
	text.text = "Combatti il nemico! HP nemico: %d" % current_enemy_health
	show_combat_buttons()

# Mostra i pulsanti specifici per il combattimento.
func show_combat_buttons():
	b1.text = "Attacca"
	b1.show()
	_clear_signals(b1)
	b1.pressed.connect(func(): attack_enemy(), CONNECT_ONE_SHOT)
	
	b2.text = "Fuggi"
	b2.show()
	_clear_signals(b2)
	b2.pressed.connect(func(): flee_combat(), CONNECT_ONE_SHOT)
	
	b3.hide()
	# Cerca nell'inventario se c'è un oggetto con la proprietà "heal"
	for item_id in inventory:
		if item_data.has(item_id) and item_data[item_id].has("heal"):
			b3.text = "Usa " + item_id
			b3.show()
			_clear_signals(b3)
			b3.pressed.connect(func(): use_item(item_id), CONNECT_ONE_SHOT)
			break # Per ora gestiamo solo il primo oggetto curativo trovato

func use_item(item_id):
	var stats = item_data[item_id]
	var heal_amount = stats.get("heal", 0)
	
	health = min(health + heal_amount, 10) # Cura senza superare il massimo (10)
	text.text = "Hai usato %s e recuperato %d HP!" % [item_id, heal_amount]
	
	if stats.get("consumable", false):
		inventory.erase(item_id)
		
	update_stats()
	await get_tree().create_timer(1.5).timeout
	enemy_turn() # Usare un oggetto consuma il turno!

func attack_enemy():
	var damage = 2
	# Calcola il danno basandosi sugli oggetti nell'inventario
	for item_id in inventory:
		if item_data.has(item_id):
			var item_stats = item_data[item_id]
			damage = max(damage, item_stats.get("damage", 0)) # Usa il danno dell'arma migliore

	current_enemy_health -= damage
	text.text = "Hai inflitto %d danni!" % damage
	update_stats()
	
	await get_tree().create_timer(1.0).timeout
	
	if current_enemy_health <= 0:
		# Il nemico è stato sconfitto
		current_enemy_health = 0
		text.text = "Hai vinto lo scontro!"
		update_stats()
		await get_tree().create_timer(1.5).timeout
		show_scene(current_victory_scene)
		return
	
	# Se il nemico è ancora vivo, è il suo turno di attaccare
	enemy_turn()

func flee_combat():
	# Tenta la fuga. C'è una probabilità del 50% di successo.
	text.text = "Tenti di fuggire..."
	await get_tree().create_timer(1.0).timeout
	
	if randf() < 0.5: # 50% di probabilità di successo
		text.text = "Sei riuscito a fuggire!"
		await get_tree().create_timer(1.5).timeout
		show_scene("start") # Torna alla scena iniziale dopo la fuga
	else:
		text.text = "La fuga è fallita! Il nemico ti attacca."
		await get_tree().create_timer(1.5).timeout
		enemy_turn() # Se la fuga fallisce, il nemico attacca

# Gestisce il turno di attacco del nemico.
func enemy_turn():
	health -= current_enemy_damage
	update_stats()
	if health <= 0:
		game_over() # Se la vita scende a 0 o meno, è game over
	else:
		text.text = "Il nemico ti colpisce! Perdi %d punti vita." % current_enemy_damage
		await get_tree().create_timer(1.5).timeout
		show_combat_buttons() # Mostra di nuovo i pulsanti di combattimento
		
func game_over():
	text.text = "SEI MORTO.\nPremi per ricominciare."
	health = 10
	inventory.clear()
	current_enemy_health = 0
	b1.text = "Ricomincia"
	b1.show()
	_clear_signals(b1)
	b1.pressed.connect(func(): show_scene("start"), CONNECT_ONE_SHOT)
	b2.hide()
	b3.hide()

# Funzione helper per rimuovere tutti i collegamenti di un segnale di un pulsante
func _clear_signals(button: Button) -> void:
	for conn in button.pressed.get_connections():
		button.pressed.disconnect(conn.callable)
