# Seashell — Design

A macOS drag-and-drop shelf. Personal tool, public on GitHub, distributed outside the App Store, not sandboxed. Targets macOS 27 only. Bundle ID `io.github.codexjdub.seashell`, MIT license.

## Layout

A pull-down panel slides from the top of the screen (Unclutter-style). It has three areas:

```
┌──────────────────────── Pull-down panel ────────────────────────┐
│  STASH                    │  CLIPBOARD             │  NOTES       │
│  [Main] [Work] [+]        │  ┌─ Copy ─┐ ┌─ Cut ─┐  │  note list   │
│  files & text, synced     │  └────────┘ └───────┘  │  + editor    │
└──────────────────────────────────────────────────────────────────┘
```

- Centered below the menu bar, up to 1000 × 320 pt, on the display the pointer is on. Slides out from under the menu bar.
- Opens by pulling down at the top screen edge (two fingers down ~40 pt, or 2 wheel clicks toward you, whatever the natural-scrolling setting), from the menu bar item, or by holding a drag at the top edge for half a second (not within 100 pt of the corners, where hot corners live).
- Closes on a click outside it, Esc, pushing up at the top edge, or the menu bar item. A press outside that turns into dragging a file or text keeps it open, so you can drag things into it.
- A pin button (top right) stops clicks elsewhere from closing it; Esc, pushing up and the menu item still do. The pin is remembered until you unpin it, across closes and launches.
- Takes keys (Esc, ⌘⌫, Space) without taking focus from the app you're in.
- Dropping an item from the panel into another app brings that app to the front, so typing goes where the item landed, and closes the panel unless it's pinned.
- Space previews the selected item in Seashell's own preview window below the panel (a Quick Look view, not the system Quick Look window, which misbehaves for an app that's never active). Space or Esc closes it; arrows move through items and the preview follows.
- A close button (top right, next to the pin) closes the panel, pinned or not.
- Until Clipboard and Notes exist, Stash fills the panel.
- Dropping onto the menu bar icon stashes into `Main`.

Shaking the cursor during a drag pops a **floating shelf** near the cursor with three drop zones: Stash, Copy, Cut (Stash only until the Clipboard exists). Its Stash zone saves into the default `Main` shelf. It hides about a second after the mouse is released, whether or not you dropped on it, and never deletes anything.

## Behaviour

| | **Stash** | **Copy** (⌘C) | **Cut** (⌘X) |
|---|---|---|---|
| Drop a file or folder in | **Moves** into the shelf folder | Reference only; nothing copied | Reference only; nothing moved |
| Drop text in | Saved as `.txt` | Held as text | Held as text |
| Drop a link / image data | Saved as `.webloc` / `.png` | Held as a local copy (acts as Copy) | Held as a local copy (acts as Copy) |
| Drop a promised file (Photos, Mail, Safari images) | Written into the shelf folder | Written to a local copy (acts as Copy) | Written to a local copy (acts as Copy) |
| Drag out | Pastes a copy; item stays | Copies the original (as it is *now*); item stays | **Moves** the original; item leaves |
| Right-click → Delete | File goes to the Trash | Item forgotten; your file untouched | Item forgotten; your file untouched |
| Right-click → Put Back | File returns to the folder it came from | — | — |
| Synced via iCloud | Yes | No (this Mac only) | No (this Mac only) |
| Original deleted / unreachable | n/a — Stash owns the file | Item shows "missing" | Item shows "missing" |

Rules:

- No modifier keys change behaviour. The drop zone decides.
- To take a file out of Stash for good: drag it out (a copy lands), then right-click → Delete.
- In the panel, text shows as a note card (two tiles wide) with its first lines and a link as a card with its title and site; hovering shows the full text or address. Files and folders show thumbnails.
- Text (`.txt` up to 1 MB) and links (`.webloc`) drag out as their content — the words or the address — so they drop into text fields and browsers. Finder still gets the file: it's a file promise that Seashell writes on drop.
- Any file or folder over 1 GB going into Stash asks first — everything in Stash uploads to iCloud and counts against its storage.
- Moving into Stash from another volume is copy → verify → delete the original, like Finder.
- Stashed text is named by its first few words (`Recently, I lived for a few.txt`, at most 6 words and 40 characters), or `Snippet 2026-10-17 0942.txt` when there are none.
- Name clash in Stash: the newcomer becomes `report 2.pdf`, like Finder.
- Folders are treated like files.
- Several items dropped at once become separate items. Select several in a shelf to drag them out together.
- **Cut only moves into Finder / a folder.** Dropped on any other app (Mail, Slack, browser) it acts like Copy and the item stays.
- Cut never deletes the original itself; Finder performs the move (see Drag out). The item is removed only once the original is confirmed gone from its old location.
- Text in Cut is a one-time paste: the source app decides whether text leaves it (most keep it).
- Copy items show a link badge to distinguish them from Stash items. The Clipboard area has a Clear button.
- Seashell never touches the system clipboard and never permanently deletes a file; removals go to the Trash.

### Dragging between areas

| From → to | Result |
|---|---|
| Stash shelf → another Stash shelf | File moves to that shelf's folder |
| Cut → Stash | Original moves into Stash; Cut item leaves |
| Copy → Stash | A copy goes into Stash; original and Copy item stay |
| Stash → Copy or Cut | Not allowed |

## Storage

```
~/Documents/Seashell/                 ← synced by iCloud Desktop & Documents
├── Stash/
│   ├── Main/                         ← default shelf
│   │   ├── report.pdf
│   │   ├── Recently, I lived for a few.txt ← stashed text, named by its first words
│   │   └── .seashell.json            ← item order, where each item came from (Put Back)
│   └── Work/
└── Notes/
    └── Groceries.md                  ← one Markdown file per note

~/Library/Application Support/Seashell/   ← this Mac only
├── clipboard.json                    ← Copy/Cut items: security bookmarks + text
├── Held/                             ← local copies of promised files, links and image data in Copy/Cut
└── settings.json                     ← larger settings (Milestone 7)

Small per-Mac preferences such as the panel's pin live in UserDefaults.

~/Library/Logs/Seashell/Seashell.log      ← readable log for testing
```

The folder on disk is the source of truth for Stash and Notes. Seashell watches it so changes from other Macs (via iCloud) or from Finder show up live.

iCloud "Optimize Mac Storage" can evict files. Items whose content is not local show a cloud badge; dragging one out starts the download first.

If two Macs edit the same note at once, iCloud keeps both as separate files (`Groceries 2.md`); Seashell shows both.

## Architecture

Swift Package Manager, no Xcode required. AppKit for windows, events, drag sessions and the item grids (`NSCollectionView`: multi-select, drag operations and context menus need AppKit's control); SwiftUI where that control isn't needed, e.g. Notes. Tests use Swift Testing (XCTest is not in the Command Line Tools).

```
Package.swift
Sources/
  SeashellCore/         ← no UI, unit-tested
    SeashellFolders     paths; creates missing folders
    Log                 os.Logger + ~/Library/Logs/Seashell/Seashell.log
    StashStore          folder-backed shelves; NSFileCoordinator writes; folder watcher
    NotesStore          Markdown files in Notes/
    ClipboardStore      Copy/Cut items as bookmarks, persisted to clipboard.json
    FileMover           move-into-Stash (same volume rename; cross-volume copy/verify/delete); name clashes
    ItemStatus          missing / evicted / downloading
  Seashell/             ← the app
    AppDelegate         menu bar item (LSUIElement, no Dock icon); single instance
    PanelController     non-activating NSPanel, top-edge slide-down
    EdgeTrigger         global scroll monitor at the top screen edge
    ShakeDetector       global drag monitor + drag pasteboard → shake detection
    FloatingShelf       three-zone drop panel near the cursor
    DragOut             NSDraggingSource per area (operation masks below)
    SettingsWindow      launch at login (SMAppService), 1 GB limit, shake sensitivity
    Views/              SwiftUI: StashView, ClipboardView, NotesView
Tests/SeashellCoreTests
scripts/bundle.sh       swift build → Seashell.app (Info.plist, icon) → codesign "codexjdub"
scripts/run.sh          quit running copy → bundle → install to ~/Applications → open
```

Build output lives in `~/Library/Caches/Seashell` (outside iCloud: iCloud tags bundles in Documents with metadata that breaks codesign). The installed app lives in `~/Applications/Seashell.app`, a stable path for launch at login that macOS won't purge and iCloud won't sync.

### Drag out

Each area offers a different operation mask, and Finder performs the file operation:

- **Stash / Copy** — file URL with mask `.copy`.
- **Cut** — file URL with mask `.move`. In `draggingSession(_:endedAt:operation:)`, if the operation was `.move` **and** the original no longer exists at its old path, remove the item. Otherwise keep it.

This keeps Seashell out of the delete business for Cut. Proven on the same volume (spike, 2026-10-17): Finder moves the file about 1 s *after* the drag session ends, so check the original's path a few times over ~3 s. Other apps answer `generic` and leave the original. On a read-only drive Finder answered `move` but the copy failed and the original stayed, so the operation alone is never proof. A move onto a writable external drive is still unproven.

### Drag in

Finder does **not** delete the original when a drop target answers `move`. Seashell moves files into Stash itself (`FileMover`).

Answer `move` only for file drops. For anything else answer `copy`: a text source such as TextEdit deletes the dragged text when the destination answers `move`.

### Shake

Use the global `leftMouseDragged` monitor plus the drag pasteboard's `changeCount` to know content is being dragged. No polling needed. Global monitors don't see drags that start inside Seashell, so add a local monitor for those.

### Permissions

- Documents folder access: no prompt appeared in the spike (macOS 27.0.1, not sandboxed). Keep `NSDocumentsFolderUsageDescription` and sign every build with `codexjdub` in case a later macOS asks.
- Global mouse/scroll monitors work without Accessibility (spike).
