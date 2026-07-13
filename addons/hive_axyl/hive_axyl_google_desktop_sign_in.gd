class_name HiveAxylGoogleDesktopSignIn
extends Node

const Util := preload("res://addons/hive_axyl/hive_axyl_util.gd")
const DesktopOAuthLoopback := preload("res://addons/hive_axyl/hive_axyl_desktop_oauth_loopback.gd")

const AUTH_URL := "https://accounts.google.com/o/oauth2/v2/auth"
const TOKEN_URL := "https://oauth2.googleapis.com/token"
var _redirect_uri := ""


func sign_in(client_id: String, client_secret: String = "", port: int = 0) -> Dictionary:
    if client_id.strip_edges().is_empty():
        return _error("Google desktop client ID is required", Util.ERROR_INVALID_ARGUMENT)

    var loopback := DesktopOAuthLoopback.new()
    add_child(loopback)
    if not loopback.start(port):
        loopback.queue_free()
        return _error("Google callback server failed", Util.ERROR_INTERNAL)

    _redirect_uri = loopback.redirect_uri
    var state := Util.random_url_token(16)
    var verifier := Util.random_url_token(32)
    var challenge := Util.base64_url(verifier.sha256_buffer())
    var nonce := Util.random_url_token(16)
    var url := AUTH_URL + "?" + Util.form_encode({
        "response_type": "code",
        "client_id": client_id,
        "redirect_uri": _redirect_uri,
        "scope": "openid email profile",
        "code_challenge": challenge,
        "code_challenge_method": "S256",
        "state": state,
        "nonce": nonce,
        "prompt": "select_account"
    })

    var open_error := OS.shell_open(url)
    if open_error != OK:
        _cleanup(loopback)
        return _error("browser open failed: " + str(open_error), Util.ERROR_INTERNAL)

    var callback = await loopback.wait_for_callback(state, "state", "Google")
    _cleanup(loopback)
    if typeof(callback) != TYPE_DICTIONARY:
        return _error("Google callback failed", Util.ERROR_INTERNAL)
    if callback.has("error"):
        return callback

    var code := str(callback.get("code", ""))
    if code.is_empty():
        return _error("Google authorization code is missing", Util.ERROR_INVALID_ARGUMENT)
    return await _exchange_code(client_id, client_secret, verifier, code)


func _exchange_code(client_id: String, client_secret: String, verifier: String, code: String) -> Dictionary:
    var request_node := HTTPRequest.new()
    add_child(request_node)
    var headers := PackedStringArray([
        "Content-Type: application/x-www-form-urlencoded",
        "Accept: application/json"
    ])
    var fields := {
        "grant_type": "authorization_code",
        "code": code,
        "client_id": client_id,
        "redirect_uri": _redirect_uri,
        "code_verifier": verifier
    }
    # Google 데스크톱 앱 클라이언트는 토큰 교환에 client_secret을 요구한다 (installed app에서는 기밀로 취급되지 않음).
    if not client_secret.strip_edges().is_empty():
        fields["client_secret"] = client_secret.strip_edges()
    var payload := Util.form_encode(fields)
    var start_error := request_node.request(TOKEN_URL, headers, HTTPClient.METHOD_POST, payload)
    if start_error != OK:
        request_node.queue_free()
        return _error("Google token request failed: " + str(start_error), Util.ERROR_INTERNAL)

    var completed: Array = await request_node.request_completed
    request_node.queue_free()

    var result := int(completed[0])
    var response_code := int(completed[1])
    var response_body: PackedByteArray = completed[3]
    var text := response_body.get_string_from_utf8()
    if result != OK:
        return _error("Google token request failed: " + str(result), Util.ERROR_INTERNAL)
    if response_code != 200:
        return _error("Google token exchange failed: HTTP " + str(response_code) + " " + text, Util.ERROR_INTERNAL)

    var parsed = JSON.parse_string(text)
    if typeof(parsed) != TYPE_DICTIONARY:
        return _error("Google token response is invalid", Util.ERROR_INTERNAL)

    var id_token := str(parsed.get("id_token", ""))
    if id_token.is_empty():
        return _error("Google token response missing id_token", Util.ERROR_INTERNAL)

    return {
        "id_token": id_token
    }


func _cleanup(loopback) -> void:
    loopback.stop()
    loopback.queue_free()


func _error(message: String, code: String) -> Dictionary:
    return {
        "error": message,
        "code": code,
        "metadata": {}
    }
