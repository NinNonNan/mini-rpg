# d:\___SVILUPPO\mini-rpg\mini-rpg\empathy_manager.gd
class_name EmpathyManager
extends Node

# Riferimento al gioco principale
var game: Game

# Indica se il giocatore conosce le statistiche dell'entità corrente
var is_known = false
# Umore dell'entità analizzata, ottenuto tramite l'analisi
var current_mood: int = 0

# Resetta la conoscenza (da chiamare quando incontri un nuovo nemico)
func reset():
	is_known = false
	current_mood = 0


# Azione di analisi: svela le info, incluso l'umore
# Restituisce il testo da mostrare al giocatore
func analyze(entity_id: String) -> String:
	is_known = true
	
	var entity = game.entity_data.get(entity_id, {})
	current_mood = int(entity.get("mood", 0))
	
	if current_mood < -10:
		return game.tr("combat_analysis_hostile")
	return game.tr("combat_analysis_success")

# Helper per ottenere testo debolezze/immunità formattato
func get_weakness_immunity_text(entity_id: String) -> String:
	var entity = game.entity_data.get(entity_id, {})
	var out_text = ""
	
	var weaknesses = entity.get("weaknesses", [])
	if not weaknesses.is_empty():
		var w_strings = []
		for w in weaknesses:
			# w è ora una stringa (es. "fuoco")
			var icon = game.get_damage_type_icon(w)
			w_strings.append("%s %s" % [icon, w])
		out_text += "\n" + game.tr("stats_weaknesses") % ", ".join(w_strings)
		
	var immunities = entity.get("immunities", [])
	if not immunities.is_empty():
		var i_strings = []
		for i in immunities:
			# i è ora una stringa
			var icon = game.get_damage_type_icon(i)
			i_strings.append("%s %s" % [icon, i])
		out_text += "\n" + game.tr("stats_immunities") % ", ".join(i_strings)
		
	return out_text
