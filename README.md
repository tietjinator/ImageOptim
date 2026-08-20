# SwiftOptim

**TL;DR:** [ImageOptim](https://imageoptim.com)'s interface, rebuilt with Claude Code and Codex
in native SwiftUI, running on ImageOptim's own unmodified compression backend — same lossless
optimization, same third-party tools, same results, modern native UI on top, plus a few new
features (filename date-tokens, a custom output folder / preserve-original option, HEIC → JPEG
conversion, a Finder Services-menu entry — see "What's different" below).

## With thanks

SwiftOptim exists entirely because of **[Kornel Lesiński](https://kornel.ski)**'s work building
and maintaining [ImageOptim](https://imageoptim.com) — every optimization tool this app runs,
every worker/queue/backend class it's built on, and the whole idea of "drag an image in, get a
smaller image out" is his. This fork changes none of that; it only changes the window dressing
around it. If SwiftOptim is useful to you, the actual compression happening under the hood is
Kornel's doing, and so is the work of everyone whose tools ImageOptim bundles and this fork
carries forward unchanged:

- [OxiPNG](https://lib.rs/crates/oxipng) — Josh Holmer
- [pngquant](https://pngquant.org) — Kornel Lesiński
- [PNGCrush](http://pmt.sourceforge.net/pngcrush/) — Glenn Randers-Pehrson
- [MozJPEG](https://github.com/mozilla/mozjpeg) — Mozilla and contributors
- [Guetzli](https://github.com/google/guetzli) and [Zopfli](https://github.com/google/zopfli) —
  Jyrki Alakuijala, Lode Vandevenne
- [AdvPNG](http://advancemame.sourceforge.net/doc-advpng.html) — Andrea Mazzoleni, Filipe Estima
- [Jpegoptim](http://www.kokkonen.net/tjko/projects.html) — Timo Kokkonen
- [Gifsicle](http://www.lcdf.org/gifsicle/) — Eddie Kohler
- [SVGO](https://github.com/svg/svgo) — Kir Belevich
- [svgcleaner](https://github.com/RazrFalcon/svgcleaner) — Evgeniy Reizner
- [PNGOUT](http://www.advsys.net/ken/utils.htm) — Ken Silverman (not GPL-covered, bundled with
  permission of Ardfry Imaging, LLC, same as upstream)

## What's different from ImageOptim

**Interface**, top to bottom, is new SwiftUI — main window chrome, file list (drag-drop, reorder,
reveal-in-Finder, Quick Look), and a sidebar-style Preferences window (inspired by
[IINA](https://github.com/iina/iina)'s) replacing the original's tab strip. The compression
backend (`Job`/`JobQueue`/`Workers`/etc.) is untouched — this is a UI layer on the same engine,
not a reimplementation of it.

**New features:**
- **Filename prefix/suffix** on save, including `{date}` / `{date:FORMAT}` tokens (e.g.
  `{date}` → `25.03.14`, `{date:HH-mm-ss}` → a timestamp) — a calendar-icon menu in
  Preferences → Files inserts common presets, or type a custom
  [`NSDateFormatter`](https://developer.apple.com/documentation/foundation/dateformatter)
  pattern directly.
- **Custom output folder** and a **Preserve Original** option — save a copy instead of
  overwriting the source file, either into a chosen folder, under a modified name, or both.
- **HEIC → JPEG conversion** (Preferences → Tools), feeding the result through the same JPEG
  compression pipeline as any other JPEG. The source `.heic` is never modified.
- **A "Optimize with ImageOptim" Finder Services-menu entry** — right-click an image, no need to
  open the app.
- Fixed a real performance bug on Apple Silicon where `RunLowPriority` defaulting to `true`
  pinned every compression worker onto the slow efficiency cores.

**Removed:** Sparkle-based auto-updates (this fork isn't signed as ImageOptim, so it can't use
ImageOptim's update feed without misrepresenting itself as a build it isn't) — grab new releases
from this repo's Releases page instead.

**Unchanged:** the license (GPLv2, same as upstream — see `LICENSE`), the actual optimization
behavior and quality, and every third-party tool listed above.

## Building

Requires:

* Xcode, signed into an Apple Developer account if you want a build you can run outside of
  Xcode's own debugger (Developer ID Application certificate, for Gatekeeper/notarization).
* [Rust](https://rust-lang.org/) installed via [rustup](https://www.rustup.rs/) (not Homebrew) —
  install both `aarch64-apple-darwin` and `x86_64-apple-darwin` targets if you're building a
  universal Release archive rather than an Apple-Silicon-only Debug build.

```sh
git clone --recursive https://github.com/tietjinator/SwiftOptim.git
cd SwiftOptim
```

To get started, open `imageoptim/ImageOptim.xcodeproj`. It will automatically download and build
all subprojects when run in Xcode.

In case of build errors, these sometimes help:

```sh
git submodule update --init
```

```sh
cd gifsicle # or pngquant
make clean
make
```
