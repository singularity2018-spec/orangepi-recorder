# AGENTS.md

## Project overview

This is an Orange Pi Zero2 24/7 audio recorder project.
Reliability is more important than adding features quickly.

## Runtime paths

- `/opt/orangepi-recorder` — deployed application
- `/etc/orangepi-recorder` — production configuration
- `/records` — audio recordings
- `/var/lib/orangepi-recorder` — future state files

## Rules

- Keep recorder core simple.
- Prefer bash + systemd + ffmpeg for low-level recording.
- Do not add GUI, Docker, backup sync, or network features unless explicitly requested.
- Do not change recording format, file naming, or production paths without documenting the change.
- Preserve `.opus.part` safety behavior.

## Checks

Run after shell changes:

```sh
bash -n bin/*.sh tests/*.sh
./tests/audio-recorder-shutdown-test.sh

If available:
shellcheck bin/*.sh tests/*.sh
shfmt -d bin/*.sh tests/*.sh
systemd-analyze verify systemd/*.service
