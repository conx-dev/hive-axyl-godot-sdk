class_name HiveAxylMailbox
extends RefCounted

const Util := preload("res://addons/hive_axyl/hive_axyl_util.gd")

var hive


func _init(hive_client) -> void:
    hive = hive_client


func list_mail(page_size: int = 20, page_token: String = "", include_claimed: bool = false) -> Dictionary:
    var response = await hive._rpc(
        "mailbox",
        "MailboxService",
        "ListMail",
        {
            "page": {
                "pageSize": page_size,
                "pageToken": page_token
            },
            "includeClaimed": include_claimed
        },
        true
    )
    if typeof(response) != TYPE_DICTIONARY:
        return {
            "mail": [],
            "next_page_token": "",
            "total": "0"
        }

    var mail: Array = []
    for item in response.get("mail", []):
        mail.append(Util.map_mail(item, hive.language))

    var page: Dictionary = response.get("page", {})
    return {
        "mail": mail,
        "next_page_token": str(page.get("nextPageToken", "")),
        "total": str(page.get("total", "0"))
    }


func check_new_mail() -> Dictionary:
    var response = await hive._rpc(
        "mailbox",
        "MailboxService",
        "CheckNewMail",
        {},
        true
    )
    if typeof(response) != TYPE_DICTIONARY:
        return {
            "has_new_mail": false
        }

    return {
        "has_new_mail": bool(response.get("hasNewMail", false))
    }


func claim_mail(mail_id: String) -> Dictionary:
    if mail_id.is_empty():
        hive._set_error(Util.ERROR_INVALID_ARGUMENT, "mailId is required")
        return {}

    var response = await hive._rpc(
        "mailbox",
        "MailboxService",
        "ClaimMail",
        {
            "mailId": mail_id
        },
        true
    )
    if typeof(response) != TYPE_DICTIONARY:
        return {}
    if not response.has("mail"):
        hive._set_error(Util.ERROR_INTERNAL, "claim response missing mail")
        return {}

    return Util.map_mail(response["mail"], hive.language)
