# Changelog

All notable changes to this Helm chart will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- Resolves a mismatch between PVC and SC prefix naming convention.

### Changed

- Make `imagePullSecrets` optional.

## [0.2.2-beta] - 2024-06-27

### Added

- Adds more verbose logging for audio content length.
- Keeps our software up-to-date.
- See the [changelog](https://deepgram.com/changelog/deepgram-on-premises-june-2024-release-240627) associated with this routine monthly release.

## [0.2.1-beta] - 2024-06-24

### Added

- Restart Deepgram containers automatically when underlying ConfigMaps have been modified.

## [0.2.0-beta] - 2024-06-20

### Added
- Support for managing node autoscaling with [cluster-autoscaler](https://github.com/kubernetes/autoscaler).
- Support for pod autoscaling of Deepgram components.
- Support for keeping the upstream Deepgram License server as a backup even when the License Proxy is deployed. See `licenseProxy.keepUpstreamServerAsBackup` for details.

### Changed

- Initial installation replica count values moved from `scaling.static.{api,engine}.replicas` to `scaling.replicas.{api,engine}`.
- License Proxy is no longer manually scaled. Instead, scaling can be indirectly controlled via `licenseProxy.{enabled,deploySecondReplica}`.
- Labels for Deepgram dedicated nodes in the sample `cluster-config.yaml` for AWS, and the `nodeAffinity` sections of the sample `values.yaml` files. The key has been renamed from `deepgram/nodeType` to `k8s.deepgram.com/node-type`, and the values are no longer prepended with `deepgram`.
- AWS EFS model download job hook delete policy changed to `before-hook-creation`.
- Concurrency limit moved from API (`api.concurrencyLimit.activeRequests`) to Engine level (`engine.concurrencyLimit.activeRequests`).

## [0.1.1-alpha] - 2024-06-03

### Added

- Various documentation improvements

## [0.1.0-alpha] - 2024-05-31

### Added

- Initial implementation of the Helm chart.


[unreleased]: https://github.com/deepgram/self-hosted-resources/compare/deepgram-self-hosted-0.2.2-beta...HEAD
[0.2.2-beta]: https://github.com/deepgram/self-hosted-resources/compare/deepgram-self-hosted-0.2.1-beta...deepgram-self-hosted-0.2.2-beta
[0.2.1-beta]: https://github.com/deepgram/self-hosted-resources/compare/deepgram-self-hosted-0.2.0-beta...deepgram-self-hosted-0.2.1-beta
[0.2.0-beta]: https://github.com/deepgram/self-hosted-resources/compare/deepgram-self-hosted-0.1.1-alpha...deepgram-self-hosted-0.2.0-beta
[0.1.1-alpha]: https://github.com/deepgram/self-hosted-resources/compare/deepgram-self-hosted-0.1.0-alpha...deepgram-self-hosted-0.1.1-alpha
[0.1.0-alpha]: https://github.com/deepgram/self-hosted-resources/releases/tag/deepgram-self-hosted-0.1.0-alpha


