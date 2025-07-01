# Batch SITS Audio Intelligence Benchmarking

## Implementation

This script tests SITS audio intelligence.

It can test any combination of SITS features, either individually, several, or all together.

It uses non-formatted Nova-2 by default.

When the first 503 error arises, the test is aborted. This is because once one 503 occurs, performance rapidly deteriorates and the system does not recover.

## Usage

Export the audio location and audio duration.

`export AUDIO_LOCATION=<URL>`

`export DURATION=<audio duration in seconds>`

To run: `k6 run -e SITS_FEATURES=intents,summarize k6batch_sits.js`

The `SITS_FEATURES` flag accepts a comma-separated list of one or more SITS features: `sentiment`, `intents`, `topics`, `summarize`.

If no `SITS_FEATURES` are specified, it will benchmark plain Nova-2 with no SITS features enabled.

Suggested test cases are 36 permutations: `SITS Features {Sentiment | Intents | Topics | Summarize | All Sits | No Sits baseline} x Audio Duration {Short | Medium | Long} x Diarization {Diarized | Non-Diarized}`

Assuming short audio duration is ~2 minutes (120 seconds), medium is ~30 minutes (1800 seconds), and long is ~60 minutes (3600 seconds).

## Computing throughput metrics

As a short-term aid, copy and paste the K6 output into `calculate_k6_throughput.py`, and set the `ASSUMED_AUDIO_DURATION_SECS` variable of the audio duration the scenarios were run with.

To run the script: `python3 calculate_k6_throughput.py`.

The script's output uses a regular expression to determine the number of iterations per scenario, and does the calculation of `audio_duration * iterations / duration` to produce the throughput metric (also known as "audio hours per hour" or "speedup").

```
% python3 calculate_k6_throughput.py
...
1.0: 120 * x / 30.6 = y
2.0: 120 * x / 31.7 = y
4.0: 120 * x / 92.2 = y
8.0: 120 * x / 95.3 = y
16.0: 120 * x / 99.6 = y
24.0: 120 * x / 100.0 = y
32.0: 120 * x / 100.0 = y
```
