# Deepgram Self-Hosted with Docker
[Docker](https://docs.docker.com/) is a popular container runtime that allows you to run applications in isolated environments. This directory contains resources for running Deepgram products in a self-hosted environment using Docker.

## Contents

There are several [Docker Compose](https://docs.docker.com/compose/) templates for deploying Deepgram services as containers with Docker. Choose one of the following:

* [Docker Compose template](./docker-compose.standard.yml) for a standard deployment
    * [Associated Deepgram configuration files](../common/standard_deploy/)
* [Docker Compose template](./docker-compose.license-proxy.yml) for a deployment with the [Deepgram License Proxy](https://developers.deepgram.com/docs/license-proxy)
    * [Associated Deepgram configuration files](../common/license_proxy_deploy/)
## Usage
1. Read the [Deepgram self-hosted documentation guides](https://developers.deepgram.com/docs/on-prem-introduction), and complete the series of guides until you have a deployment environment configured and are ready to begin the [Deploy Deepgram Services](https://developers.deepgram.com/docs/deploy-deepgram-services) guide.
2. Download a copy of your chosen Docker Compose template and copies of the associated Deepgram `toml` configuration files. 
3. Replace placeholder paths in your chosen Docker Compose template with the paths to your data and configuration files:
    * `/path/to/api.toml`
    * `/path/to/engine.toml`
    * `/path/to/models`
    * `/path/to/license-proxy.toml`, if applicable
4. Export your [Deepgram onprem API key](https://developers.deepgram.com/docs/on-prem-self-service-tutorial#create-an-on-prem-api-key) in your deployment environment.
    ```bash
    $ export DEEPGRAM_API_KEY=<your api key here>
    ```
4. Finish the walkthrough documentation by completing the [Deploy Deepgram Services](https://developers.deepgram.com/docs/deploy-deepgram-services) guide.
