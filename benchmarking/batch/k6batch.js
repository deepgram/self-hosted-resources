import http from 'k6/http';
import { Counter } from 'k6/metrics';

// K6 Testing options
export const options = {
    scenarios: {
        concurrent_1: {
            executor: 'shared-iterations',
            startTime: '0s',
            gracefulStop: '10s',
            vus: 1,
            // An arbitrarily high number, we're looking at iterations/duration
            iterations: 10000,
            maxDuration: '30s',
            env: {SCENARIO_NAME: 'concurrent_1'},
        },
        concurrent_2: {
            executor: 'shared-iterations',
            startTime: '60s', // Needs to not overlap with previous scenario
            gracefulStop: '10s',
            vus: 2,
            iterations: 10000,
            maxDuration: '30s',
            env: {SCENARIO_NAME: 'concurrent_2'},
        },
        concurrent_3: {
            executor: 'shared-iterations',
            startTime: '100s', // Needs to not overlap with previous scenario
            gracefulStop: '10s',
            vus: 3,
            iterations: 10000,
            maxDuration: '90s',
            env: {SCENARIO_NAME: 'concurrent_3'},
        },
        concurrent_4: {
            executor: 'shared-iterations',
            startTime: '200s', // Needs to not overlap with previous scenario
            gracefulStop: '10s',
            vus: 4,
            iterations: 10000,
            maxDuration: '90s',
            env: {SCENARIO_NAME: 'concurrent_4'},
        },
        concurrent_6: {
            executor: 'shared-iterations',
            startTime: '300s', // Needs to not overlap with previous scenario
            gracefulStop: '10s',
           vus: 6,
            iterations: 10000,
            maxDuration: '90s',
            env: {SCENARIO_NAME: 'concurrent_6'},
        },
        concurrent_8: {
            executor: 'shared-iterations',
            startTime: '400s', // Needs to not overlap with previous scenario
            gracefulStop: '10s',
            vus: 8,
            iterations: 10000,
            maxDuration: '90s',
            env: {SCENARIO_NAME: 'concurrent_8'},
        },
        concurrent_16: {
            executor: 'shared-iterations',
            startTime: '500s', // Needs to not overlap with previous scenario
            gracefulStop: '10s',
            vus: 16,
            iterations: 10000,
            maxDuration: '90s',
            env: {SCENARIO_NAME: 'concurrent_16'},
        },
        concurrent_24: {
            executor: 'shared-iterations',
            startTime: '600s', // Needs to not overlap with previous scenario
            gracefulStop: '10s',
            vus: 24,
            iterations: 10000,
            maxDuration: '90s',
            env: {SCENARIO_NAME: 'concurrent_24'},
        },
        concurrent_32: {
            executor: 'shared-iterations',
            startTime: '700s', // Needs to not overlap with previous scenario
            gracefulStop: '10s',
            vus: 32,
            iterations: 10000,
            maxDuration: '90s',
            env: {SCENARIO_NAME: 'concurrent_32'},
        },
    },
};

// Init variables
const payload = [{
    "audio" : open(`${__ENV.K6_AUDIO_FILENAME}`, 'b'),
    "duration" : parseInt(`${__ENV.K6_AUDIO_DURATION_IN_SECONDS}`),
}]

const endpoint = `${__ENV.DG_HTTP_URL}`;
console.log("Benchmarking endpoint is:", endpoint);
if (endpoint.includes("api.deepgram.com")) {
    throw new Error("Benchmarking cannot be run on Deepgram's hosted endpoint.");
}

// Custom Trend metrics
const throughput = new Counter('Throughput', true);

const scenarios = [1, 2, 3, 4, 6, 8, 16, 24, 32];
const metrics_per_scenario = {};
scenarios.forEach(scenario => {
    const suffix = scenario.toString().padStart(2, '0');
    const counter_503 = new Counter(`count_503_${suffix}VU`);
    const counter_200 = new Counter(`count_200_${suffix}VU`);
    const counter_other_code = new Counter(`count_200_${suffix}VU`);
    metrics_per_scenario[`concurrent_${scenario}`] = [counter_503, counter_200, counter_other_code];
});

export default function () {
    const audio = payload[0].audio;
    const duration = payload[0].duration
    const audioFile = http.file(audio);

    const res = http.post(endpoint, audioFile.data);
    const body = JSON.parse(res.body);
    if (res.status != 200){
        console.log("Response error", res.status_text);
        if (res.status == 503) {
            metrics_per_scenario[__ENV.SCENARIO_NAME][0].add(1); // 503
        } else {
            metrics_per_scenario[__ENV.SCENARIO_NAME][2].add(1); // not 503 or 200
        }
    } else if (body.results.channels[0].alternatives[0].transcript === "") {
        throw new Error("Got empty transcript in response, something is broken.");
    } else {
        throughput.add(duration*1000);
        metrics_per_scenario[__ENV.SCENARIO_NAME][1].add(1); // 200
    }
}
