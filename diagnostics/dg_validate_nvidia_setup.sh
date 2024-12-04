#!/bin/bash
#
# This script verifies the GPU environment and container runtime setup for Deepgram self-hosted products running with Docker or Podman.
# It performs a series of checks to ensure that your system is properly configured to run GPU-accelerated container workloads.
#
# This script supports Ubuntu (using dpkg) and RHEL-based distributions (using dnf).
#
# ## Usage
# Run this script with root privileges:
# ```
# sudo ./dg_validate_nvidia_setup.sh
# ```

# Function to display error messages in red
error() {
	printf "\033[0;31m%s\033[0m\n" "$1"
}

# Function to display success messages in green
success() {
	printf "\033[0;32m%s\033[0m\n" "$1"
}

direct_to_documentation() {
	doc_string=$'For details, see the Deepgram Self-Hosted documentation at:\n\t'"$1"
	error "$doc_string"
}

# Detect the package manager (dpkg for Ubuntu, dnf for RHEL-based distros)
if command -v dpkg &>/dev/null; then
	package_manager="dpkg -s"
elif command -v dnf &>/dev/null; then
	package_manager="dnf list installed"
else
	error "Unsupported package manager. This script supports Ubuntu (dpkg) and RHEL-based distros (dnf)."
	exit 1
fi

# Check if NVIDIA drivers are installed correctly
if lsmod | grep -q nouveau; then
	error "Issue: Nouveau drivers are installed instead of NVIDIA drivers."
	error "Please install the correct NVIDIA drivers and blacklist the Nouveau drivers."
	direct_to_documentation "https://developers.deepgram.com/docs/drivers-and-containerization-platforms#remove-nouveau-drivers"
	exit 1
elif ! nvidia-smi &>/dev/null; then
	error "Issue: NVIDIA drivers are not installed correctly or are corrupt."
	error "Please reinstall the NVIDIA drivers and ensure they are functioning properly."
	direct_to_documentation "https://developers.deepgram.com/docs/drivers-and-containerization-platforms#install-nvidia-drivers"
	exit 1
else
	success "NVIDIA drivers are installed correctly."
fi

# Check if NVIDIA driver version is compatible with most recent Deepgram self-hosted release
MINIMUM_DRIVER_VERSION="530.30.02"
MAXIMUM_DRIVER_VERSION="561.00.00"
nvidia_driver_version=$(nvidia-smi --query-gpu=driver_version --format=csv,noheader)
if [[ "$(printf '%s\n' "$nvidia_driver_version" "$MINIMUM_DRIVER_VERSION" | sort -V | head -n1)" != "$MINIMUM_DRIVER_VERSION" ]] || [[ "$(printf '%s\n' "$nvidia_driver_version" "$MAXIMUM_DRIVER_VERSION" | sort -V | tail -n1)" != "$MAXIMUM_DRIVER_VERSION" ]]; then
	error "Issue: The installed NVIDIA driver version is not compatible with the most recent Deepgram self-hosted release."
	error "Please install a driver with version >=$MINIMUM_DRIVER_VERSION and <$MAXIMUM_DRIVER_VERSION."
	direct_to_documentation "https://developers.deepgram.com/docs/drivers-and-containerization-platforms#download-and-install-the-official-drivers"
	exit 1
else
	success "NVIDIA driver version is compatible with the most recent Deepgram self-hosted release."
fi

# Check if NVIDIA container runtime is installed
if ! $package_manager nvidia-container-toolkit &>/dev/null; then
	error "Issue: NVIDIA container toolkit is not installed."
	error "Please install the NVIDIA container toolkit to enable GPU support in containers."
	direct_to_documentation "https://developers.deepgram.com/docs/drivers-and-containerization-platforms#install-the-nvidia-container-runtime"
	exit 1
else
	success "NVIDIA container runtime is installed."
fi

if which docker &>/dev/null; then
	# Check if NVIDIA container runtime is configured with Docker
	if ! grep -q "nvidia" /etc/docker/daemon.json 2>/dev/null; then
		error "Issue: NVIDIA container runtime is not configured with Docker."
		error "Please run the **Configuration** step for the 'nvidia-container-runtime'."
		direct_to_documentation "https://developers.deepgram.com/docs/drivers-and-containerization-platforms#docker-1"
		exit 1
	fi
elif which podman &>/dev/null; then
	# Check if NVIDIA container runtime is configured with CDI for Podman
	CDI_SPEC_FILE="/etc/cdi/nvidia.yaml"

	if [ ! -f "$CDI_SPEC_FILE" ] || [ ! -r "$CDI_SPEC_FILE" ] || [ ! -s "$CDI_SPEC_FILE" ]; then
		error "Issue: NVIDIA container runtime is not configured with Podman."
		error "Please run the **Configuration** step for the 'nvidia-container-runtime'."
		direct_to_documentation "https://developers.deepgram.com/docs/drivers-and-containerization-platforms#podman-1"
		exit 1
	fi
else
	error "Did not detect 'docker' or 'podman' container engines."
	error "This script currently only supports these two approaches."
	direct_to_documentation "https://developers.deepgram.com/docs/drivers-and-containerization-platforms#install-container-engine"
	exit 1
fi
success "NVIDIA container runtime is configured properly."

success $'\nYour instance appears to be ready to run GPU container workloads, such as Deepgram self-hosted products.'
