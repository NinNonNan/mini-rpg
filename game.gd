extends Control

# --- Riferimenti ai Nodi dell'Interfaccia Utente (UI) ---
@onready var text = $VBoxContainer/StoryText
@onready var stats = $VBoxContainer/StatsText
@onready var b1 = $VBoxContainer/Choice1
@onready var b2 = $VBoxContainer/Choice2
@onready var b3 = $VBoxContainer/Choice3

# --- Variabili di Gioco ---
# Salute del giocatore
var health = 10
# Inventario del giocatore
var inventory = []
# Salute del nemico corrente (0 se non si è in combattimento)
var current_enemy_health = 0
# Scena da mostrare in caso di vittoria nel combattimento corrente
var current_victory_scene = ""

# --- Struttura della Storia ---
# Dizionario principale che contiene tutta la storia del gioco.
# Ogni chiave è un nome di scena, che contiene il testo e le scelte possibili.
var story = {
	"start": {
		"text": "Benvenuto nel Mini-GDR! Sei davanti a una caverna.",
		"choices": [
			{"text": "Entra nella caverna", "next": "cave"},
			{"text": "Vai nella foresta", "next": "forest"}
		]
	},
	"cave": {
		"text": "Dentro la caverna trovi una spada arrugginita.",
		"choices": [
			{"text": "Prendere la spada", "action": "take_sword"},
			{"text": "Proseguire", "next": "dragon"}
		]
	},
	"forest": {
		"text": "Un lupo selvaggio appare!",
		"choices": [
			{"text": "Combattere", "action": "fight_wolf"},
			{"text": "Scappare", "next": "start"}
		]
	},
	"dragon": {
		"text": "Un piccolo drago protegge un tesoro.",
		"choices": [
			{"text": "Combattere", "action": "fight_dragon"},
			{"text": "Scappare", "next": "start"}
		]
	},
	"forest_victory": {
		"text": "Hai sconfitto il lupo. La via è libera, ma non c'è altro da vedere qui. Meglio tornare indietro.",
		"choices": [
			{"text": "Torna all'inizio", "next": "start"}
		]
	},
	"dragon_victory": {
		"text": "Hai sconfitto il drago e hai preso il suo tesoro! HAI VINTO!",
		"choices": [
			{"text": "Gioca di nuovo", "action": "restart_game"}
		]
	}
}

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
	show_scene(current_scene)

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
	if choice.has("next"):
		show_scene(choice["next"])
		return
	if choice.has("action"):
		match choice["action"]:
			# Azione per prendere la spada
			"take_sword":
				if not "spada" in inventory:
					inventory.append("spada")
					text.text = "Hai preso la spada!"
					await get_tree().create_timer(1.5).timeout
				show_scene("dragon")
			"fight_wolf":
				# Inizia il combattimento con il lupo
				start_combat(5, "forest_victory")
			"fight_dragon":
				# Inizia il combattimento con il drago
				start_combat(8, "dragon_victory")
			"restart_game":
				# Resetta il gioco
				health = 10
				inventory.clear()
				show_scene("start")

func start_combat(enemy_health, victory_scene):
	current_enemy_health = enemy_health
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

func attack_enemy():
	var damage = 2
	if "spada" in inventory:
		damage = 4
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
	health -= 3 # Il nemico infligge 3 danni
	update_stats()
	if health <= 0:
		game_over() # Se la vita scende a 0 o meno, è game over
	else:
		text.text = "Il nemico ti colpisce! Perdi 3 punti vita."
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
