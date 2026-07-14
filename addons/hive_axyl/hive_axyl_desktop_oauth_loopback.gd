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
            if _has_callback_error(params):
                var fallback := str(params.get("error_code", params.get("error", "sign-in failed")))
                var message := str(params.get("error_message", fallback))
                var code := _provider_error_code(params)
                return _error(provider_name + " sign-in failed: " + message, code)
            if str(params.get(state_parameter, "")) != expected_state:
                return _error(provider_name + " sign-in state mismatch", Util.ERROR_INVALID_ARGUMENT)
            return params
        await get_tree().create_timer(0.05).timeout
    return _error(provider_name + " sign-in timed out", Util.ERROR_INTERNAL)


func _read_request(peer: StreamPeerTCP) -> String:
    var text := ""
    var timeout_at := Time.get_ticks_msec() + 5000
    while Time.get_ticks_msec() < timeout_at:
        var available := peer.get_available_bytes()
        if available > 0:
            text += peer.get_utf8_string(available)
            if _is_request_complete(text):
                return text
        await get_tree().process_frame
    return text


func _is_request_complete(request_text: String) -> bool:
    var header_end := request_text.find("\r\n\r\n")
    if header_end < 0:
        return false
    var content_length := _content_length(request_text.substr(0, header_end))
    var body := request_text.substr(header_end + 4)
    return body.to_utf8_buffer().size() >= content_length


func _content_length(headers: String) -> int:
    var lines := headers.split("\r\n", false)
    for index in range(1, lines.size()):
        var line := str(lines[index])
        var colon := line.find(":")
        if colon < 0:
            continue
        var name := line.substr(0, colon).strip_edges()
        if name.to_lower() != "content-length":
            continue
        return max(0, int(line.substr(colon + 1).strip_edges()))
    return 0


func _parse_callback(request_text: String) -> Dictionary:
    var path := Util.parse_http_request_path(request_text)
    var question := path.find("?")
    var callback_path := path
    if question >= 0:
        callback_path = path.substr(0, question)
    if callback_path != "/callback":
        return {}

    var params := {}
    if question >= 0:
        params = Util.query_decode(path.substr(question + 1))
    var header_end := request_text.find("\r\n\r\n")
    if header_end < 0 or header_end + 4 >= request_text.length():
        return params
    var body_params := Util.query_decode(request_text.substr(header_end + 4))
    for key in body_params.keys():
        if not params.has(key):
            params[key] = body_params[key]
    return params


func _write_callback_response(peer: StreamPeerTCP, params: Dictionary) -> void:
    var title := "Hive Axyl sign-in complete"
    var message := "You can return to the game."
    if _has_callback_error(params):
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
    var provider_code := str(params.get("error_code", params.get("error", "")))
    if provider_code.begins_with("ERROR_CODE_"):
        return provider_code
    return Util.ERROR_INTERNAL


func _has_callback_error(params: Dictionary) -> bool:
    if params.has("error"):
        return true
    return str(params.get("status", "")) == "error"


func _error(message: String, code: String) -> Dictionary:
    return {
        "error": message,
        "code": code,
        "metadata": {}
    }
