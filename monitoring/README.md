# Deepgram Self-Hosted Monitoring

This repository contains a Grafana dashboard template for monitoring Deepgram self-hosted deployments.

## Overview

The dashboard provides monitoring of health and performance metrics including:

- **Request Metrics**: Active requests, request rates, and status code breakdowns
- **Error Monitoring**: Error rates (4xx/5xx) and per-pod error tracking
- **Latency Metrics**: Batch and streaming latency at P50, P90, and P99 percentiles
- **Capacity Monitoring**: Streaming load, capacity estimation, and saturation levels
- **Per-Pod Metrics**: Individual pod performance and error rates

## Requirements

- Grafana 12.3.0 or higher
- Prometheus datasource configured

## Usage

1. Import the `grafana_dashboard_template.json` file into your Grafana instance
2. Configure the Prometheus datasource (DS_PROMETHEUS) when prompted
3. The dashboard will automatically populate with metrics from your Prometheus instance

## Dashboard Features

The dashboard includes panels for:
- Active requests per pod
- Request rate by kind (RPS)
- Error rate percentages
- Status code breakdown
- Batch and streaming latency percentiles
- Stream capacity and load saturation
- Connection latency
- Per-pod error rates and latency metrics

## Recommended Alerts

### Example: Streaming P99 latency alert in Grafana

1. In Grafana, go to **Alerting → Alert rules → New alert rule**.
2. Choose the **Prometheus** data source (same as your dashboard).
3. In the query editor, paste:

   ```
   histogram_quantile(
     0.99,
     sum by (namespace, le) (
       rate(engine_stream_latency_bucket{namespace=~"dg-.*"}[5m])
     )
   )
   ```

4. Click **Run queries** to verify you see values.
5. Under **Conditions**, set something like:
   - WHEN `A` **IS ABOVE** `1.5`
   - FOR `5m`
6. Set:
   - **Rule name**: `DeepgramHighStreamingP99Latency`
   - **Folder**: `Deepgram SLOs`
   - **Evaluation interval**: `30s` or `1m`
7. Attach a **Contact point** (Slack, email, etc.) and a **Notification policy**.

Repeat similar steps for:

### Error rate alert

**Query:**

```
(
  sum by (namespace) (
    rate(engine_requests_total{
      namespace=~"dg-.*",
      response_status=~"5.."
    }[5m])
  )
  /
  sum by (namespace) (
    rate(engine_requests_total{
      namespace=~"dg-.*"
    }[5m])
  )
)
```

**Condition:**
- WHEN `A` **IS ABOVE** `0.05`
- FOR `2m`

### Saturation alert

**Query:**

```
100 *
(
  sum by (namespace) (
    rate(engine_requests_total{
      namespace=~"dg-.*",
      kind="stream"
    }[1m])
  )
  /
  avg by (namespace) (
    engine_estimated_stream_capacity{
      namespace=~"dg-.*"
    }
  )
)
```

**Condition:**
- WHEN `A` **IS ABOVE** `70`
- FOR `10m`
