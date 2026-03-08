# ⚡ OpenPS2000

Open-source **Qt 6 / QML / C++** desktop application for controlling
**EA Elektro-Automatik PS 2000 B** laboratory power supplies over USB.

**Author:** Libor Tomsik, OK1CHP  
**License:** [GNU GPL v3](LICENSE)

[![Build](https://github.com/yeckel/OpenPS2000/actions/workflows/build.yml/badge.svg)](https://github.com/yeckel/OpenPS2000/actions/workflows/build.yml)

---

| Monitor | Battery Charger |
|---------|----------------|
| ![Monitor tab](screenshots/01_main.png) | ![Charger tab](screenshots/02_charger.png) |

| Pulse Generator | Sequence Editor |
|----------------|----------------|
| ![Pulse tab](screenshots/03_pulse.png) | ![Sequence tab](screenshots/04_sequence.png) |

---

## Features

### Live Monitor Tab
- **Real-time measurements** — voltage, current, power at 4 Hz over USB
- **Live charts** — dual-axis V/I chart and power area chart with smooth scrolling
- **Zoom & pan** — scroll wheel to zoom the time axis, right-click drag to pan
- **Range statistics** — drag to select a time window; popup shows min/max/mean V/I/P,
  energy in Wh and charge in mAh for the selected interval
- **Energy counter** — cumulative energy integration with per-session reset
- **CSV & Excel export** — one-click export of the full session log

### Full Remote Control
- Set **voltage** and **current** setpoints with mouse-wheel-enabled spinboxes
- Set **OVP** (over-voltage) and **OCP** (over-current) protection limits
- **Output ON/OFF** toggle with keyboard shortcut
- **Remote / Manual** mode switch
- **Emergency stop** — large red button + `Space` key instantly cuts the output
- **Protection alarm popup** — OVP / OCP / OPP / OTP alarms detected automatically,
  shown in a modal dialog with clear descriptions and one-click acknowledgement

### Battery Charger Tab *(experimental)*
- **5 chemistries:** LiPo, LiFe, Pb, NiCd, NiMH
- **CC/CV** algorithm for Li-ion and lead-acid; **CC + −ΔV termination** for NiCd/NiMH
- **Float stage** for lead-acid batteries
- **Profile manager** — create, edit, delete named profiles; 8 built-in defaults
- **Live charging chart** — dual-axis voltage/current curve with phase markers
- **Session statistics** — capacity (mAh), energy (Wh), duration, min/max V/I
- **Safety limits** — maximum voltage, current, time enforced by the state machine

### Pulse / Cycle Generator Tab
Software-timed square-wave generator. ON phase uses the main-panel setpoint; OFF phase
can either hold a lower setpoint or fully disable the output.

| Parameter | Limit | Reason |
|-----------|-------|--------|
| Minimum ON or OFF time | **500 ms** | One command per transition; coalescing queue prevents pile-up |
| Maximum practical frequency | **≈ 1 Hz** (500 ms + 500 ms) | Output-only mode (disable during OFF) |
| Emergency stop latency | **≤ 250 ms** | Output-OFF is always prioritised; flushes any queued commands |

> **Note:** The PSU processes one USB command per ~250 ms. Commands are coalesced
> (a newer setpoint for the same object replaces any queued older one) so the queue
> never grows unbounded. Emergency stop (`Space`) always bypasses the queue.

### Sequence / Sweep Tab
Program a multi-step voltage/current profile and execute it on the PSU.

- **Step editor** — add, remove, reorder steps; each step has voltage, current,
  hold time, and an optional ramp (linear interpolation from the previous step)
- **Popup table editor** — edit the full sequence in a resizable dialog with
  tooltips on every column explaining each parameter
- **Import / Export** — CSV, XLSX (Excel), and ODS (LibreOffice Calc) supported;
  files saved by third-party apps are fully compatible
- **Named profiles** — save and reload multiple sequences by name;
  importing a file replaces any existing profile with the same name
- **Live execution** — real-time progress display; stops automatically on disconnect

### User Interface
- **Dark Material theme** throughout
- **Keyboard shortcuts:**

  | Action | Shortcut |
  |--------|----------|
  | Emergency stop | `Space` |
  | Power on (with confirmation) | `Space` (when off) |
  | Voltage up / down | `Ctrl+Up` / `Ctrl+Down` |
  | Current up / down | `Ctrl+Shift+Up` / `Ctrl+Shift+Down` |

- **Internationalization** — UI translated into 🇩🇪 German, 🇪🇸 Spanish, 🇨🇿 Czech,
  🇵🇱 Polish, 🇨🇳 Chinese (Simplified). Language persisted across restarts.
- **Port memory** — last used serial port saved and restored on startup
- **Disconnect detection** — USB cable removal detected within ~1 s; all running
  operations (charger, pulser, sequencer) stop automatically

---

## Downloads

Pre-built binaries are attached to each
[GitHub Release](https://github.com/yeckel/OpenPS2000/releases).

| Platform | File |
|----------|------|
| Linux    | `OpenPS2000-linux-x86_64.AppImage` — `chmod +x`, then run |
| Windows  | `OpenPS2000-windows-x86_64.zip` — unzip, run `openps2000app.exe` |
| macOS    | `OpenPS2000-macos.dmg` — drag to Applications |

---

## Supported Hardware

| Property | Value |
|----------|-------|
| Series   | EA Elektro-Automatik PS 2000 B |
| Tested   | EA-PS 2084-05 B (84 V / 5 A / 160 W) |
| Interface | USB → virtual COM port (VCP) |
| Baud rate | 115 200 bps, odd parity, 8 data bits |
| Linux port | `/dev/ttyACM0` |
| Windows port | `COMx` (check Device Manager) |
| macOS port | `/dev/tty.usbmodem*` |

> **Linux:** add your user to the `dialout` group, then re-login:
> ```bash
> sudo usermod -aG dialout $USER
> ```

---

## Protocol

Binary telegram protocol over the USB VCP as documented in `doc/`:

| Document | Contents |
|----------|----------|
| `ps2000b_programming.pdf` | Telegram framing, value scaling, workflow |
| `object_list_ps2000b_de_en.pdf` | Full object register list |

**Telegram format:** `SD DN OBJ [DATA…] CS_HI CS_LO`

Values are encoded as a fraction of the nominal rating:
`raw = 25600 × value / nominal`

---

## Building from Source

### Requirements

| Dependency | Version |
|------------|---------|
| Qt         | 6.7 or newer (Core, Gui, Quick, QuickControls2, SerialPort) |
| CMake      | 3.28+ |
| Compiler   | C++20 (GCC 12+, Clang 15+, MSVC 2022) |
| zlib       | system zlib (for XLSX/ODS import) |

On Debian/Ubuntu: `sudo apt install zlib1g-dev`

Install Qt from the [Qt online installer](https://www.qt.io/download) or your
distribution's package manager.

### Clone and build

```bash
git clone https://github.com/yeckel/OpenPS2000.git
cd OpenPS2000
cmake -B build -DCMAKE_BUILD_TYPE=Release app
cmake --build build --parallel
./build/bin/openps2000app
```

If Qt is installed in a non-standard location (e.g. `/opt/Qt`):

```bash
cmake -B build -DCMAKE_BUILD_TYPE=Release \
      -DCMAKE_PREFIX_PATH=/opt/Qt/6.9.2/gcc_64 app
```

---

## Quick Start

1. Connect the PS 2000 B via USB
2. Launch **OpenPS2000**
3. Select the serial port (auto-detected if only one VCP is present)
4. Click **▶ Connect** — model name, nominal voltage/current are read back
5. Enable **Remote** mode
6. Set voltage and current (spinboxes or `Ctrl+↑/↓`)
7. Press `Space` or click **Output ON**

---

## Project Structure

```
OpenPS2000/
├── doc/                          EA protocol documentation (PDFs)
├── screenshots/                  Application screenshots
├── app/
│   ├── CMakeLists.txt
│   ├── main.cpp                  App entry point, engine setup, i18n, wiring
│   ├── PS2000Protocol.h/cpp      Binary telegram encoder/decoder
│   ├── SerialTransport.h/cpp     QThread serial worker (4 Hz polling, disconnect detection)
│   ├── DeviceBackend.h/cpp       QML-exposed device control + alarm detection
│   ├── DataRecord.h              Measurement sample struct
│   ├── BatteryProfile.h/cpp      Charging profile definitions + JSON storage
│   ├── ChargerEngine.h/cpp       CC/CV/Float/−ΔV charging state machine
│   ├── SequenceProfile.h/cpp     Sequence profile storage + CSV/XLSX/ODS import/export
│   ├── SequencerEngine.h/cpp     Step-by-step voltage/current sequence executor
│   ├── XlsxWriter.h/cpp          OOXML .xlsx writer (zero external dependencies)
│   ├── OdsWriter.h/cpp           ODF Spreadsheet .ods writer
│   ├── ZipWriter.h/cpp           STORE-only ZIP (used by XlsxWriter + OdsWriter)
│   ├── ZipReader.h/cpp           ZIP reader (stored + deflate; reads LibreOffice/Excel files)
│   └── qml/
│       ├── Main.qml              Main window, toolbar, controls, alarm popup
│       ├── LiveChart.qml         Canvas scrolling dual-axis chart
│       ├── ChargerTab.qml        Battery charger UI tab
│       ├── ChargingChart.qml     Charging curve canvas chart
│       ├── SequenceTab.qml       Sequence management panel
│       └── SequenceEditorDialog.qml  Popup table editor with import/export
└── .github/workflows/
    └── build.yml                 CI: Linux AppImage · Windows zip · macOS dmg
```

---

## Battery Charger Safety

> ⚠️ **The battery charging feature is experimental.**
>
> Always supervise charging sessions. Never leave batteries unattended.
> Use proper fusing and fire-resistant containers.
> The author accepts **no liability** for damage caused by use of this software.

---

## Contributing

Pull requests are welcome. Please open an issue first to discuss what you would
like to change.

---

## License

[GNU General Public License v3.0](LICENSE)

Copyright © 2026 Libor Tomsik, OK1CHP
