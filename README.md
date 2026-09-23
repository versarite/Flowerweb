# FlowerWeb
# Written with support from CatGPT and Claude


A small web-controlled watering system for a Raspberry Pi. Open the web page from anywhere (for example over Tailscale), watch your plants on a live camera, water them with one click, or let a timer do it every 24, 48 or 72 hours.

The server is written in Free Pascal / Lazarus and runs as a systemd service. The camera stream is served by [MediaMTX](https://github.com/bluenviron/mediamtx).

## Features

- **Manual watering:** opens the valve for a set time (1–60 s by default)
- **Automatic watering:** every 24, 48 or 72 hours. The schedule survives restarts, and a watering missed while the Pi was off runs when it comes back.
- **Live camera:** a WebRTC stream from a USB webcam or the Raspberry Pi camera
- **Status:** shows the Pi's IP address, CPU temperature, next watering time and a countdown while watering
- **Remote reboot** from the web page
- **Safe valve handling:** the valve is closed at startup, at shutdown, when the service crashes and before a reboot, and the server enforces a maximum opening time

## Hardware

| Part | Notes |
|---|---|
| Raspberry Pi | Any model with GPIO. Uses `pinctrl` (Pi 5 / Bookworm) or `raspi-gpio` (older models) |
| Relay module | Signal on **GPIO 18** by default. Active-high and active-low boards are both supported (`ActiveLow` in the ini) |
| Water valve or pump | Switched by the relay. Use a separate power supply that suits the valve |
| Camera | USB webcam (`/dev/video0`) or Raspberry Pi camera module |

A ready-made **Raspberry Pi HAT** for all of this is in [`hardware/kicad`](hardware/kicad/README.md). It has a 5 V 6 A input jack, a 24 V step-up module, a TIP121 valve driver on GPIO 18, a 24 V valve jack and a status-LED header.

> ⚠️ The relay switches the valve's supply, not mains power. If your valve or pump runs on mains voltage, use a suitably rated relay and have the wiring checked by someone qualified.

The KiCAD board is not routed. It is meant as a suggestion.  

## Project layout

```
flowerweb/
├── src/        Pascal source (Lazarus project flowerweb.lpi)
│   ├── flowerweb.lpr   program start, HTTP routes
│   ├── uconfig.pas     reads/writes config/flowerweb.ini
│   ├── uRelay.pas      valve control and watering timer
│   ├── uapi.pas        REST API
│   ├── uwebfiles.pas   serves the web page
│   ├── usysinfo.pas    CPU temperature and IP address
│   └── ulog.pas        logging
├── web/        index.html, app.js, style.css
├── config/     flowerweb.ini, mediamtx.yml (USB camera), mediamtx.yml_rpicam (Pi camera)
├── systemd/    flowerweb.service, mediamtx.service
├── scripts/    deploy.sh (build and install on the Pi), reset.sh (Wi-Fi watchdog)
├── hardware/   kicad/: FlowerWeb HAT schematic, board layout and BOM (see its README)
└── docs/       notes and command reference
```

On the Pi everything lives in `/home/flowerweb`, and the compiled program goes in `/home/flowerweb/bin`.

## Installation on the Raspberry Pi

1. **Install Lazarus** (for `lazbuild`) and create the folders:

   ```bash
   sudo apt install lazarus
   sudo mkdir -p /home/flowerweb/bin
   sudo chown -R pi:pi /home/flowerweb
   ```

2. **Install MediaMTX** for the camera. Download the ARM build from the [MediaMTX releases](https://github.com/bluenviron/mediamtx/releases) and put `mediamtx` in `/home/flowerweb/bin`. Copy the config that matches your camera:

   ```bash
   cp config/mediamtx.yml        /home/flowerweb/bin/mediamtx.yml   # USB webcam (needs ffmpeg)
   # or
   cp config/mediamtx.yml_rpicam /home/flowerweb/bin/mediamtx.yml   # Pi camera module
   ```

3. **Allow the service commands without a password** (`sudo visudo -f /etc/sudoers.d/flowerweb`):

   ```
   pi ALL=(root) NOPASSWD: /usr/sbin/reboot, /usr/bin/systemctl
   ```

4. **Install the services:**

   ```bash
   sudo cp /home/flowerweb/systemd/*.service /etc/systemd/system/
   sudo systemctl daemon-reload
   sudo systemctl enable --now mediamtx flowerweb
   ```

## Building and deploying

Development happens on a PC. `scripts/deploy.sh` copies the source to the Pi over SSH, compiles it there with `lazbuild`, installs it and restarts the service:

```bash
./scripts/deploy.sh
```

Set `PI_HOST` in the script to your Pi's address. Password-free SSH login is described in `docs/`.

The Pi's `config/flowerweb.ini` is copied only the first time. After that, deploy leaves it alone so the settings you made from the web page are kept.

## Configuration

`config/flowerweb.ini`:

| Section | Key | Default | Meaning |
|---|---|---|---|
| Server | `Name` | FlowerWeb | Title shown on the web page |
| Server | `Port` | 8080 | HTTP port |
| Relay | `Pin` | 18 | GPIO pin for the relay |
| Relay | `ActiveLow` | 0 | `1` if the relay switches on when the pin is LOW |
| Relay | `PulseTimeMS` | 5000 | Valve opening time (set from the web page) |
| Relay | `MaxPulseTimeMS` | 60000 | Longest allowed opening time |
| Relay | `TimerInterval` | 0 | Hours between automatic waterings, `0` = off (set from the web page) |
| Relay | `NextWatering` | | Written by FlowerWeb. Next scheduled watering |
| Camera | `Name` / `Port` | cam / 8889 | MediaMTX path and WebRTC port |
| Logging | `Level` | INFO | `INFO` or `ERROR` |

Logs are written to `/home/flowerweb/logs/flowerweb.log`, which rolls over at 1 MB.

## Remote access

FlowerWeb has **no login**, so anyone who can reach port 8080 can water the plants and reboot the Pi. Keep it on your local network and reach it from outside through a VPN such as [Tailscale](https://tailscale.com). Don't forward the port to the internet.

Then open `http://<pi-address>:8080` in a browser.

## API

| Method | Path | Body | Description |
|---|---|---|---|
| GET | `/api/status` | | Status JSON (IP, temperature, timer, watering state, …) |
| POST | `/api/trigger` | `{"pulseTimeMS": 5000}` (optional) | Start watering. Returns `409` if already watering |
| POST | `/api/timer` | `{"timerInterval": 24}` | Set the automatic interval in hours (`0` = off) |
| POST | `/api/reboot` | | Close the valve and reboot the Pi |

Close the valve by hand at any time:

```bash
/home/flowerweb/bin/flowerweb --relay-off
```

## License

FlowerWeb is released under the [PolyForm Noncommercial License 1.0.0](LICENSE.md). You're free to use, study, change and share it for any **non-commercial** purpose: personal projects, hobby use, education, research, and charitable or public organisations. Commercial use is not permitted without the author's permission.

Copyright (c) 2026 DL1BWA