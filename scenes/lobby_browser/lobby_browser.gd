extends Control



# ─── Узлы ─────────────────────────────────────────────────────────────────────
@onready var filter_name: LineEdit = %FilterNameEdit
@onready var filter_max: SpinBox = %FilterMaxPlayers
@onready var btn_refresh: Button = %BtnRefresh
@onready var list_container: VBoxContainer = %LobbyList
@onready var label_status: Label = %LabelStatus
@onready var btn_back: Button = %BtnBack

# ─── Преднастроенная сцена одного элемента списка (создаём динамически) ───────
# Каждая строка списка — это отдельный Control с кнопкой "Войти"
const LOBBY_ENTRY_HEIGHT: int = 60


func _ready() -> void:
	# Настройка SpinBox: 0 = не фильтровать по количеству
	filter_max.min_value  = 0
	filter_max.max_value  = 6
	filter_max.step       = 1
	filter_max.value      = 0
	filter_max.prefix     = "Макс: "
	filter_max.suffix     = " (0=любое)"

	btn_refresh.pressed.connect(_on_btn_refresh_pressed)
	btn_back.pressed.connect(_on_btn_back_pressed)

	SteamManager.lobby_list_received.connect(_on_lobby_list_received)
	SteamManager.lobby_joined_ok.connect(_on_lobby_joined_ok)
	SteamManager.lobby_join_failed.connect(_on_lobby_join_failed)

	# Автозапрос при открытии браузера
	_request_list()


# ─── Запрос списка ────────────────────────────────────────────────────────────
func _on_btn_refresh_pressed() -> void:
	_request_list()


func _request_list() -> void:
	_set_status("Поиск лобби...")
	btn_refresh.disabled = true
	_clear_list()

	var name_filter: String = filter_name.text.strip_edges()
	var max_filter: int     = int(filter_max.value)

	SteamManager.request_lobby_list(name_filter, max_filter)


# ─── Получение и отображение списка ──────────────────────────────────────────
func _on_lobby_list_received(lobbies: Array) -> void:
	btn_refresh.disabled = false
	_clear_list()

	if lobbies.is_empty():
		_set_status("Лобби не найдены. Попробуйте обновить.")
		return

	_set_status("")

	for lobby_id: int in lobbies:
		_add_lobby_entry(lobby_id)


func _add_lobby_entry(lobby_id: int) -> void:
	# Читаем метаданные лобби, заданные при создании через setLobbyData
	var lobby_name: String  = Steam.getLobbyData(lobby_id, "name")
	var max_str: String     = Steam.getLobbyData(lobby_id, "max_players")
	var current_count: int  = Steam.getNumLobbyMembers(lobby_id)
	var max_count: int      = int(max_str) if max_str.is_valid_int() else 0

	# Пропускаем лобби без названия (невалидные)
	if lobby_name.is_empty():
		lobby_name = "Лобби #%d" % lobby_id

	# ── Строим строку списка динамически ──────────────────────────────────────
	var entry := HBoxContainer.new()
	entry.custom_minimum_size = Vector2(0, LOBBY_ENTRY_HEIGHT)

	var lbl_name := Label.new()
	lbl_name.text              = lobby_name
	lbl_name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lbl_name.clip_text         = true

	var lbl_players := Label.new()
	var players_text: String = "%d/%d" % [current_count, max_count]
	lbl_players.text          = players_text
	lbl_players.custom_minimum_size = Vector2(70, 0)

	var btn_join := Button.new()
	btn_join.text              = "Войти"
	btn_join.custom_minimum_size = Vector2(80, 0)
	# Блокируем если лобби заполнено
	btn_join.disabled          = (max_count > 0 and current_count >= max_count)
	# Передаём lobby_id через замыкание
	btn_join.pressed.connect(func() -> void: _join_lobby(lobby_id))

	entry.add_child(lbl_name)
	entry.add_child(lbl_players)
	entry.add_child(btn_join)
	list_container.add_child(entry)


# ─── Вход в лобби ────────────────────────────────────────────────────────────
func _join_lobby(lobby_id: int) -> void:
	_set_status("Подключение...")
	# Блокируем все кнопки "Войти" пока идёт подключение
	_set_all_join_buttons_disabled(true)
	SteamManager.join_lobby(lobby_id)


func _on_lobby_joined_ok(_lobby_id: int) -> void:
	get_tree().change_scene_to_file("uid://ii5saug6ok5e")#"res://scenes/lobby_room/lobby_room.tscn"



func _on_lobby_join_failed(reason: String) -> void:
	_set_status("Ошибка входа: %s" % reason)
	_set_all_join_buttons_disabled(false)


# ─── Утилиты ─────────────────────────────────────────────────────────────────
func _clear_list() -> void:
	for child in list_container.get_children():
		child.queue_free()


func _set_status(text: String) -> void:
	label_status.text    = text
	label_status.visible = not text.is_empty()


func _set_all_join_buttons_disabled(disabled: bool) -> void:
	for entry in list_container.get_children():
		var btn: Button = entry.get_node_or_null("Button")
		# Ищем кнопку по типу — она третий дочерний узел в HBoxContainer
		for child in entry.get_children():
			if child is Button:
				child.disabled = disabled


func _on_btn_back_pressed() -> void:
	SteamManager.lobby_list_received.disconnect(_on_lobby_list_received)
	SteamManager.lobby_joined_ok.disconnect(_on_lobby_joined_ok)
	SteamManager.lobby_join_failed.disconnect(_on_lobby_join_failed)
	#"res://scenes/main_menu/main_menu.tscn"
	get_tree().change_scene_to_file("uid://c6t7qd42fgtdw")
