#!/bin/bash
#
# This script analyzes log files from Deepgram self-hosted containers to identify common
# issues and provide troubleshooting suggestions.
#
# ## Usage
# This script can analyze individual container logs by passing a single file as an argument.
# Additionally, it can analyze logs from containers deployed in the same environment
# by passing each log file as a seperate argument. This can be useful for analyzing a
# paired API and Engine container.
#
# ```
# ./dg_log_parser.sh <logfile1> [logfile2] [logfile3] ...
# ```
#
# ## Supported Containers
# - API
# - Engine
# - License Proxy

set -euo pipefail

YELLOW='\033[0;33m'
GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m' # No Color

usage() {
	printf "Usage: %s <logfile1> [logfile2] [logfile3] ...\n" "$0"
	exit 1
}

if [ $# -eq 0 ]; then
	usage
fi

check_file_errors() {
	local file="$1"
	local error_found=false
	local container_name="Deepgram"

	if grep -q "stem::config:" "$file"; then
		container_name="API"
	elif grep -q "impeller::config:" "$file"; then
		container_name="Engine"
	elif grep -q "hermes::config:" "$file"; then
		container_name="Hermes"
	fi

	if grep -q "Configuration file not found at .* Falling back to default/bundled configuration" "$file"; then
		printf "%bWarning%b: Using default configuration for %s container.\n" "$YELLOW" "$NC" "$container_name"
		printf "If you intended to specify your own configuration file, ensure it is being properly mounted to the container.\n"
	fi

	if grep -q "Missing license configuration" "$file"; then
		printf "%bError%b: Missing API key for %s container.\n" "$RED" "$NC" "$container_name"
		printf "Suggested fix: Ensure that the environment variable \`DEEPGRAM_API_KEY\` is set within the container (usually via your Compose file or Helm chart).\n"
		error_found=true
	fi

	if grep -qE "^.*Aegis request to .* failed.*$" "$file"; then
		local target_url
		target_url=$(grep -oE "Aegis request to [^ ]+ failed" "$file" | head -n1 | cut -d' ' -f4)
		printf "%bError%b: Connection issue detected for %s container. Unable to connect/authenticate with License Server via %s\n" \
			"$RED" "$NC" "$container_name" "$target_url"

		if grep -qE "^.*Aegis request to .* failed:.*dns error.*$" "$file"; then
			printf "Suggested fix: Check DNS resolution for the target service.\n"
		elif grep -qE "^.*Aegis request to .* failed.*401.*$" "$file"; then
			printf "Suggested fix: Your API key is unauthorized. Check console.deepgram.com to ensure that your API key is active and has self-hosted access.\n"
		elif grep -qE "^.*Aegis request to .* failed:.*[TimedOut|Connection refused].*$" "$file"; then
			printf "Suggested fix: "
			if [[ "$target_url" =~ ^.*license.deepgram.com.*$ ]]; then
				printf "Verify egress traffic to license.deepgram.com is allow-listed by your firewall, and check network connectivity for your container.\n"
			else
				printf "Verify the License Proxy container is running and healthy\n"
			fi
		fi

		error_found=true
	fi

	if grep -q "impeller::config: Using devices: CPU" "$file"; then
		printf "%bWarning%b: Engine container was unable to detect a GPU, and is running in CPU mode.\n" "$YELLOW" "$NC"
		printf "CPU mode is significantly less efficient than using a GPU. If not intended, ensure all GPU setup steps have been completed from the Deepgram developer documentation.\n"
		error_found=true
	elif grep -q "half_precision=false" "$file"; then
		printf "%bWarning%b: GPU not running in half precision mode. Inference efficiency will be significantly impacted with this setting disabled.\n" "$YELLOW" "$NC"
		printf "Most modern GPUs support half precision, but auto-detection of this capability may not be working.\n"
		error_found=true
	fi

	if grep -q "impeller::model_suppliers::autoload: Unable to read model search path" "$file"; then
		printf "%bError%b: Invalid models directory for $container_name container.\n" "$RED" "$NC"
		printf "Suggested fix: Ensure that your models are mounted properly to the container.\n"
		error_found=true
	fi

	if grep -q "Failed to load model" "$file"; then
		bad_models=$(grep -P ".*Failed to load model.*" "$file" | grep -oP 'path=\K[^}]*' | sort -u)
		printf "%bWARNING%b: Some models could not be loaded by the $container_name container.\n" "$YELLOW" "$NC"
		printf "Suggested fix: Check each of the following files for corrupt downloads, and verify the model was delivered for the same project that issued your self-hosted API key.\n"
		for model in $bad_models; do
			printf "  - %s\n" "$model"
		done
		error_found=true
	fi

	$error_found
}

analyze_logs() {
	local log_files=("$@")
	local error_found=false

	# Check each file individually for errors
	for file in "${log_files[@]}"; do
		if check_file_errors "$file"; then
			error_found=true
		fi
	done

	local temp_error_file
	temp_error_file=$(mktemp)
	local engine_listening=false
	echo "false" >"$temp_error_file"
	sort -k1 --stable "${log_files[@]}" | while IFS= read -r line; do
		if [[ $line =~ ^.*INFO\ impeller:\ Listening\ on\ http.*$ ]]; then
			engine_listening=true
		fi

		if [[ "$engine_listening" = true ]] && [[ $line =~ ^.*WARN\ impeller_info:\ stem::utils::impeller_info_actor:\ Unable\ to\ get\ model\ info\ from\ Engine\ with\ any\ drivers.*$ ]]; then
			printf "%bError%b: The API container was unable to connect to the Engine container, even after the Engine container successfully started.\n" "$RED" "$NC"
			printf "Suggested fix: Check your composition files, api.toml, and engine.toml files to ensure networking between the containers is configured correctly.\n"
			echo "true" >"$temp_error_file"
			break
		fi
	done

	if [[ $(cat "$temp_error_file") == "true" ]]; then
		error_found=true
	fi
	rm "$temp_error_file"

	if [ "$error_found" = false ]; then
		printf "%bNo problems detected from provided log files.%b \
      If something is wrong with your deployment, there may be a different error that is not detected by this initial script. \
      Contact your Deepgram Account Representative for further assistance.\n" \
			"$GREEN" "$NC"
	fi

}

analyze_logs "$@"
