# Development

Cover Search uses KOReader's Lua widgets, networking, image decoding, and custom-cover storage. The current target is KOReader stable v2026.07.1. Source code lives in `coversearch.koplugin`; it has no Kindle-specific shell commands or additional runtime dependencies.

## Tests

Run the dependency-free checks and Lua syntax validation from the project root:

```sh
bash tools/check.sh
bash tests/package.sh
bash tests/release.sh
```

The Lua suites in `tests/run.lua`, `isbn.lua`, `http.lua`, `cache.lua`, and `localization.lua` can also run individually with LuaJIT. They cover provider parsing, metadata and ISBN handling, encoded image dimensions, response limits, redirects, timeout restoration, source failures, cover-store rollback, cache retention, and translation coverage. ISBN checks use the real provider parsers with deterministic responses to verify equivalent-number request counts, error isolation, result limits, and Apple's title/author exception. The packaging check verifies exact archive contents, extracted file bytes, SHA-256, repeatable builds, and rejection of mismatched tags. Draft-release checks use a fake GitHub CLI to test tag creation, draft retries, annotated tags, and refusal of conflicting tags, published releases, or failed API requests without network access or remote writes.

Native integration checks use a separately unpacked KOReader Linux distribution. From its `lib/koreader` directory, supply absolute paths to this project and a valid cover JPEG/PNG at least 100 × 100 pixels:

```sh
SDL_VIDEODRIVER=dummy SDL_AUDIODRIVER=dummy ./luajit /path/to/project/tests/runtime.lua /path/to/project /path/to/cover.jpg
SDL_VIDEODRIVER=dummy SDL_AUDIODRIVER=dummy ./luajit /path/to/project/tests/runtime.lua /path/to/project /path/to/cover.jpg landscape
SDL_VIDEODRIVER=dummy SDL_AUDIODRIVER=dummy ./luajit /path/to/project/tests/runtime.lua /path/to/project /path/to/cover.jpg keys
SDL_VIDEODRIVER=dummy SDL_AUDIODRIVER=dummy ./luajit /path/to/project/tests/cache-runtime.lua /path/to/project /path/to/cover.jpg
SDL_VIDEODRIVER=dummy SDL_AUDIODRIVER=dummy ./luajit /path/to/project/tests/runtime.lua /path/to/project /path/to/cover.jpg landscape es
SDL_VIDEODRIVER=dummy SDL_AUDIODRIVER=dummy ./luajit /path/to/project/tests/cache-runtime.lua /path/to/project /path/to/cover.jpg keys es
SDL_VIDEODRIVER=dummy SDL_AUDIODRIVER=dummy ./luajit /path/to/project/tests/menu-runtime.lua /path/to/project portrait
SDL_VIDEODRIVER=dummy SDL_AUDIODRIVER=dummy ./luajit /path/to/project/tests/menu-runtime.lua /path/to/project landscape es
```

Run native checks sequentially in a disposable runtime. They use temporary books and screenshots under `/tmp`, plus the runtime's settings and cache folders. The fourth argument selects the UI language. `tests/cache-runtime.lua` accepts a fifth argument (`message`, `outside`, or `thumbnail`) to choose a cancellation tap location; by default, it taps over the browser's Next button.

The native checks exercise real widgets, touch/key dispatch, decoding, pagination, previews, cover storage and reset, metadata events, ebook preservation, modal loading, and subprocess cancellation, including cancellation during an equivalent-ISBN request. Handcrafted EPUB 2/3 fixtures verify that KOReader exposes calibre-style identifiers to the plugin. The menu checks use a populated reader menu to verify the plugin's placement beside Book information on the first page. Network responses are substituted for these UI checks.

For optional live source verification:

```sh
SDL_VIDEODRIVER=dummy SDL_AUDIODRIVER=dummy ./luajit /path/to/project/tests/live.lua /path/to/project
```

The live check fails if fewer than five sources return an image. Keep dated provider results and hardware verification in [TESTING.md](TESTING.md).

## Releases

The [Prepare release workflow](.github/workflows/prepare-release.yml) is started manually from GitHub's Actions tab. It checks out the exact commit selected when the run begins, validates the requested version against `coversearch.koplugin/_meta.lua`, runs the checks, and builds the ZIP and SHA-256 checksum. It creates a `vX.Y.Z` tag pointing to that commit and uploads the assets to a draft release. The workflow stops there; publication is a separate action on the Releases page. Pushing a tag does not prepare or publish a release.

To prepare a release:

1. Update the plugin version and any relevant documentation, run the checks, and commit and push the changes to `main`.
2. Open **Actions → Prepare release → Run workflow**. Select `main` and enter the version without a `v` prefix, such as `0.1.16`. It must match the committed plugin metadata. The workflow file must be present on the repository's default branch for the manual control to appear.
3. Wait for the workflow to finish, then follow **Review draft release** in its summary.
4. Check the notes and assets, edit the notes as needed, and click **Publish release** when ready.

The draft includes GitHub's automatically generated notes, installation instructions, and links to the source commit and build log. Generated notes list merged pull requests and contributors and link to the full changelog; versions developed mostly through direct commits may need a hand-written summary. Review and edit the draft rather than treating generated notes as a complete description of the release.

Rerunning preparation for the same commit refreshes an existing draft's assets while preserving its note edits. A tag that points to another commit, or an already published release, stops preparation. If you change the source after preparing a draft, use a new version or explicitly resolve the old draft and tag; the workflow never moves a version tag. Uploading the assets before manual publication also supports GitHub's immutable releases setting.

No extra repository secret or approval environment is needed: the workflow uses GitHub's token. The separate [CI workflow](.github/workflows/ci.yml) checks pushes to `main` and pull requests with read-only permissions. CI validates Lua, packaging, and simulated draft preparation without downloading KOReader; the native widget checks above remain a separate step before preparing a release.

For a local installation ZIP, run:

```sh
bash tools/package.sh
```

This writes `dist/koreader-coversearch-vX.Y.Z.zip` and its `.sha256` file. Only tracked runtime files and a copy of `LICENSE` are packaged under `coversearch.koplugin/`. The script uses sorted file paths, fixed permissions, the source commit's timestamp, and no ZIP extra fields. Rebuilding the same clean checkout with the same Info-ZIP version produces identical bytes. Build output is ignored by Git; downloadable archives belong on Releases rather than in the source tree.

For a public repository, the workflow also creates a GitHub build provenance attestation linking the ZIP to its source and workflow. After downloading both release assets, verify their checksum from the download directory; you can additionally verify provenance using the GitHub CLI, substituting this repository's owner/name:

```sh
sha256sum --check koreader-coversearch-v0.1.16.zip.sha256
gh attestation verify koreader-coversearch-v0.1.16.zip --repo OWNER/REPOSITORY
```

Attestation is skipped for private repositories, where availability depends on the GitHub plan. Actions are pinned to commit hashes; their major versions are shown beside the pins for updates.

## Translations

The plugin's translation adapter follows KOReader's saved UI language without modifying its shared gettext catalog. English strings are the source text; Spanish translations are in `coversearch.koplugin/coversearch/l10n/es.lua`.

To add a language, copy that catalog to `<language-code>.lua` in the same directory and translate its values. Preserve the English keys, printf arguments such as `%d`/`%s`, and explicit line breaks. Catalogs load automatically using the base of KOReader's language code. Add a coverage check for the new language alongside the Spanish checks in `tests/localization.lua`.

## Recording the README demo

`tools/record-demo.lua` captures actual native KOReader widgets, including search and download dialogs, the thumbnail browser, previews, cover selection, and restoration. It substitutes saved cover images for network responses, so recordings are reproducible without catalog availability or changing personal books. It creates an isolated demo book in the frame output directory.

Prepare four JPEG fixtures named `cover-ol.jpg`, `cover-apple.jpg`, `cover-goodreads.jpg`, and `cover-amazon.jpg`. From the disposable runtime's `lib/koreader` directory:

```sh
SDL_VIDEODRIVER=dummy SDL_AUDIODRIVER=dummy ./luajit /path/to/project/tools/record-demo.lua /path/to/project /path/to/fixtures /tmp/coversearch-demo
```

Then, from this project's root, use ImageMagick to encode the captured frames:

```sh
bash tools/make-demo-gif.sh /tmp/coversearch-demo assets/cover-search-demo.gif
```

The frame manifest controls the pause on each screen. The GIF loops at 480 × 640 pixels. Inspect it before committing; demo media belongs in the repository rather than the plugin's install archive.

## Storage and source integrations

ISBN discovery validates checksums, normalizes common typographic separators, and prefers the dedicated ISBN field and explicitly marked identifiers over untyped numbers. Typed identifiers such as ASIN and UUID aren't treated as ISBNs. Calibre-style EPUB 2 identifiers use `opf:scheme="ISBN"`; EPUB 3 identifier text uses `isbn:…`. KOReader exposes both through its document identifiers. Multiple explicit ISBNs retain metadata order; identifier maps use sorted keys for deterministic selection.

Discovery collects all valid ISBNs and groups equivalent 10/13-digit pairs, preserving the first representation and metadata priority. The native radio chooser appears only for distinct ISBNs, preserves the search form and checkbox state, and scrolls long lists within the screen. Each ISBN-aware source searches the selected form first. Only a successful search with no parsed cover candidates can trigger one request for its equivalent ISBN-10/ISBN-13. ISBN-13 numbers starting with `979` have no 10-digit equivalent. Errors, blocked pages, and failed image downloads don't trigger this fallback; Apple Books always uses title/author. The original query and configured result limit remain unchanged, and one final status entry is reported per source.

Selected covers are staged in KOReader's metadata/sidecar folder before replacing an existing override. Cover-store failures preserve or restore the previous cover; successful changes invalidate KOReader's metadata cache.

Downloads are limited to 8 MiB per image and 20 megapixels. A 64 MiB cache per search evicts the least recently used encoded images while protecting the incoming page or preview. Thumbnails are decoded only for the current view. After cancellation, reconcile evicted entries and remove partial or untracked files because the killed subprocess cannot return its cache state.

Source integrations use Open Library's search/covers APIs, Apple's search API, Goodreads' public autocomplete, and public Amazon/OverDrive catalog pages. Goodreads, Amazon, and OverDrive parsing relies on unofficial interfaces. Keep provider errors isolated and report actual downloaded dimensions rather than requested CDN sizes.

## References

- [KOReader plugin examples](https://github.com/koreader/koreader/tree/v2026.07.1/plugins).
- [Custom-cover storage](https://github.com/koreader/koreader/blob/v2026.07.1/frontend/docsettings.lua) and [cover handling/cache invalidation](https://github.com/koreader/koreader/blob/v2026.07.1/frontend/apps/filemanager/filemanagerbookinfo.lua).
- [Cancellable subprocesses](https://github.com/koreader/koreader/blob/v2026.07.1/frontend/ui/trapper.lua).
- [UI-language selection](https://github.com/koreader/koreader/blob/v2026.07.1/frontend/ui/language.lua) and [gettext](https://github.com/koreader/koreader/blob/v2026.07.1/frontend/gettext.lua).
- [Open Library search](https://openlibrary.org/dev/docs/api/search) and [covers](https://openlibrary.org/dev/docs/api/covers).
- [Apple Search API](https://performance-partners.apple.com/search-api).
- [calibre Goodreads source](https://github.com/kiwidude68/calibre_plugins/blob/master/goodreads/__init__.py).
- [OverDrive public catalog](https://www.overdrive.com/search).
- [GitHub CLI release creation](https://cli.github.com/manual/gh_release_create) and [build provenance attestations](https://docs.github.com/en/actions/how-tos/secure-your-work/use-artifact-attestations/use-artifact-attestations).
- [Manual workflows](https://docs.github.com/en/actions/how-tos/manage-workflow-runs/manually-run-a-workflow) and [automatically generated release notes](https://docs.github.com/en/repositories/releasing-projects-on-github/automatically-generated-release-notes).
