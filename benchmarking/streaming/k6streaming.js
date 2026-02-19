import { WebSocket } from 'k6/experimental/websockets';
import { setInterval, clearInterval } from 'k6/timers';
import { Trend } from 'k6/metrics';
import encoding from 'k6/encoding';
import { importedoptions } from './streamingstages.js';

export const options = importedoptions;

// Init variables
// Test file to stream.  The values mspm, bpm, and bps need to align with the test file
const audiofile = `${__ENV.K6_AUDIO_FILENAME}`;
const fdata = open(audiofile, 'b');


// How to calculate mspm, bps, and bpm:
// mspm has units of `Hz` and is the number of milliseconds we wait between sending websocket messages.
// bps has units of `bytes per second` and is a property of the audio file (and only the audio file). For example, the audio.8k.wav file has a bitrate of 128,000 kbit/s, which is equivalent to 16,000 kbytes/s. Therefore `bps` is set to `16000` for the audio.8k.wav file.
// bpm has units of `bytes per message` and is calculated from `mspm` and `bps`. First, convert the `mspm` from Hz to "number of messages per second", i.e. 50 Hz == 1000 ms / 20 messages. Then divide `bps` by the "number of messages per second", i.e. `16,000 / 20 == 800`. Use this for `bpm`.

// You can use the constant values below for the audio.8k.wav file.
// const mspm = 50; // milliseconds per message (Hz) (how frequently we send data to the onprem instance)
// const bps = 16000; // bytes per second (dependent on audio sample rate:  audio.8k.wav is 128,000 bit/s == 16,000 bytes/s)
// const bpm = 800; // bytes per message (dependent on mspm and bps:  50 Hz == 1000 ms / 20 messages means we calculate `bps / 20 == 16,000 / 20 == 800`)

// Alternatively, load the values from your environment variables.
const mspm = parseInt(`${__ENV.K6_MSPM}`);
const bps = parseInt(`${__ENV.K6_BPS}`);
const bpm = parseInt(`${__ENV.K6_BPM}`);

// LiveKit Inference Gateway settings
const model = `${__ENV.STT_MODEL}`;       // e.g. "deepgram/nova-3"
const language = `${__ENV.STT_LANGUAGE}`; // e.g. "en"
// For pcm_s16le encoding: sample_rate = bps / 2 (2 bytes per sample)
const sampleRate = __ENV.K6_SAMPLE_RATE ? parseInt(`${__ENV.K6_SAMPLE_RATE}`) : Math.floor(bps / 2);

// Custom Trend metric to track cursor latency
const interimResultsLatency = new Trend('interimResultsLatency', true);
const endpointingLatency = new Trend('endpointingLatency', true);

function sendAudioChunk(ws, data, amount, state) {
    if (state.finalized) return;

    let index = state.index;
    if (index >= data.byteLength) {
        state.finalized = true;
        ws.send(JSON.stringify({ type: "session.finalize" }));
        return;
    }

    let end = Math.min(index + amount, data.byteLength);
    let chunk = data.slice(index, end);
    let b64 = encoding.b64encode(chunk);
    ws.send(JSON.stringify({
        type: "input_audio",
        audio: b64,
    }));
    state.index = end;
}


export default function () {
    const url = `${__ENV.GATEWAY_WS_URL}`;   // wss://<host>/stt
    const token = `${__ENV.GATEWAY_TOKEN}`;
    const params = {
        headers: { 'Authorization': 'Bearer ' + token },
    };
    const ws = new WebSocket(url, null, params);
    let interval_id;
    let audio_state = { index: 0, finalized: false };
    let transcript_cursor = 0;
    let received_session_created = false;
    let last_word = null;

    ws.onopen = () => {
        // Send session.create to configure the STT session
        ws.send(JSON.stringify({
            type: "session.create",
            model: model,
            settings: {
                language: language,
                encoding: "pcm_s16le",
                sample_rate: sampleRate,
            },
        }));
    };
    ws.onmessage = (event) => {
        let msg = JSON.parse(event.data);

        if (msg.type === "session.created") {
            received_session_created = true;
            // Start streaming audio after session is established
            interval_id = setInterval(sendAudioChunk, mspm, ws, fdata, bpm, audio_state);
            return;
        }

        if (!received_session_created) return;

        if (msg.type === "interim_transcript" && msg.transcript) {
            // Gateway provides start and duration (seconds), same semantics as Deepgram Results
            let elapsed = (msg.start || 0) + (msg.duration || 0);
            let audio_cursor = audio_state.index / bps;
            // max_latency: time between when the first bit of audio was sent and when the gateway returned a result
            let max_latency = (audio_cursor - transcript_cursor) * 1000;
            // min_latency: time between when the last bit of audio was sent and when the gateway returned a result
            let min_latency = (audio_cursor - elapsed) * 1000;
            transcript_cursor = elapsed;
            interimResultsLatency.add((min_latency + max_latency) / 2);
        } else if (msg.type === "final_transcript" && msg.transcript) {
            let elapsed = (msg.start || 0) + (msg.duration || 0);
            let audio_cursor = audio_state.index / bps;
            transcript_cursor = elapsed;

            // Use word-level timing for endpointing latency
            if (msg.words && msg.words.length > 0) {
                let word = msg.words[msg.words.length - 1];
                if (word.end) {
                    last_word = word.end;
                }
            }
            if (last_word !== null) {
                endpointingLatency.add((audio_cursor - last_word) * 1000);
            }
        }
    };
    ws.onclose = () => {
        clearInterval(interval_id);
        if (!received_session_created) {
            console.log("No session.created received!");
        }
    };
    ws.onerror = (data) => {
        console.log("WebSocket error!");
        console.log(data);
        clearInterval(interval_id);
    };
}
