# =========================================================
# GROWTH MANAGER
# =========================================================
# Gestisce la crescita e il potenziamento del personaggio.
#
# Funzionalità principali:
# - Calcola l'energia (XP) ottenuta dai nemici sconfitti.
# - Gestisce un pool di "Energia disponibile" da spendere.
# - Permette di aumentare permanentemente le statistiche massime (HP, MP, ecc.).
#
# Questo manager viene attivato da Game.gd dopo una vittoria in combattimento
# (vedi `_check_victory` in CombatManager).

class_name GrowthManager
extends Node

# Riferimento al gioco principale.
# Iniettato da Game.gd in _ready().
var game

# Energia accumulata pronta per essere distribuita
var available_energy: int = 0

# Calcola quanta energia rilascia un nemico sconfitto.
# La ricompensa è basata sulla somma delle statistiche del nemico (es. Vita + Magia).
func calculate_reward(entity_id: String) -> int:
	var entity = game.entity_data.get(entity_id)
	
	if entity == null:
		push_warning(tr("warn_growth_entity_not_found") % entity_id)
		return 0
	
	# Calcola il valore totale delle statistiche del nemico
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
func upgrade_stat(stat_type: String):
	if available_energy <= 0:
		return
		
	available_energy -= 1
	
	# 1. Aumenta il valore MASSIMO della statistica
	var current_max = game.player_max_energy.get(stat_type, 0)
	game.player_max_energy[stat_type] = current_max + 1
	
	# 2. Aumenta anche il valore ATTUALE (cura/ripristino parziale)
	# Usa modify_player_energy per gestire clamp e logiche specifiche
	game.modify_player_energy(stat_type, 1)
			
	game.update_stats() # Aggiorna le statistiche del giocatore (HP/MP)

	# Se l'energia è esaurita, procedi. Altrimenti, aggiorna il menu.
	if available_energy <= 0:
		game.show_scene(game.current_victory_scene)
	else:
		# Aggiorna l'interfaccia per mostrare la nuova energia disponibile
		game._update_growth_menu()
