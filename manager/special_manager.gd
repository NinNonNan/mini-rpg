# =========================================================
# SPECIAL MANAGER
# =========================================================
# Gestisce le abilità speciali (Magie) del giocatore.
#
# Funzionalità principali:
# - Recupero dati delle magie da definitions.json (via story_data).
# - Verifica del costo in Mana (MP).
# - Esecuzione dell'effetto (Danno elementale o Cura).
# - Calcolo delle interazioni elementali (Debolezze/Affinità).
#
# A differenza del RuneManager (che è un minigioco), questo manager
# gestisce le abilità attivabili direttamente da menu.

class_name SpecialManager
extends Node

# Riferimento al gioco principale.
# Iniettato da Game.gd in _ready().
var game: Game

# Proprietà calcolata per ottenere il dizionario delle magie.
# Recupera i dati da game.story_data["spells"].
var spells: Dictionary:
	get:
		if game:
			# Tenta di recuperare i dati unificati (story_data contiene anche definitions.json)
			var data = game.get("story_data")
			# Fallback per compatibilità con vecchie versioni
			if not data:
				data = game.get("story")
			
			if data:
				return data.get("spells", {})
		return {}

# =========================================================
# HELPER
# =========================================================

# Restituisce il dizionario dati di una specifica magia.
func get_spell_data(spell_id: String) -> Dictionary:
	return spells.get(spell_id, {})

# Verifica se il giocatore ha abbastanza mana per lanciare la magia.
# Chiamato dalla UI prima di abilitare il pulsante o eseguire l'azione.
func has_enough_mana(spell_id: String) -> bool:
	var spell = get_spell_data(spell_id)
	if not spell: return false
	
	# Recupera il valore attuale di MP tramite l'interfaccia di Game
	var current_magic = game.get_player_energy_value("magic")
	return current_magic >= spell.cost


# =========================================================
# ESECUZIONE MAGIA
# =========================================================

# Esegue l'abilità, consuma risorse e applica gli effetti.
# Restituisce una stringa descrittiva (già tradotta) per il log di gioco.
func use_spell(spell_id: String, target_entity_id: String) -> String:
	var spell = get_spell_data(spell_id)
	if not spell: return ""
	
	# 1. CONSUMO MANA
	# Modifica l'energia "magic" sottraendo il costo.
	game.modify_player_energy("magic", -spell.cost)
	
	# 2. LOGICA DI CURA DIRETTA (es. Pozione/Incantesimo "Heal")
	# Se la magia ha la proprietà "heal" definita nel JSON.
	if spell.has("heal"):
		var amount = spell.heal
		# Cura il giocatore
		game.modify_player_energy("life", amount)
		return game.tr("spell_cast_heal") % [game.tr(spell.name), amount]
	
	# 3. LOGICA DI DANNO / EFFETTO ELEMENTALE
	elif spell.has("damage"):
		var amount = spell.damage
		var type = spell.type
		
		# Recupera i dati del bersaglio per calcolare resistenze
		var entity_def = {}
		
		if target_entity_id == "player":
			entity_def = game.story_data.get("player", {})
		else:
			# Recupera i dati del nemico da entity_data
			var e_data = game.entity_data
			if e_data:
				entity_def = e_data.get(target_entity_id, {})
			
		var weaknesses = entity_def.get("weaknesses", [])
		var immunities = entity_def.get("immunities", [])
		var affinities = entity_def.get("affinity", [])
		
		var multiplier_msg = ""
		
		# --- CALCOLO MOLTIPLICATORI ---
		
		# A. AFFINITÀ -> Il danno diventa CURA
		if type in affinities:
			amount *= -1 # Inverte il danno in cura
			multiplier_msg = game.tr("combat_damage_affinity") % type
			
		# B. IMMUNITÀ -> Il danno diventa 0
		elif type in immunities:
			amount = 0
			multiplier_msg = game.tr("combat_damage_immunity") % type
			
		# C. DEBOLEZZA -> Il danno raddoppia
		elif type in weaknesses:
			amount *= 2
			multiplier_msg = game.tr("combat_damage_weakness")
			
		# --- APPLICAZIONE EFFETTO ---
		
		if target_entity_id == "player":
			# Se il bersaglio è il giocatore, sottraiamo il danno (se negativo diventa cura)
			game.modify_player_energy("life", -amount)
		elif game.combat_manager:
			# Se il bersaglio è un nemico, deleghiamo al CombatManager
			game.combat_manager.modify_current_entity_energy("life", -amount)
			
		# --- GENERAZIONE MESSAGGIO ---
		
		var text = ""
		# Caso speciale: Cura su se stessi tramite affinità
		if target_entity_id == "player" and amount < 0:
			text = game.tr("spell_cast_heal") % [game.tr(spell.name), abs(amount)]
		else:
			text = game.tr("spell_cast_damage") % [game.tr(spell.name), abs(amount)]
			
		return text + multiplier_msg
		
	return ""
