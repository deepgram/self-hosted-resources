import http from 'k6/http';
import exec from 'k6/execution';
import { Counter } from 'k6/metrics';

// K6 Testing options
export const options = {
    scenarios: {
        concurrent_1: {
            executor: 'shared-iterations',
            startTime: '0s',
            gracefulStop: '10s',
            // A number specifying the number of VUs to run concurrently.
            vus: 1,
            // An arbitrarily high number, we're looking at iterations/duration
            iterations: 10000,
            maxDuration: '30s',
        },
        concurrent_2: {
            executor: 'shared-iterations',
            startTime: '60s', // Needs to not overlap with previous scenario
            gracefulStop: '10s',
            // A number specifying the number of VUs to run concurrently.
            vus: 2,
            iterations: 10000,
            maxDuration: '30s',
        },
        concurrent_4: {
            executor: 'shared-iterations',
            startTime: '100s', // Needs to not overlap with previous scenario
            gracefulStop: '10s',
            // A number specifying the number of VUs to run concurrently.
            vus: 4,
            iterations: 10000,
            maxDuration: '90s',
        },
        concurrent_8: {
            executor: 'shared-iterations',
            startTime: '200s', // Needs to not overlap with previous scenario
            gracefulStop: '10s',
            // A number specifying the number of VUs to run concurrently.
           vus: 8,
            iterations: 10000,
            maxDuration: '90s',
        },
        concurrent_16: {
            executor: 'shared-iterations',
            startTime: '300s', // Needs to not overlap with previous scenario
            gracefulStop: '10s',
            // A number specifying the number of VUs to run concurrently.
            vus: 16,
            iterations: 10000,
            maxDuration: '90s',
        },
        concurrent_24: {
            executor: 'shared-iterations',
            startTime: '400s', // Needs to not overlap with previous scenario
            gracefulStop: '10s',
            // A number specifying the number of VUs to run concurrently.
            vus: 24,
            iterations: 10000,
            maxDuration: '90s',
        },
        concurrent_32: {
            executor: 'shared-iterations',
            startTime: '500s', // Needs to not overlap with previous scenario
            gracefulStop: '10s',
            // A number specifying the number of VUs to run concurrently.
            vus: 32,
            iterations: 10000,
            maxDuration: '90s',
        },
    },
};

// Custom Trend metrics
const throughput = new Counter('Throughput', true);

// Read the environment variables.
const audio_location = __ENV.AUDIO_LOCATION;
const duration = __ENV.DURATION;
const sits_features_string = __ENV.SITS_FEATURES;

const params = {
    headers: {
        'Content-Type': 'application/json',
    },
};

const endpoint = 'http://localhost:8080/v1/listen';

// Check if the environment variables are set.
if (!audio_location || !duration) {
    console.error('The AUDIO_LOCATION and DURATION environment variables must be set.');
}

let sits_features = "";
const supported_sits_features = ["sentiment", "intents", "topics", "summarize"];
if (sits_features_string) {
    const input_features = sits_features_string.split(",");
    input_features.forEach(feature => {
        if(!supported_sits_features.includes(feature)) {
            throw new Error(`Invalid feature found: ${feature}. Supported features are: ${supported_sits_features.join(", ")}`);
        }
    });
    sits_features = '&' + input_features
        .map(feature => feature.trim().toLowerCase() === 'summarize' ? `${feature}=v2` : `${feature}=true`)
        .join('&');
}

const url = endpoint + '?model=nova-2' + sits_features;

console.log("Benchmarking endpoint is:", url);
if (endpoint.includes("api.deepgram.com")) {
    throw new Error("Benchmarking cannot be run on Deepgram's hosted endpoint.");
}

const audio_json = JSON.stringify({url: audio_location});

export default function () {
    const res = http.post(url, audio_json, params);
    const body = JSON.parse(res.body);
    if (res.status != 200) {
        console.log("Response error", res.status_code, res.status_text, res);
        if (res.status == 503) {
            exec.test.abort("Hit a 503. Stopping VU " + __VU + ".");
        }
    } else if (body.results.channels[0].alternatives[0].transcript === "") {
        throw new Error("Got empty transcript in response, something is broken.");
    } else {
        throughput.add(duration*1000);
    }
}
