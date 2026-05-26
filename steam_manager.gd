extends Node

# ─── Константы ────────────────────────────────────────────────────────────────
const APP_ID: int = 480          # Тестовый SpaceWar ID; замени на свой

# ─── Переменные состояния ──────────────────────────────────────────────────────
var steam_id: int = 0
var steam_username: String = ""
var is_online: bool = false

# ─── Данные лобби ─────────────────────────────────────────────────────────────
var lobby_id: int = 0
var lobby_members: Array[Dictionary] = []
var lobby_members_max: int = 4
var _pending_lobby_name: String = ""
# ─── Сигналы для UI ───────────────────────────────────────────────────────────
signal lobby_created_ok(lobby_id: int)
signal lobby_joined_ok(lobby_id: int)
signal lobby_join_failed(reason: String)
signal lobby_list_received(lobbies: Array)
signal lobby_members_updated()
signal chat_message_received(sender_name: String, message: String)
signal player_ready_changed(steam_id: int, is_ready: bool)
signal lobby_left()


func _init() -> void:
	OS.set_environment("SteamAppId", str(APP_ID))
	OS.set_environment("SteamGameId", str(APP_ID))

func _ready() -> void:
	print("=== Steam DLL найдена: ", FileAccess.file_exists("res://addons/godotsteam/win64/steam_api64.dll"))
	print("=== steam_appid.txt: ", FileAccess.file_exists("steam_appid.txt"))
	print("=== Steam.is_steam_running(): ", Steam.isSteamRunning())
	var result: Dictionary = Steam.steamInitEx(APP_ID)  # без APP_ID аргументом — GDExtension принимает max 2 аргумента
	print("Steam init: ", result)
	if result["status"] != Steam.STEAM_API_INIT_RESULT_OK:
		push_error("Steam не инициализирован: %s" % result["verbal"])
		return

	is_online = true
	steam_id = Steam.getSteamID()
	steam_username = Steam.getPersonaName()
	print("Steam OK — %s (%d)" % [steam_username, steam_id])

	# Подключаем сигналы Steam
	Steam.lobby_created.connect(_on_lobby_created)
	Steam.lobby_joined.connect(_on_lobby_joined)
	Steam.lobby_match_list.connect(_on_lobby_match_list)
	Steam.lobby_chat_update.connect(_on_lobby_chat_update)
	Steam.lobby_message.connect(_on_lobby_message)
	Steam.lobby_data_update.connect(_on_lobby_data_update)
	Steam.persona_state_change.connect(_on_persona_change)
	# Присоединение через оверлей Steam (приглашение / Join Game)
	Steam.join_requested.connect(_on_join_requested)

	# Обработка аргументов командной строки (запуск по приглашению)
	_check_command_line()
	
func _process(_delta: float) -> void:
	# Обязательный вызов каждый кадр для обработки колбэков Steamworks
	Steam.run_callbacks()
	
# ─── Проверка аргументов запуска (Steam overlay invite) ───────────────────────
func _check_command_line() -> void:
	var args: Array = OS.get_cmdline_args()
	if args.size() >= 2 and args[0] == "+connect_lobby":
		var invite_lobby_id: int = int(args[1])
		if invite_lobby_id > 0:
			join_lobby(invite_lobby_id)

# ─── Создание лобби ───────────────────────────────────────────────────────────
func create_lobby(
	lobby_name: String,
	max_players: int,
	privacy: int  # Steam.LOBBY_TYPE_PUBLIC или LOBBY_TYPE_FRIENDS_ONLY
) -> void:
	if lobby_id != 0:
		push_warning("Уже находишься в лобби!")
		return

	# Ограничиваем от 2 до 6 участников
	lobby_members_max = clamp(max_players, 2, 6)
	Steam.createLobby(privacy, lobby_members_max)

	# Временно сохраняем название, чтобы установить его в колбэке
	_pending_lobby_name = lobby_name




func _on_lobby_created(result: int, new_lobby_id: int) -> void:
	if result != 1:
		push_error("Ошибка создания лобби: %d" % result)
		return

	lobby_id = new_lobby_id

	# Метаданные лобби — доступны всем в списке
	Steam.setLobbyData(lobby_id, "name", _pending_lobby_name)
	Steam.setLobbyData(lobby_id, "max_players", str(lobby_members_max))
	Steam.setLobbyData(lobby_id, "version", "1.0")  # фильтр по версии игры
	Steam.setLobbyJoinable(lobby_id, true)
	Steam.allowP2PPacketRelay(true)  # fallback через серверы Steam при NAT

	emit_signal("lobby_created_ok", lobby_id)
	get_lobby_members()
	
# ─── Запрос списка лобби с фильтрами ──────────────────────────────────────────
func request_lobby_list(filter_name: String = "", filter_max_players: int = 0) -> void:
	# Дистанция поиска — по всему миру
	Steam.addRequestLobbyListDistanceFilter(Steam.LOBBY_DISTANCE_FILTER_WORLDWIDE)

	# Фильтр по названию (частичное совпадение в метаданных)
	if filter_name.length() > 0:
		Steam.addRequestLobbyListStringFilter(
			"name",
			filter_name,
			Steam.LOBBY_COMPARISON_EQUAL_TO_OR_LESS_THAN
		)

	# Фильтр по максимальному числу игроков
	if filter_max_players > 0:
		Steam.addRequestLobbyListNumericalFilter(
			"max_players",
			filter_max_players,
			Steam.LOBBY_COMPARISON_EQUAL
		)

	# Только совместимая версия игры
	Steam.addRequestLobbyListStringFilter(
		"version", "1.0", Steam.LOBBY_COMPARISON_EQUAL
	)

	Steam.requestLobbyList()


func _on_lobby_match_list(lobbies: Array) -> void:
	emit_signal("lobby_list_received", lobbies)
	
# ─── Присоединение к лобби ────────────────────────────────────────────────────
func join_lobby(target_lobby_id: int) -> void:
	lobby_members.clear()
	Steam.joinLobby(target_lobby_id)


func _on_lobby_joined(
	joined_lobby_id: int,
	_permissions: int,
	_locked: bool,
	response: int
) -> void:
	if response == Steam.CHAT_ROOM_ENTER_RESPONSE_SUCCESS:
		lobby_id = joined_lobby_id
		Steam.allowP2PPacketRelay(true)
		get_lobby_members()
		emit_signal("lobby_joined_ok", lobby_id)
	else:
		# Расшифровываем причину отказа
		var reason: String = _get_join_fail_reason(response)
		emit_signal("lobby_join_failed", reason)


func _get_join_fail_reason(response: int) -> String:
	match response:
		Steam.CHAT_ROOM_ENTER_RESPONSE_FULL:           return "Лобби заполнено"
		Steam.CHAT_ROOM_ENTER_RESPONSE_DOESNT_EXIST:   return "Лобби не существует"
		Steam.CHAT_ROOM_ENTER_RESPONSE_NOT_ALLOWED:    return "Нет доступа"
		Steam.CHAT_ROOM_ENTER_RESPONSE_BANNED:         return "Вы забанены"
		Steam.CHAT_ROOM_ENTER_RESPONSE_LIMITED:        return "Ограниченный аккаунт"
		_:                                              return "Неизвестная ошибка (%d)" % response


# Вход через Steam overlay (Join Game из профиля друга)
func _on_join_requested(requested_lobby_id: int, _friend_id: int) -> void:
	join_lobby(requested_lobby_id)
	
	
	
# ─── Получение списка участников ──────────────────────────────────────────────
func get_lobby_members() -> void:
	lobby_members.clear()
	var count: int = Steam.getNumLobbyMembers(lobby_id)

	for i in range(count):
		var member_id: int = Steam.getLobbyMemberByIndex(lobby_id, i)
		var member_name: String = Steam.getFriendPersonaName(member_id)
		# Читаем готовность из метаданных участника
		var ready_str: String = Steam.getLobbyMemberData(lobby_id, member_id, "ready")
		lobby_members.append({
			"steam_id":   member_id,
			"steam_name": member_name,
			"is_ready":   ready_str == "true",
			"is_owner":   member_id == Steam.getLobbyOwner(lobby_id),
		})

	emit_signal("lobby_members_updated")


# ─── Изменение состава лобби (вход/выход) ─────────────────────────────────────
func _on_lobby_chat_update(
	_lid: int,
	changed_id: int,
	_making_change_id: int,
	state: int
) -> void:
	var name: String = Steam.getFriendPersonaName(changed_id)
	match state:
		Steam.CHAT_MEMBER_STATE_CHANGE_ENTERED: print("%s вошёл в лобби" % name)
		Steam.CHAT_MEMBER_STATE_CHANGE_LEFT:    print("%s покинул лобби" % name)
		Steam.CHAT_MEMBER_STATE_CHANGE_KICKED:  print("%s кикнут" % name)
	get_lobby_members()


# Обновление имён/аватаров после получения данных от Steam
func _on_persona_change(changed_id: int, _flag: int) -> void:
	if lobby_id > 0:
		get_lobby_members()


# Изменение данных лобби (например, хост поменял настройки)
func _on_lobby_data_update(_lid: int, _member_id: int, _key_changed: int) -> void:
	get_lobby_members()


# ─── Чат лобби ────────────────────────────────────────────────────────────────
func send_chat_message(text: String) -> void:
	if text.is_empty() or lobby_id == 0:
		return
	var sent: bool = Steam.sendLobbyChatMsg(lobby_id, text)
	if not sent:
		push_error("Не удалось отправить сообщение в чат")


func _on_lobby_message(
	_lid: int,
	user_id: int,
	message: String,
	_type: int
) -> void:
	var sender: String = Steam.getFriendPersonaName(user_id)
	emit_signal("chat_message_received", sender, message)


# ─── Готовность игрока ────────────────────────────────────────────────────────
# Используем LobbyMemberData — персональные метаданные участника,
# видимые всем в лобби. Это проще и надёжнее, чем P2P-пакеты для ready-check.
func set_player_ready(is_ready: bool) -> void:
	if lobby_id == 0:
		return
	Steam.setLobbyMemberData(lobby_id, "ready", "true" if is_ready else "false")
	emit_signal("player_ready_changed", steam_id, is_ready)


func all_players_ready() -> bool:
	if lobby_members.size() < 2:
		return false
	for member in lobby_members:
		if not member["is_ready"]:
			return false
	return true


# ─── Выход из лобби ───────────────────────────────────────────────────────────
func leave_lobby() -> void:
	if lobby_id == 0:
		return
	Steam.leaveLobby(lobby_id)
	for member in lobby_members:
		if member["steam_id"] != steam_id:
			Steam.closeP2PSessionWithUser(member["steam_id"])
	lobby_id = 0
	lobby_members.clear()
	emit_signal("lobby_left")
