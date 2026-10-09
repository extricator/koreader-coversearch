# Contributor guide

This is a LuaJIT plugin running inside KOReader. Runtime code lives in
`coversearch.koplugin/`; use KOReader's existing APIs and widgets. See
[DEVELOPMENT.md](DEVELOPMENT.md) for environment setup and upstream references.

## Where to make changes

- `main.lua`: reader integration, menus, search form, browser, and session lifecycle.
- `coversearch/model.lua`: metadata, ISBN normalization, and result interleaving.
- `coversearch/providers.lua` and `http.lua`: catalog parsing and bounded requests.
- `coversearch/images.lua` and `cache.lua`: image validation and disk-cache accounting.
- `coversearch/store.lua`: transactional cover replacement and restoration.
- `coversearch/dialogs.lua` and `tile.lua`: native dialogs and cover tiles.
- `coversearch/i18n.lua` and `l10n/es.lua`: translation adapter and Spanish catalog.
- `_meta.lua`: plugin metadata and version.

Paths above are relative to `coversearch.koplugin/`. Tests live in `tests/`;
release and demo scripts live in `tools/`.

## Implementation guidance

- Check KOReader APIs against the supported stable release documented in
  DEVELOPMENT.md. Follow nearby plugin patterns rather than adding dependencies
  or device-specific shell commands.
- Use the existing storage and cache helpers. Preserve rollback on failed cover
  replacement, protect files needed by the current operation, and reconcile cache
  state after a cancelled subprocess. Never modify the ebook to apply a cover.
- Keep network requests bounded and source failures isolated. Measure image
  dimensions from downloaded data rather than assuming CDN sizes.
- Use the dialog helpers for content sizing and screen bounds. Check touch and
  key navigation; loading-dialog cancellation must consume input without
  activating the browser beneath it.
- Wrap user-visible strings with `require("coversearch/i18n")` and update
  `coversearch/l10n/es.lua`. Preserve printf placeholders and line breaks. Avoid
  shadowing the translation function `_` with a loop variable where it is called.

## Verification

- For Lua changes, run `bash tools/check.sh` from the repository root. It compiles
  Lua files and runs the deterministic suites; individual suites can be run with
  `luajit tests/<suite>.lua` while developing.
- For UI, storage, or cancellation changes, also run the relevant native suites:
  `tests/runtime.lua`, `tests/cache-runtime.lua`, or `tests/menu-runtime.lua`.
  Follow DEVELOPMENT.md for invocation. Run sequentially in a disposable KOReader
  runtime, with relevant English/Spanish, orientation, and input modes. Capture
  actual widgets for UI review; keep temporary screenshots outside the repo.
- For packaging changes, run `bash tests/package.sh`. Live catalog verification
  uses `tests/live.lua` separately; it is not part of deterministic CI.
- For workflow changes, run actionlint and verify affected steps in a disposable
  checkout. Do not create a real release as a test without being asked to do so.
- For documentation-only changes, check links and `git diff --check`.
  Record validation accurately; desktop checks do not establish hardware results.

## Delivery

- Commit each coherent change with its related tests and documentation. Preserve
  unrelated edits and use the repository's configured Git identity.
- Keep README focused on usage; put implementation and test setup in
  DEVELOPMENT.md. Update the native walkthrough when its visible flow changes.
- Build with `bash tools/package.sh`; generated ZIPs/checksums belong in ignored
  `dist/`, not Git. Packaging includes tracked plugin files and LICENSE only.
- Release tags must match the version in `_meta.lua`. Keep packaging logic in
  checked-in scripts shared by local builds and GitHub Actions.
