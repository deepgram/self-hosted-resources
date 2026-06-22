# Samples

This directory contains examples of how to use the Deepgram Helm chart in various configurations and with various cloud providers. The samples are not meant to be an exhaustive demonstration of all available options; please see the chart [README](../README.md) and [values.yaml](../values.yaml) for more information.

## Available Samples

- **01-basic-setup-aws.values.yaml** - Basic AWS EKS deployment configuration
- **02-basic-setup-gcp.yaml** - Basic GCP GKE deployment configuration
- **03-basic-setup-onprem.yaml** - On-premises deployment configuration
- **04-aura-2-setup.values.yaml** - Aura-2 model deployment with English and Spanish language support
- **05-voice-agent-aws.values.yaml** - AWS EKS Voice Agent deployment configuration
- **06-aura-2-polyglot-setup.values.yaml** - Aura-2 model deployment with English and Polyglot language support (Dutch, German, French, Italian, Japanese)
- **07-basic-setup-aws-airgapped.values.yaml** - AWS EKS airgapped deployment ([see airgapped.md](./airgapped.md) for full guide)
- **[voice-agent/aws/self-hosted-llm/](./voice-agent/aws/self-hosted-llm/)** - AWS EKS Voice Agent routed to a self-hosted LLM (NVIDIA NIM serving Nemotron) running in-cluster ([see its README](./voice-agent/aws/self-hosted-llm/README.md) for the full guide)

## AWS EKS Samples
See the [Deepgram AWS EKS guide](https://developers.deepgram.com/docs/aws-k8s) for detailed instructions on how to deploy Deepgram services in a managed Kubernetes cluster in AWS.

### AWS resource tagging for Partner Relationship Management (PRM)

The AWS samples apply an `aws-apn-id` tag (value `pc: ajk5xy316takzneuu4ykhhj8c`) so the deployment is identified to AWS for [Partner Relationship Management (PRM)](https://docs.aws.amazon.com/PRM/latest/aws-prm-onboarding-guide/what-is-service.html). It is a metadata-only tag (no cost, no runtime effect), helps AWS and Deepgram coordinate a better self-hosted experience, and is **highly recommended to leave in place**. The tag is AWS-specific and is not present in the GCP or on-premises samples.

AWS does not propagate tags across resource types, so the tag is applied at each layer that creates AWS resources:

- **EKS cluster, networking, and EC2 nodes** — tagged automatically by the `*.cluster-config.yaml` files (`metadata.tags` plus `managedNodeGroups[].tags` with `propagateASGTags: true`). No action required.
- **Load balancers (NLB/ALB)** — only created if you expose a service with `type: LoadBalancer`. The AWS `*.values.yaml` samples include a commented `service.annotations` example with `service.beta.kubernetes.io/aws-load-balancer-additional-resource-tags`; uncomment it along with the load balancer to tag the provisioned NLB/ALB.
- **Dynamically provisioned EBS volumes** — only used for billing journals when `billing.journal.aws.efs.enabled` is `false` (EFS is the default). To tag them, point `billing.journal.storageClass` at an `ebs.csi.aws.com` StorageClass whose `parameters` include `tagSpecification_1: "aws-apn-id=pc: ajk5xy316takzneuu4ykhhj8c"`, or set the EBS CSI driver's `--extra-tags`.
- **EFS file system** — created by you outside this chart; add the tag when you create the file system.

All of the above are AWS-only and have no effect on GCP, on-premises, Docker, or Podman deployments.

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
