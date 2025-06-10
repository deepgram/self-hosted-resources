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

# Calculating the audio-specific values

The `.env_local` file specifies certain parameters that help the system calculate the throughput accurately.

## How to calculate mspm, bps, and bpm:
- mspm has units of `Hz` and is the number of milliseconds we wait between sending websocket messages.
- bps has units of `bytes per second` and is a property of the audio file (and only the audio file). For example, the audio.8k.wav file has a bitrate of 128,000 kbit/s, which is equivalent to 16,000 kbytes/s. Therefore `bps` is set to `16000` for the audio.8k.wav file.
- bpm has units of `bytes per message` and is calculated from `mspm` and `bps`. First, convert the `mspm` from Hz to "number of messages per second", i.e. 50 Hz == 1000 ms / 20 messages. Then divide `bps` by the "number of messages per second", i.e. `16,000 / 20 == 800`. Use this for `bpm`.

You can use the constant values below for an 8kHz, 16-bit depth PCM file.

- const mspm = 50; // milliseconds per message (Hz) (how frequently we send data to the onprem instance)
- const bps = 16000; // bytes per second (dependent on audio sample rate:  audio.8k.wav is 128,000 bit/s == 16,000 bytes/s)
- const bpm = 800; // bytes per message (dependent on mspm and bps:  50 Hz == 1000 ms / 20 messages means we calculate `bps / 20 == 16,000 / 20 == 800`)

The below script may be helpful for calculating what those values should be:

```sh
# Get WAV file info using ffprobe
ffprobe -v quiet -show_streams -of json input.wav | jq '.streams[0] | {sample_rate: .sample_rate, bits_per_sample: .bits_per_sample, channels: .channels}'

# Or using soxi (from sox package)
soxi input.wav

# Calculate the values (assuming 50ms chunks)
SAMPLE_RATE=$(soxi -r input.wav)
BITS_PER_SAMPLE=$(soxi -b input.wav)
CHANNELS=$(soxi -c input.wav)

# Calculate BPS (Bytes Per Second)
BPS=$((SAMPLE_RATE * (BITS_PER_SAMPLE/8) * CHANNELS))

# Set MSPM (Milliseconds Per Message)
MSPM=50

# Calculate BPM (Bytes Per Message)
BPM=$((BPS * MSPM / 1000))

echo "Recommended K6 settings:"
echo "BPS (Bytes Per Second): $BPS"
echo "MSPM (Milliseconds Per Message): $MSPM"
echo "BPM (Bytes Per Message): $BPM"
```
