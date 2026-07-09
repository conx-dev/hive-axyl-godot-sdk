class_name HiveAxylAuth
extends RefCounted

const Util := preload("res://addons/hive_axyl/hive_axyl_util.gd")
const GoogleDesktopSignIn := preload("res://addons/hive_axyl/hive_axyl_google_desktop_sign_in.gd")

var hive
var _player := {}


func _init(hive_client) -> void:
    hive = hive_client


func get_login_providers(country_override: String = "") -> Dictionary:
    var response = await hive._rpc(
        "auth",
        "AuthService",
        "GetLoginProviders",
        {
            "countryOverride": country_override,
            "platform": Util.CLIENT_PLATFORM_DESKTOP
        },
        true
    )
    if typeof(response) != TYPE_DICTIONARY:
        return {}

    var providers: Array = []
    for provider in response.get("providers", []):
        providers.append(Util.provider_name(provider))

    return {
        "providers": providers,
        "country": str(response.get("country", ""))
    }


func login_with_google(id_token: String) -> Dictionary:
    if id_token.is_empty():
        hive._set_error(Util.ERROR_INVALID_ARGUMENT, "idToken is required")
        return {}
    return await _login(Util.IDENTITY_PROVIDER_GOOGLE, id_token)


func login_with_google_desktop(client_id: String = "", client_secret: String = "", port: int = 0) -> Dictionary:
    var resolved_client_id := client_id.strip_edges()
    if resolved_client_id.is_empty():
        resolved_client_id = hive.google_client_id.strip_edges()
    if resolved_client_id.is_empty():
        hive._set_error(Util.ERROR_INVALID_ARGUMENT, "Google desktop client ID is required")
        return {}
    var resolved_client_secret := client_secret.strip_edges()
    if resolved_client_secret.is_empty():
        resolved_client_secret = hive.google_client_secret.strip_edges()

    var sign_in := GoogleDesktopSignIn.new()
    hive.add_child(sign_in)
    var oauth = await sign_in.sign_in(resolved_client_id, resolved_client_secret, port)
    sign_in.queue_free()

    if typeof(oauth) != TYPE_DICTIONARY:
        hive._set_error(Util.ERROR_INTERNAL, "Google sign-in failed")
        return {}
    if oauth.has("error"):
        hive._set_error(
            str(oauth.get("code", Util.ERROR_INTERNAL)),
            str(oauth.get("error", "Google sign-in failed")),
            oauth.get("metadata", {})
        )
        return {}

    return await login_with_google(str(oauth.get("id_token", "")))


func login_as_guest(device_id: String) -> Dictionary:
    if device_id.is_empty():
        hive._set_error(Util.ERROR_INVALID_ARGUMENT, "deviceId is required")
        return {}
    return await _login(Util.IDENTITY_PROVIDER_GUEST, device_id)


func restore_session() -> Dictionary:
    if not hive.current_session().has_access_token():
        return {}

    var response = await hive._rpc(
        "auth",
        "AuthService",
        "GetPlayer",
        {},
        true
    )
    if typeof(response) != TYPE_DICTIONARY:
        return {}
    if not response.has("player"):
        return {}

    _player = Util.map_player(response["player"])
    hive.session_changed.emit(_player)
    return _player


func get_player() -> Dictionary:
    return await restore_session()


func logout() -> bool:
    if hive.current_session().has_access_token():
        await hive._rpc(
            "auth",
            "AuthService",
            "Logout",
            {},
            true
        )

    hive.clear_session()
    return true


func current_player() -> Dictionary:
    return _player.duplicate(true)


func player_validation_token() -> String:
    return hive.current_session().current_player_validation_token()


func clear_player() -> void:
    _player = {}


func _login(provider: String, provider_token: String) -> Dictionary:
    var response = await hive._rpc(
        "auth",
        "AuthService",
        "LoginWithProvider",
        {
            "provider": provider,
            "providerToken": provider_token,
            "platform": Util.CLIENT_PLATFORM_DESKTOP
        },
        true
    )
    if typeof(response) != TYPE_DICTIONARY:
        return {}

    var token_pair: Dictionary = response.get("tokenPair", {})
    var player_message: Dictionary = response.get("player", {})
    if token_pair.is_empty() or player_message.is_empty():
        hive._set_error(Util.ERROR_INTERNAL, "login response missing player or token pair")
        return {}

    hive.current_session().save_tokens(token_pair)
    _player = Util.map_player(player_message)
    hive.session_changed.emit(_player)
    return _player
