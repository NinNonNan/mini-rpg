class_name GrowthManager
extends Node

var game

# Energia accumulata pronta per essere distribuita
var available_energy: int = 0

# Calcola quanta energia rilascia un nemico (Vita + Magia del nemico)
func calculate_reward(entity_id: String) -> int:
	var entity = game.entity_data.get(entity_id)
	
	if entity == null:
		push_warning(tr("warn_growth_entity_not_found") % entity_id)
		return 0
		
	var reward_base = 0.0 # Usiamo float per i calcoli intermedi
	
	if entity.has("energy"):
		for stat in entity["energy"]:
			# Sommiamo i valori positivi (es. vita), convertendo a float per sicurezza
			var val = float(stat.get("value", 0.0))
			if val > 0:
				reward_base += val
	elif entity.has("health"): # Supporto per la vecchia struttura dati
		reward_base += float(entity.get("health", 0.0))
	
	if reward_base <= 0:
		push_warning(tr("warn_growth_reward_zero") % entity_id)

	# Il reward è una frazione della forza totale (es. 50%), arrotondato per eccesso
	# Diciamo invece che l'energia rilasciata è un terzo di quella forza.
	var final_reward = ceili(reward_base * 0.33)
	return int(final_reward)

# Aggiunge energia al pool del giocatore
func add_energy(amount: int):
	available_energy += amount

# Tenta di spendere energia per potenziare una statistica
# Restituisce true se l'operazione ha successo
func upgrade_stat(stat_type: String) -> bool:
	if available_energy <= 0:
		return false
		
	available_energy -= 1
	
	match stat_type:
		"life":
			game.max_health += 1
			game.health += 1 # Cura anche di 1 quando potenzi
		"magic":
			game.max_mana += 1
			game.mana += 1
			
	game.update_stats()
	return true
