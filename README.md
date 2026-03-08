# OpenPS2000

Open-source Qt 6 / QML desktop application for controlling **EA PS 2000 B** laboratory power supplies over USB.

**Author:** Libor Tomsik, OK1CHP

---

## Features

- **Live monitoring** — voltage, current, power at 4 Hz via the USB virtual COM port
- **Full remote control** — set voltage, current, OVP threshold, OCP threshold
- **Output control** — output on/off, remote/manual mode switch, alarm acknowledgement
- **Live charts** — dual-axis voltage/current chart + power area chart, canvas-based scrolling
- **Zoom & pan** — scroll wheel to zoom, right-click drag to pan both charts
- **Range measurement** — drag to select a time window; shows mean/peak V/I/P, energy (Wh/mWh/mAh)
- **Energy counter** — cumulative energy integration with reset marker
- **CSV & Excel export** — session data with one click
- **Dark Material theme**
- **Cross-platform** — Linux (AppImage), Windows (zip), macOS (dmg)

---

## Downloads

Pre-built binaries are attached to each [GitHub Release](https://github.com/yeckel/OpenPS2000/releases).

| Platform | File |
|----------|------|
| Linux    | `OpenPS2000-linux-x86_64.AppImage` — `chmod +x`, then run |
| Windows  | `OpenPS2000-windows-x86_64.zip` — unzip, run `openps2000app.exe` |
| macOS    | `OpenPS2000-macos.dmg` — drag to Applications |

---

## Supported Hardware

| Property | Value |
|----------|-------|
| Device   | EA Elektro-Automatik PS 2000 B series |
| Tested   | EA-PS 2084-05 B (84 V / 5 A / 100 W) |
| Interface | USB → virtual COM port (VCP) |
| Baud rate | 115200, odd parity, 8N1 |
| OS port  | `/dev/ttyACM0` (Linux), `COMx` (Windows), `/dev/tty.usbmodem*` (macOS) |

> On Linux, add your user to the `dialout` group:
> ```bash
> sudo usermod -aG dialout $USER   # re-login after
> ```

---

## Protocol

Binary telegram protocol over the USB VCP.  
Reference documents in `doc/`:
- `ps2000b_programming.pdf` — telegram format, value conversion, workflow
- `object_list_ps2000b_de_en.pdf` — object list with all register definitions

Telegram structure: `SD DN OBJ [DATA…] CS_HI CS_LO`

Values are transmitted as percentages of nominal: `raw = 25600 × value / nominal`.

---

## Building from Source

### Requirements

- **Qt 6.7+** with: Core, Gui, Quick, QuickControls2, Qml, Widgets, **SerialPort**
- CMake 3.28+, C++20 compiler

Install Qt from the [Qt online installer](https://www.qt.io/download).  
`qtserialport` module is required (included in most Qt distributions).

### Build

```bash
cd app
cmake -B build -DCMAKE_BUILD_TYPE=Release .
cmake --build build --parallel
./build/bin/openps2000app
```

Linux with Qt in `/opt/Qt`:
```bash
cmake -B build -DCMAKE_BUILD_TYPE=Release \
      -DCMAKE_PREFIX_PATH=/opt/Qt/6.8.3/gcc_64 .
cmake --build build --parallel
```

---

## Usage

1. Connect the power supply via the USB cable
2. Launch **OpenPS2000**
3. Select the serial port (usually auto-detected as `/dev/ttyACM0`)
4. Click **▶ Connect** — device info is read automatically
5. Toggle **Remote** mode to enable remote control
6. Set desired voltage and current using the spinboxes
7. Click **Output ON** to enable the output

### Charts

- **Scroll wheel** — zoom in/out on the time axis
- **Right-click drag** — pan the time axis
- **Left-click drag** — select a time range for measurement (shows stats panel)
- **Double-click** — clear the selection

---

## Project Structure

```
OpenPS2000/
├── doc/                        EA protocol documentation PDFs
├── app/
│   ├── CMakeLists.txt
│   ├── main.cpp
│   ├── PS2000Protocol.h/cpp    Binary telegram encoder/decoder
│   ├── SerialTransport.h/cpp   QThread serial port worker (4 Hz polling)
│   ├── DeviceBackend.h/cpp     QML-exposed control backend
│   ├── DataRecord.h            Measurement sample struct
│   ├── XlsxWriter.h/cpp        OOXML .xlsx writer (no external deps)
│   ├── ZipWriter.h/cpp         STORE-only ZIP (used by XlsxWriter)
│   └── qml/
│       ├── Main.qml            Application window + controls
│       └── LiveChart.qml       Canvas-based scrolling chart
└── .github/workflows/
    └── build.yml               CI: Linux AppImage, Windows zip, macOS dmg
```

---

## License

[GNU General Public License v3.0](LICENSE) — see `LICENSE` for full terms.

Copyright © 2026 Libor Tomsik, OK1CHP
