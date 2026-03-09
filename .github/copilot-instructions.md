# OpenPS2000 — Copilot Agent Instructions

## Project Summary
Qt 6.7+ / QML / C++20 desktop app for controlling **EA Elektro-Automatik PS 2000 B**
laboratory power supplies. Targets Linux, Windows, macOS. License: GPL-3.0.
Author: Libor Tomsik, OK1CHP (`git@github.com:yeckel/OpenPS2000.git`).

## Build System
```bash
# Configure (Qt at /opt/Qt/6.9.2/gcc_64 on the dev machine)
cmake -B build -DCMAKE_BUILD_TYPE=Release \
      -DCMAKE_PREFIX_PATH=/opt/Qt/6.9.2/gcc_64 app

# Build
cmake --build build --parallel

# Run
./build/bin/openps2000app
# Remote client mode:
./build/bin/openps2000app --remote 192.168.1.10
```

CI: `.github/workflows/build.yml` — produces Linux AppImage, Windows zip, macOS dmg
via `jurplel/install-qt-action@v4` with `modules: 'qtserialport qtmqtt'`.

## Architecture Overview

### Backend split
| Class | Role |
|-------|------|
| `DeviceBackend` | Local USB backend; QML context property `backend` |
| `RemoteBackend` | REST polling client; same Q_PROPERTYs/signals as `DeviceBackend` |

In `main.cpp`, **exactly one** backend is created depending on `--remote` flag or
auto-detect probe (`GET http://127.0.0.1:8484/api/v1/info`, 800 ms timeout).
Both are registered as `backend` context property — QML uses `backend` everywhere.

### Engines (always created, wired to whichever backend is active)
| Object | Context property | Description |
|--------|-----------------|-------------|
| `ChargerEngine` | `charger` | CC/CV/Float/−ΔV battery charging state machine |
| `PulseEngine` | `pulser` | Software-timed pulse/cycle generator |
| `SequenceEngine` | `sequencer` | Multi-step V/I sequence executor |
| `SequenceStore` | `seqStore` | Named profile storage (JSON, QSettings) |

Wiring pattern in `main.cpp`:
```cpp
if (localBackend) {
    QObject::connect(pulser, &PulseEngine::setVoltageRequested,
                     localBackend, &DeviceBackend::sendSetVoltage);
    // ...
} else if (remoteBackend) {
    QObject::connect(pulser, &PulseEngine::setVoltageRequested,
                     remoteBackend, &RemoteBackend::sendSetVoltage);
    // ...
}
```
**Always wire BOTH backends** when adding new engine signal connections.

### Remote stack
- `RemoteServer` — QTcpServer-based HTTP/1.1 server (no optional Qt modules).
  Routes defined in `RemoteServer.cpp`. Auth via Bearer token.
- `MqttClient` — wraps Qt6::Mqtt, entire implementation behind `#ifdef HAVE_QT_MQTT`.
- `TrayManager` — system tray icon, `minimizeToTray` backed by QSettings.

### Serial transport
`SerialTransport` runs in a `QThread`. Poll timer at 4 Hz sends
`GET_OBJECT` for voltage, current, output state. Commands go into a
coalescing queue: newer command for same object replaces queued one.
`enqueueUrgent()` bypasses the queue (used for emergency output-OFF).

### Protocol
`PS2000Protocol.h` encodes/decodes binary telegrams:
`SD DN OBJ [DATA…] CS_HI CS_LO` (see `doc/ps2000b_programming.pdf`).
Values are fractions of nominal: `raw = 25600 × value / nominal`.

## QML Conventions
- All QML files in `app/qml/`; registered via `qt_add_qml_module`.
- Context properties (set in `main.cpp`):
  `backend`, `charger`, `pulser`, `sequencer`, `seqStore`,
  `remoteServer`, `mqttClient`, `trayManager`, `langChanger`
- **Do NOT use `required property`** for context properties — causes binding loops.
  Access them directly by name instead.
- Dark Material theme throughout (`Material.theme: Material.Dark`).
- Charts are Canvas-based (no QtCharts dependency): `LiveChart.qml`,
  `ChargingChart.qml`, `PulseChart.qml`, `SequenceChart.qml`.
- Timestamps in charts are **session-relative seconds** (not Unix epoch).
  `DeviceBackend` emits `t = nowSecs() - m_startTime`.
  `RemoteBackend` mirrors this with its own `m_startTime` captured on first poll.

## Key Files
| File | Notes |
|------|-------|
| `app/main.cpp` | Entry point; `normalizeUrl()`, auto-detect probe, engine wiring |
| `app/DeviceBackend.h/cpp` | Q_PROPERTYs exposed to QML: `connected`, `voltage`, `current`, `power`, `setVoltage`, `setCurrent`, `outputOn`, `remoteMode`, `nominalVoltage`, `nominalCurrent`, etc. |
| `app/RemoteBackend.h/cpp` | Mirrors DeviceBackend interface; polls `/api/v1/status` every 500 ms |
| `app/RemoteServer.h/cpp` | Lightweight HTTP/1.1 server; `HttpConn` struct per socket for incremental parsing |
| `app/PulseEngine.h/cpp` | States: `Idle=0, OnPhase=1, OffPhase=2, Done=3`; emits `setVoltageRequested`, `setCurrentRequested`, `setOutputQueuedRequested` |
| `app/qml/Main.qml` | Main window; status bar shows REST/MQTT indicators; `isRemoteMode` controls REMOTE badge |
| `app/qml/RemoteSettingsPanel.qml` | Settings stored via `Settings { category: "remote" }`; ports as `property string` not int |

## Settings Keys (QSettings)
| Key | Default | Description |
|-----|---------|-------------|
| `remote/restEnabled` | false | REST server auto-start |
| `remote/restPort` | "8484" | REST server port (string) |
| `remote/restToken` | "" | Bearer token (empty = no auth) |
| `remote/mqttEnabled` | false | MQTT client auto-start |
| `remote/mqttHost` | "localhost" | MQTT broker host |
| `remote/mqttPort` | "1883" | MQTT broker port (string) |
| `remote/mqttPrefix` | "openps2000" | MQTT topic prefix |
| `tray/minimizeToTray` | false | Hide to tray on close |
| `serial/port` | "" | Last used serial port |

## CI / Dependencies
- Qt modules required: `Core Gui Quick QuickControls2 SerialPort Network`
- Qt modules optional: `Mqtt` (guarded by `#ifdef HAVE_QT_MQTT`)
- Zlib: `find_package(ZLIB QUIET)` with fallback to `Qt6::ZlibPrivate` (Windows CI)
- No external libraries; XLSX/ODS writers are custom (zero dependencies)

## Hardware
- **Tested device:** EA-PS 2084-05 B (84 V / 5 A / 160 W)
- **Linux port:** `/dev/ttyACM0` — user must be in `dialout` group
- **Protocol docs:** `doc/ps2000b_programming.pdf`, `doc/object_list_ps2000b_de_en.pdf`

## Planned / Next
- **Android app** — Qt Quick / QML app using the REST API (`RemoteBackend`)
  to connect to a desktop instance running as server. No USB access needed on mobile.
- Target: same `RemoteBackend` C++ class reused in the Android build, or
  a Kotlin/Flutter app calling the same REST endpoints.

## Git Commit Convention
Always append trailer:
```
Co-authored-by: Copilot <223556219+Copilot@users.noreply.github.com>
```
