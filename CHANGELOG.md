# Changelog

## 0.4.0

- Changed `login_as_guest(device_id)` to `login_as_guest()` and use an SDK-generated installation credential.
- Persisted the guest installation credential across logout without affecting identity-provider login.

## 0.3.0

- Added direct Apple identity-token login for Android, iOS, Web, and Desktop bridges.
- Added Apple desktop OAuth sign-in through the Hive Axyl auth server.
- Extended the desktop loopback callback server to receive Apple form POST callbacks without changing Google or Facebook query callbacks.

## 0.2.0

- Added automatic platform detection for Desktop, Android, iOS, and Web authentication requests.
- Added direct Facebook access-token login and Facebook desktop OAuth sign-in.
- Restricted desktop OAuth helpers to Desktop and shared their loopback callback handling.

## 0.1.0

- Initial public Godot addon release.
