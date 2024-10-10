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
```bash
docker ps # Note the container ID of the relevant Deepgram container
docker logs <container_id> > dg_container.log 2>&1
```
#### Podman
```bash
```bash
podman ps # Note the container ID of the relevant Deepgram container
podman logs <container_id> > dg_container.log 2>&1
```
#### Kubernetes
```bash
```bash
kubectl get pods -n <namespace> # Note the name of the Pod containing the relevant Deepgram container
kubectl logs <pod_name> > dg_container.log 2>&1
```

## Getting Help

See the [Getting Help section](../README.md#getting-help) of the repo README.
