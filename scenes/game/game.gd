extends Node

# Сцена одного игрока — создай player.tscn с CharacterBody2D
const PLAYER_SCENE: PackedScene = preload("uid://ce3utqck1v6we") # player.tscn

@onready var players_node: Node = $Players  # узел-контейнер для игроков


func _ready() -> void:
	# Только после того как multiplayer.multiplayer_peer установлен
	if not multiplayer.has_multiplayer_peer():
		push_error("MultiplayerPeer не установлен!")
		return

	# Хост спавнит всех игроков
	if multiplayer.is_server():
		_spawn_all_players()


func _spawn_all_players() -> void:
	# Спавним по одному игроку для каждого участника лобби
	for member: Dictionary in SteamManager.lobby_members:
		var peer_id: int = _steam_id_to_peer_id(member["steam_id"])
		_spawn_player.rpc(peer_id, member["steam_name"])


# @rpc — вызывается на всех клиентах с хоста
# any_peer — любой может вызвать (достаточно authority для спавна)
@rpc("authority", "call_local", "reliable")
func _spawn_player(peer_id: int, player_name: String) -> void:
	var player := PLAYER_SCENE.instantiate()
	player.name         = str(peer_id)  # имя узла = peer_id для маршрутизации RPC
	player.set_multiplayer_authority(peer_id)  # этот игрок управляется данным peer
	players_node.add_child(player)
	# Передаём имя если в player.gd есть такая переменная
	if player.has_method("init"):
		player.init(player_name)
	print("Заспавнен игрок: %s (peer %d)" % [player_name, peer_id])


# Конвертация Steam ID → Peer ID через список участников SteamMultiplayerPeer
func _steam_id_to_peer_id(sid: int) -> int:
	# Хост всегда peer_id = 1 в Godot MultiplayerAPI
	if sid == Steam.getLobbyOwner(SteamManager.lobby_id):
		return 1
	# Для остальных — ищем через peer list
	for pid in multiplayer.get_peers():
		# SteamMultiplayerPeer хранит steam_id в имени peer
		if multiplayer.multiplayer_peer is SteamMultiplayerPeer:
			var mp_peer := multiplayer.multiplayer_peer as SteamMultiplayerPeer
			if mp_peer.get_steam64_from_peer_id(pid) == sid:
				return pid
	return 1  # fallback
