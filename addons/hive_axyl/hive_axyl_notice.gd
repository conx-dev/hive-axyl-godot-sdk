class_name HiveAxylNotice
extends RefCounted

const Util := preload("res://addons/hive_axyl/hive_axyl_util.gd")

var hive


func _init(hive_client) -> void:
    hive = hive_client


func list_active_notices() -> Array:
    var response = await hive._rpc(
        "notice",
        "NoticeService",
        "ListActiveNotices",
        {},
        true
    )
    if typeof(response) != TYPE_DICTIONARY:
        return []

    var notices: Array = []
    for notice in response.get("notices", []):
        notices.append(Util.map_notice(notice, hive.language))
    return notices
