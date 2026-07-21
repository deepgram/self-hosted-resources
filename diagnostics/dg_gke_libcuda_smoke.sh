#!/bin/bash
#
# Tests whether a Deepgram Engine image can load the NVIDIA driver in a
# GKE-shaped environment: driver libraries bind-mounted at
# /usr/local/nvidia/lib64, with NO NVIDIA container toolkit to inject them.
#
# Engine crashes on GKE take the form:
#   impeller: error while loading shared libraries: libcuda.so.1: cannot open
#   shared object file: No such file or directory
# This is a dynamic-LINK failure, so the test only checks linker VISIBILITY:
#   - any valid shared object named libcuda.so.1 satisfies the linker's path
#     search, so a stub stands in for the real driver, and
#   - LD_TRACE_LOADED_OBJECTS=1 prints library resolution without executing
#     the binary, so no GPU, Deepgram license, or model files are needed.
#
# ## Usage
# ```
# # Is the image GKE-safe by itself?
# ./dg_gke_libcuda_smoke.sh IMAGE
#
# # Is the image plus the Helm chart's env contract GKE-safe (what actually ships)?
# ./dg_gke_libcuda_smoke.sh IMAGE --chart ../charts/deepgram-self-hosted
# ```
#
# Environment variables:
#   STUB_DIR      directory already containing a libcuda.so.1 stub (skips the build)
#   IMPELLER_BIN  binary to trace inside the image (default: /bin/impeller)
#
# Exit codes: 0 = libcuda.so.1 visible; 1 = not visible (would CrashLoopBackOff
# on GKE); 2 = test harness error.

set -uo pipefail

IMAGE="${1:?usage: dg_gke_libcuda_smoke.sh IMAGE [--chart CHART_DIR]}"
shift || true
CHART=""
if [ "${1:-}" = "--chart" ]; then
	CHART="${2:?--chart requires a chart directory}"
fi

# 1. Stub driver library: content is irrelevant, the dynamic linker only needs
#    a valid shared object named libcuda.so.1 to exist on a searched path.
WORK="${STUB_DIR:-}"
if [ -z "$WORK" ] || [ ! -f "$WORK/libcuda.so.1" ]; then
	WORK=$(mktemp -d)
	trap 'rm -rf "$WORK"' EXIT
	docker run --rm -v "$WORK":/out debian:bookworm-slim sh -c \
		'apt-get update -qq >/dev/null && apt-get install -y -qq gcc libc6-dev >/dev/null 2>&1 &&
		 echo "int cuda_stub;" > /tmp/s.c && gcc -shared -fPIC -o /out/libcuda.so.1 /tmp/s.c' ||
		{
			echo "ERROR: failed to build stub libcuda.so.1"
			exit 2
		}
fi

# 2. Optionally extract the env contract the Helm chart ships for the Engine
#    container, so the test covers the image + chart combination that customers
#    actually deploy.
ENV_ARGS=()
if [ -n "$CHART" ]; then
	while IFS='=' read -r key value; do
		[ -n "$key" ] && ENV_ARGS+=(-e "$key=$value")
	done < <(
		helm template smoke "$CHART" \
			--set global.deepgramSecretRef=placeholder \
			--set engine.modelManager.volumes.gcp.gpd.enabled=true \
			--set engine.modelManager.volumes.gcp.gpd.volumeHandle=placeholder \
			--show-only templates/engine/engine.deployment.yaml 2>/dev/null |
			awk '/- name: /{n=$3} /^[ ]+value: /{gsub(/"/,"",$2); if(n!=""){print n"="$2; n=""}}'
	)
	echo "chart env contract: ${ENV_ARGS[*]+"${ENV_ARGS[*]}"}"
fi

# 3. GKE-shaped run: driver only via bind mount, no toolkit. Trace the dynamic
#    linker; never execute the binary.
OUT=$(docker run --rm -v "$WORK":/usr/local/nvidia/lib64:ro \
	${ENV_ARGS[@]+"${ENV_ARGS[@]}"} \
	--entrypoint /bin/sh "$IMAGE" -c \
	"LD_TRACE_LOADED_OBJECTS=1 ${IMPELLER_BIN:-/bin/impeller} 2>&1 | grep libcuda" 2>&1)

echo "$OUT"
if echo "$OUT" | grep -q "libcuda.so.1 => /usr/local/nvidia/lib64/libcuda.so.1"; then
	echo "PASS: libcuda.so.1 is visible in a GKE-shaped environment"
	exit 0
fi
echo "FAIL: libcuda.so.1 is NOT visible; this image/chart combination will CrashLoopBackOff on GKE"
exit 1
