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
- The app icon's shell sits on the panel's right edge like a seal: the shell and strands without the icon's white tile, which glared on a dark panel, its center a fifth of the way down (the same on the grab shelf, drop shelf and tear-off shelves), about a third outside (click it for Settings; 42 pt at Small, no shadow of its own), and pin and close sit in a small pill over the bottom right corner the same way. They act on the whole panel, not on Notes. The window keeps 16 pt of room past the right edge for them, and the same empty room on the left so the panel stays centered; clicks in that see-through room go to whatever is underneath. The buttons are round, with a faint gray fill that darkens on hover and press, echoing the pill's rounded ends. The icon and pill scale with the text size.
- The shell reacts to its shelf (SealView), moving only as a whole, never its wind curls on their own (those are the easter egg's):
  - **Catch**: anything that lands (a drop, a paste, items dragged onto a tab) gets a squash and a bounce, about a third of a second, pivoting at the hinge.
  - **Lean**: while a drag from another app is over a Seashell window, its shell tips in toward the pointer (6°, give or take 4 as the pointer is higher or lower, and 3 pt to the left) and settles when the drag leaves or ends. It goes by DragWatcher's global drag events, so drags from Seashell's own grid don't count.
  - **Head shake**: side to side with the beep, when ⌘Z finds nothing to take back.
  - **Breathing**: while Read Aloud reads (below).
  - **Pearl**: something new on a shelf puts a small pearl at every shell's hinge (popping in), and its shelf's row in the menu bar menu says "N new" instead of the count. New means it turned up and Seashell on this Mac didn't put it there: saved from an iPhone (Files) or another Mac, or added or renamed in Finder. Everything Seashell writes into a shelf is noted first (LocalWrites, kept 10 minutes), and StashStore counts the rest, from launch, on shelves it already knew (a shelf renamed here would otherwise arrive whole, so one made elsewhere with items in it doesn't count). The source can't be told: macOS doesn't say which device saved a file. The pearl stays while the panel is open, so its shell shows it, and goes when the panel closes.
  - With Reduce Motion on, nothing moves; the pearl still shows, without its pop. Tried on 2026-10-24: the catch, lean and shake, the pearl popping in on the open panel, "1 new" in the menu, and closing the panel clearing it.
- The pin stops clicks elsewhere from closing it; Esc, pushing up and the menu item still do. The pin is remembered until you unpin it, across closes and launches.
- Takes keys (Esc, ⌘⌫, Space) without taking focus from the app you're in.
- Dropping an item from the panel into another app brings that app to the front, so typing goes where the item landed, and closes the panel unless it's pinned.
- Space previews the selected item in Seashell's own preview window below the panel (a Quick Look view, not the system Quick Look window, which misbehaves for an app that's never active). Space or Esc closes it; arrows move through items and the preview follows.
- The close button closes the panel, pinned or not.
- Shelf tabs wrap onto more rows when they don't fit, with + always last; the first row lines up with Notes' header.
- Shelf tabs: Main first, then the order you drag them into (drag a tab onto another; a line shows where it lands). New shelves go at the end; ones made in Finder or on another Mac come after the saved order, by name. The order lives in `Stash/.seashell.json`, so every Mac sees it. A click still selects a tab; control-click or right-click opens Rename… / Delete….
- The Stash tabs and the Notes header share one height, so tabs, +, Notes and the pencil sit on one center line.
- Stash (55%) and Notes each sit on their own rounded, lightly tinted card with a small gap. The Notes card and Stash's note cards share one faint yellow wash, and the selected note is a little stronger. Dark Mode: 6% (border 22%, selected 16%). Light Mode needs a little more to show: 10% (border 30%, selected 22%).
- Notes: a list (most recently edited first) beside a plain-text editor; Markdown is kept exactly as typed. The first line is the title, and the file is renamed to match when you leave the note (switch notes, close the panel, quit). Two notes with the same title are `Groceries.md` and `Groceries 2.md`, and the second keeps its number rather than being renamed on every visit. If a note can't be saved, it stays open with its text instead of being left. Saves 1 s after you stop typing. ⌘N or the pencil adds a selected "New Note" row with the cursor in the editor; it gets a file once you type, and left empty it just disappears. An existing note left empty goes to the Trash. A note that can't be read (only in iCloud while offline, or not UTF-8) isn't opened: it says so and stays as it is, since shown blank it would look emptied and go to the Trash on leaving. The same goes for its own window, and one that can't be read at launch isn't restored. Rows show live titles as you type. Drag a note out as its text (plus a `.md` for Finder); drop text onto the list to start a note, including a text card dragged from Stash. The list holds still while a note is dragged out of it.
- The notes cat (NotesCat; Settings ▸ "Show a cat by your notes", off at first): a grey tabby with white socks lying like a loaf on the Notes header, right of "Notes", its paws on the line where the list and editor start; about the shell's size (42 pt tall at Small, scaled with text), kept 20 pt from the card's right edge so it stays clear of the shell. Drawn in code from the mock-up's shapes (a 120 × 76 grid), each moving part on its own layer pivoting where it would. Panel only, not note windows. It reacts (mock-up of the newer moves: https://claude.ai/artifact/K7jRXUiaGPi3zGSJvEEuNU):
  - **Watching**: its eyes follow the pointer anywhere over the panel (a tracking area on the window's content view), and the text cursor as you type; it blinks every few seconds.
  - **Typing**: an ear twitches with each key; a paw bat at most every 2.5 s and 8 keys (CatPace).
  - **New note**: it hops into an open note-yellow box with its flaps up, paws out of sight, happy eyes and a ♪, and hops out after about 2 s.
  - **To-do ticked** by a click (NoteTextView.onTick): a paw pat and a sparkle; the last one ticked gets happy eyes, pink cheeks, hearts and a purr.
  - **Pinned**: sits up proud with a slow blink. **Moved to the Trash**: swats, then looks away with a flat mouth.
  - **Read Aloud** (anything Seashell reads): ears up, its head tilting, ♪ now and then.
  - **Petted** (a click): happy eyes, hearts, "prrr"; the third pet within 5 s (PetStreak) gets kneading instead, left paw, right paw, with a purr and hearts. Clicking does nothing else.
  - **Shelves**: a nod with happy eyes when something is dropped onto a shelf in the panel (from another app, or moved onto a tab); a paw waved when items start being dragged out of the grid; a drag from another app over the panel (DragWatcher's onDragMoved) has it watching with its head down, pupils wide and back end wiggling, pouncing (a hop and a bat) the first time it comes within 1.6 cat-heights (CatPounce), and stopping 0.45 s after the drag stops moving or leaves; 5 or more arrivals at once (ArrivalBurst, from StashStore's arrivals, which leave out Seashell's own writes) puff it up: a hop, "!", wide eyes, ears flat, a dashed outline of fur on end and a bottle-brush tail for about a second. Fewer arrivals just wake it.
  - **Left alone** (nothing typed, clicked, hovered over it or done to a note or shelf): once in each quiet spell, at a random moment 40–120 s in (CatIdle), it grooms (the paw up a little, head down to it, eyes shut, four licks with the tongue showing) or pats a pencil along the header three times until it falls off, then looks straight at you with a flat mouth and a slow blink. At 3 minutes it puts its chin on its paws, eyelids drooping, then dozes off (eyes shut, head down, breathing, z's) and its tail swings down onto the ledge and slides round behind it until the tip curls up by its front paw. The tail is one path in three shapes with the same points, so one turns into the next.
  - **Waking**: typing, hovering over it, petting or something arriving wakes it with a yawn (mouth wide, eyes shut, ears back) and a stretch (paws out in front, head back); a reaction to a note or shelf wakes it with just a hop. Either way its tail comes back up first. It's awake whenever the panel opens; nothing runs while the panel is closed or the cat is off.
  - **Hats** by the Mac's date (CatHat): a Santa hat through December, a small pumpkin beside its paws through October, checked as the panel opens.
  - With Reduce Motion on it keeps its faces (eyes, mouth, cheeks, yawning, sleepy eyelids) and the glyphs fade in place, the box, hat and pumpkin just appear, but nothing moves, turns or blinks, and there are no idle moves.
- Pinned notes: right-click a note → Pin keeps it at the top of the list, with a pin at the end of its title line (Unpin puts it back among the rest). Pins are kept by file name in `Notes/.seashell.json`, written the same careful way as a shelf's, so they sync. A note renamed to its first line keeps its pin and one moved to the Trash loses it; renaming one in Finder loses it too. A pin whose note has stayed gone for a minute (deleted or renamed in Finder, say) is forgotten, so a later note of that name doesn't come back pinned; the minute covers iCloud bringing the pin list before the note.
- To-dos: a line starting `- [ ]` is a to-do and `- [x]` a done one, as in GitHub's Markdown (`*` or `+` work too, indented or not). Click the `- [ ]` to tick or untick it. Done ones show grey with their words struck through, only on screen: the file stays plain text. Return at the end of a to-do starts the next one with the same indentation and bullet; Return on an empty to-do ends the list. ⇧⌘L (as in Apple Notes) turns the line, or the selected lines, into to-dos (a bulleted line keeps its bullet; blank lines in a selection are skipped), or back into plain lines if they all are already. Ticks, Return and ⇧⌘L undo like typing. A note whose first line is a to-do is titled by the words after the box.
- Lists: Return after `- milk` (or `*`, `+`) starts the next bullet, after `3. milk` (or `3)`) the next number, and after a to-do a new box. Return on an empty item moves it out a level, or ends the list if it isn't indented. Tab moves a list line in a level (or every selected line, when several are, blank ones aside) and ⇧Tab moves out (a tab, or up to four spaces); elsewhere Tab types a tab. A level is a tab character, which nests under bullets and numbers alike in Markdown.
- A note's right-click menu: Open in Its Own Window, Open With ▸ (apps that open Markdown, the default first), Show in Finder, Copy (its text), Duplicate (a copy named after its first line, e.g. "Groceries 2", opened), Pin / Unpin, Move to Trash. Right-clicking a note shows its menu without opening it, and the menu acts on that note whichever is open. Edits waiting to be saved are written first, so other apps and copies get the latest text.
- **Note windows**: Open in Its Own Window puts a note in a small window just below the panel, by the pointer, washed in the note yellow, with its title along the top and the same editor (to-dos, lists, ⌘Z, ⇧⌘L, the edit shortcuts and ⌘W). Like a torn-off shelf it floats above other windows on every Space and stays until closed; open ones come back after a restart where they were, at their size. It saves 1 s after you stop typing and is renamed to its first line when you click away; closing an emptied one sends it to the Trash. A note in a window is edited only there: its row in the panel shows a window symbol, and choosing it brings the window forward. Moving it to the Trash from the panel saves and closes its window first; if the window can't save, both stay. Deleted or renamed in Finder or on another Mac, its window closes, unless edits are waiting: then it stays, and saving them brings the file back. The panel and note windows share one editor (NoteEditor), so they save and follow the folder alike.
- If a note changed on disk since Seashell read it (another Mac, another app), saving writes `Title (edited here).md` instead of overwriting. With no pending edits, the editor just shows the new version.
- Text size: Small (the original), Medium (default, +15%), Large (+30%), Extra Large (+50%). Set in Settings or with ⌘+ / ⌘− / ⌘0 in the panel, a note window or a tear-off shelf; remembered on this Mac. It scales all of Seashell's text, and tiles, cards, rows, the floating shelf and the panel grow with it (as far as the screen allows). macOS's own menus and alerts follow the system.
- Settings window: "Settings…" (⌘,) in the menu bar menu, or ⌘, in the panel. Esc or ⌘W closes it. Like the panel, it takes the keyboard without making Seashell the active app (macOS can refuse to bring Seashell forward when it's opened from the panel); it opens below the panel when that's open, and other apps' windows go over it as usual. Tips works the same way.
  - Theme: System (default), Light or Dark for Seashell's own windows (panel, floating shelf, preview, Settings, alerts). The menu bar icon follows the menu bar.
  - Text size: the same four steps as ⌘+ / ⌘− / ⌘0 in the panel, with that tip underneath.
  - Open Seashell when you log in: off until turned on; macOS tracks it (`SMAppService`) and lists it in Login Items. If macOS wants approval, Seashell opens Login Items and says so.
  - Folder: where Seashell's folder is (`~/Documents/Seashell` by default), with Choose…, Show in Finder and, when it's elsewhere, Use Documents; a note says whether iCloud syncs it. Choosing a folder puts Seashell's folder inside it: after asking, Seashell saves the choice and restarts, and the next launch moves the folder before anything reads it, so nothing still open saves into the old place. Across disks it's copied beside its new place, checked to come out the same size and renamed into place, and only then is the original removed, as FileMover does; a move that fails leaves it where it was and says why. A Seashell folder there with files in it (synced from another Mac, say) is used as it is, and the old one stays; one with no files (only empty shelves, as other Macs' Seashells leave it in iCloud) goes to the Trash and the move goes ahead. Leaving iCloud warns that the other Macs lose it, and waits until everything is downloaded (it starts the downloads and asks you to choose again). If the folder isn't there at launch (a disk not connected), Seashell waits 5 s for it, then offers Try Again, Choose…, Use Documents or Quit, rather than starting an empty one.
  - Ask before stashing: Over 500 MB, Over 1 GB (default), Over 5 GB, or Never.
  - Shake to show the shelf: Off, Gentle (2 swings of 15 pt), Normal (3 of 20 pt in 0.6 s, the default), Firm (4 of 30 pt in 0.8 s).
  - Ignore shakes in: a list of apps (+ chooses from Applications, − removes) where shakes do nothing, for both the drop shelf and the grab shelf, judged by the app in front. Drawing apps and games move the pointer fast on purpose. The menu bar menu also has "Ignore Shakes in <app>" for the app you're in.
  - Keyboard shortcut: ⌃⌥S (default), ⌃⌥⌘S, ⌃⌥Z or Off. Opens and closes the panel from any app; a Carbon hot key, so no Accessibility permission. The menu bar menu shows it beside Open Seashell.
  - Pull down at the top edge to open the panel: on by default. Pushing up still closes it, and holding a drag at the top edge still opens it.
- Seashell's alerts (rename, new shelf, confirmations, errors) open above the panel and shelves. `runModal` puts its window at the modal panel level (8), below the panel (23), whatever level it had, so `Alerts` raises it to 25 once the modal session runs (checked on macOS 27). Clicking a panel doesn't make Seashell the active app, so an alert opened from one does; that can finish after the raise and put the alert back at 8, so `Alerts` raises open alerts again when Seashell becomes active.
- Edit shortcuts (⌘X ⌘C ⌘V ⌘A ⌘Z ⇧⌘Z) are wired up by hand: a menu bar app has no Edit menu. In the editor they use the system clipboard as usual. Every shortcut is matched against the key as it types with ⌘ held, as menus do, so they work in layouts whose ⌘ keys differ from their plain ones (Russian types "с" on the C key, but "c" with ⌘).
- Dropping onto the menu bar icon stashes into `Main`.
- Services: "Stash in Seashell" takes files, folders or text selected in any app (in Finder: right-click ▸ Services) into `Main`, quietly, like a drop on the menu bar icon: files move and can be put back, and big ones ask first. "New Seashell Note" makes a note of the selected text and opens the panel on it, cursor at the end. Both are declared under `NSServices` in Info.plist; with `NSRequiredContext` macOS turns them on by default, and System Settings ▸ Keyboard ▸ Keyboard Shortcuts ▸ Services can give them shortcuts.

Shaking the cursor during a drag pops a **floating shelf** near the cursor with one drop zone per shelf, in the panel's tab order (Main first), so you drop straight into the shelf you want. 5 shelves show at a time; past that, holding the drag over **More…** for 0.4 s shows the next 5 in the same spot (the shelf keeps its size, so More… stays under the pointer), and on the last page it reads **Back to Main…** and starts over. Move off More… and back to flip again. It hides about a second after the mouse is released, whether or not you dropped on it, and never deletes anything. It wears the app icon on its right edge too, a fifth of the way down (just a picture: it can't be clicked mid-drag).

**Grab shelf**: shake the pointer with ⌥ held and no button down, and a shelf pops up above the pointer with the 8 most recently added items from every shelf, newest first, as the same tiles as the panel, four to a row; it's sized to show all of them at once and never scrolls or bounces. The app icon sits on its right edge like the panel's seal, a fifth of the way down; clicking it opens Settings. Drag one out and a copy lands where you drop it (the item stays in Stash), and that app comes forward. It goes away after a drop, a click elsewhere, a second ⌥-shake, or when the pointer moves more than 220 pt away (not in the first second, so the end of the shake doesn't count); More… opens the full panel. A pin in a small pill over its bottom right corner, like the panel's, keeps it up through drops, clicks elsewhere and moving away, so several items can be dragged out one after another; pinned, it moves by its header, a close button shows under the pin, and items stashed meanwhile appear in it (its top edge stays put, as far as the screen allows). A second ⌥-shake still puts it away, and each ⌥-shake shows it unpinned. Empty, it's tall enough for the pill to clear the seal. Tried on 2026-10-28. ⌥ keeps it from firing when you shake the pointer just to find it (macOS enlarges the pointer on a plain shake, and still does with ⌥). It follows the shake sensitivity in Settings; Off turns it off too. Seashell listens for ⌥ and follows the pointer only while ⌥ alone is held, so ordinary mouse movement never wakes it.

**Tear-off shelves**: drag a shelf's tab out of the panel and let go anywhere outside it, and that shelf opens in its own small floating window there (Main too; Main still can't be reordered). It's a window onto the shelf, not a copy: the same files, in iCloud and in the panel. It shows the shelf's name, a close button and its items, four tiles across and two rows high to begin with (more scroll); dragging any edge or corner resizes it a whole column or row of tiles at a time, the opposite edges staying put, as far as the screen allows on that side, down to one tile. Its size is kept in tiles, so it keeps its shape when the text size changes, and comes back with it after a restart. It does what the panel does: drop to stash, drag out for a copy, double-click or ⌘O to open, Space to preview, ⌘⌫, ⌘Z, ⌘+ / ⌘− / ⌘0 and the right-click menu. It wears the seal on its right edge a fifth of the way down, like the panel and shelves (click it for Settings). Drag it by its header to move it. It floats above other windows on every Space and stays until you close it (the shelf stays in Stash). Open ones come back after a restart where they were. Renaming the shelf in the panel keeps its window open under the new name; deleting it, or renaming it in Finder or on another Mac (which can't be told from a deletion), closes the window. One per shelf: tearing off an open one moves its window.

## Behaviour

| | **Stash** |
|---|---|
| Drop a file or folder in | **Moves** into the shelf folder (with ⌥ held, a copy goes in and the original stays) |
| Drop text in | Saved as `.txt` |
| Drop a link / image data | Saved as `.webloc` / `.png` |
| Drop a promised file (Photos, Mail, pictures from web pages) | Written into the shelf folder |
| Drag out | Pastes a copy; item stays |
| Drag onto another shelf's tab | File moves to that shelf's folder, keeping its Put Back origin |
| Right-click → Move to Trash | File goes to the Trash |
| Right-click → Put Back | File returns to the folder it came from |
| Synced via iCloud | Yes |

Rules:

- The drop zone decides, and only ⌥ changes anything: ⌥-dropping files copies them in and leaves the originals, as in Finder, and the pointer shows + to say so. A drag from an app that only lets its files be copied is the same. ⌘Z sends such a copy to the Trash.
- To take a file out of Stash for good: Put Back, or drag it out (a copy lands) and then Move to Trash.
- ⌘Z in the panel's Stash side or a tear-off shelf takes back the latest drop, paste or move onto another tab, wherever it went (the menu bar icon, the floating shelf and Stash in Seashell count too): one step per drop, the last 20, while Seashell runs. A file that came from a folder goes back there under its old name (numbered if that name is taken now). A pasted copy, text, link, picture or promised file goes to the Trash, since the original is still where it came from. Items moved onto another tab go back to their shelf under their old name. Items moved, renamed or trashed since are left alone, and with nothing left to undo it beeps. A drop still landing (a big copy from another disk, a promised file) is the one taken back, once it has landed; a second ⌘Z while that waits beeps. If it lands with nothing (a promise never kept), the drop before it is taken back instead. It waits up to a minute (an app may never hand over a file it promised), then takes back what has landed; anything of that drop landing later is the next ⌘Z's. Move to Trash, Put Back and Rename aren't undone (the Trash has Put Back of its own). In the notes editor ⌘Z undoes typing as usual.
- Copy, Paste and Rename… are in an item's right-click menu, in the panel and tear-off shelves; ⌘C and ⌘V work too. Copy puts a file on the clipboard as the file, a text snippet as its text and a link as its address. Paste stashes what the clipboard holds like a drop, except files are copied in and the originals stay. Rename keeps the item's place and Put Back origin. Copy Text, shown when the selection has a PDF or a picture macOS can open (about 60 formats, camera RAW included; not SVG, which ImageIO can't read), reads their words on this Mac and puts them on the clipboard (several with a blank line between): a PDF page's text layer as it is, and pictures and scanned pages through Vision's text recognition (a page whose text layer is under 100 characters too, as a scan may carry only a stamped page number or fax header: what Vision finds is used if it's more than twice as long) (accurate, the language detected), sideways photos turned upright first, and every page of a multi-page TIFF (a scan's; other formats' extra images are the same picture again, so only the first is read). It takes about a tenth of a second a picture, the first time too, and after a reinstall (tried 2026-10-21). Unsigned test programs wait 15–30 s on their first use while macOS sets up the model, but the signed app didn't, so nothing sets it up ahead. The model (about 10 MB) stays in memory once Copy Text has been used, until Seashell quits. An item only in iCloud starts downloading, with a note to try again; no text found says so, and so does a PDF locked with a password. A long scan is read a page at a time, each page's picture let go before the next (a 60-page scan peaked at 121 MB rather than 418 MB). If the clipboard changes while it reads (you copied something else, or chose Copy Text again), the newer one stays. No Share: macOS only shows its share sheet for the active app, and clicking Seashell's panels never makes it active; Show in Finder → Share covers it.
- Read Aloud, in the right-click menu of text snippets, pictures and PDFs (the panel and tear-off shelves) and of notes in the list, reads them on this Mac: a snippet as it is, a note with its waiting edits saved first, a picture or PDF through Copy Text's reading of its words; several one after another. The voice is the one Spoken Content (System Settings ▸ Accessibility) chose for the text's language, which NaturalLanguage tells from its first 2,000 characters, when apps may use it: Siri voices they may not, so English on this Mac (Spoken Content set to a Siri voice) falls back to the best English voice in the Mac's own region (Samantha), while Chinese, which Spoken Content reads as Cantonese, gets the premium Hong Kong voice (Sinji). Without a usable choice it's the best voice for the language (Traditional Chinese: Taiwan's, then Hong Kong's), else the default. One reading at a time; a new one replaces it. While it reads, the item menus and the notes menu offer Stop Reading instead, and the menu bar menu has Stop Reading under Open/Close, since reading goes on after the panel closes. Every shell breathes meanwhile (a little larger and back, about every 2.5 s; still with Reduce Motion). Tried on 2026-10-24: English and Chinese snippets, the breathing, Stop Reading from the item menu and the menu bar menu; notes, pictures and PDFs not yet in the app.
- The menu bar menu, top to bottom: Open/Close Seashell (with the keyboard shortcut); a grey Stash heading over the shelves, indented, each with its item count as a badge; a grey Notes heading over an indented All Notes row with the number of notes (choosing a shelf opens the panel on it; All Notes opens it with the keyboard in the editor, on the last note); Show in Finder (Seashell's folder, which holds both), Ignore Shakes in <app> and Settings…; Tips… and About Seashell; Quit.
- Easter egg (not mentioned anywhere users look): typing 1 1 1 and Return in About Seashell, each key within 2 s of the last, shows the app icon at its native 1024 pixels (512 points on a Retina screen, 1024 on a 1x one, smaller if the screen is) in the middle of the screen, on a 4-second loop: the wind strands blow in from the left one after another, a soft ring of pearly light (pink, white, mint) spreads from the hinge up and out across the ribs to the rim, never onto the ears, and the strands drift off up and to the right as they fade. A click, Esc or any key, or clicking elsewhere, puts it away. Reduce Motion shows the still icon. About takes the 1s and Return quietly, since nothing there uses them and they'd beep. Its pieces are small SVGs in `Resources/EasterEgg` (made by make-icon.sh), drawn when it opens.
- About Seashell is Seashell's own window, since the standard one keeps the icon at 64 points: a 128-point icon, the name, version and build (selectable, for bug reports), a line on what it is, the GitHub address, a Check for Updates… button, and the copyright and MIT License. Checking asks GitHub's API for the newest release (not drafts or pre-releases) only when chosen, compares versions part by part as numbers, and offers the release page if it's newer; nothing runs in the background and nothing downloads by itself.
- Tips: a welcome window on first launch shows the gestures (pull down, shake while dragging, ⌥-shake, the keyboard shortcut, tearing off a shelf, dropping on the menu bar icon, Stash in Seashell from Finder's Services, and saving screenshots to Stash through the Screenshot app's Other Location, which needs no code or watcher); "Tips…" in the menu bar menu shows it again.
- Promised files arrive in `$TMPDIR/Seashell-Incoming/<id>/`, which is removed once the file has moved into a shelf (or couldn't); anything left there is cleared at launch.
- A promised file (Photos, Mail, pictures from web pages) goes into the shelf only once it has content that has stopped growing for half a second. Chrome and other Chromium browsers use an older promise that reports the file before writing it. If it's still empty after 15 s, Seashell downloads the picture from the web address the drag carried (if that's really a picture), or else saves the picture data the drag carried as a PNG; failing both, it says so. An empty file is never stashed.
- In the panel, every item takes one tile. Text shows as a note card with its first lines (up to five at 13 pt), on the faint note yellow and a link as a neutral card with a blue link symbol, its title and site (a blue card would look selected); hovering shows the full text or address. Files and folders show thumbnails.
- Tiles read their thumbnails, words or addresses in the background (file coordination can wait on iCloud) and cache them per modification date and whether the item is on this Mac yet, in one cache shared by the panel, the grab shelf and tear-off shelves. An item edited in place, or one iCloud finishes downloading, counts as changed, so its tile redraws with what it now shows. A tile asked for again while its thumbnail is still being made (the grid reloading as a drop lands) waits for that one rather than starting another. What finds nothing (text only in iCloud, a file Quick Look can't draw) is remembered too, so it isn't tried again on every reload, until the item changes or downloads. Grids keep their selection when they reload.
- A pasted or dropped picture that's already PNG goes in as it is; others are converted to PNG in the background from the data they came with (a photo stored on its side comes out upright), rather than first being made into a full-size TIFF, which holds everything up for a tenth of a second per photo.
- Text (`.txt` up to 1 MB) and links (`.webloc`) drag out as their content — the words or the address — so they drop into text fields and browsers. Text is UTF-8, or UTF-16 with the byte order mark it starts with; without one, UTF-16 would turn almost any bytes into nonsense (a Latin-1 file comes out as Chinese), so a file in another encoding drags out and copies as the file, and its card shows its name. Finder still gets the file: it's a file promise that Seashell writes on drop.
- Any file or folder over the limit in Settings (1 GB by default) going into Stash asks first — everything in Stash uploads to iCloud and counts against its storage.
- Moving into Stash from another volume is copy → verify → delete the original, like Finder.
- Stashed text is named by its first few words (`Recently, I lived for a few.txt`, at most 6 words and 40 characters), or `Snippet 2026-10-17 0942.txt` when there are none.
- Names Seashell makes up (note titles, snippets, links) are cut to 200 UTF-16 units if need be, at a whole character. macOS allows 255, and one emoji can take 11, so 60 characters of emoji could otherwise make a note impossible to save; the rest leaves room for " (edited here)", a number and the extension.
- Name clash in Stash: the newcomer becomes `report 2.pdf`, like Finder. A numbered copy counts on (`report 2.pdf` → `report 3.pdf`) only when the original is there too; a name that merely ends in a number keeps it (`Budget 2024.xlsx` → `Budget 2024 2.xlsx`). Dropping a file that's already in that shelf (back in from Finder, say) leaves it as it is.
- Folders are treated like files.
- Several items dropped at once become separate items. Select several in a shelf to drag them out together.
- Seashell touches the system clipboard only when you Copy, Copy Text or Paste, and never permanently deletes a file; removals go to the Trash.

## Storage

```
~/Documents/Seashell/                 ← synced by iCloud Desktop & Documents; or Seashell in the folder chosen in Settings
├── Stash/
│   ├── Main/                         ← default shelf
│   │   ├── report.pdf
│   │   ├── Recently, I lived for a few.txt ← stashed text, named by its first words
│   │   └── .seashell.json            ← item order, where each item came from (Put Back)
│   ├── Work/
│   └── .seashell.json                ← shelf order (after Main)
└── Notes/
    ├── Groceries.md                  ← one Markdown file per note
    └── .seashell.json                ← which notes are pinned

~/Library/Application Support/Seashell/   ← this Mac only; created at launch, empty until the Clipboard

~/Library/Logs/Seashell/Seashell.log      ← readable log; past 1 MB, launching keeps its newest half
```

Per-Mac preferences live in UserDefaults: the panel's pin, sizes and split, open tear-off shelves (where, and how many tiles across and down), and every choice in Settings except launch at login, which macOS keeps. The folder chosen for Seashell's folder is kept as a path (none for Documents), with the old folder's path while a move waits for the restart.

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
    FolderMove            choosing another folder: what it would do (move, use one there, nothing); the move itself
    StashLibrary          shelves and items on disk; shelf order
    StashStore            the live view of Stash for the UI; re-reads changed shelves in the background; new arrivals
    LocalWrites           what Seashell just put on a shelf, so it isn't counted as arrived
    ShelfManifest         a shelf's .seashell.json: item order, Put Back origins
    FileMover             in (same-volume rename; cross-volume copy/verify/delete), between shelves, back out, to the Trash; rename; undo; batches write each manifest once
    StashUndo             what ⌘Z takes back: each drop's changes, the last 20 steps; drops still landing
    VanishedEntries       manifest entries whose items have gone, forgotten after a grace (Stash items, pins)
    SecretCode            a short code typed on the keyboard (the easter egg's 1 1 1 Return)
    FileNaming            names for text, links and pictures; Finder-style name clashes
    Notes, NotesStore     Markdown notes and their live list
    NotesManifest         the Notes folder's .seashell.json: pinned notes
    NoteSession           the note being edited: saving, "(edited here)" copies, following the folder
    Checklist             to-do lines in notes: finding, ticking, ⇧⌘L
    CatPace               how often the notes cat bats at your typing
    CatHabits             the notes cat's rules: petting streaks, big batches, idle moves, pouncing, hats
    NoteLines             line-by-line note edits; MarkdownList: Return in lists, Tab and ⇧Tab
    FolderWatcher         FSEvents on the Seashell folder, with which folders changed
    Coordinated           NSFileCoordinator wrappers, so iCloud sees orderly writes
    PromisedFile          waits for a promised file to be written
    ItemContent           a text or link item's content, for dragging it out
    TextRecognition       Copy Text: the words in a picture or PDF (PDFKit's text layer, else Vision)
    SpeechVoices          Read Aloud's voice: Spoken Content's choice for the text's language, else the best one there is
    CloudStatus           iCloud state: local, downloaded, cloud only, downloading
    ShakeDetector         recognises a shake; fed by the drag and ⌥ watchers
    EdgeScrollDetector    recognises a pull down or push up at the top edge
    PanelGeometry, TileGrid, TextSize, SettingChoices, ImageConversion, FileSize, Log
  Seashell/               ← the app
    AppDelegate           wires it all up; single instance
    FolderLocation        where Seashell's folder is: settled at launch (a waiting move, a missing disk); choosing another, then restarting
    MenuBarController     the menu bar icon's menu and drop target (MenuBarIcon draws it)
    PanelController       the pull-down panel: non-activating NSPanel, slide, pin, resize
    StashPanelController  shelf tabs and the item grid (StashGridView)
    NotesPanelController  the note list and editor
    NotesCat              the cat on the Notes header and its reactions
    NoteEditor            the editor and its note (a NoteSession), shared by the panel and note windows
    NoteTextView          the note text view (to-dos, lists), and EditShortcuts for windows with no Edit menu
    NoteWindow            notes in their own floating windows (NoteWindows keeps and restores them)
    EasterEgg             the icon, animated, for 1 1 1 Return in About (AboutWindow watches for it)
    FloatingShelf         the drop shelf for a shake during a drag
    GrabShelf             the ⌥-shake shelf of recent items, and its OptionShakeWatcher
    TearOffShelf          a shelf in its own window
    DragWatcher           global drag monitor: shakes and holds at the top edge
    EdgeScrollWatcher     global scroll monitor, on only while pull down is on or the panel is open
    StashDropper          drops and pastes into a shelf; records them for ⌘Z
    ReadAloud             speaks text in the chosen voice; one reading at a time, Stop Reading
    ServiceProvider       Stash in Seashell and New Seashell Note in the Services menu
    DragOut, ItemActions  dragging items out; copy and rename
    HotKey                the global keyboard shortcut (Carbon hot key)
    SettingsWindow, AppSettings, TextSizeSetting, TipsWindow, PreviewWindow, Alerts, Seal, FlowView, DragHandle
Tests/SeashellCoreTests
Resources/AppIcon.svg     the app icon's source drawing
Resources/AppIcon.icns    built from it by scripts/make-icon.sh (svg2png.swift + iconutil)
Resources/Seal.png        the panels' seal: the same drawing without its tile, also made by make-icon.sh
Resources/EasterEgg/      the easter egg's pieces, also made by make-icon.sh
scripts/bundle.sh         swift build for arm64 and x86_64 → lipo → Seashell.app (Info.plist, icon) → codesign: SIGN_IDENTITY, else codexjdub if it's in the keychain, else ad hoc
scripts/run.sh            quit the running copy → bundle → install to /Applications → open
scripts/test.sh           the unit tests
scripts/release.sh        Seashell-<version>.zip for a GitHub release: needs a clean tree and a real certificate; NOTARY_PROFILE notarizes
```

### App icon

A pearl-white scallop on pearl white, with Zephyr's breath from *The Birth of Venus*: three wind curls at the upper left, all 14 pt wide (on the 1024 canvas): light blonde on top (`#D7B682`), warm tan in the middle (`#DE9E63`) and orange at the bottom (`#EE8F3A`). The shell has a lobed rim, light-catching ribs and small ears at the hinge, so it reads as a scallop, not a fan. It follows the Big Sur icon grid (an 824 pt rounded square on a 1024 canvas) as a classic `.icns`: Apple's layered format needs Xcode. To change it, edit `Resources/AppIcon.svg` and run `scripts/make-icon.sh`; AppKit renders the SVG (Quick Look's renderer would fill the corners white). The same script makes the panels' seal, `Resources/Seal.png` (256 px): the drawing without the groups whose id starts with `tile`, framed a fifth closer so the shell fills the seal's spot. About and Tips still show the full icon. It also makes the easter egg's pieces in `Resources/EasterEgg`: the drawing without the `strands` group, each strand on its own, and the shell's outline above the hinge (y 724, where the ribs meet) as the ripple's mask.

The menu bar icon matches it: the scallop in lines (seven lobes, six ribs, ears) with the three wind strands across its left edge, a small gap cut around them so they read in front. It's an 18 pt template image drawn in code (`MenuBarIcon.swift`), so macOS tints it for light and dark menu bars and it stays sharp at 1x and 2x. AppKit's SVG renderer blurs masked gaps, which is why it isn't an SVG.

Releases: version in `scripts/bundle.sh` (0.1.7), build number = commit count. The zip is signed with `codexjdub` and not notarized, so a downloaded copy is blocked on first launch ("“Seashell.app” Not Opened"); System Settings ▸ Privacy & Security ▸ Open Anyway lets it run (checked on macOS 27.0.1). Universal: `bundle.sh` builds Apple silicon natively and Intel with `--triple x86_64-apple-macosx26.0`, then joins them with `lipo`; `release.sh` refuses anything else. So far it has only run on macOS 27 on Apple silicon.

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
- Stash follows the folder shelf by shelf: a change re-reads only the shelves it touched, in the background, since reading a shelf asks iCloud about each item (about 0.75 ms each, measured 2026-10-21) and reads its manifest through file coordination (about 1.6 ms). When macOS can't say what changed, all of Stash is read. Adding, renaming, deleting or reordering shelves reads the list of shelves at once, since what follows needs it, and the items only of a shelf new to the list (made or renamed): reading every item would hold the panel up for about 1–2.5 ms an item (measured 2026-11-04).
- Trashing, putting back, moving or stashing several items, and ⌘Z on a drop of several, write each shelf's manifest once rather than once per item: every write is another upload to each Mac.
- A note's title comes from its first filled line, read only that far (it runs on every key; splitting a 300 KB note took 50 ms). Reloading Notes reads its manifest once, for the pins and for the pins whose notes have gone.

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
