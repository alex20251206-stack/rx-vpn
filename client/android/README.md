# RX VPN Android (minimal)

Reference direction: `ics-openvpn`.

Current scope:
- maintain subscription URLs
- show realtime link speed (device traffic)
- built-in `VpnService` start/stop skeleton (no external app dependency)
- native dependency loader for embedded `openvpn` + `stunnel`
- runtime flow: subscription fetch -> generate stunnel/openvpn config -> launch embedded binaries
- all Android app code is in `app/` (single standalone project layout)

Bundled arm64 binaries (already committed):
- `openvpn` from `openvpn_2.7.1_aarch64.deb` (Termux root repo)
- `stunnel` from `stunnel_5.78_aarch64.deb` (Termux main repo)

## Run

1. Open `client/android` in Android Studio.
2. Let Gradle sync.
3. Run `app` on device/emulator.

## Notes

- This phase removes runtime dependency on ICS OpenVPN / SSLDroid.
- Current VPN service validates embedded binaries and starts framework skeleton.
- Current service launches embedded binaries with generated configs under:
  - `/data/data/com.rxvpn.android/files/runtime/`
  - `client.ovpn`, `stunnel.conf`, `stunnel-ca.pem`, `client.log`
- Embedded runtime binaries are packaged via:
  - `app/src/main/jniLibs/arm64-v8a/libopenvpn.so`
  - `app/src/main/jniLibs/arm64-v8a/libstunnel.so`
- Runtime execute path:
  - `/data/app/.../lib/arm64/libopenvpn.so`
  - `/data/app/.../lib/arm64/libstunnel.so`
- Source package checksums:
  - `third_party/android/SHA256SUMS.txt`
  - `third_party/android/ASSET_SHA256SUMS.txt`
- Helper script:
  - `client/android/scripts/fetch-native-deps.sh`
  - Example:
    - `OPENVPN_URL=<url> STUNNEL_URL=<url> bash client/android/scripts/fetch-native-deps.sh`
- `client/android/app` contains the full app module source directly (no virtual module mapping).
