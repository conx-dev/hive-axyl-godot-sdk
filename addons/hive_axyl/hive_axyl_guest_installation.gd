class_name HiveAxylGuestInstallation
extends RefCounted

const Util := preload("res://addons/hive_axyl/hive_axyl_util.gd")
const PATH := "user://hive_ng_installation.cfg"
const SECTION := "installation"
const KEY := "hive-ng.device.id"


func get_or_create_credential() -> String:
    var config := ConfigFile.new()
    var load_error := config.load(PATH)
    if load_error == OK:
        var existing := str(config.get_value(SECTION, KEY, ""))
        if _is_credential(existing):
            return existing
    elif load_error != ERR_FILE_NOT_FOUND:
        return ""

    var crypto := Crypto.new()
    var random := crypto.generate_random_bytes(32)
    if random.size() != 32:
        return ""
    var credential := "g1_" + Util.base64_url(random)
    config.set_value(SECTION, KEY, credential)
    var save_error := config.save(PATH)
    if save_error != OK:
        return ""

    var persisted := ConfigFile.new()
    if persisted.load(PATH) != OK:
        return ""
    if str(persisted.get_value(SECTION, KEY, "")) != credential:
        return ""
    return credential


func _is_credential(value: String) -> bool:
    if value.length() != 46 or not value.begins_with("g1_"):
        return false
    var encoded := value.substr(3)
    var standard := encoded.replace("-", "+").replace("_", "/") + "="
    var decoded := Marshalls.base64_to_raw(standard)
    if decoded.size() != 32:
        return false
    return Util.base64_url(decoded) == encoded
