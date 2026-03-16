extends Control

@onready var text = $VBoxContainer/StoryText
@onready var stats = $VBoxContainer/StatsText
@onready var b1 = $VBoxContainer/Choice1
@onready var b2 = $VBoxContainer/Choice2
@onready var b3 = $VBoxContainer/Choice3

var health = 10
var inventory = []
var current_enemy_health = 0

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
	}
}

var current_scene = "start"

func _ready():
	show_scene(current_scene)

func update_stats():
	var enemy_text = ""
	if current_enemy_health > 0:
		enemy_text = " | Nemico: %d HP" % current_enemy_health
	stats.text = "Vita: %d | Inventario: %s%s" % [health, inventory, enemy_text]

func show_scene(name):
	current_scene = name
	current_enemy_health = 0
	var scene = story[name]
	text.text = scene["text"]
	update_stats()
	var choices = scene["choices"]
	var buttons = [b1, b2, b3]

	for i in range(buttons.size()):
		if i < choices.size():
			buttons[i].text = choices[i]["text"]
			buttons[i].show()
			var choice = choices[i]
			_clear_signals(buttons[i])
			buttons[i].pressed.connect(func(): handle_choice(choice), CONNECT_ONE_SHOT)
		else:
			buttons[i].hide()

func handle_choice(choice):
	if choice.has("next"):
		show_scene(choice["next"])
		return
	if choice.has("action"):
		match choice["action"]:
			"take_sword":
				if not "spada" in inventory:
					inventory.append("spada")
					text.text = "Hai preso la spada!"
				show_scene("dragon")
			"fight_wolf":
				start_combat(5)
			"fight_dragon":
				start_combat(8)

func start_combat(enemy_health):
	current_enemy_health = enemy_health
	update_stats()
	text.text = "Combatti il nemico! HP nemico: %d" % current_enemy_health
	show_combat_buttons()

func show_combat_buttons():
	b1.text = "Attacca"
	b1.show()
	_clear_signals(b1)
	b1.pressed.connect(func(): attack_enemy(), CONNECT_ONE_SHOT)
	b2.hide()
	b3.hide()

func attack_enemy():
	var damage = 2
	if "spada" in inventory:
		damage = 4
	current_enemy_health -= damage
	
	if current_enemy_health <= 0:
		text.text = "Hai vinto lo scontro!"
		current_enemy_health = 0
		update_stats()
		show_scene("start")
		return
	
	# nemico contrattacca
	health -= 3
	if health <= 0:
		game_over()
	else:
		text.text = "Il nemico ti colpisce! Perdi vita."
		update_stats()
		show_combat_buttons()

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
	for conn in button.pressed.get_signal_connection_list():
		button.pressed.disconnect(conn.target, conn.method)
