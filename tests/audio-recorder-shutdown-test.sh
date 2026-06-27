#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
tmp_dir="$(mktemp -d)"
cleanup() {
	if [ -n "${recorder_pid:-}" ] && kill -0 "${recorder_pid}" 2>/dev/null; then
		kill -TERM "${recorder_pid}" 2>/dev/null || true
		wait "${recorder_pid}" 2>/dev/null || true
	fi
	rm -rf "${tmp_dir}"
}
trap cleanup EXIT

fake_bin="${tmp_dir}/bin"
records_dir="${tmp_dir}/records"
mkdir -p "${fake_bin}" "${records_dir}"

cat > "${fake_bin}/arecord" <<'FAKE_ARECORD'
#!/usr/bin/env bash
if [ "${1:-}" = "-l" ]; then
	printf 'card 1: Dummy [Dummy], device 0: Dummy PCM [Dummy PCM]\n'
	exit 0
fi
if [ "${1:-}" = "-L" ]; then
	printf 'hw:1,0\n'
	exit 0
fi
exit 0
FAKE_ARECORD
chmod +x "${fake_bin}/arecord"

cat > "${fake_bin}/ffmpeg" <<'FAKE_FFMPEG'
#!/usr/bin/env bash
out="${@: -1}"
printf 'partial opus data\n' > "${out}"
trap 'exit 255' TERM INT
while IFS= read -r command; do
	if [ "${command}" = "q" ]; then
		# Simulate ffmpeg finalizing the container only after the normal stdin quit command.
		printf 'finalized\n' >> "${out}"
		exit 0
	fi
done
exit 1
FAKE_FFMPEG
chmod +x "${fake_bin}/ffmpeg"

PATH="${fake_bin}:${PATH}" \
AUDIO_DEVICE="hw:1,0" \
RECORDS_DIR="${records_dir}" \
SEGMENT_SECONDS=3600 \
OPUS_BITRATE=24k \
SAMPLE_RATE=16000 \
CHANNELS=1 \
GRACEFUL_STOP_TIMEOUT_SECONDS=15 \
"${repo_root}/bin/audio-recorder.sh" > "${tmp_dir}/recorder.log" 2>&1 &
recorder_pid=$!

part_file=""
for _ in {1..50}; do
	part_file="$(find "${records_dir}" -type f -name '*.opus.part' -print -quit)"
	if [ -n "${part_file}" ]; then
		break
	fi
	sleep 0.1
done

if [ -z "${part_file}" ]; then
	echo "did not observe active .opus.part file" >&2
	cat "${tmp_dir}/recorder.log" >&2 || true
	exit 1
fi

kill -TERM "${recorder_pid}"
wait "${recorder_pid}"
recorder_pid=""

final_file="$(find "${records_dir}" -type f -name '*.opus' -print -quit)"
remaining_part="$(find "${records_dir}" -type f -name '*.opus.part' -print -quit)"

if [ -z "${final_file}" ]; then
	echo "expected finalized .opus file after graceful stop" >&2
	cat "${tmp_dir}/recorder.log" >&2 || true
	exit 1
fi

if [ -n "${remaining_part}" ]; then
	echo "expected no remaining .opus.part after successful graceful stop, found ${remaining_part}" >&2
	cat "${tmp_dir}/recorder.log" >&2 || true
	exit 1
fi

if ! grep -q 'sent q to ffmpeg stdin for graceful shutdown' "${tmp_dir}/recorder.log"; then
	echo "expected q-to-stdin graceful shutdown log" >&2
	cat "${tmp_dir}/recorder.log" >&2 || true
	exit 1
fi

if ! grep -q 'ffmpeg exit status: 0' "${tmp_dir}/recorder.log"; then
	echo "expected ffmpeg exit status log" >&2
	cat "${tmp_dir}/recorder.log" >&2 || true
	exit 1
fi

if ! grep -q 'segment finalized after graceful stop' "${tmp_dir}/recorder.log"; then
	echo "expected graceful-stop finalization log" >&2
	cat "${tmp_dir}/recorder.log" >&2 || true
	exit 1
fi
