#!/usr/bin/env bash
set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=bin/recorder-common.sh
. "${SCRIPT_DIR}/recorder-common.sh"

stop_requested=0
ffmpeg_pid=""
ffmpeg_stdin_fd=""
ffmpeg_stop_sent=0
ffmpeg_status=0

recorder_request_ffmpeg_stop() {
	if [ -z "${ffmpeg_pid:-}" ] || ! kill -0 "${ffmpeg_pid}" 2>/dev/null; then
		return 0
	fi

	if [ "${ffmpeg_stop_sent}" -eq 1 ]; then
		return 0
	fi

	if [ -n "${ffmpeg_stdin_fd:-}" ]; then
		# shellcheck disable=SC2261 # False positive: stdout goes to ffmpeg stdin FD; stderr goes to /dev/null.
		printf 'q\n' >&"${ffmpeg_stdin_fd}" 2>/dev/null || true
		ffmpeg_stop_sent=1
		log "sent q to ffmpeg stdin for graceful shutdown"
	else
		log "WARNING: ffmpeg stdin is not available; cannot send graceful shutdown command"
	fi
}

close_ffmpeg_stdin() {
	if [ -n "${ffmpeg_stdin_fd:-}" ]; then
		eval "exec ${ffmpeg_stdin_fd}>&-" 2>/dev/null || true
		ffmpeg_stdin_fd=""
	fi
}

wait_for_ffmpeg() {
	local status watchdog_pid

	while :; do
		wait "${ffmpeg_pid}"
		status=$?

		if [ "${stop_requested}" -eq 1 ] && [ "${status}" -ge 128 ]; then
			(
				sleep "${GRACEFUL_STOP_TIMEOUT_SECONDS}"
				if kill -0 "${ffmpeg_pid}" 2>/dev/null; then
					log \
						"WARNING: ffmpeg did not exit within ${GRACEFUL_STOP_TIMEOUT_SECONDS}s" \
						"after graceful stop request; sending SIGTERM"
					kill -TERM "${ffmpeg_pid}" 2>/dev/null || true
					sleep 2
					if kill -0 "${ffmpeg_pid}" 2>/dev/null; then
						log "WARNING: ffmpeg did not exit after SIGTERM; sending SIGKILL"
						kill -KILL "${ffmpeg_pid}" 2>/dev/null || true
					fi
				fi
			) &
			watchdog_pid=$!
			wait "${ffmpeg_pid}"
			status=$?
			kill "${watchdog_pid}" 2>/dev/null || true
			wait "${watchdog_pid}" 2>/dev/null || true
		fi

		ffmpeg_status="${status}"
		return 0
	done
}

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

	log \
		"starting segment: device=${AUDIO_DEVICE}" \
		"duration=${SEGMENT_SECONDS}s" \
		"output=${final_file}" \
		"temp=${part_file}"

	coproc FFMPEG_PROCESS {
		ffmpeg \
			-hide_banner \
			-loglevel info \
			-f alsa \
			-channels "${CHANNELS}" \
			-sample_rate "${SAMPLE_RATE}" \
			-i "${AUDIO_DEVICE}" \
			-t "${SEGMENT_SECONDS}" \
			-vn \
			-c:a libopus \
			-b:a "${OPUS_BITRATE}" \
			-application voip \
			-f opus \
			-y "${part_file}"
	}

	ffmpeg_pid="${FFMPEG_PROCESS_PID}"
	ffmpeg_stdin_fd="${FFMPEG_PROCESS[1]}"
	ffmpeg_stop_sent=0

	wait_for_ffmpeg
	status="${ffmpeg_status}"
	log "ffmpeg exit status: ${status}"
	close_ffmpeg_stdin
	ffmpeg_pid=""
	ffmpeg_stop_sent=0

	if [ "${status}" -eq 0 ]; then
		mv "${part_file}" "${final_file}"
		if [ "${stop_requested}" -eq 1 ]; then
			log "segment finalized after graceful stop: ${final_file}"
		else
			log "completed segment: ${final_file}"
		fi
		return 0
	fi

	log \
		"ERROR: ffmpeg exited with status ${status};" \
		"kept temp segment for troubleshooting: ${part_file}"
	return "${status}"
}

main() {
	trap request_stop TERM INT
	validate_recorder_config || exit $?

	log \
		"audio recorder starting: device=${AUDIO_DEVICE}" \
		"records_dir=${RECORDS_DIR}" \
		"segment_seconds=${SEGMENT_SECONDS}" \
		"bitrate=${OPUS_BITRATE}" \
		"sample_rate=${SAMPLE_RATE}" \
		"channels=${CHANNELS}" \
		"graceful_stop_timeout_seconds=${GRACEFUL_STOP_TIMEOUT_SECONDS}"

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
