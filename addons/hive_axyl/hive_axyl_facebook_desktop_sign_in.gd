class_name HiveAxylFacebookDesktopSignIn
extends Node

const Util := preload("res://addons/hive_axyl/hive_axyl_util.gd")
const DesktopOAuthLoopback := preload("res://addons/hive_axyl/hive_axyl_desktop_oauth_loopback.gd")


func sign_in(hive, port: int = 0) -> Dictionary:
    var loopback := DesktopOAuthLoopback.new()
    add_child(loopback)
    if not loopback.start(port):
        loopback.queue_free()
        return _error("Facebook callback server failed", Util.ERROR_INTERNAL)

    var callback_state := Util.random_url_token(16)
    var start_response = await hive._rpc(
        "auth",
        "AuthService",
        "StartFacebookDesktopLogin",
        {
            "returnUrl": loopback.redirect_uri,
            "callbackState": callback_state,
            "platform": Util.CLIENT_PLATFORM_DESKTOP
        },
        false
    )
    if typeof(start_response) != TYPE_DICTIONARY:
        _cleanup(loopback)
        return {}

    var authorization_url := str(start_response.get("authorizationUrl", ""))
    if authorization_url.is_empty():
        _cleanup(loopback)
        return _error("Facebook login response missing authorization URL", Util.ERROR_INTERNAL)

    var open_error := OS.shell_open(authorization_url)
    if open_error != OK:
        _cleanup(loopback)
        return _error("browser open failed: " + str(open_error), Util.ERROR_INTERNAL)

    var callback = await loopback.wait_for_callback(callback_state, "callback_state", "Facebook")
    _cleanup(loopback)
    if typeof(callback) != TYPE_DICTIONARY:
        return _error("Facebook callback failed", Util.ERROR_INTERNAL)
    if callback.has("error"):
        return callback

    var completion_code := str(callback.get("completion_code", ""))
    if completion_code.is_empty():
        return _error("Facebook completion code is missing", Util.ERROR_INVALID_ARGUMENT)

    var complete_response = await hive._rpc(
        "auth",
        "AuthService",
        "CompleteFacebookDesktopLogin",
        {
            "completionCode": completion_code
        },
        false
    )
    if typeof(complete_response) != TYPE_DICTIONARY:
        return {}
    return complete_response


func _cleanup(loopback) -> void:
    loopback.stop()
    loopback.queue_free()


func _error(message: String, code: String) -> Dictionary:
    return {
        "error": message,
        "code": code,
        "metadata": {}
    }
