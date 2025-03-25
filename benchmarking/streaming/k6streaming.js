import { WebSocket } from 'k6/experimental/websockets';
import { setInterval, clearInterval } from 'k6/timers';
import { Trend } from 'k6/metrics';
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

// Only one of these can be true:
const measureInterimResults = true;  // i.e. is_final=true
const measureEndpointing = true;  // i.e. speech_final=true


// Custom Trend metric to track cursor latency
const interimResultsLatency = new Trend('interimResultsLatency', true);
const endpointingLatency = new Trend('endpointingLatency', true);

function datainterval(ws, data, amount, d) {
    let index = d.index
    ws.send(data.slice(index, index + amount));
    d.index = index + amount; // update so we can track latency
}


export default function () {
    const url = `${__ENV.DG_WS_URL}`;
    const params = {
      headers: { 'Authorization': 'Token ' + `${__ENV.DEEPGRAM_API_KEY}` },
    };
    const ws = new WebSocket(url, null, params);
    let interval_id;
    let audio_state = { index: 0 }; // for tracking how much data has been sent
    let transcript_cursor = 0;
    let received_metadata = false;
    let last_word = null;

    ws.onopen = () => {
        // console.log('WebSocket connection established!');
        interval_id = setInterval(datainterval, mspm, ws, fdata, bpm, audio_state);
    };
    ws.onmessage = (data) => {
        //  console.log('a message received');
        let dg_results = JSON.parse(data.data);
        // console.log(dg_results);

        if (measureInterimResults && (dg_results.type == "Results") && (dg_results.is_final == false)) {
            let elapsed = dg_results.start + dg_results.duration; // times are in seconds
            let audio_cursor = audio_state.index / bps;
            // The max_latency is the amount of time between when the first bit of audio was sent and when Deepgram returned a result.
            let max_latency = (audio_cursor - transcript_cursor) * 1000; // times are in ms
            // The min_latency is the amount of time between when the last bit of audio was sent and when Deepgram returned a result.
            let min_latency = (audio_cursor - elapsed) * 1000; // times are in ms
            transcript_cursor = elapsed;
            // console.log("Cursor latency: ", (audio_state.index / bps) - elapsed);

            // We average the min_latency and max_latency to calculate the average amount of time it took to return an interim result.
            interimResultsLatency.add((min_latency + max_latency) / 2);
        } else if (measureEndpointing && (dg_results.type == "Results") && (dg_results.is_final == true)) {
            // Logic for endpoint latency based on endpointing
            // If the last word is not empty, set last_word to the last word end time
            let word = dg_results.channel.alternatives[0].words.at(-1)
            // Update transcript cursor for interim result latency
            let elapsed = dg_results.start + dg_results.duration; // times are in seconds
            let audio_cursor = audio_state.index / bps;
            transcript_cursor = elapsed;

            if (dg_results.speech_final == true) {
                if (word.word) {
                    last_word = word.end
                }
                endpointingLatency.add((audio_cursor - last_word) * 1000);
                // console.log("Endpointing Audio Last Word: ", last_word)
            }
        } else if (measureEndpointing && (dg_results.type == "UtteranceEnd")) {
            // Logic for endpoint latency based on UtteranceEnd
            // console.log("UtteranceEnd.  Current last word: ", last_word, " last_word_end: ", dg_results.last_word_end)

            if (last_word < dg_results.last_word_end) {
                // Last word is only updated on speech_final or UtteranceEnd
                // This is true when the last final result was not a speech_final and UtteranceEnd then fires.
                last_word = dg_results.last_word_end
                let audio_cursor = audio_state.index / bps;
                console.log("Adding last word from utterance end", last_word, " Audio cursor: ", audio_cursor)
                endpointingLatency.add((audio_cursor - last_word) * 1000);
            }
        }


        if (dg_results.type == "Metadata") {
            received_metadata = true;
        }
    };
    ws.onclose = (data) => {
        // console.log('Closing connection')
        clearInterval(interval_id);
        if (!received_metadata) {
            console.log("No metadata received!!!")
        }
    }
    ws.onerror = (data) => {
        console.log("Websocket error!");
        console.log(data);
        clearInterval(interval_id);
    }
}
