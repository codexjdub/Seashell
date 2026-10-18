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

- Centered below the menu bar, on the display the pointer is on; slides out from under the menu bar. 1000 × 320 pt at Small text by default, scaled with the text size.
- Resizable: drag the bottom edge for height, either side edge for width (it stays centered); remembered per display, measured at Small so it still scales with text. Minimum 640 × 220 at Small. Drag the gap between the cards to change the Stash / Notes split (30–75%), remembered.
- Opens by pulling down at the top screen edge (two fingers down ~40 pt, or 2 wheel clicks toward you, whatever the natural-scrolling setting), from the menu bar item, or by holding a drag at the top edge for half a second (not within 100 pt of the corners, where hot corners live).
- Closes on a click outside it, Esc, pushing up at the top edge, or the menu bar item. A press outside that turns into dragging a file or text keeps it open, so you can drag things into it.
- The app icon sits over the panel's top right corner like a seal, about a third outside (click it for Settings; 42 pt at Small, no shadow of its own), and pin and close sit in a small pill over the bottom right corner the same way. They act on the whole panel, not on Notes. The window keeps 16 pt of room past the right edge for them, and the same empty room on the left so the panel stays centered; clicks in that see-through room go to whatever is underneath. The buttons are round, with a faint gray fill that darkens on hover and press, echoing the pill's rounded ends. The icon and pill scale with the text size.
- The pin stops clicks elsewhere from closing it; Esc, pushing up and the menu item still do. The pin is remembered until you unpin it, across closes and launches.
- Takes keys (Esc, ⌘⌫, Space) without taking focus from the app you're in.
- Dropping an item from the panel into another app brings that app to the front, so typing goes where the item landed, and closes the panel unless it's pinned.
- Space previews the selected item in Seashell's own preview window below the panel (a Quick Look view, not the system Quick Look window, which misbehaves for an app that's never active). Space or Esc closes it; arrows move through items and the preview follows.
- The close button closes the panel, pinned or not.
- Shelf tabs wrap onto more rows when they don't fit, with + always last; the first row lines up with Notes' header.
- Shelf tabs: Main first, then the order you drag them into (drag a tab onto another; a line shows where it lands). New shelves go at the end; ones made in Finder or on another Mac come after the saved order, by name. The order lives in `Stash/.seashell.json`, so every Mac sees it. A click still selects a tab; control-click or right-click opens Rename… / Delete….
- The Stash tabs and the Notes header share one height, so tabs, +, Notes and the pencil sit on one center line.
- Stash (55%) and Notes each sit on their own rounded, lightly tinted card with a small gap. The Notes card and Stash's note cards share one faint yellow wash, and the selected note is a little stronger. Dark Mode: 6% (border 22%, selected 16%). Light Mode needs a little more to show: 10% (border 30%, selected 22%). The Clipboard becomes a third card with Milestone 4 (on hold).
- Notes: a list (most recently edited first) beside a plain-text editor; Markdown is kept exactly as typed. The first line is the title, and the file is renamed to match when you leave the note (switch notes, close the panel, quit). Saves 1 s after you stop typing. ⌘N or the pencil adds a selected "New Note" row with the cursor in the editor; it gets a file once you type, and left empty it just disappears. An existing note left empty goes to the Trash. Rows show live titles as you type. Drag a note out as its text (plus a `.md` for Finder); drop text onto the list to start a note.
- If a note changed on disk since Seashell read it (another Mac, another app), saving writes `Title (edited here).md` instead of overwriting. With no pending edits, the editor just shows the new version.
- Text size: Small (the original), Medium (default, +15%), Large (+30%), Extra Large (+50%). Set in Settings or with ⌘+ / ⌘− / ⌘0 in the panel; remembered on this Mac. It scales all of Seashell's text, and tiles, cards, rows, the floating shelf and the panel grow with it (as far as the screen allows). macOS's own menus and alerts follow the system.
- Settings window: "Settings…" (⌘,) in the menu bar menu, or ⌘, in the panel. Esc or ⌘W closes it. It sits above the panel and hides when you switch to another app.
  - Theme: System (default), Light or Dark for Seashell's own windows (panel, floating shelf, preview, Settings, alerts). The menu bar icon follows the menu bar.
  - Text size: the same four steps as ⌘+ / ⌘− / ⌘0 in the panel, with that tip underneath.
  - Open Seashell when you log in: off until turned on; macOS tracks it (`SMAppService`) and lists it in Login Items. If macOS wants approval, Seashell opens Login Items and says so.
  - Ask before stashing: Over 500 MB, Over 1 GB (default), Over 5 GB, or Never.
  - Shake to show the shelf: Off, Gentle (2 swings of 15 pt), Normal (3 of 20 pt in 0.6 s, the default), Firm (4 of 30 pt in 0.8 s).
  - Pull down at the top edge to open the panel: on by default. Pushing up still closes it, and holding a drag at the top edge still opens it.
- Edit shortcuts (⌘X ⌘C ⌘V ⌘A ⌘Z ⇧⌘Z) are wired up by hand: a menu bar app has no Edit menu. In the editor they use the system clipboard as usual.
- Dropping onto the menu bar icon stashes into `Main`.

Shaking the cursor during a drag pops a **floating shelf** near the cursor with one drop zone per shelf, in the panel's tab order (Main first), so you drop straight into the shelf you want. 5 shelves show at a time; past that, holding the drag over **More…** for 0.4 s shows the next 5 in the same spot (the shelf keeps its size, so More… stays under the pointer), and on the last page it reads **Back to Main…** and starts over. Move off More… and back to flip again. Copy and Cut zones would join it with the Clipboard (on hold). It hides about a second after the mouse is released, whether or not you dropped on it, and never deletes anything.

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
- Any file or folder over the limit in Settings (1 GB by default) going into Stash asks first — everything in Stash uploads to iCloud and counts against its storage.
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
│   ├── Work/
│   └── .seashell.json                ← shelf order (after Main)
└── Notes/
    └── Groceries.md                  ← one Markdown file per note

~/Library/Application Support/Seashell/   ← this Mac only
├── clipboard.json                    ← Copy/Cut items: security bookmarks + text
└── Held/                             ← local copies of promised files, links and image data in Copy/Cut

Per-Mac preferences live in UserDefaults: the panel's pin, sizes and split, and every choice in Settings except launch at login, which macOS keeps.

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
    FloatingShelf       drop panel near the cursor: one zone per shelf, 5 per page, More… flips pages
    DragOut             NSDraggingSource per area (operation masks below)
    SettingsWindow      theme, text size, launch at login (SMAppService), large-file limit, shake sensitivity, pull down
    Views/              SwiftUI: StashView, ClipboardView, NotesView
Tests/SeashellCoreTests
Resources/AppIcon.svg   the app icon's source drawing
Resources/AppIcon.icns  built from it by scripts/make-icon.sh (svg2png.swift + iconutil)
scripts/bundle.sh       swift build → Seashell.app (Info.plist, icon) → codesign "codexjdub"
scripts/run.sh          quit running copy → bundle → install to /Applications → open
```

### App icon

A pearl-white scallop on pearl white, with Zephyr's breath from *The Birth of Venus*: three wind curls at the upper left, orange on the lowest strand to light brown on the highest. The shell has a lobed rim, light-catching ribs and small ears at the hinge, so it reads as a scallop, not a fan. It follows the Big Sur icon grid (an 824 pt rounded square on a 1024 canvas) as a classic `.icns`: Apple's layered format needs Xcode. To change it, edit `Resources/AppIcon.svg` and run `scripts/make-icon.sh`; AppKit renders the SVG (Quick Look's renderer would fill the corners white).

The menu bar icon matches it: the scallop in lines (seven lobes, six ribs, ears) with the three wind strands across its left edge, a small gap cut around them so they read in front. It's an 18 pt template image drawn in code (`MenuBarIcon.swift`), so macOS tints it for light and dark menu bars and it stays sharp at 1x and 2x. AppKit's SVG renderer blurs masked gaps, which is why it isn't an SVG.

Build output lives in `~/Library/Caches/Seashell` (outside iCloud: iCloud tags bundles in Documents with metadata that breaks codesign). The installed app lives in `/Applications/Seashell.app`, where you'd look for it, a stable path for launch at login that iCloud won't sync (an admin account writes there without a password).

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
