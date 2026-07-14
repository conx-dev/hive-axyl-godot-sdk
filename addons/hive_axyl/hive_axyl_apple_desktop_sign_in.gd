class_name HiveAxylAppleDesktopSignIn
extends Node

const Util := preload("res://addons/hive_axyl/hive_axyl_util.gd")
const DesktopOAuthLoopback := preload("res://addons/hive_axyl/hive_axyl_desktop_oauth_loopback.gd")


func sign_in(hive, client_id: String, port: int = 0) -> Dictionary:
    var loopback := DesktopOAuthLoopback.new()
    add_child(loopback)
    if not loopback.start(port):
        loopback.queue_free()
        return _error("Apple callback server failed", Util.ERROR_INTERNAL)

    var callback_state := Util.random_url_token(16)
    var return_url := loopback.redirect_uri
    return_url += "?callback_state=" + callback_state.uri_encode()
    var start_response = await hive._post_auth_json(
        "auth",
        "/oauth/apple/start",
        {
            "clientId": client_id,
            "returnUrl": return_url,
            "platform": "desktop"
        }
    )
    if typeof(start_response) != TYPE_DICTIONARY:
        _cleanup(loopback)
        return {}

    var authorization_url := str(start_response.get("authorizationUrl", ""))
    if authorization_url.is_empty():
        _cleanup(loopback)
        return _error("Apple login response missing authorization URL", Util.ERROR_INTERNAL)

    var open_error := OS.shell_open(authorization_url)
    if open_error != OK:
        _cleanup(loopback)
        return _error("browser open failed: " + str(open_error), Util.ERROR_INTERNAL)

    var callback = await loopback.wait_for_callback(callback_state, "callback_state", "Apple")
    _cleanup(loopback)
    if typeof(callback) != TYPE_DICTIONARY:
        return _error("Apple callback failed", Util.ERROR_INTERNAL)
    if callback.has("error"):
        return callback
    if str(callback.get("status", "")) != "ok":
        return _error("Apple login callback is invalid", Util.ERROR_INVALID_ARGUMENT)
    return callback


func _cleanup(loopback) -> void:
    loopback.stop()
    loopback.queue_free()


func _error(message: String, code: String) -> Dictionary:
    return {
        "error": message,
        "code": code,
        "metadata": {}
    }
