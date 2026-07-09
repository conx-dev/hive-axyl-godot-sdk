# Hive Axyl Godot SDK

Hive Axyl Godot SDK is a Godot 4.x GDScript addon for game clients. It provides authentication, session persistence, notices, and mailbox APIs over Hive Axyl platform services.

## Requirements

- Godot 4.6 or higher
- GDScript
- Desktop targets for Google desktop sign-in

Payments and push APIs are not included in this release. Payment support is planned separately for Steam integration.

## Installation

### Git Submodule

Add the SDK directly into your Godot project's `addons` directory:

```bash
git submodule add https://github.com/conx-dev/hive-axyl-godot-sdk.git addons/hive_axyl
```

### Manual Copy

Copy this repository's `addons/hive_axyl` directory into your Godot project:

```text
your-godot-project/
  addons/
    hive_axyl/
      hive_axyl.gd
      hive_axyl_auth.gd
      ...
```

This SDK is a runtime GDScript addon, not an editor plugin. No plugin activation is required in Project Settings.

## Initialize

Create a `HiveAxyl` node, add it to the scene tree, configure it, and call `initialize()`.

```gdscript
extends Node

var hive: HiveAxyl

func _ready() -> void:
    hive = HiveAxyl.create_hive_axyl({
        "projectId": "PROJECT_ID",
        "apiKey": "CLIENT_API_KEY",
        "clientVersion": ProjectSettings.get_setting("application/config/version", "")
    })
    add_child(hive)

    var initialized := await hive.initialize()
    if not initialized:
        push_error(str(hive.last_error))
        return
```

## Configuration

| Option | Required | Description |
| --- | --- | --- |
| `projectId` or `project_id` | Yes | Hive Axyl project ID. |
| `apiKey` or `api_key` | Yes | Client API key issued for the project. |
| `gatewayUrl` or `gateway_url` | No | Discovery gateway URL. Empty values fall back to the SDK default gateway. |
| `clientVersion` or `client_version` | No | Client version reported during discovery. |
| `language` | No | Language code used for localized platform content. Defaults to `OS.get_locale_language()`. |
| `persistSession` or `persist_session` | No | Stores session tokens in `user://` by default. Set to `false` for in-memory storage. |
| `googleClientId` or `google_client_id` | No | Google OAuth desktop client ID. |
| `debug` | No | Enables SDK debug logging. |

## Authentication

Fetch enabled login providers before showing login UI:

```gdscript
var providers := await hive.auth.get_login_providers()
```

Supported auth entry points:

- `hive.auth.login_as_guest(device_id)`
- `hive.auth.login_with_google(id_token)`
- `hive.auth.login_with_google_desktop()`
- `hive.auth.restore_session()`
- `hive.auth.logout()`
- `hive.auth.current_player()`

OAuth tokens are obtained by your game through the platform provider SDKs. Hive Axyl SDK sends those tokens to the Hive Axyl server for validation.

## Notices and Mailbox

After `initialize()`, the same client exposes:

- `hive.notice` for active notices
- `hive.mailbox` for player mailbox operations

## Error Handling

APIs return dictionaries or `null`/`false` on failure. The latest structured error is available through `hive.last_error`, and `HiveAxyl.error_occurred` is emitted when errors are recorded.

```gdscript
var player := await hive.auth.login_as_guest(device_id)
if player.is_empty():
    var error := hive.last_error
    if error.get("code", "") == "PLAYER_BANNED":
        pass
```

## Release Policy

Use a fixed SDK version in production builds. Git releases are immutable tags, so fixes are released as new versions.

## License and Support

Use of this SDK is governed by the Hive Axyl license or service agreement for your project. For support, contact your Hive Axyl representative or support channel.
