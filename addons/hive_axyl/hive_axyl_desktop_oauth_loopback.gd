class_name HiveAxylDesktopOAuthLoopback
extends Node

const Util := preload("res://addons/hive_axyl/hive_axyl_util.gd")
const CALLBACK_TIMEOUT_MS := 120000

var redirect_uri := ""
var _server: TCPServer


func start(port: int = 0) -> bool:
    _server = TCPServer.new()
    var listen_error := _server.listen(port, "127.0.0.1")
    if listen_error != OK:
        _server = null
        return false
    redirect_uri = "http://127.0.0.1:" + str(_server.get_local_port()) + "/callback"
    return true


func stop() -> void:
    if _server != null:
        _server.stop()
    _server = null
    redirect_uri = ""


func wait_for_callback(expected_state: String, state_parameter: String, provider_name: String) -> Dictionary:
    var timeout_at := Time.get_ticks_msec() + CALLBACK_TIMEOUT_MS
    while Time.get_ticks_msec() < timeout_at:
        if _server != null and _server.is_connection_available():
            var peer := _server.take_connection()
            var request_text := await _read_request(peer)
            var params := _parse_callback(request_text)
            _write_callback_response(peer, params)
            if params.has("error"):
                var message := str(params.get("error_message", params.get("error", "sign-in failed")))
                var code := _provider_error_code(params)
                return _error(provider_name + " sign-in failed: " + message, code)
            if str(params.get(state_parameter, "")) != expected_state:
                return _error(provider_name + " sign-in state mismatch", Util.ERROR_INVALID_ARGUMENT)
            return params
        await get_tree().create_timer(0.05).timeout
    return _error(provider_name + " sign-in timed out", Util.ERROR_INTERNAL)


func _read_request(peer: StreamPeerTCP) -> String:
    var text := ""
    for _index in range(80):
        var available := peer.get_available_bytes()
        if available > 0:
            text += peer.get_utf8_string(available)
            if text.find("\r\n\r\n") >= 0:
                return text
        await get_tree().process_frame
    return text


func _parse_callback(request_text: String) -> Dictionary:
    var path := Util.parse_http_request_path(request_text)
    var question := path.find("?")
    if question < 0 or path.substr(0, question) != "/callback":
        return {}
    return Util.query_decode(path.substr(question + 1))


func _write_callback_response(peer: StreamPeerTCP, params: Dictionary) -> void:
    var title := "Hive Axyl sign-in complete"
    var message := "You can return to the game."
    if params.has("error"):
        title = "Hive Axyl sign-in failed"
        message = "You can close this window."
    var body := "<!doctype html><html><body><h1>" + title + "</h1><p>" + message + "</p></body></html>"
    var body_bytes := body.to_utf8_buffer()
    var response := "HTTP/1.1 200 OK\r\n"
    response += "Content-Type: text/html; charset=utf-8\r\n"
    response += "Cache-Control: no-store\r\n"
    response += "Content-Length: " + str(body_bytes.size()) + "\r\n"
    response += "Connection: close\r\n\r\n"
    response += body
    peer.put_data(response.to_utf8_buffer())


func _provider_error_code(params: Dictionary) -> String:
    var provider_code := str(params.get("error", ""))
    if provider_code.begins_with("ERROR_CODE_"):
        return provider_code
    return Util.ERROR_INTERNAL


func _error(message: String, code: String) -> Dictionary:
    return {
        "error": message,
        "code": code,
        "metadata": {}
    }
