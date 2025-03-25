# Benchmark Scripts

`streaming/k6streaming.js` defines a [k6 script](https://k6.io/docs/get-started/running-k6/) for benchmarking cursor latency for streaming.

`batch/k6batch.js` defines a similar k6 script for batch/prerecorded.

## Installation

Install k6 using `sudo apt-get install k6`. This code was tested on `k6 --version == v0.50.0`.

## Streaming

Update the values in `.env_local` based on your environment.

To run the k6 streaming script, run:

```sh
export $(cat .env_local <(echo "K6_TARGET=15") | xargs) && k6 run streaming/k6streaming.js
```

`streaming/streamingstages.js` controls the k6 configuration and is imported into `k6streaming.js` on line 4. Update the stages in `streamingstages.js` to control how many streams are started and how long they run for.

The `K6_TARGET` variable sets the max number of VUs to reach and is required.  This can be set in `.env_local` but is useful to set in the command-line here to parameterize the running of multiple tests.

If you receive the error message `at least one has abortOnFail enabled, stopping test prematurely`, change `abortOnFail` in `streamingstages.js` to `false`.


## Batch / Prerecorded

Update the values in `.env_local` based on your environment.

To run the k6 batch script, run:

```sh
export $(cat .env_local | xargs) && k6 run batch/k6batch.js
```

