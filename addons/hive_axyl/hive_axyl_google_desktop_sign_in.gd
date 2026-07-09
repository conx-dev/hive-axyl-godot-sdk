class_name HiveAxylGoogleDesktopSignIn
extends Node

const Util := preload("res://addons/hive_axyl/hive_axyl_util.gd")

const AUTH_URL := "https://accounts.google.com/o/oauth2/v2/auth"
const TOKEN_URL := "https://oauth2.googleapis.com/token"
const CALLBACK_TIMEOUT_MS := 120000

var _server: TCPServer
var _state := ""
var _redirect_uri := ""


func sign_in(client_id: String, client_secret: String = "", port: int = 0) -> Dictionary:
    if client_id.strip_edges().is_empty():
        return _error("Google desktop client ID is required", Util.ERROR_INVALID_ARGUMENT)

    _server = TCPServer.new()
    var listen_error := _server.listen(port, "127.0.0.1")
    if listen_error != OK:
        return _error("Google callback server failed: " + str(listen_error), Util.ERROR_INTERNAL)

    var local_port := _server.get_local_port()
    _redirect_uri = "http://127.0.0.1:" + str(local_port) + "/callback"
    _state = Util.random_url_token(16)
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
        "state": _state,
        "nonce": nonce,
        "prompt": "select_account"
    })

    var open_error := OS.shell_open(url)
    if open_error != OK:
        _server.stop()
        return _error("browser open failed: " + str(open_error), Util.ERROR_INTERNAL)

    var callback = await _wait_for_callback()
    _server.stop()
    if typeof(callback) != TYPE_DICTIONARY:
        return _error("Google callback failed", Util.ERROR_INTERNAL)
    if callback.has("error"):
        return callback

    return await _exchange_code(client_id, client_secret, verifier, str(callback.get("code", "")))


func _wait_for_callback() -> Dictionary:
    var timeout_at := Time.get_ticks_msec() + CALLBACK_TIMEOUT_MS
    while Time.get_ticks_msec() < timeout_at:
        if _server.is_connection_available():
            var peer := _server.take_connection()
            var request_text := await _read_request(peer)
            var path := Util.parse_http_request_path(request_text)
            var query := ""
            var question := path.find("?")
            if question >= 0:
                query = path.substr(question + 1)

            var params := Util.query_decode(query)
            _write_callback_response(peer, params)
            if params.has("error"):
                return _error(str(params.get("error", "Google sign-in failed")), Util.ERROR_INTERNAL)
            if str(params.get("state", "")) != _state:
                return _error("Google sign-in state mismatch", Util.ERROR_INVALID_ARGUMENT)
            var code := str(params.get("code", ""))
            if code.is_empty():
                return _error("Google authorization code is missing", Util.ERROR_INVALID_ARGUMENT)
            return {
                "code": code
            }
        await get_tree().create_timer(0.05).timeout
    return _error("Google sign-in timed out", Util.ERROR_INTERNAL)


func _read_request(peer: StreamPeerTCP) -> String:
    var text := ""
    for _i in range(80):
        var available := peer.get_available_bytes()
        if available > 0:
            text += peer.get_utf8_string(available)
            if text.find("\r\n\r\n") >= 0:
                return text
        await get_tree().process_frame
    return text


func _write_callback_response(peer: StreamPeerTCP, params: Dictionary) -> void:
    var body := "<!doctype html><html><body><h1>Hive Axyl sign-in complete</h1><p>You can return to Godot.</p></body></html>"
    if params.has("error"):
        body = "<!doctype html><html><body><h1>Hive Axyl sign-in failed</h1><p>You can close this window.</p></body></html>"
    var body_bytes := body.to_utf8_buffer()
    var response := "HTTP/1.1 200 OK\r\n"
    response += "Content-Type: text/html; charset=utf-8\r\n"
    response += "Content-Length: " + str(body_bytes.size()) + "\r\n"
    response += "Connection: close\r\n\r\n"
    response += body
    peer.put_data(response.to_utf8_buffer())


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


func _error(message: String, code: String) -> Dictionary:
    return {
        "error": message,
        "code": code,
        "metadata": {}
    }
