# Changelog

All notable changes to this Helm chart will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Fixed

- Fixed a misleading comment in the `03-basic-setup-onprem.yaml` sample file that wrongly suggested `engine.modelManager.volumes.customVolumeClaim.name` should be a `PersistentVolume` instead of a `PersistentVolumeClaim`

## [0.4.0] - 2024-07-25

### Added

- Introduced entity detection feature flag for API containers (`false` by default).
- Updated default container tags to July 2024 release. Refer to the [main Deepgram changelog](https://deepgram.com/changelog/deepgram-self-hosted-july-2024-release-240725) for additional details. Highlights include:
  - Support for Deepgram's new English/Spanish multilingual code-switching model
  - Beta support for entity detection for pre-recorded English audio
  - Beta support for improved redaction for pre-recorded English audio
  - Beta support for improved entity formatting for streaming English audio

### Removed

- Removed some items nested under `api.features` and `engine.features` sections in favor of opinionated defaults.

## [0.3.0] - 2024-07-18

### Added

- Allow specifying custom annotations for deployments.

## [0.2.3] - 2024-07-15

### Added

- Sample `values.yaml` file for on-premises/self-managed Kubernetes clusters.

### Fixed

- Resolves a mismatch between PVC and SC prefix naming convention.
- Resolves error when specifying custom service account names.

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


[unreleased]: https://github.com/deepgram/self-hosted-resources/compare/deepgram-self-hosted-0.4.0...HEAD
[0.4.0]: https://github.com/deepgram/self-hosted-resources/compare/deepgram-self-hosted-0.3.0...deepgram-self-hosted-0.4.0
[0.3.0]: https://github.com/deepgram/self-hosted-resources/compare/deepgram-self-hosted-0.2.3...deepgram-self-hosted-0.3.0
[0.2.3]: https://github.com/deepgram/self-hosted-resources/compare/deepgram-self-hosted-0.2.2-beta...deepgram-self-hosted-0.2.3
[0.2.2-beta]: https://github.com/deepgram/self-hosted-resources/compare/deepgram-self-hosted-0.2.1-beta...deepgram-self-hosted-0.2.2-beta
[0.2.1-beta]: https://github.com/deepgram/self-hosted-resources/compare/deepgram-self-hosted-0.2.0-beta...deepgram-self-hosted-0.2.1-beta
[0.2.0-beta]: https://github.com/deepgram/self-hosted-resources/compare/deepgram-self-hosted-0.1.1-alpha...deepgram-self-hosted-0.2.0-beta
[0.1.1-alpha]: https://github.com/deepgram/self-hosted-resources/compare/deepgram-self-hosted-0.1.0-alpha...deepgram-self-hosted-0.1.1-alpha
[0.1.0-alpha]: https://github.com/deepgram/self-hosted-resources/releases/tag/deepgram-self-hosted-0.1.0-alpha


