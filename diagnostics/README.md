# Diagnostics

This directory contains a collection of tools and scripts designed to help validate, monitor, and troubleshoot the deployment of Deepgram's self-hosted product. 

## Usage

For detailed usage instructions and features of each script, please refer to the header comments within the respective script files.

## Contents
### 1. [dg_validate_nvidia_setup.sh](./dg_validate_nvidia_setup.sh)

This script verifies the GPU environment and container runtime setup for Deepgram self-hosted products running with Docker or Podman. 

### 2. [dg_log_parser.sh](./dg_log_parser.sh)
This script analyzes log files from Deepgram self-hosted containers to identify common issues and provide troubleshooting suggestions.

Collecting log files for analysis will vary depending on your container orchestrator:

#### Docker
```bash
docker ps # Note the container ID of the relevant Deepgram container
docker logs <container_id> > dg_container.log 2>&1
```
#### Podman
```bash
podman ps # Note the container ID of the relevant Deepgram container
podman logs <container_id> > dg_container.log 2>&1
```
#### Kubernetes
```bash
kubectl get pods -n <namespace> # Note the name of the Pod containing the relevant Deepgram container
kubectl logs <pod_name> > dg_container.log 2>&1
```

### 3. [dg_gke_libcuda_smoke.sh](./dg_gke_libcuda_smoke.sh)

This script tests whether a Deepgram Engine image (or the image plus the Helm chart's environment contract) can load the NVIDIA driver in a GKE-shaped environment, where the driver is bind-mounted at `/usr/local/nvidia/lib64` without the NVIDIA container toolkit. It requires no GPU, Deepgram license, or Kubernetes cluster, because it only verifies dynamic-linker visibility. CI runs it against a linker-level model image ([gke_sim_engine_image](./gke_sim_engine_image/Dockerfile)); it can also be run directly against real Engine images:

```bash
./dg_gke_libcuda_smoke.sh quay.io/deepgram/self-hosted-engine:release-XXXXXX
./dg_gke_libcuda_smoke.sh quay.io/deepgram/self-hosted-engine:release-XXXXXX --chart ../charts/deepgram-self-hosted
```

## Getting Help

See the [Getting Help section](../README.md#getting-help) of the repo README.
