# Third-party notices

Afterglow depends on [Yams 6.2.2](https://github.com/jpsim/Yams/tree/6.2.2), an MIT-licensed YAML parser. Yams also incorporates libYAML; its upstream notices remain applicable. The build includes Yams's license in the app bundle.

Lyric services, lyrics, album artwork and player brands are owned by their respective rights holders; Afterglow's rights notice does not cover them.

## Linux and Windows previews

The desktop previews also use Tauri, its plugins, the pinned Rust dependencies in `linux/src-tauri/Cargo.lock`, and the bundled Swift/Foundation runtime. Windows adapters use the `windows` and `windows-future` Rust crates. `linux/scripts/collect-notices.py` collects the dependency license files and an inventory into the packaged `notices` directory, together with Swift, Foundation, ICU, Yams and Afterglow notices. Run it before packaging either platform.

The shared interface bundles Manrope and Instrument Serif; their SIL Open Font License files accompany them in `linux/public/fonts/`. Windows uses Microsoft's installed WebView2 runtime, which is separate from the Swift lyric helper.

## Yams license

```text
The MIT License (MIT)

Copyright (c) 2016 JP Simard.

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
```

## Sparkle 2.10.1 (macOS updater)

Sparkle is distributed under the MIT license, with additional bundled third-party notices. Its complete LICENSE is copied into `Afterglow.app/Contents/Resources/Sparkle-LICENSE.txt`. The framework and installer helpers are embedded under `Contents/Frameworks/Sparkle.framework`. Source: https://github.com/sparkle-project/Sparkle/tree/2.10.1 .
