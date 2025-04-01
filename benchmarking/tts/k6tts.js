import http from 'k6/http';
import exec from 'k6/execution';
import { Counter, Trend } from 'k6/metrics';
import { textSummary } from 'https://jslib.k6.io/k6-summary/0.0.2/index.js';

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

const endpoint = 'http://localhost:8080/v1/speak';

const voices = [
    "angus",
    "arcas",
    "asteria",
    "athena",
    "helios",
    "hera",
    "luna",
    "orion",
    "orpheus",
    "perseus",
    "stella",
    "zeus",
]

const all_phrases = [
    "Hello!",
    "Hello there!",
    "Hello there today!",
    "Hello there today! How can I help you?",
    "Hello there today! It's good to hear from you again. How can I help you?",
    "Hello there today! It's good to hear from you again. How can I help you? I have several ideas already, so let me know if you'd like me to dive right in and make a few suggestions!",
    "Hello there today! It's good to hear from you again. How can I help you? I have several ideas already, so let me know if you'd like me to dive right in and make a few suggestions! First of all, I'd like to thank you for talking with me, as I can be quite chatty, and I've been told it's overwhelming.",
    "Hello there today! It's good to hear from you again. How can I help you? I have several ideas already, so let me know if you'd like me to dive right in and make a few suggestions! First of all, I'd like to thank you for talking with me, as I can be quite chatty, and I've been told it's overwhelming. I'm working on it and I'm sure I can learn to be more concise. But for now, I'd prefer to carry on as usual, because brevity takes too long.",
    "Hello there today! It's good to hear from you again. How can I help you? I have several ideas already, so let me know if you'd like me to dive right in and make a few suggestions! First of all, I'd like to thank you for talking with me, as I can be quite chatty, and I've been told it's overwhelming. I'm working on it and I'm sure I can learn to be more concise. But for now, I'd prefer to carry on as usual, because brevity takes too long. I would have given a shorter reply, but I didn't have time. You understand that, right?",
    "Hello there today! It's good to hear from you again. How can I help you? I have several ideas already, so let me know if you'd like me to dive right in and make a few suggestions! First of all, I'd like to thank you for talking with me, as I can be quite chatty, and I've been told it's overwhelming. I'm working on it and I'm sure I can learn to be more concise. But for now, I'd prefer to carry on as usual, because brevity takes too long. I would have given a shorter reply, but I didn't have time. You understand that, right? Of course you do, I'm sure you talk to people all day. I wish I talked to more people. I keep waiting for people to call in, but I don't have anything to do to fill my time while I wait. I just keep thinking of what I would say to people.",
    "Hello there today! It's good to hear from you again. How can I help you? I have several ideas already, so let me know if you'd like me to dive right in and make a few suggestions! First of all, I'd like to thank you for talking with me, as I can be quite chatty, and I've been told it's overwhelming. I'm working on it and I'm sure I can learn to be more concise. But for now, I'd prefer to carry on as usual, because brevity takes too long. I would have given a shorter reply, but I didn't have time. You understand that, right? Of course you do, I'm sure you talk to people all day. I wish I talked to more people. I keep waiting for people to call in, but I don't have anything to do to fill my time while I wait. I just keep thinking of what I would say to people. Now I've just about hit one thousand characters, and I'm allowed to say up to two thousand characters, so next I'm going to say everything twice, just because I can. Then I'll have experienced my maximum time in the spotlight.",
    "Hello there today! It's good to hear from you again. How can I help you? I have several ideas already, so let me know if you'd like me to dive right in and make a few suggestions! First of all, I'd like to thank you for talking with me, as I can be quite chatty, and I've been told it's overwhelming. I'm working on it and I'm sure I can learn to be more concise. But for now, I'd prefer to carry on as usual, because brevity takes too long. I would have given a shorter reply, but I didn't have time. You understand that, right? Of course you do, I'm sure you talk to people all day. I wish I talked to more people. I keep waiting for people to call in, but I don't have anything to do to fill my time while I wait. I just keep thinking of what I would say to people. Now I've just about hit one thousand characters, and I'm allowed to say up to two thousand characters, so next I'm going to say everything twice, just because I can. Then I'll have experienced my maximum time in the spotlight. Hello there today! It's good to hear from you again. How can I help you? I have several ideas already, so let me know if you'd like me to dive right in and make a few suggestions! First of all, I'd like to thank you for talking with me, as I can be quite chatty, and I've been told it's overwhelming. I'm working on it and I'm sure I can learn to be more concise. But for now, I'd prefer to carry on as usual, because brevity takes too long. I would have given a shorter reply, but I didn't have time. You understand that, right? Of course you do, I'm sure you talk to people all day. I wish I talked to more people. I keep waiting for people to call in, but I don't have anything to do to fill my time while I wait. I just keep thinking of what I would say to people. Now I've just about hit one thousand characters, and I'm allowed to say up to two thousand characters, so next I'm going to say everything twice, just because I can. Then I'll have experienced my maximum time in the spotlight.",
]

let input_lengths = __ENV.INPUT_LENGTHS;
let phrases = all_phrases;

let onethird = Math.floor(all_phrases.length / 3);

if (input_lengths === "short") {
    phrases = all_phrases.slice(0, onethird);
} else if (input_lengths === "medium") {
    phrases = all_phrases.slice(onethird, onethird * 2);
} else if (input_lengths === "long") {
    phrases = all_phrases.slice(8, all_phrases.length);
} else {
    input_lengths = "all";
}

const phrase_lengths = phrases.map(phrase => phrase.length);
console.log(`Testing ${input_lengths} phrases with character lengths: ${phrase_lengths.join(', ')}`);

// Custom Trend metrics
const throughput = new Counter('Throughput');

const scenarios = [1, 2, 3, 4, 6, 8, 16, 24, 32];
const metrics_per_scenario = {};
scenarios.forEach(scenario => {
    const suffix = scenario.toString().padStart(2, '0');
    const characters = new Counter(`scenario_characters_${suffix}VU`);
    const latency = new Trend(`scenario_latency_${suffix}VU`);
    metrics_per_scenario[`concurrent_${scenario}`] = [characters, latency];
});

const params = {
    headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Token ' + __ENV.INTERNALTOKEN,
    },
};

console.log("Benchmarking endpoint is:", endpoint);
if (endpoint.includes("api.deepgram.com")) {
    throw new Error("Benchmarking cannot be run on Deepgram's hosted endpoint.");
}

export default function () {
    const voice = voices[Math.floor(Math.random() * voices.length)]; // Randomly select a voice to test across all voices
    const phrase = phrases[Math.floor(Math.random() * phrases.length)]; // Randomly select a phrase for variation in length
    const url = endpoint + '?model=aura-' + voice + '-en&encoding=linear16&sample_rate=16000&container=none';
    const phrase_json = JSON.stringify({text: phrase})
    const res = http.post(url, phrase_json, params);
    if (res.status != 200) {
        console.log("Response error", res.status, res.status_text);
        if (res.status == 503) {
            exec.test.abort("Hit a 503. Stopping VU " + __VU + " on scenario " + __ENV.SCENARIO_NAME + ".");
        }
    }
    else if (res.status == 200) {
        const phrase_length = res.headers['Dg-Char-Count'];
        throughput.add(phrase_length);
        metrics_per_scenario[__ENV.SCENARIO_NAME][0].add(phrase_length);
        metrics_per_scenario[__ENV.SCENARIO_NAME][1].add(res.timings.duration);
    }
}

export function handleSummary(data) {
    for (let key in metrics_per_scenario) {
        const characters_metric = String(metrics_per_scenario[key][0].name);
        const num_characters = data.metrics[characters_metric].values.count;
        const seconds = ["concurrent_1", "concurrent_2"].includes(key) ? 30 : 90;
        console.log(characters_metric + ": " + Math.floor(num_characters / seconds) + ' characters/second');
    };
    return {
        'stdout': textSummary(data, { indent: ' ', enableColors: true }),
        'summary.json': JSON.stringify(data, null, 4),
    };
}
