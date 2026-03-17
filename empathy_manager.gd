# d:\___SVILUPPO\mini-rpg\mini-rpg\empathy_manager.gd
class_name EmpathyManager
extends Node

# Indica se il giocatore conosce le statistiche dell'entità corrente
var is_known = false
# Umore dell'entità analizzata, ottenuto tramite l'analisi
var current_mood: int = 0

# Resetta la conoscenza (da chiamare quando incontri un nuovo nemico)
func reset():
	is_known = false
	current_mood = 0


# Azione di analisi: svela le info, incluso l'umore
func analyze(mood_value: int):
	is_known = true
	current_mood = mood_value
