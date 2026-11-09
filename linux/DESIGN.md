# Afterglow desktop interface

The Linux and Windows ports share the existing local Canvas/SVG listening surface. This port preserves its established dark palette, Manrope typography, graph, glow and ribbon identity; it introduces no visual redesign. `src/style.css` owns runtime visual tokens and geometry, `src/clock-preview.js` owns seven clock faces, and `src/render.js` owns playback and frozen map rendering. Mac source `Sources/Afterglow` and the original Mac workspace DESIGN.md define intended feature behavior.

The listening surface displays synchronized words as a graph. Untimed lyrics remain in the explicitly opened library. Provider and timing diagnostics belong in that library. Appearance and clock fields use native HTML input/select controls, including operating-system-owned popup geometry and keyboard behavior. Preserve reduced motion, native keyboard focus and bounded panel scrolling.

`src/domain.js` owns validation, recording identity, scene snapshots and collection color precedence. Explicitly selecting an inheriting collection must inherit the scene/default even when another membership has a color. Provider privacy choices are global and never stored in song scenes. Clock scale is 70–140%; older 60–180% stored values migrate into this range. New collection names are unique without case/diacritic differences and contain 1–40 Unicode characters.

`src/app.js` owns UI state and `notice()` is the shared accessible status surface. The app's existing native HTML `dialog` owns modal focus, Escape and background isolation; deletion extends that owner through an app-owned dialog naming the collection, consequence and explicit Delete/Cancel actions. Cancel is focused first. Inputs retain invalid drafts, expose `aria-invalid` and focus the offending field.

`src/bridge.js` owns native invocation and the explicitly silent browser preview. Browser checks establish shared UI behavior; they do not certify WebView2, clipboard, native dialogs, real players, system audio, Explorer wallpaper or suspend/wake. Windows-specific copy must name Windows media sessions and native shortcut registration and must not direct Windows users to Linux compositor or MPRIS setup.
