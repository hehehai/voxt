# MLX Audio Dependency Policy

Voxt uses `mlx-audio-swift` through the mirror fork at `https://github.com/hehehai/mlx-audio-swift`.

The current Xcode package reference is:

- URL: `https://github.com/hehehai/mlx-audio-swift.git`
- Requirement: `revision`
- Revision: `c96fe7b8577fb1db5a9987a6582e706acb388a8e`

## Version rules

- Prefer upstream release tags when they already contain the STT features or fixes Voxt needs.
- When upstream `main` contains required changes that are not released yet, sync the fork's `main` to upstream and create a Voxt tag on the selected commit.
- Switch Voxt back to upstream release tags once an official release covers the same changes.

## Tag rules

- Keep the fork as a mirror plus tags only. Do not land Voxt-specific source patches there unless absolutely required.
- Use tags in the form `v<upstream-version>-voxt.<n>`.
- Do not reuse upstream tag names for different commits.

## Update workflow

1. Sync `hehehai/mlx-audio-swift` `main` from `Blaizzy/mlx-audio-swift`.
2. Pick the target commit from fork `main`.
3. Create a new annotated Voxt tag on that commit, for example `v0.1.2-voxt.2`.
4. Point `Voxt.xcodeproj` at the fork URL and `exactVersion`.
5. Build Voxt and verify STT model loading, legacy repo migration, and downloaded-model detection before shipping.

If Voxt needs to consume a synced fork commit before a new tag exists, pin the project to that exact `revision` temporarily, then switch back to a release tag once the fork tag is cut.

## Practical rules for Voxt maintainers

- Use upstream releases directly when they already include the models or fixes Voxt needs.
- Use the fork only when Voxt must consume unreleased upstream commits.
- Keep the fork as a mirror plus tags. Do not put long-lived Voxt-only API changes into the fork.
- Once upstream publishes an official release that covers the same changes, switch Voxt back to the upstream release tag instead of staying on a fork tag forever.
- If a new MLX Audio update renames model repos, add canonical mapping in `MLXModelManager` so existing user settings and downloaded caches continue to work.

## Current pin

- Fork: `hehehai/mlx-audio-swift`
- Requirement: `revision`
- Commit: `c96fe7b8577fb1db5a9987a6582e706acb388a8e`
- Notes: includes `Cohere Transcribe` support from fork `main`; replace with a new Voxt tag once one is cut
