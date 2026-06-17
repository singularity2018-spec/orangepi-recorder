#!/usr/bin/env bash
set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_FILE="${RECORDER_ENV_FILE:-/etc/orangepi-recorder/audio-recorder.env}"

if [ -r "${ENV_FILE}" ]; then
  # shellcheck source=/etc/orangepi-recorder/audio-recorder.env
  . "${ENV_FILE}"
fi

# shellcheck source=bin/recorder-common.sh
. "${SCRIPT_DIR}/recorder-common.sh"

status=0

print_check() {
  local state label detail
  state="$1"
  label="$2"
  detail="$3"
  printf '%-7s %s' "${state}" "${label}"
  if [ -n "${detail}" ]; then
    printf ' - %s' "${detail}"
  fi
  printf '\n'
}

check_command() {
  local name path version
  name="$1"
  path="$(command -v "${name}" 2>/dev/null || true)"
  if [ -n "${path}" ] && [ -x "${path}" ]; then
    version="$(${name} -version 2>/dev/null | head -n 1 || true)"
    if [ -z "${version}" ] && [ "${name}" = "arecord" ]; then
      version="$(${name} --version 2>/dev/null | head -n 1 || true)"
    fi
    print_check "OK" "${name} availability" "${path}${version:+ (${version})}"
  else
    print_check "FAIL" "${name} availability" "not found or not executable in PATH"
    status=1
  fi
}

check_command ffmpeg
check_command arecord

print_check "INFO" "configured ALSA device" "${AUDIO_DEVICE}"
if command_is_executable arecord && alsa_device_exists "${AUDIO_DEVICE}"; then
  print_check "OK" "ALSA device exists" "${AUDIO_DEVICE}"
else
  print_check \
    "FAIL" \
    "ALSA device exists" \
    "${AUDIO_DEVICE} was not found; run 'arecord -l' to list capture hardware"
  status=1
fi

if [ -d "${RECORDS_DIR}" ]; then
  print_check "OK" "RECORDS_DIR exists" "${RECORDS_DIR}"
else
  print_check "FAIL" "RECORDS_DIR exists" "${RECORDS_DIR} does not exist"
  status=1
fi

if [ -d "${RECORDS_DIR}" ] && [ -w "${RECORDS_DIR}" ]; then
  print_check \
    "OK" \
    "RECORDS_DIR writable" \
    "${RECORDS_DIR} is writable by $(id -un)"
else
  print_check \
    "FAIL" \
    "RECORDS_DIR writable" \
    "${RECORDS_DIR} is not writable by $(id -un)"
  status=1
fi

if [ -d "${RECORDS_DIR}" ]; then
  print_check \
    "INFO" \
    "free disk space" \
    "$(
      df -h "${RECORDS_DIR}" \
        | awk 'NR == 2 {print $4 " available on " $1 " (" $5 " used)"}'
    )"
else
  print_check "WARN" "free disk space" "cannot check because RECORDS_DIR does not exist"
fi

printf '\nCurrent recorder configuration%s:\n' "$(
  [ -r "${ENV_FILE}" ] \
    && printf ' (loaded %s)' "${ENV_FILE}" \
    || printf ' (using environment/defaults)'
)"
printf '  AUDIO_DEVICE=%s\n' "${AUDIO_DEVICE}"
printf '  RECORDS_DIR=%s\n' "${RECORDS_DIR}"
printf '  SEGMENT_SECONDS=%s\n' "${SEGMENT_SECONDS}"
printf '  OPUS_BITRATE=%s\n' "${OPUS_BITRATE}"
printf '  SAMPLE_RATE=%s\n' "${SAMPLE_RATE}"
printf '  CHANNELS=%s\n' "${CHANNELS}"
printf '  RECORDER_SERVICE=%s\n' "${RECORDER_SERVICE}"

printf '\nConfiguration validation:\n'
if validate_recorder_config; then
  print_check "OK" "recorder startup validation" "all required checks passed"
else
  print_check \
    "FAIL" \
    "recorder startup validation" \
    "fix the errors above before starting the service"
  status=1
fi

printf '\nSystemd service status:\n'
if command_is_executable systemctl; then
  if systemctl list-unit-files "${RECORDER_SERVICE}" >/dev/null 2>&1; then
    systemctl --no-pager --lines=0 status "${RECORDER_SERVICE}" || true
  else
    print_check "WARN" "${RECORDER_SERVICE}" "unit file is not installed"
  fi
else
  print_check \
    "WARN" \
    "systemd service status" \
    "systemctl is not available on this system"
fi

exit "${status}"
