# Airgapped Deployment Guide

Deploy Deepgram Self-Hosted in environments without external network access.

## Overview

In airgapped deployments, the Billing container validates licenses locally and manages a journal file for usage/billing.

## Architecture

- Standard: API/Engine → Billing Container
- High Availability: API/Engine → License Proxy → Billing Container

## Prerequisites

Obtain from Deepgram:
- License key (`DEEPGRAM_LICENSE_KEY`)
- License file (`.dg`)
- Registry access for `quay.io/deepgram/*` (including for Billing container)

## Storage Options

Choose your journal storage backend based on your requirements:

| Storage Type                  | Access Mode     | Journal Retrieval      | HA Support  | AWS Example | GCP Example       |
|-------------------------------|-----------------|-----------------------|-------------|-------------|-------------------|
| Shared Storage (EFS/Filestore)| ReadWriteMany   | Zero downtime         | Yes         | efs-sc      | Filestore         |
| Block Storage (EBS/PD)        | ReadWriteOnce   | Requires downtime (~30-60s) | No    | gp2, gp3    | pd-standard, pd-ssd|

### When to Use EFS/Shared Storage
- Default and recommended for most installations
- Zero-downtime journal retrieval required
- High availability (multiple billing replicas needed)
- Frequent journal retrieval (daily automated backups)
- Production environments with strict SLAs

When sharing the models PVC, billing creates a subdirectory for journals (e.g., `journal-deepgram-billing-0/`). This allows zero-downtime journal retrieval without affecting model storage.

### When to Use EBS/Block Storage
- Simpler setup
- Single billing replica
- Infrequent journal retrieval (weekly, monthly, or less)
- Scheduled maintenance windows acceptable

## Getting Started

See the [Deepgram Kubernetes docs](https://developers.deepgram.com/docs/kubernetes)
for step-by-step instructions on deploying Deepgram to:
- [Amazon Elastic Kubernetes Service (EKS)](https://developers.deepgram.com/docs/aws-k8s)
- [Google Kubernetes Engine (GKE)](https://developers.deepgram.com/docs/gcp-k8s)
- [Self-managed Kubernetes](https://developers.deepgram.com/docs/self-managed-kubernetes)

Additional repository resources:
- Sample airgapped AWS configuration: [`07-basic-setup-aws-airgapped.values.yaml`](./07-basic-setup-aws-airgapped.values.yaml)
- Full configuration reference: [`values.yaml`](../values.yaml)
- Main chart docs: [`README.md`](./README.md)

## Journal Retrieval

**IMPORTANT:** The billing container maintains a usage journal that must be provided to Deepgram regularly.

### Manual Journal Retrieval

#### For EFS/Shared Storage Users (Zero Downtime)

If billing uses EFS (either dedicated or shared with models), you can retrieve journals with zero downtime using a temporary helper pod.

1. **Identify the PVC**

First, identify the name of your billing pod(s):

```bash
kubectl get pods -n dg-self-hosted | grep billing
```

Then, check which PVC the billing pod is using (replace `<billing-pod-name>` with the pod name you found):

```bash
kubectl describe pod <billing-pod-name> -n dg-self-hosted | grep -A 3 "journal:"
```

You'll see output like:

```
journal:
  Type:       PersistentVolumeClaim
  ClaimName:  dg-models-aws-efs-pvc
```

2. **Create Helper Pod**

Create a temporary pod with the PVC mounted:

```bash
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: Pod
metadata:
  name: billing-efs-helper
  namespace: dg-self-hosted
spec:
  containers:
  - name: helper
    image: busybox
    command: ["sleep", "3600"]
    volumeMounts:
    - name: efs-volume
      mountPath: /efs
  volumes:
  - name: efs-volume
    persistentVolumeClaim:
      claimName: dg-models-aws-efs-pvc  # Use your PVC name from step 1
EOF
```

Wait for the temporary pod to be ready:

```bash
kubectl wait --for=condition=Ready pod/billing-efs-helper -n dg-self-hosted --timeout=60s
```

3. **Locate the Journal File**

List the EFS contents to find the journal directory:

```bash
kubectl exec -n dg-self-hosted billing-efs-helper -- ls -lah /efs/
```

You should see a directory like `journal-deepgram-billing-0/`. List its contents:

```bash
kubectl exec -n dg-self-hosted billing-efs-helper -- ls -lah /efs/journal-deepgram-billing-0/
```

The journal file is typically named `journal`.

4. **Download the Journal File**

```bash
kubectl cp dg-self-hosted/billing-efs-helper:/efs/journal-deepgram-billing-0/journal ./billing_journal_$(date +%Y%m%d).db
```

5. **Verify Download**

```bash
ls -lh billing_journal_*.db
cat billing_journal_*.db
```

Example journal JSON-lines contents:

```
{"d":"...","s":"..."}
{"d":"...","s":"..."}
```

6. **Clean Up Helper Pod**

```bash
kubectl delete pod billing-efs-helper -n dg-self-hosted
```

Billing continues running throughout this entire process.

7. **Send to Deepgram**

Send the journal file to your Deepgram contact via email attachment or cloud storage link.

---

#### For EBS/Block Storage Users (Requires Downtime)

**Important:** If using EBS storage (ReadWriteOnce), manual retrieval requires scaling down the billing container (30-60 seconds of downtime). Consider using EFS for zero-downtime retrieval or scheduling retrievals during maintenance windows.

1. **Find Your Billing Pod Name**

```bash
kubectl get pods -n dg-self-hosted | grep billing
```

2. **Find Your Journal PVC Name**

```bash
kubectl get pvc -n dg-self-hosted | grep journal
```

Note the exact PVC name (e.g. `journal-deepgram-billing-0`).

3. **Create Debug Pod YAML**

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
      claimName: journal-deepgram-billing-0 # Use your actual PVC name
```

4. **Scale Down Billing**

```bash
kubectl scale statefulset deepgram-billing -n dg-self-hosted --replicas=0
kubectl wait --for=delete pod/deepgram-billing-0 -n dg-self-hosted --timeout=60s
```

5. **Deploy the Debug Pod**

```bash
kubectl apply -f journal-debug-pod.yaml
kubectl wait --for=condition=ready pod/billing-journal-debug -n dg-self-hosted --timeout=60s
```

6. **Verify Journal File Exists**

```bash
kubectl exec -n dg-self-hosted billing-journal-debug -- ls -lh /mnt/
```

7. **Download the Journal File**

```bash
kubectl cp dg-self-hosted/billing-journal-debug:/mnt/journal ./billing-journal-$(date +%Y%m%d).backup
```

8. **Verify Download**

```bash
ls -lh billing-journal-*.backup
```

9. **Clean Up Debug Pod**

```bash
kubectl delete pod billing-journal-debug -n dg-self-hosted
```

10. **Restore Billing**

```bash
kubectl scale statefulset deepgram-billing -n dg-self-hosted --replicas=1
```

11. **Send to Deepgram**

Send the journal backup to Deepgram by email or via download link.

---

### Validation Checklist

Before setting up automated backups, verify:

- Your airgapped deployment has processed at least one API request
- You successfully downloaded a journal file manually
- The file size is greater than `0` bytes
- You can send the file to Deepgram
- Your Deepgram contact confirms they received and can validate it

---

### Automated Journal Backup (Recommended for Production)

Use a Kubernetes `CronJob` to automate regular journal backups.

**Important for EBS Users**: With EBS storage, only one pod can access the journal volume at a time. This means the CronJob cannot run while the billing container is running. To use automated backups with EBS:
- Schedule the CronJob during maintenance windows when billing is scaled down
- Modify the Job script to scale down billing before backup and scale it back up after
- Or switch to EFS for zero-downtime backups

Note for fully airgapped environments: Replace the `aws s3 cp` command below with your local storage solution (mount to NFS, copy to local PV, etc.).

**1. Create CronJob YAML**

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

Be sure to:
- Replace `YOUR-BUCKET` with your S3 bucket name.
- Replace `claimName` with your journal PVC name.
- Ensure proper S3 write permissions (`IAM`, access keys, etc.).

#### AWS Credentials Setup

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

**2. Deploy the CronJob**

```bash
kubectl apply -f billing-journal-cronjob.yaml
```

**3. Check CronJob Creation**

```bash
kubectl get cronjob -n dg-self-hosted
```

**4. Test Backup Job Immediately (Recommended)**

```bash
kubectl create job --from=cronjob/billing-journal-backup billing-journal-test -n dg-self-hosted
kubectl logs -n dg-self-hosted job/billing-journal-test
```

**5. Monitor Backups**

Check if jobs are scheduled and running:

```bash
kubectl get jobs -n dg-self-hosted | grep billing-journal-backup
aws s3 ls s3://YOUR-BUCKET/deepgram-journals/
```

---

## Multi-Replica Billing Pods

### If Using EBS (One PVC per Pod)

Each billing pod has its own PVC. Retrieve journals for **each pod**:

```bash
kubectl get pvc -n dg-self-hosted | grep journal
```

For each PVC:
- Update the debug pod manifest with the correct `claimName`.
- Repeat the manual retrieval steps above for every PVC (e.g., `journal-deepgram-billing-0`, `journal-deepgram-billing-1`, ...).

### If Using EFS (Shared PVC)

When billing uses EFS (shared or dedicated), each billing pod writes to its own subdirectory within the PVC.

View all billing journal directories:

```bash
kubectl exec -n dg-self-hosted billing-efs-helper -- ls -lah /efs/ | grep journal
```

You'll see directories like:

```
journal-deepgram-billing-0/
journal-deepgram-billing-1/
journal-deepgram-billing-2/
...
```

To download all journals:

```bash
for dir in $(kubectl exec -n dg-self-hosted billing-efs-helper -- ls -1 /efs/ | grep '^journal-deepgram-billing-[0-9]\+/$\|^journal-deepgram-billing-[0-9]\+$'); do
  podnum=$(echo "$dir" | grep -o '[0-9]\+$')
  kubectl cp dg-self-hosted/billing-efs-helper:/efs/${dir%/}/journal \
    ./billing_journal_pod${podnum}_$(date +%Y%m%d).db
done
```

---

## Best Practices

- Backup frequency: Daily via automated `CronJob` (see above)
- Retention: Retain all journal files until they have been delivered to Deepgram
- Testing: Verify you can retrieve and restore journal files before going to production
- Documentation: Record your backup/retrieval process for your team
