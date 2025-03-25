// K6 Testing options
const target = parseInt(`${__ENV.K6_TARGET}`);
export const importedoptions = {
    stages: [
        { target: target, duration: '20s' }, // Since this is the first one, it means scale from 0 to target VUs in 20s
        { target: target, duration: '120s' }, // Stay at target VUs for 120s
        // By default, K6 allows 30 seconds for the requests to finish (i.e. a graceful shutdown)
    ],
    thresholds: {
        // Not necessarily the most fine-tuned thresholds, but a reasonable start. Settings should be adjusted for interim_results=true/false
        'interimResultsLatency': [{ threshold: 'p(50) < 750', abortOnFail: true }, { threshold: 'p(90) < 1500', abortOnFail: true }],
        'endpointingLatency': [{ threshold: 'p(50) < 1000', abortOnFail: false }, { threshold: 'p(90) < 3000', abortOnFail: false }],
    },
};

// If you want to run a basic test, define a single stage like this:
// {target: 1, duration: '10s'},

// Note that the audio file audio.8k.wav is 20s long, which may have a minor impact on results depending on your stages.

