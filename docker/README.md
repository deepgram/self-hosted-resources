# Deepgram Self-Hosted with Docker
[Docker](https://docs.docker.com/) is a popular container runtime that allows you to run applications in isolated environments. This directory contains resources for running Deepgram products in a self-hosted environment using Docker.

## Contents

There are several [Docker Compose](https://docs.docker.com/compose/) templates for deploying Deepgram services as containers with Docker. Choose one of the following:

* [Docker Compose template](./docker-compose.standard.yml) for a standard deployment
    * [Associated Deepgram configuration files](../common/standard_deploy/)
* [Docker Compose template](./docker-compose.license-proxy.yml) for a deployment with the [Deepgram License Proxy](https://developers.deepgram.com/docs/license-proxy)
    * [Associated Deepgram configuration files](../common/license_proxy_deploy/)
## Usage
1. Read the [Deepgram self-hosted introduction](https://developers.deepgram.com/docs/self-hosted-introduction), then proceed to the [Docker/Podman](https://developers.deepgram.com/docs/dockerpodman) deployment path. Complete the series of guides until you have a deployment environment configured and are ready to begin the [Deploy Deepgram Services](https://developers.deepgram.com/docs/deploy-deepgram-services) guide.
2. Download a copy of your chosen Docker Compose template and copies of the associated Deepgram `toml` configuration files.
3. Replace placeholder paths in your chosen Docker Compose template with the paths to your data and configuration files:
    * `/path/to/api.toml`
    * `/path/to/engine.toml`
    * `/path/to/models`
    * `/path/to/license-proxy.toml`, if applicable
4. Export your [Deepgram self-hosted API key](https://developers.deepgram.com/docs/on-prem-self-service-tutorial#create-an-on-prem-api-key) in your deployment environment.
    ```bash
    $ export DEEPGRAM_API_KEY=<your api key here>
    ```
4. Finish the walkthrough documentation by completing the [Deploy Deepgram Services](https://developers.deepgram.com/docs/deploy-deepgram-services) guide.

## Getting Help

See the [Getting Help](../README.md#getting-help) section in the root of this repository for a list of resources to help you troubleshoot and resolve issues.

### Troubleshooting

If you encounter issues while deploying or using Deepgram, consider the following troubleshooting steps:

1. Check the pod status and logs:
   - Use `docker ps` to check the status of the Deepgram containers.
   - Use `docker logs <container-id>` to view the logs of a specific container.
   - Use `docker inspect <container-id>` to view the configuration and status of a specific container.

2. Verify resource availability:
   - Ensure that the host machine has sufficient CPU, memory, and storage resources to accommodate the Deepgram components.
   - Check for any resource constraints or limits imposed by your Docker Compose file or `docker run` command.

3. Check the network connectivity:
   - Verify that the Deepgram components can communicate with each other and with the Deepgram license server (license.deepgram.com).
   - Check the network policies and firewall rules to ensure that the necessary ports and protocols are allowed.

4. Collect diagnostic information:
   - Gather relevant logs and metrics.
   - Collect your existing configuration files:
     - `api.toml`
     - `engine.toml`
     - `docker-compose.yml`
     - `license-proxy.toml`, if applicable
   - Provide the collected diagnostic information to Deepgram for assistance.


