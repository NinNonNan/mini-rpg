# =========================================================
# EMPATHY MANAGER
# =========================================================
# Gestisce la "conoscenza" che il giocatore ha di un'entità.
#
# Funzionalità principali:
# - Traccia se un nemico è stato "analizzato".
# - Svela le statistiche nascoste (debolezze, immunità, umore)
#   dopo un'analisi riuscita.
# - Fornisce testo formattato per la UI.
#
# Questo manager non agisce direttamente, ma viene consultato da altri
# sistemi (es. Game.gd per aggiornare la UI) per sapere COSA mostrare.

class_name EmpathyManager
extends Node

# Riferimento al gioco principale per accedere a `entity_data` e `tr()`.
# Viene iniettato da Game.gd in _ready().
var game: Game

# Flag che indica se il giocatore conosce le statistiche dell'entità corrente.
# Se `false`, la UI mostrerà "???" per HP, umore, ecc.
# Se `true`, la UI mostrerà i valori reali.
var is_known = false

# Umore dell'entità analizzata, ottenuto tramite la funzione `analyze`.
# Viene usato per decidere quale messaggio di feedback mostrare.
var current_mood: int = 0

# Resetta lo stato di conoscenza.
# Viene chiamato da Game.gd ogni volta che si cambia scena o si inizia
# un nuovo incontro, per assicurarsi che ogni nemico debba essere analizzato di nuovo.
func reset():
	is_known = false
	current_mood = 0


# Azione di analisi: svela le informazioni sull'entità.
# Restituisce una stringa di testo (già tradotta) da mostrare al giocatore.
func analyze(entity_id: String) -> String:
	is_known = true
	
	var entity = game.entity_data.get(entity_id, {})
	current_mood = int(entity.get("mood", 0))
	
	if current_mood < -10:
		# Se l'umore è molto basso, restituisce un messaggio di avvertimento.
		return game.tr("combat_analysis_hostile")
	
	# Altrimenti, restituisce un messaggio di successo generico.
	return game.tr("combat_analysis_success")

# Funzione helper per ottenere una stringa formattata con debolezze e immunità.
# Viene chiamata da Game.gd (in `update_stats`) quando `is_known` è `true`
# per mostrare le icone e i nomi delle vulnerabilità del nemico.
func get_weakness_immunity_text(entity_id: String) -> String:
	var entity = game.entity_data.get(entity_id, {})
	var out_text = ""
	
	var weaknesses = entity.get("weaknesses", [])
	if not weaknesses.is_empty():
		var w_strings = []
		for w in weaknesses:
			# w è ora una stringa (es. "fuoco")
			var icon = game.get_damage_type_icon(w) # Recupera l'icona (es. "🔥")
			w_strings.append("%s %s" % [icon, w])
		out_text += "\n" + game.tr("stats_weaknesses") % ", ".join(w_strings)
		
	var immunities = entity.get("immunities", [])
	if not immunities.is_empty():
		var i_strings = []
		for i in immunities:
			# i è ora una stringa
			var icon = game.get_damage_type_icon(i) # Recupera l'icona
			i_strings.append("%s %s" % [icon, i])
		out_text += "\n" + game.tr("stats_immunities") % ", ".join(i_strings)
		
	return out_text
