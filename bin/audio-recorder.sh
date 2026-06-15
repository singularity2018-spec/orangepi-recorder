#!/usr/bin/env bash
set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=bin/recorder-common.sh
. "${SCRIPT_DIR}/recorder-common.sh"

stop_requested=0
ffmpeg_pid=""

record_segment() {
  local day segment_name day_dir final_file part_file status counter suffix

  day="$(date +%F)"
  segment_name="$(date +%Y-%m-%d_%H-%M-%S)"
  day_dir="${RECORDS_DIR}/${day}"

  mkdir -p "${day_dir}"

  counter=0
  while :; do
    if [ "${counter}" -eq 0 ]; then
      suffix=""
    else
      suffix="-${counter}"
    fi

    final_file="${day_dir}/${segment_name}${suffix}.opus"
    part_file="${day_dir}/.${segment_name}${suffix}.opus.part"

    if [ ! -e "${final_file}" ] && [ ! -e "${part_file}" ]; then
      break
    fi

    counter=$((counter + 1))
  done

  log "starting segment: device=${AUDIO_DEVICE} duration=${SEGMENT_SECONDS}s output=${final_file} temp=${part_file}"

  ffmpeg \
    -hide_banner \
    -nostdin \
    -loglevel info \
    -f alsa \
    -ac "${CHANNELS}" \
    -ar "${SAMPLE_RATE}" \
    -i "${AUDIO_DEVICE}" \
    -t "${SEGMENT_SECONDS}" \
    -vn \
    -c:a libopus \
    -b:a "${OPUS_BITRATE}" \
    -application voip \
    -f opus \
    -y "${part_file}" &

  ffmpeg_pid=$!
  wait "${ffmpeg_pid}"
  status=$?
  ffmpeg_pid=""

  if [ "${status}" -eq 0 ]; then
    mv "${part_file}" "${final_file}"
    log "completed segment: ${final_file}"
    return 0
  fi

  log "ERROR: ffmpeg exited with status ${status}; keeping temp file for troubleshooting: ${part_file}"
  return "${status}"
}

main() {
  trap request_stop TERM INT
  validate_recorder_config || exit $?

  log "audio recorder starting: device=${AUDIO_DEVICE} records_dir=${RECORDS_DIR} segment_seconds=${SEGMENT_SECONDS} bitrate=${OPUS_BITRATE} sample_rate=${SAMPLE_RATE} channels=${CHANNELS}"

  while [ "${stop_requested}" -eq 0 ]; do
    if ! record_segment; then
      if [ "${stop_requested}" -eq 1 ]; then
        break
      fi
      log "waiting 5 seconds before retry"
      sleep 5
    fi
  done

  log "audio recorder stopped"
}

main "$@"
