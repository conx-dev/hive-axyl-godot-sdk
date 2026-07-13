class_name HiveAxyl
extends Node

const AuthApi := preload("res://addons/hive_axyl/hive_axyl_auth.gd")
const NoticeApi := preload("res://addons/hive_axyl/hive_axyl_notice.gd")
const MailboxApi := preload("res://addons/hive_axyl/hive_axyl_mailbox.gd")
const SessionStore := preload("res://addons/hive_axyl/hive_axyl_session.gd")
const Util := preload("res://addons/hive_axyl/hive_axyl_util.gd")
const DEFAULT_GATEWAY_URL := "https://gw-test-gcl.c2xstation.net:8081"

signal error_occurred(error: Dictionary)
signal session_changed(player: Dictionary)

var auth
var notice
var mailbox
var last_error := {}
var debug := false
var gateway_url := ""
var project_id := ""
var api_key := ""
var client_version := ""
var language := ""
var google_client_id := ""
var google_client_secret := ""

var _session := SessionStore.new()
var _endpoints := {}
var _ready := false


static func create_hive_axyl(config: Dictionary) -> HiveAxyl:
    var client := HiveAxyl.new()
    client.configure(config)
    return client


func _init() -> void:
    var client_platform := Util.detect_client_platform()
    auth = AuthApi.new(self, client_platform)
    notice = NoticeApi.new(self)
    mailbox = MailboxApi.new(self)


func configure(config: Dictionary) -> bool:
    gateway_url = Util.trim_trailing_slash(Util.normalize_config_value(config, "gateway_url", "gatewayUrl"))
    project_id = Util.normalize_config_value(config, "project_id", "projectId")
    api_key = Util.normalize_config_value(config, "api_key", "apiKey")
    client_version = Util.normalize_config_value(config, "client_version", "clientVersion")
    google_client_id = Util.normalize_config_value(config, "google_client_id", "googleClientId")
    google_client_secret = Util.normalize_config_value(config, "google_client_secret", "googleClientSecret")
    language = str(config.get("language", ""))
    if language.is_empty():
        language = OS.get_locale_language()
    debug = bool(config.get("debug", false))

    var persist_session := bool(config.get("persist_session", config.get("persistSession", true)))
    _session.configure(persist_session)

    if gateway_url.is_empty():
        gateway_url = DEFAULT_GATEWAY_URL
    if project_id.is_empty():
        _set_error(Util.ERROR_INVALID_ARGUMENT, "projectId is required")
        return false
    if api_key.is_empty():
        _set_error(Util.ERROR_INVALID_ARGUMENT, "apiKey is required")
        return false

    _clear_error()
    return true


func initialize() -> bool:
    if not is_inside_tree():
        _set_error(Util.ERROR_FAILED_PRECONDITION, "HiveAxyl node must be inside the scene tree")
        return false

    var response = await _connect_json(
        gateway_url,
        "DiscoveryService",
        "ResolveEndpoints",
        {
            "clientVersion": client_version,
            "projectId": project_id
        },
        true,
        true
    )
    if typeof(response) != TYPE_DICTIONARY:
        return false

    var resolved := {}
    for endpoint in response.get("endpoints", []):
        var domain := str(endpoint.get("domain", ""))
        var base_url := Util.trim_trailing_slash(str(endpoint.get("baseUrl", "")))
        if domain.is_empty() or base_url.is_empty():
            continue
        resolved[domain] = base_url

    if not resolved.has("auth"):
        _set_error(Util.ERROR_NOT_FOUND, "discovery returned no endpoint for domain: auth")
        return false

    _endpoints = resolved
    _ready = true
    _clear_error()
    _log("initialized")
    return true


func is_ready() -> bool:
    return _ready


func _endpoint_for(domain: String) -> String:
    return str(_endpoints.get(domain, ""))


func current_session() -> HiveAxylSession:
    return _session


func clear_session() -> void:
    _session.clear()
    auth.clear_player()
    session_changed.emit({})


func _rpc(domain: String, service: String, method: String, body: Dictionary, allows_session_refresh: bool) -> Variant:
    if not _ready:
        _set_error(Util.ERROR_FAILED_PRECONDITION, "HiveAxyl not initialized - call initialize() first")
        return null

    var base_url := _endpoint_for(domain)
    if base_url.is_empty():
        _set_error(Util.ERROR_NOT_FOUND, "discovery returned no endpoint for domain: " + domain)
        return null

    var response = await _connect_json(
        base_url,
        service,
        method,
        body,
        true,
        _is_idempotent_method(method)
    )
    if typeof(response) == TYPE_DICTIONARY:
        return response

    if not allows_session_refresh:
        return null
    if str(last_error.get("code", "")) != Util.ERROR_SESSION_EXPIRED:
        return null
    if method == "RefreshToken":
        return null

    var refreshed := await _refresh_session()
    if not refreshed:
        return null

    return await _connect_json(
        base_url,
        service,
        method,
        body,
        true,
        _is_idempotent_method(method)
    )


func _refresh_session() -> bool:
    if not _session.has_refresh_token():
        return false

    var base_url := _endpoint_for("auth")
    if base_url.is_empty():
        return false

    var response = await _connect_json(
        base_url,
        "AuthService",
        "RefreshToken",
        {
            "refreshToken": _session.refresh_token
        },
        true,
        false
    )
    if typeof(response) != TYPE_DICTIONARY:
        return false

    var token_pair: Dictionary = response.get("tokenPair", {})
    if token_pair.is_empty():
        _set_error(Util.ERROR_INTERNAL, "refresh response missing token pair")
        return false

    _session.save_tokens(token_pair)
    _clear_error()
    return true


func _connect_json(
    base_url: String,
    service: String,
    method: String,
    body: Dictionary,
    requires_auth: bool,
    idempotent: bool
) -> Variant:
    var attempts := 1
    if idempotent:
        attempts = 3

    for attempt in range(attempts):
        var result = await _send_json_once(base_url, service, method, body, requires_auth)
        if typeof(result) == TYPE_DICTIONARY:
            return result

        var can_retry := bool(last_error.get("retryable", false))
        if not can_retry:
            return null
        if attempt == attempts - 1:
            return null

        var delay := 0.2 * float(attempt + 1)
        await get_tree().create_timer(delay).timeout
    return null


func _send_json_once(
    base_url: String,
    service: String,
    method: String,
    body: Dictionary,
    requires_auth: bool
) -> Variant:
    var request_node := HTTPRequest.new()
    add_child(request_node)

    var url := base_url + "/hiveng.v1." + service + "/" + method
    var headers := _build_headers(method, requires_auth)
    var payload := JSON.stringify(body)
    var error := request_node.request(url, headers, HTTPClient.METHOD_POST, payload)
    if error != OK:
        request_node.queue_free()
        _set_error(Util.ERROR_INTERNAL, "request start failed: " + str(error), {}, 0, true)
        return null

    var completed: Array = await request_node.request_completed
    request_node.queue_free()

    var result := int(completed[0])
    var response_code := int(completed[1])
    var response_body: PackedByteArray = completed[3]
    var text := response_body.get_string_from_utf8()

    if result != OK:
        _set_error(Util.ERROR_INTERNAL, "request failed: " + str(result), {}, response_code, true)
        return null

    if response_code != 200:
        _set_http_error(response_code, text)
        return null

    if text.strip_edges().is_empty():
        _clear_error()
        return {}

    var parsed = JSON.parse_string(text)
    if typeof(parsed) != TYPE_DICTIONARY:
        _set_error(Util.ERROR_INTERNAL, "invalid response body for " + service + "/" + method)
        return null

    _clear_error()
    return parsed


func _build_headers(method: String, requires_auth: bool) -> PackedStringArray:
    var headers := PackedStringArray([
        "Content-Type: application/json",
        "Accept: application/json"
    ])
    if not requires_auth:
        return headers

    headers.append("Authorization: Bearer " + api_key)
    if not language.is_empty():
        headers.append("X-Hive-Ng-Language: " + language)
    if _session.has_access_token() and _uses_player_token(method):
        headers.append("X-Player-Token: " + _session.access_token)
    return headers


func _uses_player_token(method: String) -> bool:
    match method:
        "RefreshToken", "StartFacebookDesktopLogin", "CompleteFacebookDesktopLogin":
            return false
        _:
            return true


func _set_http_error(response_code: int, body: String) -> void:
    var envelope = JSON.parse_string(body)
    if typeof(envelope) != TYPE_DICTIONARY:
        _set_error(Util.ERROR_INTERNAL, "HTTP " + str(response_code), {}, response_code, response_code == 0)
        return

    var detail := Util.decode_error_detail(envelope)
    var code := str(detail.get("code", Util.ERROR_UNSPECIFIED))
    var metadata: Dictionary = detail.get("metadata", {})
    var message := str(envelope.get("message", "HTTP " + str(response_code)))
    _set_error(code, message, metadata, response_code)


func _set_error(
    code: String,
    message: String,
    metadata: Dictionary = {},
    http_status: int = 0,
    retryable: bool = false
) -> Dictionary:
    last_error = {
        "code": code,
        "message": message,
        "metadata": metadata,
        "http_status": http_status,
        "retryable": retryable
    }
    _log("error: " + code + " " + message)
    error_occurred.emit(last_error)
    return last_error


func _clear_error() -> void:
    last_error = {}


func _log(message: String) -> void:
    if not debug:
        return
    print("[hive-axyl] " + message)


func _is_idempotent_method(method: String) -> bool:
    match method:
        "ResolveEndpoints", "GetLoginProviders", "GetPlayer", "ListActiveNotices", "ListMail", "CheckNewMail":
            return true
        _:
            return false
