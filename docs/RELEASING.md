# Build and attach a GitHub release

The [release workflow](../.github/workflows/release.yml) builds the exact version tag when you **publish a GitHub release**, including a prerelease. Saving a draft or pushing a tag alone does not publish an app. A manual workflow run can build an existing tag into Actions artifacts without changing any release. [GitHub documents the published event](https://docs.github.com/en/actions/reference/workflows-and-actions/events-that-trigger-workflows#release).

## Owner's release steps

1. Push the commit containing this workflow to `main` before creating your first version tag.
2. On [GitHub Releases](https://github.com/Ampi-Project/ampi-macos/releases), choose **Draft a new release**. Create/select a tag such as `v0.1.0-beta.1` pointing to the intended commit. Use a prerelease for this early prototype.
3. Describe actual features and known limits. Publish the release. No personal access token or Apple signing secret is required; the workflow uses GitHub's scoped temporary token.
4. Open **Actions → Build macOS release**. Apple Silicon (`macos-15`) and Intel (`macos-15-intel`) build independently. Their core tests must pass, and both builds must succeed before the upload job starts.
5. Refresh the release's Assets after the upload job succeeds. Download/extract the ZIP for your Mac and launch `Ampi.app`.

Attached files for tag `v0.1.0-beta.1`:

- `Ampi-v0.1.0-beta.1-macos-arm64.zip` — Apple Silicon app.
- `Ampi-v0.1.0-beta.1-macos-x86_64.zip` — Intel app.
- `Ampi-v0.1.0-beta.1-source.tar.gz` — app/build sources and the exact pinned ZIPFoundation sources/licenses.
- A `.sha256` companion for each archive.

The app's marketing version is the three numeric tag components; `AmpiReleaseTag` retains the full tag, including a prerelease suffix. Bundle build number defaults to 1. Archives contain an ad-hoc signed optimized app, not an Apple Developer ID-signed/notarized release. macOS may require explicit approval through **System Settings → Privacy & Security → Open Anyway** for a downloaded build. Do not tell users to disable Gatekeeper. Deployment target is macOS 13; compatibility on older systems/Intel hardware still needs real user acceptance.

The source archive contains the tagged app source, build instructions, license notices, and `vendor/ZIPFoundation` with its pinned revision. SwiftPM normally resolves that dependency from its original URL; the vendor folder supplies the matching source independently of that service. Build caches, `.git`, and user music/settings are excluded.

## Manual run, failures, and retries

For a test without announcing a release, open **Actions → Build macOS release → Run workflow**, supply an existing version tag, and download the resulting `release-arm64` and `release-x86_64` Actions artifacts. The manual upload job is skipped. The workflow must already exist on the default branch; the chosen tag must also contain the packaging scripts.

If a release build fails, inspect the failed job and use **Re-run all jobs** after fixing runner/permission issues. Source changes require a new commit/tag, rather than moving an already published version tag. Reruns upload to the same existing release and replace matching asset names. A failure before upload leaves the release's existing assets intact; GitHub's individual file uploads are not an atomic transaction, so a network failure during upload can leave partial assets until rerun.

Both build jobs have read-only repository permissions. Only the final upload job has `contents: write`. Official checkout/artifact actions are pinned to immutable commit IDs. Tags enter shell commands through validated environment variables. Release tags must have the `vMAJOR.MINOR.PATCH` form, optionally with an alphanumeric/dot/hyphen prerelease suffix.

Core tests run on hosted runners because native playback tests need a working AppKit/audio environment. Continue the complete local test suite and [manual acceptance checklist](TESTING.md) before publishing. Configuring this workflow does not prove a hosted run or notarization succeeded; verify the first published/prerelease or manual run in Actions.

Local optimized packaging (replaces generated `dist/Ampi.app`):

```sh
bash scripts/package-release.sh v0.1.0-beta.1
# Run from a clean committed checkout after SwiftPM resolves its pinned dependency:
bash scripts/package-source.sh v0.1.0-beta.1
```

The source script exports the checked-out commit; on GitHub the workflow checks out the exact release tag first. Local callers must also check out their intended commit. No script creates/pushes a tag, publishes a release, or edits Application Support state.
