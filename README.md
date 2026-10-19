# Seashell

A shelf for your Mac that slides down from under the menu bar. Drop files, folders, text, links and pictures on it, keep notes beside them, and drag them back out whenever you need them.

Everything lives as ordinary files in `~/Documents/Seashell`, so iCloud syncs it to your other Macs and Finder can always see it.

## Download

Seashell needs macOS 27 or later on a Mac with Apple silicon.

1. Download `Seashell-<version>.zip` from the [latest release](https://github.com/codexjdub/Seashell/releases/latest) and open it.
2. Move Seashell to your Applications folder.
3. Open it. The first time, macOS says **“Seashell.app” Not Opened**, because Seashell isn't notarized by Apple. Click **Done**, not Move to Trash.
4. Open System Settings ▸ Privacy & Security, scroll down to Security, click **Open Anyway** next to the message about Seashell, and confirm.

After that it opens normally. Its icon appears in the menu bar, and a welcome window shows how to reach it.

## What it does

- **Shelves.** Stash things on Main, or make as many shelves as you like. Drag tabs to reorder them.
- **Files move in, copies come out.** A file dropped on a shelf moves there, as it would in Finder, and **Put Back** returns it to where it came from. Dragging an item out drops a copy and leaves it on the shelf.
- **Text, links and pictures become files.** Text is saved as a `.txt` named by its first few words, a link as a `.webloc`, and picture data as a `.png`. Text and links drag back out as their words or address, so they drop straight into text fields and browsers.
- **Notes.** Plain-text notes next to your shelves, each saved as a Markdown file. The first line is the title.
- **Grab shelf.** Hold ⌥ and shake the pointer to see your 8 newest items, ready to drag out.
- **Tear-off shelves.** Drag a shelf's tab out of the panel to keep that shelf in its own small floating window.

## Opening it

- **Pull down at the top edge.** With the pointer at the very top of the screen, scroll down: two fingers on a trackpad, or the mouse wheel. Push up to close.
- **Keyboard shortcut.** ⌃⌥S from any app. Settings offers ⌃⌥⌘S and ⌃⌥Z too, or Off.
- **Menu bar icon.** Click it and choose Open Seashell.
- **Hold a drag at the top edge** for half a second while dragging something.

It closes on a click elsewhere, Esc, pushing up, or the same shortcut. The pin keeps it open.

## Getting things in

- **Drag onto the panel**, or onto a shelf's tab.
- **Shake while dragging.** A small shelf pops up by the pointer with a drop zone for each shelf.
- **Drop onto the menu bar icon.** It goes into Main.
- **Paste.** ⌘V in the panel stashes what's on the clipboard. Files are copied in and the originals stay.
- **Screenshots.** Press ⇧⌘5. In the toolbar near the bottom of the screen, click Options, choose Other Location… and pick Documents ▸ Seashell ▸ Stash ▸ Main.

Anything over 1 GB asks first, since everything in Stash uploads to iCloud. Change the limit in Settings.

## Working with items

| | |
|---|---|
| Preview | Space (arrow keys move through items) |
| Open | Double-click, or ⌘O |
| Copy to the clipboard | ⌘C |
| Move to the Trash | ⌘⌫ |
| Move to another shelf | Drag it onto that shelf's tab |
| More | Right-click: Open, Quick Look, Show in Finder, Copy, Paste, Rename…, Put Back, Move to Trash |

Seashell never deletes anything permanently: removed items go to the Trash.

## Where your things live

```
~/Documents/Seashell/
├── Stash/
│   ├── Main/          ← one folder per shelf
│   └── Work/
└── Notes/             ← one Markdown file per note
```

They're plain files and folders. Changes you make in Finder, or on another Mac, show up in Seashell as they happen. Syncing between Macs needs iCloud Drive's **Desktop & Documents Folders** turned on.

## Settings

Open Settings from the menu bar icon, with ⌘, in the panel, or by clicking the Seashell icon on the panel's edge.

- Theme: System, Light or Dark
- Text size, also ⌘+ / ⌘− / ⌘0 in the panel
- Open Seashell when you log in
- Ask before stashing: over 500 MB, 1 GB, 5 GB, or never
- Shake sensitivity: Off, Gentle, Normal or Firm
- Apps where shakes are ignored, such as drawing apps and games
- Keyboard shortcut
- Pull down at the top edge to open the panel

To see the welcome tips again, click the menu bar icon and choose Tips….

## Privacy and resources

- No accounts, analytics or tracking. Seashell goes online only to fetch a picture you dragged from a web page, when the browser didn't hand over the file itself.
- It needs no Accessibility or Input Monitoring permission.
- It stays out of the way: no CPU use while idle and about 17 MB of memory at launch. It ignores ordinary pointer movement, watching only drags, scrolls (for pulling down) and the pointer while ⌥ is held.

## Building from source

You need Xcode, or just the Command Line Tools, with the macOS 27 SDK. There's no Xcode project: it's a Swift package.

Clone the repository:

```bash
git clone https://github.com/codexjdub/Seashell.git
```

Then build it, install it to `/Applications` and open it:

```bash
cd Seashell && scripts/run.sh
```

It signs the app ad hoc, which works but can make macOS treat each rebuild as a new app when it comes to permissions. To keep one identity across rebuilds, make a certificate of your own: open Keychain Access (search for it in Spotlight), choose Keychain Access ▸ Certificate Assistant ▸ Create a Certificate, and set the type to Code Signing. Then build with its name:

```bash
SIGN_IDENTITY="Your Certificate" scripts/run.sh
```

Other scripts:

```bash
scripts/test.sh
```

```bash
scripts/make-icon.sh
```

```bash
scripts/release.sh
```

`test.sh` runs the unit tests, `make-icon.sh` rebuilds the app icon from `Resources/AppIcon.svg`, and `release.sh` builds the zip for a GitHub release (it needs a signing certificate, not ad hoc). The version is set in `scripts/bundle.sh`. Build output goes to `~/Library/Caches/Seashell`, outside iCloud. Seashell writes a readable log to `~/Library/Logs/Seashell/Seashell.log`, trimmed at launch once it passes 1 MB.

## Uninstalling

1. In Settings, turn off Open Seashell when you log in.
2. Quit Seashell from its menu bar icon.
3. Delete `/Applications/Seashell.app`.

Your shelves and notes stay in `~/Documents/Seashell`. To clear Seashell's preferences as well:

```bash
defaults delete io.github.codexjdub.seashell
```

## Acknowledgements

Inspired by Unclutter, Dropover, Yoink and OpenYoink. The icon borrows Zephyr's breath from Botticelli's *The Birth of Venus*.

## License

MIT. See [LICENSE](LICENSE).
