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

# Richiede alla UI di mostrare un testo
signal text_requested(text_content)

# Richiede alla UI di aggiornare i pulsanti con nuove scelte
signal choices_requested(choices_array)

# Segnale emesso quando il dialogo termina con successo
signal dialogue_finished(victory_scene_name)

# Segnale emesso quando il dialogo fallisce
# (di solito porta a un combattimento)
signal dialogue_failed()

# Segnale emesso quando cambia lo stato interno
# (es. l'umore) e la UI deve aggiornare le statistiche
signal stats_updated()


# =========================================================
# STATO DEL DIALOGO
# =========================================================

# Indica se un dialogo è attualmente attivo
var is_active = false

# Umore attuale dell'entità durante il dialogo
# Valori positivi = più favorevole
# Valori negativi = più ostile
var current_mood = 0


# =========================================================
# DATI DELL'ENTITÀ CORRENTE
# =========================================================

# Nome dell'entità con cui stiamo parlando
var _entity_name = ""

# Pronome dell'entità (es. "lui", "lei", "esso")
var _entity_pronoun = ""

# Scena da caricare se il dialogo ha successo
var _victory_scene = ""


# =========================================================
# INIZIO DEL DIALOGO
# =========================================================
# Viene chiamato dal Game quando il giocatore sceglie
# di parlare con un'entità invece di attaccare.

func start_dialogue(entity_name: String, pronoun: String, starting_mood: int, victory_scene: String):

	is_active = true

	_entity_name = entity_name
	_entity_pronoun = pronoun
	current_mood = starting_mood
	_victory_scene = victory_scene

	# Mostra il messaggio iniziale
	text_requested.emit(
		"Inizi a parlare con %s %s." % [_entity_pronoun, _entity_name]
	)

	# Aggiorna le statistiche (mostra umore se conosciuto)
	stats_updated.emit()

	# Piccola pausa narrativa
	await get_tree().create_timer(1.0).timeout

	# Mostra le scelte di dialogo
	_present_choices()


# =========================================================
# RESET DEL DIALOGO
# =========================================================
# Usato quando il dialogo termina o quando si cambia scena.

func reset():

	is_active = false
	current_mood = 0


# =========================================================
# GESTIONE SCELTA DEL GIOCATORE
# =========================================================
# action_key identifica il tipo di risposta scelta dal giocatore.

func handle_choice(action_key: String):

	# Se il giocatore decide di attaccare
	if action_key == "attack":
		_fail_dialogue()
		return

	var mood_change = 0
	var response_text = ""

	# Determina l'effetto della scelta sull'umore
	match action_key:

		"compliment":
			mood_change = 15
			response_text = "L'entità sembra apprezzare il gesto."

		"threaten":
			mood_change = -20
			response_text = "L'entità non sembra gradire il tuo tono."

	# Aggiorna l'umore dell'entità
	# clamp evita che superi i limiti
	current_mood = clamp(current_mood + mood_change, -50, 50)

	# Aggiorna il testo della UI
	text_requested.emit(response_text)

	# Aggiorna le statistiche visibili
	stats_updated.emit()

	# Pausa narrativa
	await get_tree().create_timer(1.5).timeout

	# Controlla se il dialogo è finito
	_check_status()


# =========================================================
# PRESENTAZIONE DELLE SCELTE
# =========================================================
# Mostra le opzioni disponibili al giocatore.

func _present_choices():

	text_requested.emit("Umore attuale: %d. Cosa dici?" % current_mood)

	# Ogni elemento rappresenta un pulsante
	var choices = [
		{"text": "Fai un complimento", "action": "compliment"},
		{"text": "Minaccia", "action": "threaten"},
		{"text": "Basta parlare, attacca!", "action": "attack"}
	]

	choices_requested.emit(choices)


# =========================================================
# CONTROLLO STATO DEL DIALOGO
# =========================================================
# Determina se il dialogo:
# - continua
# - ha successo
# - fallisce

func _check_status():

	# Successo del dialogo
	if current_mood >= 30:

		is_active = false

		text_requested.emit(
			"Sei riuscito a convincere %s %s! Ti lascia passare in pace."
			% [_entity_pronoun, _entity_name]
		)

		await get_tree().create_timer(2.0).timeout

		dialogue_finished.emit(_victory_scene)

	# Fallimento del dialogo
	elif current_mood <= -15:

		_fail_dialogue()

	# Dialogo ancora in corso
	else:

		_present_choices()


# =========================================================
# FALLIMENTO DEL DIALOGO
# =========================================================
# Porta generalmente a un combattimento.

func _fail_dialogue():

	is_active = false

	text_requested.emit(
		"Hai fatto infuriare %s %s! Si prepara a combattere."
		% [_entity_pronoun, _entity_name]
	)

	await get_tree().create_timer(2.0).timeout

	dialogue_failed.emit()