# Install the audio recorder on Orange Pi Zero2

These steps install the first audio-only recorder version on an Orange Pi Zero2 running Armbian or Debian. The recorder uses an ALSA USB audio device and `ffmpeg` to write Opus segments under `/records/YYYY-MM-DD/`.

## 1. Install packages

```sh
sudo apt update
sudo apt install -y ffmpeg alsa-utils git
```

## 2. Create the recorder user and storage directory

```sh
sudo useradd --system --create-home --shell /usr/sbin/nologin recorder
sudo mkdir -p /records
sudo chown recorder:recorder /records
```

If `/records` is a separate disk or partition, mount it before starting the service and keep ownership assigned to `recorder`.

## 3. Find the USB audio device

Plug in the USB audio adapter, then list capture devices:

```sh
arecord -l
```

The default configuration uses `hw:1,0`. If your adapter appears as another card/device pair, set `AUDIO_DEVICE` accordingly in the environment file below.

You can test capture manually before enabling the service:

```sh
sudo -u recorder ffmpeg -f alsa -channels 1 -sample_rate 16000 -i hw:1,0 -t 10 -c:a libopus -b:a 24k /records/test.opus
```

## 4. Install the project files

Clone or copy this repository to `/opt/orangepi-recorder`:

```sh
sudo git clone <repository-url> /opt/orangepi-recorder
sudo chown -R root:root /opt/orangepi-recorder
sudo chmod +x /opt/orangepi-recorder/bin/audio-recorder.sh
```

## 5. Configure the recorder

```sh
sudo mkdir -p /etc/orangepi-recorder
sudo cp /opt/orangepi-recorder/config/audio-recorder.env.example /etc/orangepi-recorder/audio-recorder.env
sudo nano /etc/orangepi-recorder/audio-recorder.env
```

Available settings:

```sh
AUDIO_DEVICE=hw:1,0
RECORDS_DIR=/records
SEGMENT_SECONDS=1800
OPUS_BITRATE=24k
SAMPLE_RATE=16000
CHANNELS=1
```

`SEGMENT_SECONDS=1800` creates 30-minute files. During recording the current file is hidden and ends with `.opus.part`; after `ffmpeg` exits successfully it is renamed to a visible `.opus` file. If `ffmpeg` fails, the `.part` file is kept for troubleshooting.

## 6. Install and start the systemd service

```sh
sudo cp /opt/orangepi-recorder/systemd/audio-recorder.service /etc/systemd/system/audio-recorder.service
sudo systemctl daemon-reload
sudo systemctl enable --now audio-recorder.service
```

## 7. Watch logs and verify output

All recorder logs go to stdout, so systemd stores them in journald:

```sh
journalctl -u audio-recorder.service -f
```

Check created files:

```sh
find /records -type f \( -name '*.opus' -o -name '*.opus.part' \)
```

## 8. Stop or restart

```sh
sudo systemctl stop audio-recorder.service
sudo systemctl restart audio-recorder.service
```

The service sends SIGTERM on stop. The script forwards SIGTERM to the active `ffmpeg` process and then exits cleanly.
