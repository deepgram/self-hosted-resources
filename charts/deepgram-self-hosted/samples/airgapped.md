# Airgapped Deployment Guide

Deploy Deepgram Self-Hosted in environments without external network access.

## Overview

In airgapped deployments, the **Billing container** validates licenses locally and manages a journal file for usage/billing.

| Aspect             | Cloud                  | Airgapped                   |
|--------------------|-----------------------|-----------------------------|
| License Server     | license.deepgram.com   | Billing container           |
| Required Secrets   | API key                | License key + License file  |
| Journal Management | Automatic              | Manual retrieval required   |

## Architecture

- **Standard:** API/Engine → Billing Container
- **High Availability:** API/Engine → License Proxy → Billing Container

## Prerequisites

Obtain from Deepgram:
- **License Key** (`DEEPGRAM_LICENSE_KEY`)
- **License File** (`.dg`)
- **Registry Access** for `quay.io/deepgram/*`

## Example Configurations

<details>
<summary>Minimal Airgapped Setup</summary>

```yaml
global:
  pullSecretRef: dg-regcred
  deepgramLicenseSecretRef: dg-license-key

billing:
  enabled: true
  licenseFile:
    secretRef: dg-license-file
  journal:
    storageClass: gp2 # or your StorageClass
    size: 1Gi

licenseProxy:
  enabled: false
```
</details>

<details>
<summary>With License Proxy</summary>

```yaml
billing:
  enabled: true
licenseProxy:
  enabled: true
  upstream:
    useBilling: true
```
</details>

<details>
<summary>High Availability with EFS</summary>

```yaml
billing:
  replicas: 3
  journal:
    existingPvcName: my-efs-pvc # shared EFS pvc
```
</details>

<details>
<summary>Custom Init Container (private registry)</summary>

```yaml
global:
  initContainer:
    image:
      registry: your-private-registry.com
      repository: ubuntu
      tag: 22.04
    pullSecretRef: dg-regcred
```
</details>

---

## Quick Start

### 1. Create Namespace & Secrets

```bash
kubectl create namespace dg-self-hosted

kubectl create secret docker-registry dg-regcred \
  --docker-server=quay.io \
  --docker-username='YOUR_USERNAME' \
  --docker-password='YOUR_PASSWORD' \
  -n dg-self-hosted

kubectl create secret generic dg-license-key \
  --from-literal=DEEPGRAM_LICENSE_KEY='your-key-here' \
  -n dg-self-hosted

kubectl create secret generic dg-license-file \
  --from-file=license.dg=/path/to/your/license.dg \
  -n dg-self-hosted
```

### 2. Deploy

```bash
helm install deepgram-self-hosted ./charts/deepgram-self-hosted \
  -f samples/06-basic-setup-aws-airgapped.values.yaml \
  -n dg-self-hosted \
  --timeout 45m
```

### 3. Verify

```bash
kubectl get pods -n dg-self-hosted
# deepgram-api-xxxxx       1/1  Running
# deepgram-billing-0       1/1  Running
# deepgram-engine-xxxxx    1/1  Running
```

### Troubleshooting

- **Pods not starting:**  
  ```kubectl get secrets -n dg-self-hosted```  
  ```kubectl logs -n dg-self-hosted deepgram-billing-0```
- **PVC pending:**  
  ```kubectl get storageclass```  
  Ensure `storageClass` is set in values.yaml.

---

## Journal Retrieval (Critical)

**You must regularly retrieve the journal file and provide it to Deepgram for billing.**

### Method 1: One-Time Retrieval (Debug Pod)

1. Create `debug-pod.yaml`:

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: billing-journal-debug
  namespace: dg-self-hosted
spec:
  containers:
  - name: shell
    image: alpine:latest
    command: ["sleep", "3600"]
    volumeMounts:
      - mountPath: /mnt
        name: journal-pvc
  volumes:
    - name: journal-pvc
      persistentVolumeClaim:
        claimName: journal-deepgram-billing-0
```

2. Retrieve the journal file:

```bash
kubectl apply -f debug-pod.yaml
kubectl wait --for=condition=ready pod/billing-journal-debug -n dg-self-hosted
kubectl cp dg-self-hosted/billing-journal-debug:/mnt/journal ./billing-journal-backup
kubectl delete pod billing-journal-debug -n dg-self-hosted
```

### Method 2: Automated Backup (CronJob)

Edit and apply this example as needed:

```yaml
apiVersion: batch/v1
kind: CronJob
metadata:
  name: billing-journal-backup
  namespace: dg-self-hosted
spec:
  schedule: "0 2 * * *"  # Daily at 2AM
  jobTemplate:
    spec:
      template:
        spec:
          containers:
          - name: backup
            image: amazon/aws-cli:latest
            command: ["/bin/sh", "-c"]
            args:
              - tar czf /tmp/journal-$(date +%Y%m%d).tar.gz -C /mnt . && \
                aws s3 cp /tmp/journal-$(date +%Y%m%d).tar.gz s3://your-bucket/deepgram-journals/
            volumeMounts:
              - name: journal
                mountPath: /mnt
          restartPolicy: OnFailure
          volumes:
            - name: journal
              persistentVolumeClaim:
                claimName: journal-deepgram-billing-0
```

---

### Best Practices

- **Backup frequency:** Daily (minimum: weekly)
- **Retention:** Keep historical journals for audit
- **High Availability:** 
  - EBS (default): Each pod has its own PVC (`journal-deepgram-billing-0`, `journal-deepgram-billing-1`, etc.)
  - EFS (shared): All pods write to subdirectories under one PVC (`/mnt/journal-deepgram-billing-0/`, etc.)
- **Security:** Encrypt journal files when transferring to Deepgram
---

## Additional Resources

- Full configuration reference: `values.yaml`
- Sample files: `samples/06-basic-setup-aws-airgapped.values.yaml`
- Main chart docs: `README.md`
