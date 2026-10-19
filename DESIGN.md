# Seashell — Design

A macOS drag-and-drop shelf. Personal tool, public on GitHub, distributed outside the App Store, not sandboxed. Targets macOS 26 and later (26 is the last macOS for Intel Macs), as one universal app for Apple silicon and Intel. Bundle ID `io.github.codexjdub.seashell`, MIT license.

## Layout

A pull-down panel slides from the top of the screen (Unclutter-style). It has two areas:

```
┌─────────────── Pull-down panel ───────────────┐
│  STASH                        │  NOTES        │
│  [Main] [Work] [+]            │  note list    │
│  files & text, synced         │  + editor     │
└───────────────────────────────────────────────┘
```

A third area, the Clipboard (Copy and Cut), is designed but on hold; see the end.

- Centered below the menu bar, on the display the pointer is on; slides out from under the menu bar (its window sits one level below the menu bar's; the shelves that pop up at the pointer sit one above the panel). 1000 × 320 pt at Small text by default, scaled with the text size.
- Resizable: drag the bottom edge for height, either side edge for width (it stays centered); remembered per display, measured at Small so it still scales with text. Minimum 640 × 220 at Small. Drag the gap between the cards to change the Stash / Notes split (30–75%), remembered.
- Opens by pulling down at the top screen edge (two fingers down ~40 pt, or 2 wheel clicks toward you, whatever the natural-scrolling setting), from the menu bar item, or by holding a drag at the top edge for half a second (not within 100 pt of the corners, where hot corners live).
- Closes on a click outside it, Esc, pushing up at the top edge, or the menu bar item. A press outside that turns into dragging a file or text keeps it open, so you can drag things into it.
- The app icon sits on the panel's right edge like a seal, its center a fifth of the way down (the same on the grab shelf, drop shelf and tear-off shelves), about a third outside (click it for Settings; 42 pt at Small, no shadow of its own), and pin and close sit in a small pill over the bottom right corner the same way. They act on the whole panel, not on Notes. The window keeps 16 pt of room past the right edge for them, and the same empty room on the left so the panel stays centered; clicks in that see-through room go to whatever is underneath. The buttons are round, with a faint gray fill that darkens on hover and press, echoing the pill's rounded ends. The icon and pill scale with the text size.
- The pin stops clicks elsewhere from closing it; Esc, pushing up and the menu item still do. The pin is remembered until you unpin it, across closes and launches.
- Takes keys (Esc, ⌘⌫, Space) without taking focus from the app you're in.
- Dropping an item from the panel into another app brings that app to the front, so typing goes where the item landed, and closes the panel unless it's pinned.
- Space previews the selected item in Seashell's own preview window below the panel (a Quick Look view, not the system Quick Look window, which misbehaves for an app that's never active). Space or Esc closes it; arrows move through items and the preview follows.
- The close button closes the panel, pinned or not.
- Shelf tabs wrap onto more rows when they don't fit, with + always last; the first row lines up with Notes' header.
- Shelf tabs: Main first, then the order you drag them into (drag a tab onto another; a line shows where it lands). New shelves go at the end; ones made in Finder or on another Mac come after the saved order, by name. The order lives in `Stash/.seashell.json`, so every Mac sees it. A click still selects a tab; control-click or right-click opens Rename… / Delete….
- The Stash tabs and the Notes header share one height, so tabs, +, Notes and the pencil sit on one center line.
- Stash (55%) and Notes each sit on their own rounded, lightly tinted card with a small gap. The Notes card and Stash's note cards share one faint yellow wash, and the selected note is a little stronger. Dark Mode: 6% (border 22%, selected 16%). Light Mode needs a little more to show: 10% (border 30%, selected 22%).
- Notes: a list (most recently edited first) beside a plain-text editor; Markdown is kept exactly as typed. The first line is the title, and the file is renamed to match when you leave the note (switch notes, close the panel, quit). Two notes with the same title are `Groceries.md` and `Groceries 2.md`, and the second keeps its number rather than being renamed on every visit. If a note can't be saved, it stays open with its text instead of being left. Saves 1 s after you stop typing. ⌘N or the pencil adds a selected "New Note" row with the cursor in the editor; it gets a file once you type, and left empty it just disappears. An existing note left empty goes to the Trash. Rows show live titles as you type. Drag a note out as its text (plus a `.md` for Finder); drop text onto the list to start a note, including a text card dragged from Stash. The list holds still while a note is dragged out of it.
- If a note changed on disk since Seashell read it (another Mac, another app), saving writes `Title (edited here).md` instead of overwriting. With no pending edits, the editor just shows the new version.
- Text size: Small (the original), Medium (default, +15%), Large (+30%), Extra Large (+50%). Set in Settings or with ⌘+ / ⌘− / ⌘0 in the panel; remembered on this Mac. It scales all of Seashell's text, and tiles, cards, rows, the floating shelf and the panel grow with it (as far as the screen allows). macOS's own menus and alerts follow the system.
- Settings window: "Settings…" (⌘,) in the menu bar menu, or ⌘, in the panel. Esc or ⌘W closes it. Like the panel, it takes the keyboard without making Seashell the active app (macOS can refuse to bring Seashell forward when it's opened from the panel); it opens below the panel when that's open, and other apps' windows go over it as usual. Tips works the same way.
  - Theme: System (default), Light or Dark for Seashell's own windows (panel, floating shelf, preview, Settings, alerts). The menu bar icon follows the menu bar.
  - Text size: the same four steps as ⌘+ / ⌘− / ⌘0 in the panel, with that tip underneath.
  - Open Seashell when you log in: off until turned on; macOS tracks it (`SMAppService`) and lists it in Login Items. If macOS wants approval, Seashell opens Login Items and says so.
  - Ask before stashing: Over 500 MB, Over 1 GB (default), Over 5 GB, or Never.
  - Shake to show the shelf: Off, Gentle (2 swings of 15 pt), Normal (3 of 20 pt in 0.6 s, the default), Firm (4 of 30 pt in 0.8 s).
  - Ignore shakes in: a list of apps (+ chooses from Applications, − removes) where shakes do nothing, for both the drop shelf and the grab shelf, judged by the app in front. Drawing apps and games move the pointer fast on purpose. The menu bar menu also has "Ignore Shakes in <app>" for the app you're in.
  - Keyboard shortcut: ⌃⌥S (default), ⌃⌥⌘S, ⌃⌥Z or Off. Opens and closes the panel from any app; a Carbon hot key, so no Accessibility permission. The menu bar menu shows it beside Open Seashell.
  - Pull down at the top edge to open the panel: on by default. Pushing up still closes it, and holding a drag at the top edge still opens it.
- Edit shortcuts (⌘X ⌘C ⌘V ⌘A ⌘Z ⇧⌘Z) are wired up by hand: a menu bar app has no Edit menu. In the editor they use the system clipboard as usual.
- Dropping onto the menu bar icon stashes into `Main`.

Shaking the cursor during a drag pops a **floating shelf** near the cursor with one drop zone per shelf, in the panel's tab order (Main first), so you drop straight into the shelf you want. 5 shelves show at a time; past that, holding the drag over **More…** for 0.4 s shows the next 5 in the same spot (the shelf keeps its size, so More… stays under the pointer), and on the last page it reads **Back to Main…** and starts over. Move off More… and back to flip again. It hides about a second after the mouse is released, whether or not you dropped on it, and never deletes anything. It wears the app icon on its right edge too, a fifth of the way down (just a picture: it can't be clicked mid-drag).

**Grab shelf**: shake the pointer with ⌥ held and no button down, and a shelf pops up above the pointer with the 8 most recently added items from every shelf, newest first, as the same tiles as the panel, four to a row; it's sized to show all of them at once and never scrolls or bounces. The app icon sits on its right edge like the panel's seal, a fifth of the way down; clicking it opens Settings. Drag one out and a copy lands where you drop it (the item stays in Stash), and that app comes forward. It goes away after a drop, a click elsewhere, a second ⌥-shake, or when the pointer moves more than 220 pt away (not in the first second, so the end of the shake doesn't count); More… opens the full panel. ⌥ keeps it from firing when you shake the pointer just to find it (macOS enlarges the pointer on a plain shake, and still does with ⌥). It follows the shake sensitivity in Settings; Off turns it off too. Seashell listens for ⌥ and follows the pointer only while ⌥ alone is held, so ordinary mouse movement never wakes it.

**Tear-off shelves**: drag a shelf's tab out of the panel and let go anywhere outside it, and that shelf opens in its own small floating window there (Main too; Main still can't be reordered). It's a window onto the shelf, not a copy: the same files, in iCloud and in the panel. It shows the shelf's name, a close button and its items, four tiles across and two rows high (more scroll), and does what the panel does: drop to stash, drag out for a copy, double-click or ⌘O to open, Space to preview, ⌘⌫ and the right-click menu. It wears the seal on its right edge a fifth of the way down, like the panel and shelves (click it for Settings). Drag it by its header to move it. It floats above other windows on every Space and stays until you close it (the shelf stays in Stash). Open ones come back after a restart where they were. Renaming the shelf in the panel keeps its window open under the new name; deleting it, or renaming it in Finder or on another Mac (which can't be told from a deletion), closes the window. One per shelf: tearing off an open one moves its window.

## Behaviour

| | **Stash** |
|---|---|
| Drop a file or folder in | **Moves** into the shelf folder |
| Drop text in | Saved as `.txt` |
| Drop a link / image data | Saved as `.webloc` / `.png` |
| Drop a promised file (Photos, Mail, pictures from web pages) | Written into the shelf folder |
| Drag out | Pastes a copy; item stays |
| Drag onto another shelf's tab | File moves to that shelf's folder, keeping its Put Back origin |
| Right-click → Move to Trash | File goes to the Trash |
| Right-click → Put Back | File returns to the folder it came from |
| Synced via iCloud | Yes |

Rules:

- No modifier keys change behaviour. The drop zone decides.
- To take a file out of Stash for good: Put Back, or drag it out (a copy lands) and then Move to Trash.
- Copy, Paste and Rename… are in an item's right-click menu, in the panel and tear-off shelves; ⌘C and ⌘V work too. Copy puts a file on the clipboard as the file, a text snippet as its text and a link as its address. Paste stashes what the clipboard holds like a drop, except files are copied in and the originals stay. Rename keeps the item's place and Put Back origin. No Share: macOS only shows its share sheet for the active app, and clicking Seashell's panels never makes it active; Show in Finder → Share covers it.
- The menu bar menu, top to bottom: Open/Close Seashell (with the keyboard shortcut); a grey Stash heading over the shelves, indented, each with its item count as a badge; a grey Notes heading over an indented All Notes row with the number of notes (choosing a shelf opens the panel on it; All Notes opens it with the keyboard in the editor, on the last note); Show in Finder (`~/Documents/Seashell`, which holds both), Ignore Shakes in <app> and Settings…; Tips… and About Seashell; Quit.
- About Seashell is Seashell's own window, since the standard one keeps the icon at 64 points: a 128-point icon, the name, version and build (selectable, for bug reports), a line on what it is, the GitHub address, a Check for Updates… button, and the copyright and MIT License. Checking asks GitHub's API for the newest release (not drafts or pre-releases) only when chosen, compares versions part by part as numbers, and offers the release page if it's newer; nothing runs in the background and nothing downloads by itself.
- Tips: a welcome window on first launch shows the gestures (pull down, shake while dragging, ⌥-shake, the keyboard shortcut, tearing off a shelf, dropping on the menu bar icon, and saving screenshots to Stash through the Screenshot app's Other Location, which needs no code or watcher); "Tips…" in the menu bar menu shows it again.
- Promised files arrive in `$TMPDIR/Seashell-Incoming/<id>/`, which is removed once the file has moved into a shelf (or couldn't); anything left there is cleared at launch.
- A promised file (Photos, Mail, pictures from web pages) goes into the shelf only once it has content that has stopped growing for half a second. Chrome and other Chromium browsers use an older promise that reports the file before writing it. If it's still empty after 15 s, Seashell downloads the picture from the web address the drag carried (if that's really a picture), or else saves the picture data the drag carried as a PNG; failing both, it says so. An empty file is never stashed.
- In the panel, every item takes one tile. Text shows as a note card with its first lines (up to five at 13 pt), on the faint note yellow and a link as a neutral card with a blue link symbol, its title and site (a blue card would look selected); hovering shows the full text or address. Files and folders show thumbnails.
- Text and link tiles read their words or address in the background (file coordination can wait on iCloud) and cache them per modification date; an item edited in place, or one iCloud finishes downloading, counts as changed, so its tile redraws.
- A lone pasted or dropped picture that's already PNG goes in as it is; other pictures are converted to PNG in the background.
- Text (`.txt` up to 1 MB) and links (`.webloc`) drag out as their content — the words or the address — so they drop into text fields and browsers. Finder still gets the file: it's a file promise that Seashell writes on drop.
- Any file or folder over the limit in Settings (1 GB by default) going into Stash asks first — everything in Stash uploads to iCloud and counts against its storage.
- Moving into Stash from another volume is copy → verify → delete the original, like Finder.
- Stashed text is named by its first few words (`Recently, I lived for a few.txt`, at most 6 words and 40 characters), or `Snippet 2026-10-17 0942.txt` when there are none.
- Name clash in Stash: the newcomer becomes `report 2.pdf`, like Finder. A numbered copy counts on (`report 2.pdf` → `report 3.pdf`) only when the original is there too; a name that merely ends in a number keeps it (`Budget 2024.xlsx` → `Budget 2024 2.xlsx`). Dropping a file that's already in that shelf (back in from Finder, say) leaves it as it is.
- Folders are treated like files.
- Several items dropped at once become separate items. Select several in a shelf to drag them out together.
- Seashell touches the system clipboard only when you Copy or Paste, and never permanently deletes a file; removals go to the Trash.

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

~/Library/Application Support/Seashell/   ← this Mac only; created at launch, empty until the Clipboard

~/Library/Logs/Seashell/Seashell.log      ← readable log; past 1 MB, launching keeps its newest half
```

Per-Mac preferences live in UserDefaults: the panel's pin, sizes and split, open tear-off shelves, and every choice in Settings except launch at login, which macOS keeps.

A shelf's `.seashell.json` is read back as part of a merging coordinated write, so iCloud hands over the current version first. One that exists but can't be read is left untouched and the operation reports it, rather than being replaced with an empty list that would drop every item's place and Put Back on every Mac.

The folder on disk is the source of truth for Stash and Notes. Seashell watches it so changes from other Macs (via iCloud) or from Finder show up live.

iCloud "Optimize Mac Storage" can evict files. Items whose content is not local show a cloud badge; dragging one out starts the download first.

If two Macs edit the same note at once, iCloud keeps both as separate files (`Groceries 2.md`); Seashell shows both.

## Architecture

Swift Package Manager, no Xcode required. AppKit throughout, Notes included: windows, events, drag sessions and the item grids (`NSCollectionView`: multi-select, drag operations and context menus). Tests use Swift Testing (XCTest is not in the Command Line Tools).

```
Package.swift
Sources/
  SeashellCore/           ← no UI, unit-tested
    SeashellFolders       where things live; creates missing folders
    StashLibrary          shelves and items on disk; shelf order
    StashStore            the live view of Stash for the UI
    ShelfManifest         a shelf's .seashell.json: item order, Put Back origins
    FileMover             in (same-volume rename; cross-volume copy/verify/delete), between shelves, back out, to the Trash; rename
    FileNaming            names for text, links and pictures; Finder-style name clashes
    Notes, NotesStore     Markdown notes and their live list
    FolderWatcher         FSEvents on the Seashell folder
    Coordinated           NSFileCoordinator wrappers, so iCloud sees orderly writes
    PromisedFile          waits for a promised file to be written
    ItemContent           a text or link item's content, for dragging it out
    CloudStatus           iCloud state: local, downloaded, cloud only, downloading
    ShakeDetector         recognises a shake; fed by the drag and ⌥ watchers
    EdgeScrollDetector    recognises a pull down or push up at the top edge
    PanelGeometry, TextSize, SettingChoices, ImageConversion, FileSize, Log
  Seashell/               ← the app
    AppDelegate           wires it all up; single instance
    MenuBarController     the menu bar icon's menu and drop target (MenuBarIcon draws it)
    PanelController       the pull-down panel: non-activating NSPanel, slide, pin, resize
    StashPanelController  shelf tabs and the item grid (StashGridView)
    NotesPanelController  the note list and editor
    FloatingShelf         the drop shelf for a shake during a drag
    GrabShelf             the ⌥-shake shelf of recent items, and its OptionShakeWatcher
    TearOffShelf          a shelf in its own window
    DragWatcher           global drag monitor: shakes and holds at the top edge
    EdgeScrollWatcher     global scroll monitor, on only while pull down is on or the panel is open
    StashDropper          drops and pastes into a shelf
    DragOut, ItemActions  dragging items out; copy and rename
    HotKey                the global keyboard shortcut (Carbon hot key)
    SettingsWindow, AppSettings, TextSizeSetting, TipsWindow, PreviewWindow, Alerts, Seal, FlowView, DragHandle
Tests/SeashellCoreTests
Resources/AppIcon.svg     the app icon's source drawing
Resources/AppIcon.icns    built from it by scripts/make-icon.sh (svg2png.swift + iconutil)
scripts/bundle.sh         swift build for arm64 and x86_64 → lipo → Seashell.app (Info.plist, icon) → codesign: SIGN_IDENTITY, else codexjdub if it's in the keychain, else ad hoc
scripts/run.sh            quit the running copy → bundle → install to /Applications → open
scripts/test.sh           the unit tests
scripts/release.sh        Seashell-<version>.zip for a GitHub release: needs a clean tree and a real certificate; NOTARY_PROFILE notarizes
```

### App icon

A pearl-white scallop on pearl white, with Zephyr's breath from *The Birth of Venus*: three wind curls at the upper left, orange on the lowest strand to light brown on the highest. The shell has a lobed rim, light-catching ribs and small ears at the hinge, so it reads as a scallop, not a fan. It follows the Big Sur icon grid (an 824 pt rounded square on a 1024 canvas) as a classic `.icns`: Apple's layered format needs Xcode. To change it, edit `Resources/AppIcon.svg` and run `scripts/make-icon.sh`; AppKit renders the SVG (Quick Look's renderer would fill the corners white).

The menu bar icon matches it: the scallop in lines (seven lobes, six ribs, ears) with the three wind strands across its left edge, a small gap cut around them so they read in front. It's an 18 pt template image drawn in code (`MenuBarIcon.swift`), so macOS tints it for light and dark menu bars and it stays sharp at 1x and 2x. AppKit's SVG renderer blurs masked gaps, which is why it isn't an SVG.

Releases: version in `scripts/bundle.sh` (0.1.1), build number = commit count. The zip is signed with `codexjdub` and not notarized, so a downloaded copy is blocked on first launch ("“Seashell.app” Not Opened"); System Settings ▸ Privacy & Security ▸ Open Anyway lets it run (checked on macOS 27.0.1). Universal: `bundle.sh` builds Apple silicon natively and Intel with `--triple x86_64-apple-macosx26.0`, then joins them with `lipo`; `release.sh` refuses anything else. So far it has only run on macOS 27 on Apple silicon.

Build output lives in `~/Library/Caches/Seashell` (outside iCloud: iCloud tags bundles in Documents with metadata that breaks codesign). The installed app lives in `/Applications/Seashell.app`, where you'd look for it, a stable path for launch at login that iCloud won't sync (an admin account writes there without a password).

### Drag out

Stash items go out as a file URL with the operation mask `.copy`: Finder and other apps copy, and the item stays. Text and links go out as their content too (see Rules).

### Drag in

Finder does **not** delete the original when a drop target answers `move`. Seashell moves files into Stash itself (`FileMover`).

Answer `move` only for file drops. For anything else answer `copy`: a text source such as TextEdit deletes the dragged text when the destination answers `move`.

### Shake

Use the global `leftMouseDragged` monitor plus the drag pasteboard's `changeCount` to know content is being dragged. No polling needed. Global monitors don't see drags that start inside Seashell, so add a local monitor for those.

### Resource use

Keep it lean: every global monitor wakes Seashell for each matching event anywhere on the Mac, and that delivery (not Seashell's own code) is the cost: roughly 2–12% of one core while events stream in at ~120 a second. So nothing watches what it doesn't need:

- ⌥-shake listens for ⌥ (rare) and follows the pointer only while ⌥ alone is held.
- Scrolls are watched only while pull down is on or the panel is open (pushing up closes it).
- Drags are watched on press and drag only; checking the drag pasteboard costs under a microsecond.
- Shake Off stops the ⌥-shake watcher; the drag watcher stays for holding a drag at the top edge.

Measured 2026-10-18: 2.6 MB on disk; 17 MB of memory at launch, 47 MB once the panel has opened (kept for an instant reopen); 0% CPU and no wakeups when idle; 0% while the mouse moves without ⌥ (it was 2–12% before).

### Permissions

- Documents folder access: no prompt appeared in the spike (macOS 27.0.1, not sandboxed). Keep `NSDocumentsFolderUsageDescription` and sign every build with the same certificate (`codexjdub` for the maintainer's) in case a later macOS asks.
- Global mouse/scroll monitors work without Accessibility (spike), and so does a modifier-key (`flagsChanged`) monitor (tested 2026-10-18).

## On hold: Clipboard (Copy / Cut)

Designed, not built: on hold since 2026-10-17. A third card between Stash and Notes would hold references to your files instead of moving them in, and the floating shelf would gain Copy and Cut zones next to the shelves.

| | **Copy** | **Cut** |
|---|---|---|
| Drop a file or folder in | Reference only; nothing copied | Reference only; nothing moved |
| Drop text in | Held as text | Held as text |
| Drop a link / image data | Held as a local copy (acts as Copy) | Held as a local copy (acts as Copy) |
| Drop a promised file | Written to a local copy (acts as Copy) | Written to a local copy (acts as Copy) |
| Drag out | Copies the original (as it is *now*); item stays | **Moves** the original; item leaves |
| Right-click → Delete | Item forgotten; your file untouched | Item forgotten; your file untouched |
| Synced via iCloud | No (this Mac only) | No (this Mac only) |
| Original deleted / unreachable | Item shows "missing" | Item shows "missing" |

- **Cut only moves into Finder / a folder.** Dropped on any other app (Mail, Slack, browser) it acts like Copy and the item stays.
- Cut never deletes the original itself; Finder performs the move. The item is removed only once the original is confirmed gone from its old location.
- Text in Cut is a one-time paste: the source app decides whether text leaves it (most keep it).
- Copy items show a link badge to tell them from Stash items. The Clipboard area has a Clear button.
- Between areas: Cut → Stash moves the original into Stash and the Cut item leaves; Copy → Stash copies it in and both stay; Stash → Copy or Cut isn't allowed.
- Storage, this Mac only: `~/Library/Application Support/Seashell/clipboard.json` (security bookmarks + text) and `Held/` (local copies of promised files, links and image data).

Cut drags out a file URL with the mask `.move`. In `draggingSession(_:endedAt:operation:)`, if the operation was `.move` **and** the original no longer exists at its old path, the item is removed; otherwise it stays. This keeps Seashell out of the delete business. Proven on the same volume (spike, 2026-10-17): Finder moves the file about 1 s *after* the drag session ends, so check the original's path a few times over ~3 s. Other apps answer `generic` and leave the original. On a read-only drive Finder answered `move` but the copy failed and the original stayed, so the operation alone is never proof. A move onto a writable external drive is still unproven.
