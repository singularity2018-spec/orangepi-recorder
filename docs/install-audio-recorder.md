# Install the audio recorder on Orange Pi Zero2

These steps install the first audio-only recorder version on an Orange Pi Zero2 running
Armbian or Debian. The recorder uses an ALSA USB audio device and `ffmpeg` to write Opus
segments under `/records/YYYY-MM-DD/`.

## 1. Install packages

```sh
sudo apt update
sudo apt install -y ffmpeg alsa-utils git
```

## 2. Create the recorder user and storage directory

```sh
if ! getent group recorder >/dev/null; then
  sudo groupadd --system recorder
fi

if ! id -u recorder >/dev/null 2>&1; then
  sudo useradd --system --create-home --shell /usr/sbin/nologin --gid recorder recorder
fi

sudo usermod -aG audio recorder
sudo mkdir -p /records
sudo chown recorder:recorder /records
```

If `/records` is a separate disk or partition, mount it before starting the service and
keep ownership assigned to `recorder`.

## 3. Find the USB audio device

Plug in the USB audio adapter, then list capture devices:

```sh
arecord -l
```

The default configuration uses `hw:1,0`. If your adapter appears as another card/device
pair, set `AUDIO_DEVICE` accordingly in the environment file below.

You can test capture manually before enabling the service:

```sh
sudo -u recorder ffmpeg \
  -f alsa \
  -channels 1 \
  -sample_rate 16000 \
  -i hw:1,0 \
  -t 10 \
  -c:a libopus \
  -b:a 24k \
  /records/test.opus
```

## 4. Install the project files

Clone or copy this repository to `/opt/orangepi-recorder`:

```sh
sudo git clone \
  https://github.com/singularity2018-spec/orangepi-recorder.git \
  /opt/orangepi-recorder
sudo chown -R root:root /opt/orangepi-recorder
sudo chmod +x \
  /opt/orangepi-recorder/bin/audio-recorder.sh \
  /opt/orangepi-recorder/bin/doctor.sh \
  /opt/orangepi-recorder/bin/recorder-common.sh
```

## 5. Configure the recorder

```sh
sudo mkdir -p /etc/orangepi-recorder
sudo cp \
  /opt/orangepi-recorder/config/audio-recorder.env.example \
  /etc/orangepi-recorder/audio-recorder.env
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
GRACEFUL_STOP_TIMEOUT_SECONDS=15
```

`SEGMENT_SECONDS=1800` creates 30-minute files. `GRACEFUL_STOP_TIMEOUT_SECONDS=15` gives
`ffmpeg` 15 seconds to finalize after the recorder sends `q` to stdin during service
stop. `SEGMENT_SECONDS`, `SAMPLE_RATE`, `CHANNELS`, and `GRACEFUL_STOP_TIMEOUT_SECONDS`
must be positive integers. Before recording starts, the recorder validates that `ffmpeg`
and `arecord` are executable, the configured ALSA device exists, and `RECORDS_DIR`
exists and is writable. During recording the current file is hidden and ends with
`.opus.part`; after `ffmpeg` exits successfully it is renamed to a visible `.opus` file.
If `ffmpeg` fails, the `.part` file is kept for troubleshooting.

## 6. Run diagnostics before starting

Use the doctor script after editing the environment file and any time hardware, storage,
or service configuration changes:

```sh
sudo -u recorder /opt/orangepi-recorder/bin/doctor.sh
```

The doctor reports `ffmpeg` and `arecord` availability, the configured ALSA device,
whether that device exists, whether `RECORDS_DIR` exists and is writable, free disk
space, the current recorder configuration, and systemd service status. If
`/etc/orangepi-recorder/audio-recorder.env` is readable, the doctor loads it
automatically; set `RECORDER_ENV_FILE=/path/to/file` to check a different environment
file.

Fix any `FAIL` lines before enabling or restarting the recorder.

## 7. Install and start the systemd service

```sh
sudo cp \
  /opt/orangepi-recorder/systemd/audio-recorder.service \
  /etc/systemd/system/audio-recorder.service
sudo systemctl daemon-reload
sudo systemctl enable --now audio-recorder.service
```

## 8. Watch logs and verify output

All recorder logs go to stdout, so systemd stores them in journald:

```sh
journalctl -u audio-recorder.service -f
```

Check created files:

```sh
find /records -type f \( -name '*.opus' -o -name '*.opus.part' \)
```

## 9. Stop or restart

```sh
sudo systemctl stop audio-recorder.service
sudo systemctl restart audio-recorder.service
```

The service sends SIGTERM to the recorder script on stop. The script does not forward
SIGTERM to `ffmpeg` during normal shutdown; it sends `q` to the active `ffmpeg` process
stdin, waits up to `GRACEFUL_STOP_TIMEOUT_SECONDS` for container finalization, and only
then falls back to SIGTERM/SIGKILL if needed. The same finalization rule applies as
normal segment completion: status `0` is renamed from hidden `.opus.part` to visible
`.opus`, while any non-zero status keeps the `.opus.part` file for troubleshooting. The
journal logs the stop request, the `q` command, the `ffmpeg` exit status, and whether
the segment was finalized or kept.
