# Verification and device checklist

The current verification target is Cover Search v0.1.16 on KOReader stable
v2026.07.1 (upstream commit `9192014`). The results below were recorded on
2026-10-08. See [DEVELOPMENT.md](DEVELOPMENT.md) for commands and test setup.

## Automated coverage

All 59 deterministic Lua checks and LuaJIT syntax validation pass:

| Suite | Checks | Coverage |
| --- | ---: | --- |
| `tests/run.lua` | 18 | Metadata, provider parsing, encoded image dimensions, and cover-store transactions/rollback |
| `tests/isbn.lua` | 19 | ISBN normalization and validation, metadata priority, calibre representations, distinct choices, equivalent grouping, bounded fallback requests, and failure isolation |
| `tests/http.lua` | 7 | Body-size and time limits, redirects, rate limiting, exception cleanup, and JSON errors |
| `tests/cache.lua` | 7 | Byte-based retention, least recently used eviction, protected pages, missing files, and deletion failures |
| `tests/localization.lua` | 8 | Language selection/fallback, Spanish coverage for 87 UI strings, printf placeholders, line breaks, and translated errors |

`tests/package.sh` verifies exact install-archive contents, extracted file bytes,
SHA-256 checksums, repeatable builds, and rejection of invalid or mismatched
release tags. Local verification of the release workflow used disposable
repositories with local Git remotes and substituted GitHub CLI responses. It covered version
selection, metadata commits, ZIP/source consistency, existing tags, concurrent
changes, and the flags for drafts, prereleases, and immediate publication.
Both GitHub Actions workflows pass actionlint v1.7.12 with only its unknown
`copilot-requests` permission diagnostic excluded; GitHub accepted that permission
in the hosted test. The [v0.1.17 run](https://github.com/extricator/koreader-coversearch/actions/runs/37964737672)
verified publication, including its ZIP and checksum assets.

On 2026-10-09, a [notes-only Actions run](https://github.com/extricator/koreader-coversearch/actions/runs/37973622920)
verified Copilot generation with the built-in workflow token and no available
tools. It ran on a temporary branch with read-only repository access and created
no release. Local checks exercised generated notes, authentication errors,
partial failed responses, empty output, timeouts, installation failures, the
first release, and no new commits. They also verified bounded input, excluded
media, omission of version-bump commits, and preservation of the description
when build/source links are appended. Draft creation remains untested on GitHub.

## Native KOReader checks

The native suites use actual KOReader widgets, image decoding, cover storage,
metadata events, and subprocesses in a disposable desktop runtime. Network
responses are substituted to make UI and storage checks deterministic.

- `tests/runtime.lua` covers plugin initialization, ISBN discovery and opt-in,
  disabled touch/key input, manual ISBN validation, keyboard-height rebuilds,
  active-field visibility and key navigation with a visible on-screen keyboard,
  distinct-ISBN selection/cancellation, preserved title and author edits,
  equivalent grouping, long-list focus scrolling, actual submitted queries,
  thumbnail interaction, pagination, previews, cover application/restoration,
  ebook preservation, failed downloads, and cancellable provider requests.
  Current checks pass in English portrait and key-only modes and Spanish
  landscape. Earlier checks also covered English landscape and Spanish portrait.
- `tests/cache-runtime.lua` covers three-page retention, zero download workers
  for cached pages and previews, partially cached views, eviction, subprocess
  state transfer, partial files, cleanup, and cancellation followed by retry.
  Checks passed in portrait, landscape, and key-only modes, including Spanish
  landscape and key input.
- `tests/menu-runtime.lua` checks the populated reader menu: Cover search appears
  immediately after Book information in the same group on page one. It also
  checks duplicate registration, existing ordering, missing-anchor fallback,
  and opening the search form. English/Spanish portrait and landscape checks
  passed.

Modal cancellation checks dispatch actual taps or key events. A tap on the
loading message, outside it, or over an underlying thumbnail/Next button cancels
without activating the browser. The current page remains visible and usable;
stale cache entries and partial files are reconciled before navigation resumes.
Content-sized dialogs remain within screen bounds, and translated resolution
labels remain visible. The [README walkthrough](assets/cover-search-demo.gif)
records native widgets, including the current ISBN chooser.

## Live-source verification

The last live-source check used Dune by Frank Herbert on 2026-10-08, with the US
Apple store and amazon.com. Each of the five supported sources returned a
downloadable cover without API keys or login cookies:

| Source | Downloaded resolution |
| --- | --- |
| Open Library | 317 × 500 |
| Apple Books | 894 × 1600 |
| Goodreads | 295 × 475 |
| Amazon | 2400 × 2400 |
| OverDrive | 510 × 680 |

These results were recorded for v0.1.1; live-source verification was not repeated
for the current version. They establish that a candidate downloaded during that
check, rather than guaranteeing source availability or an exact edition match.
`tests/live.lua` keeps this check separate from deterministic tests.

## Physical Kindle checklist

Installation and the initial plugin test worked on a physical Kindle according
to user feedback. The complete checklist below still needs hardware verification,
especially Wi-Fi handling, e-ink refresh, and device screen/font settings.

1. Install the plugin, restart KOReader, and open an ebook. Find Cover search
   directly below Book information in the top menu's hamburger tab.
2. Verify the title and author remain editable. Check that a discovered ISBN is
   prefilled beneath the unchecked Use ISBN control, with the field grayed out.
   Enable it, edit or paste an ISBN, then disable and enable it again; the value
   should survive. Invalid or empty enabled ISBNs should keep the form open.
   With multiple distinct ISBNs, select another value and cancel a change; verify
   all edits are preserved. Equivalent ISBN-10/13 forms should count as one
   choice. Books without an ISBN should allow manual entry or a title/author search.
3. Search and check source names and actual pixel dimensions below the thumbnails.
   Open a cover, preview it full screen, and navigate between result pages.
4. Apply a cover and check KOReader's book-browser thumbnail and configured
   book-cover sleep screen. The ebook's embedded cover and Kindle home-screen
   thumbnail should remain unchanged. Restore the original and verify both
   KOReader displays reset.
5. Cancel a search and a page download by tapping the modal message, outside it,
   and over an underlying control. Each tap must cancel without activating that
   control. Confirm the retained page remains usable and retry navigation. On
   devices with keys, verify the key-cancellation hint and cancellation behavior.
6. Revisit cached pages and previews and confirm they open without a loading
   dialog. Close the browser and start another search to check session cleanup.
7. Turn Wi-Fi off, start a search, and verify KOReader's normal network handling.
8. Change enabled sources, result count, and store region; restart and verify
   preferences persist.
9. Switch KOReader to Español and restart. Check menus, search fields, ISBN
   controls, navigation, cancellation hints, and confirmations. Verify resolution
   labels and dialog bounds in landscape, then switch back to English.
