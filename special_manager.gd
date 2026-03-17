class_name SpecialManager
extends Node

var game

# Proprietà calcolata per compatibilità con CombatManager
var spells: Dictionary:
	get:
		if game:
			# Fix: Usa get() per accesso sicuro. Supporta 'story_data' o 'story' come fallback.
			var data = game.get("story_data")
			if not data:
				data = game.get("story")
			if data:
				return data.get("spells", {})
		return {}

# Helper per ottenere i dati di una magia in modo sicuro
func get_spell_data(spell_id: String) -> Dictionary:
	return spells.get(spell_id, {})

# Verifica se il giocatore ha abbastanza mana
func has_enough_mana(spell_id: String) -> bool:
	var spell = get_spell_data(spell_id)
	if not spell: return false
	# CRITICITÀ RISOLTA: Legge il valore "magic" dalla nuova struttura energy
	var current_magic = game.get_player_energy_value("magic")
	return current_magic >= spell.cost

# Esegue l'abilità e restituisce il testo descrittivo dell'effetto
func use_spell(spell_id: String, target_entity_id: String) -> String:
	var spell = get_spell_data(spell_id)
	if not spell: return ""
	
	# Consuma Mana
	# CRITICITÀ RISOLTA: Modifica il valore "magic" usando una funzione helper
	game.modify_player_energy("magic", -spell.cost)
	
	# Logica di cura
	if spell.has("heal"):
		var amount = spell.heal
		# CRITICITÀ RISOLTA: Modifica il valore "life" usando una funzione helper
		# Nota: la funzione helper dovrebbe gestire il clamp al valore massimo.
		game.modify_player_energy("life", amount)
		return game.tr("spell_cast_heal") % [game.tr(spell.name), amount]
	
	# Logica di danno
	elif spell.has("damage"):
		var amount = spell.damage
		var type = spell.type
		
		# Calcolo resistenze tramite dati globali
		var entity_def = {}
		# Fix: Accesso sicuro a entity_data (o fallback su story.entities)
		var e_data = game.get("entity_data")
		if not e_data and game.get("story"):
			e_data = game.get("story").get("entities")
			
		if e_data:
			entity_def = e_data.get(target_entity_id, {})
			
		var weaknesses = entity_def.get("weaknesses", [])
		var immunities = entity_def.get("immunities", [])
		
		var multiplier_msg = ""
		
		if type in immunities:
			amount = 0
			multiplier_msg = game.tr("combat_damage_immunity") % type
		elif type in weaknesses:
			amount *= 2
			multiplier_msg = game.tr("combat_damage_weakness")
			
		# Applica danno al manager di combattimento
		# CRITICITÀ RISOLTA: Comunica al CombatManager di modificare l'energia del nemico
		if game.combat_manager:
			game.combat_manager.modify_current_entity_energy("life", -amount)
			
		var text = game.tr("spell_cast_damage") % [game.tr(spell.name), amount]
		return text + multiplier_msg
		
	return ""
