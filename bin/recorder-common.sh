#!/usr/bin/env bash

: "${AUDIO_DEVICE:=hw:1,0}"
: "${RECORDS_DIR:=/records}"
: "${SEGMENT_SECONDS:=1800}"
: "${OPUS_BITRATE:=24k}"
: "${SAMPLE_RATE:=16000}"
: "${CHANNELS:=1}"
: "${RECORDER_SERVICE:=audio-recorder.service}"
: "${GRACEFUL_STOP_TIMEOUT_SECONDS:=15}"

log() {
  printf '%s %s\n' "$(date --iso-8601=seconds)" "$*"
}

request_stop() {
  stop_requested=1
  log "stop requested; requesting graceful ffmpeg shutdown"
  if declare -F recorder_request_ffmpeg_stop >/dev/null 2>&1; then
    recorder_request_ffmpeg_stop
  fi
}

is_positive_integer() {
  case "${1:-}" in
    ''|*[!0-9]*) return 1 ;;
  esac
  [ "$1" -gt 0 ] 2>/dev/null
}

command_is_executable() {
  local path
  path="$(command -v "$1" 2>/dev/null || true)"
  [ -n "${path}" ] && [ -x "${path}" ]
}

alsa_device_exists() {
  local device card pcm escaped_device
  device="$1"

  if ! command_is_executable arecord; then
    return 2
  fi

  case "${device}" in
    hw:[0-9]*,[0-9]*|plughw:[0-9]*,[0-9]*)
      card="${device#*:}"
      pcm="${card#*,}"
      card="${card%%,*}"
      case "${card}${pcm}" in
        *[!0-9]*|'') return 1 ;;
      esac
      arecord -l 2>/dev/null | awk -v card="${card}" -v pcm="${pcm}" '
        $1 == "card" && $2 == card ":" {
          for (i = 3; i <= NF; i++) {
            if ($i == "device" && $(i + 1) == pcm ":") found = 1
          }
        }
        END { exit(found ? 0 : 1) }
      '
      ;;
    *)
      escaped_device="$(printf '%s' "${device}" | sed 's/[][\\.^$*+?{}|()]/\\&/g')"
      arecord -L 2>/dev/null | awk -v device="${escaped_device}" 'BEGIN { pattern="^" device "([[:space:]]|$)" } $0 ~ pattern { found = 1 } END { exit(found ? 0 : 1) }'
      ;;
  esac
}

validate_recorder_config() {
  local errors=0

  if ! command_is_executable ffmpeg; then
    log "ERROR: ffmpeg was not found or is not executable. Install ffmpeg and make sure it is available in PATH before starting the recorder."
    errors=$((errors + 1))
  fi

  if ! command_is_executable arecord; then
    log "ERROR: arecord was not found or is not executable. Install alsa-utils so the recorder can verify ALSA capture devices."
    errors=$((errors + 1))
  elif ! alsa_device_exists "${AUDIO_DEVICE}"; then
    log "ERROR: ALSA capture device '${AUDIO_DEVICE}' was not found. Run 'arecord -l' to list hardware devices, then update AUDIO_DEVICE in the recorder configuration."
    errors=$((errors + 1))
  fi

  if [ ! -d "${RECORDS_DIR}" ]; then
    log "ERROR: RECORDS_DIR '${RECORDS_DIR}' does not exist. Create it and assign write permissions to the recorder user before starting."
    errors=$((errors + 1))
  elif [ ! -w "${RECORDS_DIR}" ]; then
    log "ERROR: RECORDS_DIR '${RECORDS_DIR}' is not writable by user '$(id -un)'. Fix ownership or permissions before starting."
    errors=$((errors + 1))
  fi

  if ! is_positive_integer "${SEGMENT_SECONDS}"; then
    log "ERROR: SEGMENT_SECONDS must be a positive integer number of seconds, got '${SEGMENT_SECONDS}'."
    errors=$((errors + 1))
  fi

  if ! is_positive_integer "${SAMPLE_RATE}"; then
    log "ERROR: SAMPLE_RATE must be a positive integer in Hz, got '${SAMPLE_RATE}'."
    errors=$((errors + 1))
  fi

  if ! is_positive_integer "${CHANNELS}"; then
    log "ERROR: CHANNELS must be a positive integer, got '${CHANNELS}'."
    errors=$((errors + 1))
  fi

  if ! is_positive_integer "${GRACEFUL_STOP_TIMEOUT_SECONDS}"; then
    log "ERROR: GRACEFUL_STOP_TIMEOUT_SECONDS must be a positive integer number of seconds, got '${GRACEFUL_STOP_TIMEOUT_SECONDS}'."
    errors=$((errors + 1))
  fi

  if [ "${errors}" -gt 0 ]; then
    log "ERROR: recorder configuration validation failed with ${errors} problem(s); refusing to start."
    return 2
  fi

  return 0
}
