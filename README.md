# orangepi-recorder

Orange Pi recorder is a small, hardware-focused recording project for an Orange Pi Zero2
running Armbian or Debian.

## Current status

This repository currently contains the first working audio-recorder core only. It is
intentionally simple so it can be tested on real hardware before adding more services.

Implemented now:

- Record audio from an ALSA USB audio device, default `hw:1,0`.
- Use `ffmpeg` to encode audio as Opus.
- Store recordings in daily directories under `/records/YYYY-MM-DD/`.
- Split recordings into configurable segments, default `1800` seconds.
- Write the active segment to a hidden `.opus.part` file.
- Rename the segment to a visible `.opus` file only after `ffmpeg` exits successfully.
- Keep failed `.opus.part` files for troubleshooting.
- Log all actions to stdout for systemd/journald.
- Handle SIGTERM gracefully by sending `q` to the active `ffmpeg` process stdin,
  with SIGTERM/SIGKILL used only as a timeout fallback.
- Validate recorder configuration before starting so production failures are clear and
  early.
- Provide a `bin/doctor.sh` diagnostics script for dependencies, ALSA device checks,
  storage checks, disk space, configuration, and systemd status.
- Provide example environment configuration and a systemd service for the `recorder`
  user.

Not implemented yet:

- Docker.
- Web UI.
- Video recording.
- Backup or archive synchronization.
- Remote access features.

## Files

- `bin/audio-recorder.sh` — recorder loop, startup validation, and `ffmpeg` invocation.
- `bin/recorder-common.sh` — shared validation and diagnostic helpers.
- `bin/doctor.sh` — production diagnostics for dependencies, ALSA, storage,
  configuration, and systemd status.
- `config/audio-recorder.env.example` — example configuration.
- `systemd/audio-recorder.service` — systemd unit for production use.
- `docs/install-audio-recorder.md` — installation and verification guide.

## Quick start

See [docs/install-audio-recorder.md](docs/install-audio-recorder.md) for step-by-step
installation instructions on Orange Pi Zero2. After configuring the environment file,
run `sudo -u recorder /opt/orangepi-recorder/bin/doctor.sh` to check the host before
enabling or restarting the service.
