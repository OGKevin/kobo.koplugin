# Changelog

## [0.4.0](https://github.com/OGKevin/kobo.koplugin/compare/v0.3.0...v0.4.0) (2026-01-11)

### Features

- **bluetooth:** add Libra 2 support ([#145](https://github.com/OGKevin/kobo.koplugin/issues/145))
  ([5e259d4](https://github.com/OGKevin/kobo.koplugin/commit/5e259d4f68c4abde6b0a8249b6427547e5a3b517))
- **bluetooth:** add setting to control device ready notifications
  ([#175](https://github.com/OGKevin/kobo.koplugin/issues/175))
  ([34a0377](https://github.com/OGKevin/kobo.koplugin/commit/34a037729b4b7ade41359da2f0a86b195d26c08e)),
  closes [#70](https://github.com/OGKevin/kobo.koplugin/issues/70)
- **BT key bindings:** add option to dismiss pop-ups
  ([#154](https://github.com/OGKevin/kobo.koplugin/issues/154))
  ([c92f872](https://github.com/OGKevin/kobo.koplugin/commit/c92f872f906b5db96b40e958de7bbf323a07ad7b)),
  closes [#149](https://github.com/OGKevin/kobo.koplugin/issues/149)
- **virtual library:** add Kobo DRM decryption support
  (https://github.com/OGKevin/kobo.koplugin/pull/172)
  ([cf8c23a](https://github.com/OGKevin/kobo.koplugin/commit/cf8c23ab4eb3c25347dacc0c750b418d808af6be))
- **virtual library:** set virtual library as Home folder
  ([#159](https://github.com/OGKevin/kobo.koplugin/issues/159))
  ([353c938](https://github.com/OGKevin/kobo.koplugin/commit/353c938bc6e5340c19e2a16b2f259afd8005a980))

### Bug Fixes

- being able to disable the plugin ([#146](https://github.com/OGKevin/kobo.koplugin/issues/146))
  ([a06ffbe](https://github.com/OGKevin/kobo.koplugin/commit/a06ffbecc7b4f6557e6ab38ab0df4c669dd0fc58))
- **bluetooth:** exit early when fd is nil
  ([#153](https://github.com/OGKevin/kobo.koplugin/issues/153))
  ([5ed4833](https://github.com/OGKevin/kobo.koplugin/commit/5ed48338ff1c1324e3bbd00589db9e49b56c802d))
- **bluetooth:** speed up connect when no known WiFi
  ([#150](https://github.com/OGKevin/kobo.koplugin/issues/150))
  ([d5183db](https://github.com/OGKevin/kobo.koplugin/commit/d5183db508a13fc9e634834d1c9b4b76ed4011b2)),
  closes [#117](https://github.com/OGKevin/kobo.koplugin/issues/117)
- **BT key bindings:** support registered actions after init
  ([#148](https://github.com/OGKevin/kobo.koplugin/issues/148))
  ([b7118b4](https://github.com/OGKevin/kobo.koplugin/commit/b7118b4a20868c988956811507f23cfda72bc516)),
  closes [#138](https://github.com/OGKevin/kobo.koplugin/issues/138)
- **virtual library:** pass mimetype args to hasProvider
  ([#174](https://github.com/OGKevin/kobo.koplugin/issues/174))
  ([8abac71](https://github.com/OGKevin/kobo.koplugin/commit/8abac719711403395b1548187e3b0beb09cd1359)),
  closes [#124](https://github.com/OGKevin/kobo.koplugin/issues/124)
  [#48](https://github.com/OGKevin/kobo.koplugin/issues/48)
- **virtual library:** remove refresh on device wakeup
  ([#162](https://github.com/OGKevin/kobo.koplugin/issues/162))
  ([787236e](https://github.com/OGKevin/kobo.koplugin/commit/787236edd68ee4080baf0af359235b431d6911a6)),
  closes [#161](https://github.com/OGKevin/kobo.koplugin/issues/161)
- **virtual library:** resolve paths in realpath
  ([#159](https://github.com/OGKevin/kobo.koplugin/issues/159))
  ([353c938](https://github.com/OGKevin/kobo.koplugin/commit/353c938bc6e5340c19e2a16b2f259afd8005a980)),
  closes [#155](https://github.com/OGKevin/kobo.koplugin/issues/155)
- **virtual library:** support navigation to virtual paths
  ([#166](https://github.com/OGKevin/kobo.koplugin/issues/166))
  ([7e0f0e1](https://github.com/OGKevin/kobo.koplugin/commit/7e0f0e1d8210984ae9b572e8facfcddf43186a9e)),
  closes [#155](https://github.com/OGKevin/kobo.koplugin/issues/155)
- **virtual_library:** override default docsetting
  ([#152](https://github.com/OGKevin/kobo.koplugin/issues/152))
  ([a624456](https://github.com/OGKevin/kobo.koplugin/commit/a624456c04c74614f7aeb83b6288344a80c1ae69)),
  closes [#129](https://github.com/OGKevin/kobo.koplugin/issues/129)

### Performance Improvements

- **bluetooth:** bluetooth now turns on faster when WiFi is initially off
  ([#150](https://github.com/OGKevin/kobo.koplugin/issues/150))
  ([d5183db](https://github.com/OGKevin/kobo.koplugin/commit/d5183db508a13fc9e634834d1c9b4b76ed4011b2))
- optimize DRM detection by using database lookup instead of attempting to open the file
  ([#169](https://github.com/OGKevin/kobo.koplugin/issues/169))
  ([53f4942](https://github.com/OGKevin/kobo.koplugin/commit/53f4942273fbacd44925e803775ee2e974657c2c)),
  closes [#73](https://github.com/OGKevin/kobo.koplugin/issues/73)
- resume from suspend no longer refreshes virtual library this means that resuming from suspend is
  faster ([#162](https://github.com/OGKevin/kobo.koplugin/issues/162))
  ([787236e](https://github.com/OGKevin/kobo.koplugin/commit/787236edd68ee4080baf0af359235b431d6911a6)),
  closes [#161](https://github.com/OGKevin/kobo.koplugin/issues/161)

## [0.3.0](https://github.com/OGKevin/kobo.koplugin/compare/v0.2.6...v0.3.0) (2025-12-27)

### ⚠ BREAKING CHANGES

- **bluetooth:** Key binding action IDs are now prefixed with category names (e.g.,
  "Reader:next*page" instead of "next_page"). Existing key bindings must be manually reassigned
  after updating. This can be done by going to: Network -> Bluetooth -> Paired Devices -> Select a
  device -> \_Reset key bindings*

### Features

- **bluetooth:** add trust/untrust support for Bluetooth devices
  ([#85](https://github.com/OGKevin/kobo.koplugin/issues/85))
  ([c0e2a77](https://github.com/OGKevin/kobo.koplugin/commit/c0e2a77e4b8133d388e223a3b415ec7c8b8555b2))
- **bluetooth:** auto detect and connect to devices
  ([#87](https://github.com/OGKevin/kobo.koplugin/issues/87))
  ([ff36cfc](https://github.com/OGKevin/kobo.koplugin/commit/ff36cfcdd09e0aa49e7590aa29ff3dfd1f9bdaa4))
- **bluetooth:** dynamic key binding actions from Dispatcher
  ([#92](https://github.com/OGKevin/kobo.koplugin/issues/92))
  ([889f63d](https://github.com/OGKevin/kobo.koplugin/commit/889f63d0e677b1ca5885106332b90cc04fa2b12d))

### Bug Fixes

- **virtual library:** detect DRM by checking content
  ([#127](https://github.com/OGKevin/kobo.koplugin/issues/127))
  ([d5b8eb6](https://github.com/OGKevin/kobo.koplugin/commit/d5b8eb681c5bdf85268b165a3734257c7d76be2d))

## [0.2.6](https://github.com/OGKevin/kobo.koplugin/compare/v0.2.5...v0.2.6) (2025-12-09)

### Features

- **bluetooth:** add auto-resume option after device wake
  ([#109](https://github.com/OGKevin/kobo.koplugin/issues/109))
  ([9214113](https://github.com/OGKevin/kobo.koplugin/commit/9214113c14cfa430de687c6ae536ea786d404b22))
- **bluetooth:** show status in reader footer
  ([#111](https://github.com/OGKevin/kobo.koplugin/issues/111))
  ([d233c6c](https://github.com/OGKevin/kobo.koplugin/commit/d233c6cb39e6ae7714f9734743c8c2a2e44a288d))

### Bug Fixes

- **bluetooth:** reset auto-standby timer on key input
  ([1c66bf3](https://github.com/OGKevin/kobo.koplugin/commit/1c66bf37d0a3e607c6d25b1212b5482405ca7e6c))

## [0.2.5](https://github.com/OGKevin/kobo.koplugin/compare/v0.2.4...v0.2.5) (2025-12-07)

### Features

- **bluetooth:** add reset key bindings option
  ([#93](https://github.com/OGKevin/kobo.koplugin/issues/93))
  ([f1b918a](https://github.com/OGKevin/kobo.koplugin/commit/f1b918a1e4b826a79a1e28d35035462608a19682))
- **virtual library:** add enablement toggle
  ([#96](https://github.com/OGKevin/kobo.koplugin/issues/96))
  ([9b72f3f](https://github.com/OGKevin/kobo.koplugin/commit/9b72f3f1ca0e83ba3e3c4f988dc24de61dbca203))

### Bug Fixes

- **virtual library:** improve book encryption check
  ([#100](https://github.com/OGKevin/kobo.koplugin/issues/100))
  ([895d0cd](https://github.com/OGKevin/kobo.koplugin/commit/895d0cd4d6a110b9ca659f5258e7cd921f172038))

## [0.2.4](https://github.com/OGKevin/kobo.koplugin/compare/v0.2.3...v0.2.4) (2025-12-05)

### Features

- **bluetooth:** add "Forget" button to device options menu
  ([bb5aefb](https://github.com/OGKevin/kobo.koplugin/commit/bb5aefb4d1ac5fb2b854c9c84bf1e5df783ec2f6))
- **bluetooth:** add dispatcher actions for control
  ([#63](https://github.com/OGKevin/kobo.koplugin/issues/63))
  ([1ac9a9e](https://github.com/OGKevin/kobo.koplugin/commit/1ac9a9ea3f8b81ae8d470eb050536522eda1e68a))

### Bug Fixes

- **bluetooth:** add refresh button to scan results menu
  ([#82](https://github.com/OGKevin/kobo.koplugin/issues/82))
  ([f4cc2e9](https://github.com/OGKevin/kobo.koplugin/commit/f4cc2e970dbc7ce2d7784564d1de379894b8141a))
- **bluetooth:** correct MTK device check in isDeviceSupported
  ([#79](https://github.com/OGKevin/kobo.koplugin/issues/79))
  ([2b1a8ed](https://github.com/OGKevin/kobo.koplugin/commit/2b1a8eda5b862a8d13611fec38b14311a1cb8048))

## [0.2.3](https://github.com/OGKevin/kobo.koplugin/compare/v0.2.2...v0.2.3) (2025-12-04)

### Bug Fixes

- **bluetooth:** only show reachable and named devices in results
  ([#62](https://github.com/OGKevin/kobo.koplugin/issues/62))
  ([2714605](https://github.com/OGKevin/kobo.koplugin/commit/2714605d2e5aff4a06bb05f9c05635859742c10e))
- **bluetooth:** show configure keys button only when connected
  ([#66](https://github.com/OGKevin/kobo.koplugin/issues/66))
  ([09ac717](https://github.com/OGKevin/kobo.koplugin/commit/09ac7176bc8cd83825869b243dd33e23af3dc7ab))
- **ui:** make device scanning asynchronous with callback
  ([#61](https://github.com/OGKevin/kobo.koplugin/issues/61))
  ([c6bbfbd](https://github.com/OGKevin/kobo.koplugin/commit/c6bbfbd368fb4803a241eb6b4ee5d9491fc3b597))

## [0.2.2](https://github.com/OGKevin/kobo.koplugin/compare/v0.2.1...v0.2.2) (2025-12-02)

### Bug Fixes

- **bluetooth:** use isolated reader for BT input
  ([#41](https://github.com/OGKevin/kobo.koplugin/issues/41))
  ([26c422a](https://github.com/OGKevin/kobo.koplugin/commit/26c422ae59d652a3d86ee501d2fb7f7fc86a7d7e))
- **ui:** unify device menus and prevent keybindings stacking
  ([#46](https://github.com/OGKevin/kobo.koplugin/issues/46))
  ([fa2ecc8](https://github.com/OGKevin/kobo.koplugin/commit/fa2ecc86c9c8dbcebebeecf5bc46e2d44cd1e45d))

## [0.2.1](https://github.com/OGKevin/kobo.koplugin/compare/v0.2.0...v0.2.1) (2025-12-01)

### Bug Fixes

- ensure WiFi is enabled before Bluetooth connection
  ([#35](https://github.com/OGKevin/kobo.koplugin/issues/35))
  ([3f7931f](https://github.com/OGKevin/kobo.koplugin/commit/3f7931fa89d4e9136c30f67050654efb4739f9a5))
- virtual library discovery to support UUID-style book IDs
  ([#32](https://github.com/OGKevin/kobo.koplugin/issues/32))
  ([414c16e](https://github.com/OGKevin/kobo.koplugin/commit/414c16e43f25094a28a0bbb4bafa92217199359e))

### Performance Improvements

- cache accessible books for improved performance
  ([#34](https://github.com/OGKevin/kobo.koplugin/issues/34))
  ([cfc0809](https://github.com/OGKevin/kobo.koplugin/commit/cfc0809c6a5da30bd8ed6ce1cb89fa5b9d8b8f07))

## [0.2.0](https://github.com/OGKevin/kobo.koplugin/compare/v0.1.0...v0.2.0) (2025-11-17)

### Features

- add Bluetooth control for MTK Kobo devices
  ([#14](https://github.com/OGKevin/kobo.koplugin/issues/14))
  ([32ee799](https://github.com/OGKevin/kobo.koplugin/commit/32ee7992116bd3ee6ab2b758270be32e3ac90def))

### Bug Fixes

- properly manage info messages during key capture
  ([#23](https://github.com/OGKevin/kobo.koplugin/issues/23))
  ([adb18eb](https://github.com/OGKevin/kobo.koplugin/commit/adb18eb5d5f9f6bc5174f4bd36b4c9827478616f))
- release-please extra files path ([#25](https://github.com/OGKevin/kobo.koplugin/issues/25))
  ([92e142d](https://github.com/OGKevin/kobo.koplugin/commit/92e142db12501b352c32fe36fbacec11623f12d0))
