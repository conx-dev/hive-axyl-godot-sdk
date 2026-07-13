class_name HiveAxylUtil
extends RefCounted

const CLIENT_PLATFORM_WEB := "CLIENT_PLATFORM_WEB"
const CLIENT_PLATFORM_ANDROID := "CLIENT_PLATFORM_ANDROID"
const CLIENT_PLATFORM_IOS := "CLIENT_PLATFORM_IOS"
const CLIENT_PLATFORM_DESKTOP := "CLIENT_PLATFORM_DESKTOP"
const IDENTITY_PROVIDER_GOOGLE := "IDENTITY_PROVIDER_GOOGLE"
const IDENTITY_PROVIDER_FACEBOOK := "IDENTITY_PROVIDER_FACEBOOK"
const IDENTITY_PROVIDER_GUEST := "IDENTITY_PROVIDER_GUEST"
const ERROR_UNSPECIFIED := "ERROR_CODE_UNSPECIFIED"
const ERROR_INTERNAL := "ERROR_CODE_INTERNAL"
const ERROR_INVALID_ARGUMENT := "ERROR_CODE_INVALID_ARGUMENT"
const ERROR_NOT_FOUND := "ERROR_CODE_NOT_FOUND"
const ERROR_FAILED_PRECONDITION := "ERROR_CODE_FAILED_PRECONDITION"
const ERROR_SESSION_EXPIRED := "ERROR_CODE_SESSION_EXPIRED"
const ERROR_PLAYER_BANNED := "ERROR_CODE_PLAYER_BANNED"
const ERROR_MAINTENANCE := "ERROR_CODE_MAINTENANCE_IN_PROGRESS"
const ERROR_PROJECT_NOT_LIVE := "ERROR_CODE_PROJECT_NOT_LIVE"
const ERROR_PROJECT_SUSPENDED := "ERROR_CODE_PROJECT_SUSPENDED"
const ERROR_PROJECT_DELETED := "ERROR_CODE_PROJECT_DELETED"

const ERROR_CODE_NAMES := {
    0: "ERROR_CODE_UNSPECIFIED",
    1: "ERROR_CODE_INTERNAL",
    2: "ERROR_CODE_INVALID_ARGUMENT",
    3: "ERROR_CODE_NOT_FOUND",
    4: "ERROR_CODE_ALREADY_EXISTS",
    5: "ERROR_CODE_PERMISSION_DENIED",
    6: "ERROR_CODE_UNAUTHENTICATED",
    100: "ERROR_CODE_MAINTENANCE_IN_PROGRESS",
    101: "ERROR_CODE_GEO_BLOCKED",
    102: "ERROR_CODE_CLIENT_VERSION_UNSUPPORTED",
    200: "ERROR_CODE_PLAYER_BANNED",
    201: "ERROR_CODE_INVALID_PROVIDER_TOKEN",
    202: "ERROR_CODE_PROVIDER_NOT_ENABLED",
    203: "ERROR_CODE_CREDENTIAL_NOT_CONFIGURED",
    204: "ERROR_CODE_SESSION_EXPIRED",
    205: "ERROR_CODE_PLAYER_NOT_FOUND",
    300: "ERROR_CODE_DUPLICATE_RECEIPT",
    301: "ERROR_CODE_RECEIPT_VERIFICATION_FAILED",
    302: "ERROR_CODE_MARKET_NOT_SUPPORTED",
    400: "ERROR_CODE_API_KEY_INVALID",
    401: "ERROR_CODE_API_KEY_REVOKED",
    402: "ERROR_CODE_SERVER_KEY_INVALID",
    403: "ERROR_CODE_SERVER_KEY_REVOKED",
    500: "ERROR_CODE_ADMIN_EMAIL_EXISTS",
    501: "ERROR_CODE_ADMIN_INVALID_CREDENTIALS",
    502: "ERROR_CODE_PACKAGE_NAME_EXISTS",
    503: "ERROR_CODE_PROJECT_NOT_LIVE",
    504: "ERROR_CODE_PROJECT_SUSPENDED",
    505: "ERROR_CODE_PROJECT_DELETED",
    600: "ERROR_CODE_MAIL_NOT_FOUND",
    601: "ERROR_CODE_MAIL_ALREADY_CLAIMED",
    602: "ERROR_CODE_MAIL_NOT_CLAIMABLE"
}


static func detect_client_platform() -> String:
    if OS.has_feature("web"):
        return CLIENT_PLATFORM_WEB
    if OS.has_feature("android"):
        return CLIENT_PLATFORM_ANDROID
    if OS.has_feature("ios"):
        return CLIENT_PLATFORM_IOS
    return CLIENT_PLATFORM_DESKTOP

static func trim_trailing_slash(value: String) -> String:
    var next := value.strip_edges()
    while next.ends_with("/"):
        next = next.substr(0, next.length() - 1)
    return next


static func normalize_config_value(config: Dictionary, snake_name: String, camel_name: String) -> String:
    var value = config.get(snake_name, null)
    if value == null:
        value = config.get(camel_name, "")
    return str(value)


static func provider_name(provider: Variant) -> String:
    var raw := str(provider)
    match raw:
        "IDENTITY_PROVIDER_KAKAO":
            return "kakao"
        "IDENTITY_PROVIDER_NAVER":
            return "naver"
        "IDENTITY_PROVIDER_GOOGLE":
            return "google"
        "IDENTITY_PROVIDER_FACEBOOK":
            return "facebook"
        "IDENTITY_PROVIDER_APPLE":
            return "apple"
        "IDENTITY_PROVIDER_LINE":
            return "line"
        "IDENTITY_PROVIDER_TRUECALLER":
            return "truecaller"
        "IDENTITY_PROVIDER_PHONE_OTP":
            return "phone_otp"
        "IDENTITY_PROVIDER_GUEST":
            return "guest"
        _:
            return "unspecified"


static func platform_name(platform: Variant) -> String:
    var raw := str(platform)
    match raw:
        "CLIENT_PLATFORM_WEB":
            return "web"
        "CLIENT_PLATFORM_ANDROID":
            return "android"
        "CLIENT_PLATFORM_IOS":
            return "ios"
        "CLIENT_PLATFORM_DESKTOP":
            return "desktop"
        _:
            return "unspecified"


static func localized(values: Variant, language: String) -> String:
    if typeof(values) != TYPE_DICTIONARY:
        return str(values)

    var dictionary: Dictionary = values
    var normalized := language.strip_edges()
    if normalized.length() > 0 and dictionary.has(normalized):
        return str(dictionary[normalized])

    var dash := normalized.find("-")
    if dash > 0:
        var base := normalized.substr(0, dash)
        if dictionary.has(base):
            return str(dictionary[base])

    if dictionary.has("en"):
        return str(dictionary["en"])
    if dictionary.has("ko"):
        return str(dictionary["ko"])

    var keys := dictionary.keys()
    keys.sort()
    if keys.is_empty():
        return ""
    return str(dictionary[keys[0]])


static func map_player(message: Dictionary) -> Dictionary:
    var providers: Array = []
    for provider in message.get("providers", []):
        providers.append(provider_name(provider))

    return {
        "player_id": str(message.get("playerId", "")),
        "project_id": str(message.get("projectId", "")),
        "country": str(message.get("country", "")),
        "email": str(message.get("email", "")),
        "nickname": str(message.get("nickname", "")),
        "last_login_platform": platform_name(message.get("lastLoginPlatform", "")),
        "providers": providers,
        "created_at": str(message.get("createdAt", "")),
        "last_login_at": str(message.get("lastLoginAt", ""))
    }


static func map_notice(message: Dictionary, language: String) -> Dictionary:
    return {
        "id": str(message.get("id", "")),
        "project_id": str(message.get("projectId", "")),
        "title": localized(message.get("title", {}), language),
        "body": localized(message.get("body", {}), language),
        "starts_at": str(message.get("startsAt", "")),
        "ends_at": str(message.get("endsAt", "")),
        "view_count": str(message.get("viewCount", "0"))
    }


static func map_mail(message: Dictionary, language: String) -> Dictionary:
    var reward_display: Array = []
    for item in message.get("rewardDisplay", []):
        reward_display.append({
            "icon": str(item.get("icon", "")),
            "label": str(item.get("label", "")),
            "quantity": str(item.get("quantity", ""))
        })

    return {
        "id": str(message.get("id", "")),
        "mail_id": str(message.get("mailId", "")),
        "project_id": str(message.get("projectId", "")),
        "type": str(message.get("type", "")),
        "title": localized(message.get("title", {}), language),
        "body": localized(message.get("body", {}), language),
        "sender": str(message.get("sender", "")),
        "reward_preview": message.get("rewardPreview", {}),
        "reward_display": reward_display,
        "claimed": bool(message.get("claimed", false)),
        "claimable_from": str(message.get("claimableFrom", "")),
        "expires_at": str(message.get("expiresAt", "")),
        "claimed_at": str(message.get("claimedAt", "")),
        "created_at": str(message.get("createdAt", ""))
    }


static func base64_url(bytes: PackedByteArray) -> String:
    var encoded := Marshalls.raw_to_base64(bytes)
    encoded = encoded.replace("+", "-")
    encoded = encoded.replace("/", "_")
    encoded = encoded.replace("=", "")
    return encoded


static func random_url_token(byte_count: int) -> String:
    return base64_url(OS.get_entropy(byte_count))


static func form_encode(values: Dictionary) -> String:
    var pairs: Array = []
    for key in values.keys():
        var encoded_key := str(key).uri_encode()
        var encoded_value := str(values[key]).uri_encode()
        pairs.append(encoded_key + "=" + encoded_value)
    return "&".join(pairs)


static func query_decode(query: String) -> Dictionary:
    var result := {}
    if query.is_empty():
        return result

    for pair in query.split("&", false):
        var equals := pair.find("=")
        var key := pair
        var value := ""
        if equals >= 0:
            key = pair.substr(0, equals)
            value = pair.substr(equals + 1)
        key = key.replace("+", " ").uri_decode()
        value = value.replace("+", " ").uri_decode()
        result[key] = value
    return result


static func parse_http_request_path(request_text: String) -> String:
    var first_line_end := request_text.find("\r\n")
    if first_line_end < 0:
        return ""

    var first_line := request_text.substr(0, first_line_end)
    var parts := first_line.split(" ", false)
    if parts.size() < 2:
        return ""
    return str(parts[1])


static func decode_error_detail(envelope: Dictionary) -> Dictionary:
    var parsed := {
        "code": ERROR_UNSPECIFIED,
        "metadata": {}
    }
    var details = envelope.get("details", [])
    if typeof(details) != TYPE_ARRAY:
        return parsed

    for detail in details:
        if typeof(detail) != TYPE_DICTIONARY:
            continue
        if str(detail.get("type", "")) != "hiveng.v1.ErrorDetail":
            continue
        var bytes := Marshalls.base64_to_raw(str(detail.get("value", "")))
        return _decode_error_detail_bytes(bytes)
    return parsed


static func _decode_error_detail_bytes(bytes: PackedByteArray) -> Dictionary:
    var parsed := {
        "code": ERROR_UNSPECIFIED,
        "metadata": {}
    }
    var metadata := {}
    var index := {"value": 0}
    while int(index["value"]) < bytes.size():
        var tag := _read_varint(bytes, index)
        var field_number := int(tag) >> 3
        var wire_type := int(tag) & 7
        if field_number == 1 and wire_type == 0:
            var raw_code := int(_read_varint(bytes, index))
            parsed["code"] = ERROR_CODE_NAMES.get(raw_code, "ERROR_CODE_" + str(raw_code))
            continue
        if field_number == 2 and wire_type == 2:
            var entry := _read_length_delimited(bytes, index)
            var decoded_entry := _decode_metadata_entry(entry)
            if decoded_entry.has("key"):
                metadata[decoded_entry["key"]] = decoded_entry.get("value", "")
            continue
        _skip_field(bytes, index, wire_type)
    parsed["metadata"] = metadata
    return parsed


static func _decode_metadata_entry(bytes: PackedByteArray) -> Dictionary:
    var result := {}
    var index := {"value": 0}
    while int(index["value"]) < bytes.size():
        var tag := _read_varint(bytes, index)
        var field_number := int(tag) >> 3
        var wire_type := int(tag) & 7
        if field_number == 1 and wire_type == 2:
            result["key"] = _read_length_delimited(bytes, index).get_string_from_utf8()
            continue
        if field_number == 2 and wire_type == 2:
            result["value"] = _read_length_delimited(bytes, index).get_string_from_utf8()
            continue
        _skip_field(bytes, index, wire_type)
    return result


static func _read_varint(bytes: PackedByteArray, index: Dictionary) -> int:
    var shift := 0
    var result := 0
    while int(index["value"]) < bytes.size():
        var current := int(bytes[int(index["value"])])
        index["value"] = int(index["value"]) + 1
        result = result | ((current & 0x7f) << shift)
        if (current & 0x80) == 0:
            return result
        shift += 7
    return result


static func _read_length_delimited(bytes: PackedByteArray, index: Dictionary) -> PackedByteArray:
    var size := int(_read_varint(bytes, index))
    var start := int(index["value"])
    var end := min(start + size, bytes.size())
    index["value"] = end
    return bytes.slice(start, end)


static func _skip_field(bytes: PackedByteArray, index: Dictionary, wire_type: int) -> void:
    if wire_type == 0:
        _read_varint(bytes, index)
        return
    if wire_type == 1:
        index["value"] = min(int(index["value"]) + 8, bytes.size())
        return
    if wire_type == 2:
        var size := int(_read_varint(bytes, index))
        index["value"] = min(int(index["value"]) + size, bytes.size())
        return
    if wire_type == 5:
        index["value"] = min(int(index["value"]) + 4, bytes.size())
        return
    index["value"] = bytes.size()
