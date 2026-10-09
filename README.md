# Cover Search for KOReader

Cover Search helps you find a cover you like for the book you're reading in KOReader. It searches **Open Library, Apple Books, Goodreads, Amazon, and OverDrive**, bringing different editions together in a thumbnail browser. Each result shows its source and actual image resolution, and you can preview a cover full screen before choosing it.

KOReader uses your chosen cover in its book browser and book-cover sleep screen. The plugin saves it as a cover override, leaving the ebook's embedded cover intact so you can restore the original at any time. Kindle home-screen thumbnails are managed separately and aren't changed by the plugin.

![Cover Search walkthrough: search, compare, preview, apply, and restore a book cover](assets/cover-search-demo.gif)

*Recorded in KOReader's desktop emulator.*

## Installation

1. Download `koreader-coversearch-vX.Y.Z.zip` from the [latest release](../../releases/latest) and extract it into KOReader's `plugins` directory. The resulting path should be `koreader/plugins/coversearch.koplugin/main.lua`.
2. Restart KOReader, then open a book.
3. Open the top menu's **page-icon tab** (fonts and layout). You'll find **Cover search** immediately below **Document settings**.

You can also install from this repository by copying the `coversearch.koplugin` folder into `koreader/plugins`. If the menu entry doesn't appear after restarting, check that **Cover search** is enabled in KOReader's plugin management menu.

The plugin has been tested with KOReader **v2026.07.1**. Other versions should work too, but haven't been verified. You'll need an internet connection to search and download covers. There are no accounts to set up, API keys to obtain, or extra dependencies to install.

## Choosing a cover

Open **Cover search → Search covers for this book**. The title and author are filled in from the book's metadata, and you can edit either before selecting **Search**. By default, the search uses these details to find covers across editions. You can also enable the optional ISBN filter, described below.

Results from the different sources are mixed together in the cover browser. Use **Previous** and **Next** to browse the pages, then tap a cover for a larger view. **Preview** shows it full screen, and **Details** opens its source information. Select **Use this cover** when you've found one you like.

While a search or download is running, you can **tap anywhere to cancel**, or press any key on a device with keys. Cancelling a page download leaves you on the page you were browsing. Pages still in the browser's temporary cache open without another download when you return to them; closing the browser clears that cache.

Devices without touch input have numbered buttons for opening covers. If you'd like quicker access to the plugin, you can assign **Search book covers** to a gesture or shortcut in KOReader's action settings.

To go back to the embedded cover, choose **Cover search → Restore original cover** and confirm. This removes the current KOReader cover override, including one you may have set outside this plugin.

## Searching by ISBN

When a book has an ISBN in its metadata, the plugin fills it in beneath **Use ISBN**. Check that box to enable the field and search with the number shown, or type or paste a different one. Turning the filter off returns to a title-and-author search and keeps the ISBN you entered. Editing these search fields doesn't change the book's metadata.

If several different ISBNs are found, **Choose ISBN** lets you pick one after enabling the filter. Your title and author edits are kept when you choose another number. Both ISBN-10 and ISBN-13 are supported, including identifiers added by calibre, and equivalent 10- and 13-digit numbers count as one choice. You can leave spaces and dashes in the value; the plugin checks that the ISBN is valid before searching.

An ISBN search can help narrow the results, although sources may still return covers from other editions. Apple Books always searches by title and author. For the other sources, if the chosen ISBN finds no cover candidates, the plugin tries its equivalent 10- or 13-digit number once when one exists. An unavailable or blocked source won't trigger that extra request.

## Preferences

You can adjust searches from the **Cover search** menu. All five sources are enabled initially, and **Sources** lets you turn individual catalogs on or off. **Results per source** sets how many covers to request from each catalog: 3 by default, with options for 5 or 10. **Store regions** lets you change the Apple Books country and Amazon store, which default to US and amazon.com.

English and Spanish are included, and the plugin follows KOReader's own language setting. To use Spanish, choose **Español** under **Settings → Language** and restart when prompted. For other UI languages, the plugin's text falls back to English.

## Troubleshooting

If the results aren't what you're looking for, try shortening the title, checking the author's spelling, or turning off the ISBN filter to include other editions. **Summary** in the cover browser shows which sources returned results and which encountered an error. You can keep browsing results from the other sources when a catalog is unavailable, or turn it off in **Sources**. Images that fail to download appear as unavailable tiles.

If your chosen cover doesn't appear while the device is asleep, check that KOReader's sleep screen is set to show the book cover. Its **Full stretch** setting will fill the screen without bars, although covers with different proportions will be stretched.

## Contributing

See [DEVELOPMENT.md](DEVELOPMENT.md) for contributing instructions, including tests, translations, releases, and recording the demo. [TESTING.md](TESTING.md) contains verification results and the device test checklist. Release ZIPs are built through GitHub Actions; each release includes a SHA-256 checksum and links to its source commit and build log.

## License

[AGPL-3.0-or-later](LICENSE).
