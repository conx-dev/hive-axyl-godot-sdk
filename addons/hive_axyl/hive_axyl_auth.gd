class_name HiveAxylAuth
extends RefCounted

const Util := preload("res://addons/hive_axyl/hive_axyl_util.gd")
const GoogleDesktopSignIn := preload("res://addons/hive_axyl/hive_axyl_google_desktop_sign_in.gd")
const FacebookDesktopSignIn := preload("res://addons/hive_axyl/hive_axyl_facebook_desktop_sign_in.gd")
const AppleDesktopSignIn := preload("res://addons/hive_axyl/hive_axyl_apple_desktop_sign_in.gd")

var hive
var _client_platform := ""
var _player := {}


func _init(hive_client, client_platform: String) -> void:
    hive = hive_client
    _client_platform = client_platform


func get_login_providers(country_override: String = "") -> Dictionary:
    var response = await hive._rpc(
        "auth",
        "AuthService",
        "GetLoginProviders",
        {
            "countryOverride": country_override,
            "platform": _client_platform
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


func login_with_facebook(access_token: String) -> Dictionary:
    if access_token.is_empty():
        hive._set_error(Util.ERROR_INVALID_ARGUMENT, "accessToken is required")
        return {}
    return await _login(Util.IDENTITY_PROVIDER_FACEBOOK, access_token)


func login_with_apple(identity_token: String) -> Dictionary:
    if identity_token.is_empty():
        hive._set_error(Util.ERROR_INVALID_ARGUMENT, "identityToken is required")
        return {}
    return await _login(Util.IDENTITY_PROVIDER_APPLE, identity_token)


func login_with_google_desktop(client_id: String = "", client_secret: String = "", port: int = 0) -> Dictionary:
    if not _is_desktop_platform():
        hive._set_error(
            Util.ERROR_FAILED_PRECONDITION,
            "Google desktop sign-in is only available on desktop"
        )
        return {}

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


func login_with_facebook_desktop(port: int = 0) -> Dictionary:
    if not _is_desktop_platform():
        hive._set_error(
            Util.ERROR_FAILED_PRECONDITION,
            "Facebook desktop sign-in is only available on desktop"
        )
        return {}

    var sign_in := FacebookDesktopSignIn.new()
    hive.add_child(sign_in)
    var response = await sign_in.sign_in(hive, port)
    sign_in.queue_free()

    if typeof(response) != TYPE_DICTIONARY:
        hive._set_error(Util.ERROR_INTERNAL, "Facebook sign-in failed")
        return {}
    if response.is_empty():
        return {}
    if response.has("error"):
        hive._set_error(
            str(response.get("code", Util.ERROR_INTERNAL)),
            str(response.get("error", "Facebook sign-in failed")),
            response.get("metadata", {})
        )
        return {}
    return _save_login(response)


func login_with_apple_desktop(client_id: String, port: int = 0) -> Dictionary:
    if not _is_desktop_platform():
        hive._set_error(
            Util.ERROR_FAILED_PRECONDITION,
            "Apple desktop sign-in is only available on desktop"
        )
        return {}

    var resolved_client_id := client_id.strip_edges()
    if resolved_client_id.is_empty():
        hive._set_error(Util.ERROR_INVALID_ARGUMENT, "Apple Services ID is required")
        return {}

    var sign_in := AppleDesktopSignIn.new()
    hive.add_child(sign_in)
    var response = await sign_in.sign_in(hive, resolved_client_id, port)
    sign_in.queue_free()

    if typeof(response) != TYPE_DICTIONARY:
        hive._set_error(Util.ERROR_INTERNAL, "Apple sign-in failed")
        return {}
    if response.is_empty():
        return {}
    if response.has("error"):
        hive._set_error(
            str(response.get("code", Util.ERROR_INTERNAL)),
            str(response.get("error", "Apple sign-in failed")),
            response.get("metadata", {})
        )
        return {}
    return await _save_apple_login(response)


func login_as_guest() -> Dictionary:
    var credential := hive._guest_installation_credential()
    if credential.is_empty():
        return {}
    return await _login(Util.IDENTITY_PROVIDER_GUEST, credential)


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
            "platform": _client_platform
        },
        true
    )
    if typeof(response) != TYPE_DICTIONARY:
        return {}

    return _save_login(response)


func _is_desktop_platform() -> bool:
    return _client_platform == Util.CLIENT_PLATFORM_DESKTOP


func _save_login(response: Dictionary) -> Dictionary:
    var token_pair: Dictionary = response.get("tokenPair", {})
    var player_message: Dictionary = response.get("player", {})
    if token_pair.is_empty() or player_message.is_empty():
        hive._set_error(Util.ERROR_INTERNAL, "login response missing player or token pair")
        return {}

    hive.current_session().save_tokens(token_pair)
    _player = Util.map_player(player_message)
    hive.session_changed.emit(_player)
    return _player


func _save_apple_login(response: Dictionary) -> Dictionary:
    var access_token := str(response.get("access_token", ""))
    var refresh_token := str(response.get("refresh_token", ""))
    if access_token.is_empty() or refresh_token.is_empty():
        hive._set_error(Util.ERROR_INTERNAL, "Apple login response missing token pair")
        return {}

    hive.current_session().save_tokens({
        "accessToken": access_token,
        "refreshToken": refresh_token,
        "accessTokenExpiresAt": str(response.get("access_token_expires_at", "")),
        "playerValidationToken": str(response.get("player_validation_token", "")),
        "playerValidationTokenExpiresAt": str(response.get("player_validation_token_expires_at", ""))
    })
    var restored: Dictionary = await restore_session()
    if restored.is_empty() and hive.last_error.is_empty():
        hive._set_error(Util.ERROR_INTERNAL, "Apple login response missing player")
    return restored
