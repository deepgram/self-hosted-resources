# Samples

This directory contains examples of how to use the Deepgram Helm chart in various configurations and with various cloud providers. The samples are not meant to be an exhaustive demonstration of all available options; please see the chart [README](../README.md) and [values.yaml](../values.yaml) for more information.

## Available Samples

- **01-basic-setup-aws.values.yaml** - Basic AWS EKS deployment configuration
- **02-basic-setup-gcp.yaml** - Basic GCP GKE deployment configuration
- **03-basic-setup-onprem.yaml** - On-premises deployment configuration
- **04-aura-2-setup.values.yaml** - Aura-2 model deployment with English and Spanish language support
- **05-voice-agent-aws.values.yaml** - AWS EKS Voice Agent deployment configuration
- **06-aura-2-polyglot-setup.values.yaml** - Aura-2 model deployment with English and Polyglot language support (Dutch, German, French, Italian, Japanese)

## AWS EKS Samples
See the [Deepgram AWS EKS guide](https://developers.deepgram.com/docs/aws-k8s) for detailed instructions on how to deploy Deepgram services in a managed Kubernetes cluster in AWS.

## GCP GKE Samples
See the [Deepgram GCP GKE guide](https://developers.deepgram.com/docs/gcp-k8s) for detailed instructions on how to deploy Deepgram services in a managed Kubernetes cluster in GCP.

## Aura-2 Deployment
For deploying Aura-2 models, use the `04-aura-2-setup.values.yaml` sample configuration for English and Spanish, or `06-aura-2-polyglot-setup.values.yaml` for English and Polyglot languages (Dutch, German, French, Italian, Japanese). These configurations include:

- Aura-2 specific environment variables and UUIDs
- Multi-language support (separate engine instances for each language)
- GPU resource allocation (English on GPUs 0,1 and either Spanish or Polyglot on GPUs 2,3)
- Model management configuration
- License proxy setup for production deployments

To deploy with Aura-2 English/Spanish support:
```bash
helm install deepgram ./charts/deepgram-self-hosted -f samples/04-aura-2-setup.values.yaml
```

To deploy with Aura-2 English/Polyglot support:
```bash
helm install deepgram ./charts/deepgram-self-hosted -f samples/06-aura-2-polyglot-setup.values.yaml
```
