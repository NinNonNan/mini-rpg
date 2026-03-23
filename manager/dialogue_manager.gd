# =========================================================
# DIALOGUE MANAGER
# =========================================================
# Gestisce tutta la logica dei dialoghi con le entità del gioco.
#
# Questo manager NON manipola direttamente la UI.
# Invece comunica con Game e con l'interfaccia tramite segnali.
#
# Vantaggi di questo approccio:
# - separazione tra logica e interfaccia (decoupling)
# - codice più modulare
# - possibilità di riutilizzare il sistema di dialogo
# - più facile testare e mantenere
#
# Il Game ascolta i segnali e aggiorna:
# - testo narrativo
# - pulsanti delle scelte
# - statistiche del giocatore

class_name DialogueManager
extends Node

# Riferimento al gioco principale per coerenza architetturale.
# Viene iniettato da Game.gd in _ready().
var game: Game


# =========================================================
# SEGNALI
# =========================================================
# I segnali permettono al DialogueManager di comunicare
# con altri nodi senza dipendere direttamente da essi.

# Richiede alla UI (tramite Game) di mostrare un testo narrativo.
signal text_requested(text_content)

# Richiede alla UI di aggiornare i pulsanti con un array di scelte.
signal choices_requested(choices_array)

# Emesso quando il dialogo termina con successo (mood >= 30).
# Passa il nome della scena successiva a Game.gd.
signal dialogue_finished(victory_scene_name)

# Emesso quando il dialogo fallisce (mood <= -15 o il giocatore attacca).
# Di solito porta a un combattimento.
signal dialogue_failed()

# Emesso quando cambia lo stato interno (es. l'umore)
# e la UI deve aggiornare le statistiche mostrate.
signal stats_updated()


# =========================================================
# STATO DEL DIALOGO
# =========================================================

# Flag che indica se un dialogo è attualmente in corso.
var is_active = false

# Umore attuale dell'entità durante il dialogo
# Valori positivi = più favorevole.
# Valori negativi = più ostile.
var current_mood = 0


# =========================================================
# DATI DELL'ENTITÀ CORRENTE
# =========================================================

# Nome dell'entità con cui stiamo parlando (es. "Drago").
var _entity_name = ""

# Pronome dell'entità (es. "il", "la") per costruire frasi corrette.
var _entity_pronoun = ""

# Scena da caricare se il dialogo ha successo (es. "dragon_victory").
var _victory_scene = ""


# =========================================================
# INIZIO DEL DIALOGO
# =========================================================
# Viene chiamato dal Game quando il giocatore sceglie
# "Dialoga" da una scena.

func start_dialogue(entity_name: String, pronoun: String, starting_mood: int, victory_scene: String):

	is_active = true

	_entity_name = entity_name
	_entity_pronoun = pronoun
	current_mood = starting_mood
	_victory_scene = victory_scene

	# Emette un segnale per mostrare il messaggio iniziale.
	text_requested.emit(
		tr("dialogue_start") % [_entity_pronoun, _entity_name]
	)

	# Notifica la UI di aggiornare le statistiche (es. per mostrare l'umore).
	stats_updated.emit()

	# Piccola pausa narrativa per dare tempo al giocatore di leggere.
	await get_tree().create_timer(1.0).timeout

	# Mostra le scelte di dialogo
	_present_choices()


# =========================================================
# RESET DEL DIALOGO
# =========================================================
# Usato da Game.gd quando il dialogo termina o si cambia scena.

func reset():

	is_active = false
	current_mood = 0


# =========================================================
# GESTIONE SCELTA DEL GIOCATORE
# =========================================================
# `action_key` (es. "compliment", "threaten") identifica la scelta.
# Questa funzione viene chiamata da Game.gd quando un pulsante di dialogo viene premuto.

func handle_choice(action_key: String):

	# Se il giocatore decide di attaccare, il dialogo fallisce immediatamente.
	if action_key == "attack":
		_fail_dialogue()
		return

	var mood_change = 0
	var response_text = ""

	# Determina l'effetto della scelta sull'umore dell'entità.
	match action_key:

		"compliment":
			mood_change = 15
			response_text = tr("dialogue_res_good")

		"threaten":
			mood_change = -20
			response_text = tr("dialogue_res_bad")

	# Aggiorna l'umore dell'entità
	# `clamp` evita che l'umore superi i limiti definiti (-50, 50).
	current_mood = clamp(current_mood + mood_change, -50, 50)

	# Richiede alla UI di mostrare il risultato dell'azione.
	text_requested.emit(response_text)

	# Notifica la UI di aggiornare le statistiche (es. il valore dell'umore).
	stats_updated.emit()

	# Pausa narrativa per dare tempo di leggere.
	await get_tree().create_timer(1.5).timeout

	# Controlla se il dialogo è finito
	_check_status()


# =========================================================
# PRESENTAZIONE DELLE SCELTE
# =========================================================
# Prepara e richiede alla UI di mostrare le opzioni disponibili al giocatore.

func _present_choices():

	text_requested.emit(tr("dialogue_mood_status") % current_mood)

	# Ogni dizionario nell'array rappresenta un pulsante che Game.gd dovrà creare.
	var choices = [
		{"text": "dialogue_opt_compliment", "action": "compliment"},
		{"text": "dialogue_opt_threaten", "action": "threaten"},
		{"text": "dialogue_opt_attack", "action": "attack"}
	]

	choices_requested.emit(choices)


# =========================================================
# CONTROLLO STATO DEL DIALOGO
# =========================================================
# Funzione chiamata dopo ogni azione del giocatore per determinare se il dialogo:
# - continua (mostrando nuove scelte)
# - ha successo (raggiunto l'obiettivo di umore)
# - fallisce (umore troppo basso)

func _check_status():

	# CONDIZIONE DI SUCCESSO: umore >= 30
	if current_mood >= 30:

		is_active = false

		text_requested.emit(
			tr("dialogue_success_msg")
			% [_entity_pronoun, _entity_name]
		)

		await get_tree().create_timer(2.0).timeout

		dialogue_finished.emit(_victory_scene)

	# CONDIZIONE DI FALLIMENTO: umore <= -15
	elif current_mood <= -15:

		_fail_dialogue()

	# Il dialogo continua: ripresenta le scelte.
	else:

		_present_choices()


# =========================================================
# FALLIMENTO DEL DIALOGO
# =========================================================
# Funzione helper che gestisce la sequenza di fallimento.

func _fail_dialogue():

	is_active = false

	text_requested.emit(
		tr("dialogue_fail_msg")
		% [_entity_pronoun, _entity_name]
	)

	await get_tree().create_timer(2.0).timeout

	dialogue_failed.emit()
