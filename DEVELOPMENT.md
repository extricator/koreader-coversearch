# Development

Cover Search uses KOReader's Lua widgets, networking, image decoding, and custom-cover storage. The current target is KOReader stable v2026.07.1. Source code lives in `coversearch.koplugin`; it has no Kindle-specific shell commands or additional runtime dependencies.

## Tests

Run the dependency-free checks and Lua syntax validation from the project root:

```sh
bash tools/check.sh
bash tests/package.sh
```

The Lua suites in `tests/run.lua`, `isbn.lua`, `http.lua`, `cache.lua`, and `localization.lua` can also run individually with LuaJIT. They cover provider parsing, metadata and ISBN handling, encoded image dimensions, response limits, redirects, timeout restoration, source failures, cover-store rollback, cache retention, and translation coverage. ISBN checks use the real provider parsers with deterministic responses to verify equivalent-number request counts, error isolation, result limits, and Apple's title/author exception. The packaging check verifies exact archive contents, extracted file bytes, SHA-256, repeatable builds, and rejection of mismatched tags. For workflow changes, use actionlint and exercise the affected steps in a disposable checkout.

Actionlint v1.7.12 does not recognize GitHub's newer `copilot-requests` permission. Until the linter supports it, ignore only that specific diagnostic; GitHub accepts the permission:

```sh
actionlint -ignore '^unknown permission scope "copilot-requests"\.'
```

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

The native checks exercise real widgets, touch/key dispatch, decoding, pagination, previews, cover storage and reset, metadata events, ebook preservation, modal loading, and subprocess cancellation, including cancellation during an equivalent-ISBN request. Handcrafted EPUB 2/3 fixtures verify that KOReader exposes calibre-style identifiers to the plugin. The menu checks use populated reader menus to verify Cover search immediately below Document settings on the page-icon tab's first page, and compare the hamburger menu and Exit pagination with the plugin absent. Network responses are substituted for these UI checks.

For optional live source verification:

```sh
SDL_VIDEODRIVER=dummy SDL_AUDIODRIVER=dummy ./luajit /path/to/project/tests/live.lua /path/to/project
```

The live check fails if fewer than five sources return an image. Keep dated provider results and hardware verification in [TESTING.md](TESTING.md).

## Releases

Start the [Prepare release workflow](.github/workflows/prepare-release.yml) from GitHub's Actions tab whenever you want a release. Choose the version there; the workflow updates `coversearch.koplugin/_meta.lua` and commits the change when needed. You do not need to edit the version locally or push a tag. Release titles and tags are simply `vX.Y.Z`, and the downloadable archive is `koreader-coversearch-vX.Y.Z.zip`.

To prepare a release:

1. Commit and push the changes you want to release to `main`.
2. Open **Actions → Prepare release → Run workflow**, with `main` selected. Leave **Version selection** on **Automatic**, choose a bump, or enter **Custom version**. A custom number overrides the selector.
3. Leave **Result** on **Draft release** to review before publication, or choose **Publish immediately** to publish when the build succeeds. Check **Prerelease** only for a testing release.
4. Follow the release link in the completed run's summary. For a draft, review the notes and assets, then click **Publish release** when ready.

The version choices work as follows:

| Selection | Version used |
| --- | --- |
| Automatic | Start with the code version if it is newer than every published numeric version, or the next patch otherwise. Increment the patch until the version has no existing tag. For the first release, start with the code version. |
| Use code version | Exactly the version in `_meta.lua`; it must be newer than published releases. |
| Patch | Increment the patch number, such as `0.1.16` → `0.1.17`. |
| Minor | Increment the minor number and reset the patch, such as `0.1.16` → `0.2.0`. |
| Major | Increment the major number and reset minor/patch, such as `0.1.16` → `1.0.0`. |
| Custom version | Your exact `X.Y.Z` number, without `v`, leading zeros, or a suffix. |

Bumps start from the greater of the code version and the highest published numeric version. Published prereleases also reserve their number. A custom version must be newer than published versions, but the first release can use any valid number. GitHub's prerelease flag labels the release and excludes it from the normal latest release; it does not add `-beta` to the version or filenames. GitHub's native workflow form cannot calculate a suggested number before running, so the resolved version appears in the run summary instead.

The workflow runs the checks, commits the version change if needed, and builds the ZIP and SHA-256 checksum. It pushes the release commit and tag together, then uses GitHub's CLI to create the release with your chosen settings. An ordinary published release becomes latest; a prerelease does not. Pushing a tag alone never prepares or publishes a release.

Copilot drafts a short release description from the commits and a bounded text diff since the previous published version. It uses automatic model selection and cannot run tools. If installation or generation fails, times out, or returns empty text, the workflow uses commit-message bullets instead and continues preparing the release. The run summary shows the description and whether fallback was used. GitHub's generated changelog and links to the source commit and build log follow the description. Review a draft's notes before publishing it.

Automatic skips existing version tags, including tags left behind when a draft is deleted. An explicitly selected version that already has a tag stops the workflow; it does not refresh drafts or overwrite releases. Review an existing draft on the Releases page, or choose a new version. If a run fails after pushing its tag, you can finish that release through GitHub's release form using the existing tag. Start a new workflow run for a fresh version. Release notes still compare against the latest published version. Concurrent changes to `main` cause the push to fail rather than overwrite those changes.

No extra repository secret or approval environment is needed: the workflow uses GitHub's token. Copilot requests require the repository owner's Copilot access and consume their plan's allowance; Free has a limited allowance. The workflow grants `copilot-requests: write` and pins the CLI version. See [GitHub's Copilot CLI Actions guide](https://docs.github.com/en/copilot/how-tos/copilot-cli/use-copilot-cli-in-actions). It also needs permission to push the version commit to `main`; repository rules that block bot pushes would need to allow that operation. The separate [CI workflow](.github/workflows/ci.yml) checks pushes to `main` and pull requests with read-only permissions. Release preparation runs those same checks itself, because a push made using GitHub's workflow token does not trigger another push workflow. Native widget checks remain a separate step before preparing a release.

For a local installation ZIP, run:

```sh
bash tools/package.sh
```

This writes `dist/koreader-coversearch-vX.Y.Z.zip` and its `.sha256` file. Only tracked runtime files and a copy of `LICENSE` are packaged under `coversearch.koplugin/`. The script uses sorted file paths, fixed permissions, the source commit's timestamp, and no ZIP extra fields. Rebuilding the same clean checkout with the same Info-ZIP version produces identical bytes. Build output is ignored by Git; downloadable archives belong on Releases rather than in the source tree.

Each release links to its source commit and Actions build log. After downloading both release assets, verify their checksum from the download directory:

```sh
sha256sum --check koreader-coversearch-v0.1.16.zip.sha256
```

Actions are pinned to commit hashes; their major versions are shown beside the pins for updates.

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

ReaderUI's customized `doc_props` omit document identifiers. The search form retrieves them from the original `doc_props` saved in the book's settings, while retaining customized title and author values.

The search form has an editable ISBN field below an opt-in checkbox. `ISBNForm` in `dialogs.lua` integrates that checkbox into the native field layout so keyboard-height changes preserve its state and text. Short viewports scroll to keep the focused control above the keyboard. Disabled ISBN controls consume touch input, skip field focus, and use native read-only behavior. The field is normalized and validated only when enabled; selecting a detected ISBN fills it without modifying book metadata.

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
- [GitHub CLI release creation](https://cli.github.com/manual/gh_release_create).
- [Manual workflows](https://docs.github.com/en/actions/how-tos/manage-workflow-runs/manually-run-a-workflow) and [automatically generated release notes](https://docs.github.com/en/repositories/releasing-projects-on-github/automatically-generated-release-notes).
