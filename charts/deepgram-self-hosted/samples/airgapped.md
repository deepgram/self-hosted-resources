# Airgapped Deployment Guide

Deploy Deepgram Self-Hosted in environments without external network access.

## Overview

In airgapped deployments, the Billing container validates licenses locally and manages a journal file for usage/billing.

| Method             | Self-Hosted            | Airgapped                    |
|--------------------|------------------------|------------------------------|
| License Server     | `license.deepgram.com` | Billing container            |
| Required Secrets   | API key                | License key + License file   |
| Journal Management | Not applicable         | Retrieval & return required  |

## Architecture

- Standard: API/Engine → Billing Container
- High Availability: API/Engine → License Proxy → Billing Container

## Prerequisites

Obtain from Deepgram:
- License key (`DEEPGRAM_LICENSE_KEY`)
- License file (`.dg`)
- Registry access for `quay.io/deepgram/*` (including for Billing container)

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
  --timeout 1h
```

### 3. Verify

```bash
kubectl get pods -n dg-self-hosted
# deepgram-api-xxxxx       1/1  Running
# deepgram-billing-0       1/1  Running
# deepgram-engine-xxxxx    1/1  Running
```

---

## Journal Retrieval

**IMPORTANT:** The billing container maintains a usage journal that **must be provided to Deepgram regularly**.

---

## Manual Journal Retrieval

This method uses a temporary debug pod to access the journal file.

### 1. Find Your Billing Pod Name

```bash
kubectl get pods -n dg-self-hosted | grep billing
```

Example output:

```
deepgram-billing-0       1/1     Running
```

### 2. Find Your Journal PVC Name

```bash
kubectl get pvc -n dg-self-hosted | grep journal
```

Note the exact PVC name corresponding to your billing pod (e.g. `journal-deepgram-billing-0`).

### 3. Create Debug Pod YAML

Create a file named `journal-debug-pod.yaml`:

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: billing-journal-debug
  namespace: dg-self-hosted
spec:
  containers:
  - name: shell
    image: ubuntu:22.04
    command: ["sleep", "3600"]
    volumeMounts:
    - mountPath: /mnt
      name: journal-pvc
  volumes:
  - name: journal-pvc
    persistentVolumeClaim:
      claimName: journal-deepgram-billing-0 # Replace with your actual PVC name
```

**Important:** Replace `claimName` with your journal PVC name from step 2.

### 4. Deploy the Debug Pod

```bash
kubectl apply -f journal-debug-pod.yaml
kubectl wait --for=condition=ready pod/billing-journal-debug -n dg-self-hosted --timeout=60s
```

### 5. Verify Journal File Exists

```bash
kubectl exec -n dg-self-hosted billing-journal-debug -- ls -lh /mnt/
```

You should see output similar to:

```
-rw-r--r--    1 root     root        12.3K Nov 20 01:23 journal
```

### 6. Download the Journal File

```bash
kubectl cp dg-self-hosted/billing-journal-debug:/mnt/journal ./billing-journal-$(date +%Y%m%d).backup
```

You’ll now have e.g. `billing-journal-20251120.backup` in your current directory.

### 7. Verify Download

```bash
ls -lh billing-journal-*.backup
```

The file should have non-zero size.

### 8. Clean Up Debug Pod

```bash
kubectl delete pod billing-journal-debug -n dg-self-hosted
```

### 9. Send to Deepgram

Send the journal backup to Deepgram by email in an attachment or a cloud storage download link.

---

### Validation Checklist

Before setting up automated backups, verify:

- Your airgapped deployment has processed at least one API request
- You successfully downloaded a journal file manually
- The file size is greater than `0` bytes
- You can send the file to Deepgram
- Your Deepgram contact confirms they received and can process it

---

## Automated Backup (Recommended for Production)

Use a Kubernetes `CronJob` to automate regular journal backups.

Note for fully airgapped environments: Replace the `aws s3 cp` command below with your local storage solution (mount to NFS, copy to local PV, etc.).

### 1. Create CronJob YAML

Create a file named `billing-journal-cronjob.yaml`:

```yaml
apiVersion: batch/v1
kind: CronJob
metadata:
  name: billing-journal-backup
  namespace: dg-self-hosted
spec:
  schedule: "0 2 * * *" # Daily at 2 AM UTC
  jobTemplate:
    spec:
      template:
        spec:
          containers:
          - name: backup
            image: ubuntu:22.04
            command: ["/bin/sh", "-c"]
            args:
            - |
              apt-get update -qq && apt-get install -y -qq awscli tar gzip > /dev/null
              DATE=$(date +%Y%m%d-%H%M%S)
              tar czf /tmp/journal-${DATE}.tar.gz -C /mnt .
              aws s3 cp /tmp/journal-${DATE}.tar.gz s3://YOUR-BUCKET/deepgram-journals/
              echo "Backup complete: journal-${DATE}.tar.gz"
            env:
            - name: AWS_REGION
              value: "us-west-2"  # Change to your region
            volumeMounts:
            - name: journal
              mountPath: /mnt
          restartPolicy: OnFailure
          volumes:
          - name: journal
            persistentVolumeClaim:
              claimName: journal-deepgram-billing-0  # Replace with your PVC name
```

**Be sure to:**
- Replace `YOUR-BUCKET` with your S3 bucket name.
- Replace `claimName` with your journal PVC name.
- Ensure proper S3 write permissions (`IAM`, access keys, etc.).

#### AWS Credentials Setup:

The `CronJob` needs AWS credentials. Choose one method:

**Option A: IAM Role for Service Account (Recommended)**

- Create `IAM` policy for S3 write access, then associate with Kubernetes service account. See AWS IRSA documentation for your EKS cluster.

**Option B: AWS Secret**

- Create a secret with `AWS_ACCESS_KEY_ID` and `AWS_SECRET_ACCESS_KEY`, then add `envFrom` to the CronJob container to reference it.

---

For Multiple Billing Pods:

The example above only backs up **one** PVC. If you have multiple billing replicas with multiple PVCs, you need to back up each one. Either:

- Create separate `CronJob`s for each PVC, OR
- Modify the script to loop through all journal PVCs

---

### 2. Deploy the CronJob

```bash
kubectl apply -f billing-journal-cronjob.yaml
```

### 3. Check CronJob Creation

```bash
kubectl get cronjob -n dg-self-hosted
```

### 4. Test Backup Job Immediately (Optional)

```bash
kubectl create job --from=cronjob/billing-journal-backup billing-journal-test -n dg-self-hosted
kubectl logs -n dg-self-hosted job/billing-journal-test
```

### 5. Monitor Backups

Check if jobs are scheduled and running:

```bash
kubectl get jobs -n dg-self-hosted | grep billing-journal-backup
aws s3 ls s3://YOUR-BUCKET/deepgram-journals/
```

---

## Multi-Replica Billing Pods

### If Using EBS (Default, One PVC per Pod)

Each billing pod has its own PVC. Retrieve journals for **each pod**:

```bash
kubectl get pvc -n dg-self-hosted | grep journal
```

For each PVC:
- Update the debug pod manifest with the correct `claimName`.
- Repeat the manual retrieval steps above for every PVC (e.g., `journal-deepgram-billing-0`, `journal-deepgram-billing-1`, ...).

### If Using EFS (Shared PVC)

All billing pods write to separate subdirectories within one shared PVC.

To download all journals:

```bash
kubectl cp dg-self-hosted/billing-journal-debug:/mnt/ ./all-billing-journals/
```

This copies all files and subdirectories.

---

## Troubleshooting

- `kubectl cp` fails with `"tar: command not found"`:<br>
  Use `alpine:latest` for the debug pod (it includes `tar`).
- Journal file is empty (`0` bytes):<br>
  The billing container may not be running yet. If the journal file only contains a single initialization line, it's likely that no billing activity has started and the container isn't up. Check the status:
  ```kubectl get pods -n dg-self-hosted -l app=deepgram-billing```
- `CronJob` never runs:<br>
  Check status:
  ```kubectl describe cronjob billing-journal-backup -n dg-self-hosted```
- `"Permission denied"` accessing journal:<br>
  The debug pod defaults to `root` — shouldn't occur, but check pod spec/image.

---

## Best Practices

- Backup frequency: Daily via automated `CronJob` (see above)
- Retention: Retain all journal files until they have been delivered to Deepgram
- Testing: Verify you can retrieve and restore journal files before going to production
- Documentation: Record your backup/retrieval process for your team

---

## Additional Resources

- Sample airgapped AWS configuration: [`samples/06-basic-setup-aws-airgapped.values.yaml`](samples/06-basic-setup-aws-airgapped.values.yaml)
- Full configuration reference: [`values.yaml`](../../values.yaml)
- Sample files: [`samples/06-basic-setup-aws-airgapped.values.yaml`](samples/06-basic-setup-aws-airgapped.values.yaml)
- Main chart docs: [`README.md`](../../README.md)
