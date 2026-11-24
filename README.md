# Comic Dual Page for KOReader

*Deutsch: [README.de.md](README.de.md)*

> **Based on [ComicReader](https://github.com/KORComic/comicreader.koplugin) 0.0.7 by [KORComic](https://github.com/KORComic)** (AGPL-3.0).
> The dual page mode and almost all of the code come from the original. This is an unofficial version that adds spread detection and a few fixes. All credit for the original plugin goes to its authors. If you like it, please star the original too.
> The idea for the spread detection comes from [pull request #78](https://github.com/KORComic/comicreader.koplugin/pull/78) by hatlessman. It was implemented anew for version 0.0.7.

ComicReader shows two comic pages side by side in landscape. The original always pairs 1+2, 3+4 and so on, even when a page is already a double-page spread on its own. Then two landscape pages end up next to each other.

## New: spread detection

Pages in landscape format (wider than tall) count as spreads and are shown **on their own**. The pages before and after are re-paired so that nothing shifts:

- Portrait + portrait = pair
- Landscape = on its own
- Portrait directly before a landscape page = on its own
- Cover (if "First page is cover" is on) = on its own

Example with spreads on pages 3 and 6: views 1+2 · 3 · 4+5 · 6 · 7+8.

This applies to page turning, jumping, bookmarks and the dog-ear. When a page stands alone, the bookmark no longer asks "left or right page".

**Setting:** open a comic, then go to: top menu → "Dual Page Mode" → **Detect spreads**. The settings there can also be changed in portrait, before you rotate. It is on by default and can be switched off per comic. When it is off, everything behaves exactly like the original.

**Speed:** For the detection, the size of every page must be known. The first time a comic is opened in dual page mode, the pages up to the current page are measured once, and while you read on, the next ones are measured. The result is saved with the comic, so after that there's no waiting.

## Installation

1. Download the ZIP from [Releases](../../releases) and unpack it, or download this repository.
2. **Delete the original `comicreader.koplugin`** from KOReader's `plugins` folder. Both change the same parts of KOReader and must not be installed at the same time.
3. Copy the folder **`comicdualpage.koplugin`** to KOReader's `plugins` folder. On a Kobo, that is `.adds/koreader/plugins/`.
4. Restart KOReader.

ZenOS users: don't reinstall the original from the ZenOS storefront.

## Statistics

As with the original: without the adapted statistics plugin from the original project, KOReader's reading statistics count a dual view as one page in dual page mode. Everything else works independently of that.

## Changes from the original (AGPL notice)

Changed by Claude (AI by Anthropic) in October 2026:

- The folder, plugin name and module path are renamed (`crplus/` instead of `src/`), so it never collides with the original.
- `crplus/readerpaging.lua`: the spread detection is added at the end of the file (page pairing, page turning, the bookmark question and the menu entry). The original functions stay unchanged and are used when the detection is off.
- Name "Comic Dual Page" (`comicdualpage.koplugin`) and `_meta.lua` with a bilingual description.
- Fixes: the last page is always reached when turning pages in dual page mode (original issue #76); books with flowing text (EPUB) are no longer affected (#65); the settings in the dual page menu can also be changed in portrait; a "How does it work?" entry at the end of that menu.

The full source code is in this repository, under the same license as the original.

## Tested on

Kobo Libra Colour with KOReader 2026.07.1 and ZenOS.

## Who made this

- **Original plugin:** [KORComic](https://github.com/KORComic) and the contributors of [comicreader.koplugin](https://github.com/KORComic/comicreader.koplugin).
- **Idea for the spread detection:** hatlessman ([pull request #78](https://github.com/KORComic/comicreader.koplugin/pull/78)).
- **Changes in this version:** written entirely by **Claude**, an AI by Anthropic (in Claude Code). The owner of this repository asked for the feature, tested on a Kobo and gave feedback, but did not write the code.

Please report problems with this version [here](../../issues), not to the original project. There is no warranty and no guaranteed support.

## License

[GNU AGPL-3.0](LICENSE.md), the same as the original.
