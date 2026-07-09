class_name HiveAxylSession
extends RefCounted

# 리브랜드(Hive Axyl) 전 경로 유지 — 변경 시 기존 설치본의 저장 세션이 유실된다.
const PATH := "user://hive_ng_session.cfg"
const SECTION := "session"
const ACCESS_TOKEN := "access_token"
const REFRESH_TOKEN := "refresh_token"
const PLAYER_VALIDATION_TOKEN := "player_validation_token"
const PLAYER_VALIDATION_TOKEN_EXPIRES_AT := "player_validation_token_expires_at"

var persist := false
var access_token := ""
var refresh_token := ""
var player_validation_token := ""
var player_validation_token_expires_at := ""


func configure(should_persist: bool) -> void:
    persist = should_persist
    if persist:
        load_session()


func has_access_token() -> bool:
    return not access_token.is_empty()


func has_refresh_token() -> bool:
    return not refresh_token.is_empty()


func current_player_validation_token() -> String:
    if player_validation_token.is_empty() or player_validation_token_expires_at.is_empty():
        return ""
    var expires_at := _timestamp_unix_seconds(player_validation_token_expires_at)
    if expires_at <= Time.get_unix_time_from_system():
        player_validation_token = ""
        player_validation_token_expires_at = ""
        return ""
    return player_validation_token


func save_tokens(token_pair: Dictionary) -> void:
    access_token = str(token_pair.get("accessToken", ""))
    refresh_token = str(token_pair.get("refreshToken", ""))
    player_validation_token = str(token_pair.get("playerValidationToken", ""))
    player_validation_token_expires_at = str(token_pair.get("playerValidationTokenExpiresAt", ""))
    if not persist:
        return

    var config := ConfigFile.new()
    config.set_value(SECTION, ACCESS_TOKEN, access_token)
    config.set_value(SECTION, REFRESH_TOKEN, refresh_token)
    config.set_value(SECTION, PLAYER_VALIDATION_TOKEN, player_validation_token)
    config.set_value(SECTION, PLAYER_VALIDATION_TOKEN_EXPIRES_AT, player_validation_token_expires_at)
    config.save(PATH)


func clear() -> void:
    access_token = ""
    refresh_token = ""
    player_validation_token = ""
    player_validation_token_expires_at = ""
    if not persist:
        return

    var config := ConfigFile.new()
    config.save(PATH)


func load_session() -> void:
    var config := ConfigFile.new()
    var error := config.load(PATH)
    if error != OK:
        return

    access_token = str(config.get_value(SECTION, ACCESS_TOKEN, ""))
    refresh_token = str(config.get_value(SECTION, REFRESH_TOKEN, ""))
    player_validation_token = str(config.get_value(SECTION, PLAYER_VALIDATION_TOKEN, ""))
    player_validation_token_expires_at = str(config.get_value(SECTION, PLAYER_VALIDATION_TOKEN_EXPIRES_AT, ""))


func _timestamp_unix_seconds(value: String) -> float:
    var normalized := value.strip_edges()
    if normalized.ends_with("Z"):
        normalized = normalized.substr(0, normalized.length() - 1)
    var dot_index := normalized.find(".")
    if dot_index >= 0:
        normalized = normalized.substr(0, dot_index)
    return Time.get_unix_time_from_datetime_string(normalized)
