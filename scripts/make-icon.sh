#!/bin/bash
# Rebuild Resources/AppIcon.icns, the panels' seal (Resources/Seal.png) and the
# easter egg's pieces (Resources/EasterEgg) from Resources/AppIcon.svg.
#
# Usage: scripts/make-icon.sh
#
# Renders every size macOS asks for (16 to 1024 px) and packs them with
# iconutil. bundle.sh copies the result into the app.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

xcrun swiftc -O -o "$WORK/svg2png" "$ROOT/scripts/svg2png.swift"
mkdir "$WORK/AppIcon.iconset"
for spec in 16:16x16 32:16x16@2x 32:32x32 64:32x32@2x 128:128x128 256:128x128@2x \
            256:256x256 512:256x256@2x 512:512x512 1024:512x512@2x; do
    "$WORK/svg2png" "$ROOT/Resources/AppIcon.svg" "$WORK/AppIcon.iconset/icon_${spec#*:}.png" "${spec%%:*}"
done
iconutil -c icns "$WORK/AppIcon.iconset" -o "$ROOT/Resources/AppIcon.icns"
echo "$ROOT/Resources/AppIcon.icns"

# The seal on the edge of Seashell's panels: the same drawing without its tile
# (the groups whose id starts with "tile"), framed a fifth closer so the shell
# fills its spot. 256 px covers the largest text size at 2x.
perl -0pe 's/<g id="tile[^"]*">.*?<\/g>//gs; s/viewBox="0 0 1024 1024"/viewBox="43 38.5 853 853"/' \
    "$ROOT/Resources/AppIcon.svg" > "$WORK/Seal.svg"
grep -q 'id="tile' "$WORK/Seal.svg" && { echo "The tile is still in Seal.svg" >&2; exit 1; }
"$WORK/svg2png" "$WORK/Seal.svg" "$ROOT/Resources/Seal.png" 256
echo "$ROOT/Resources/Seal.png"

# The easter egg's pieces (EasterEgg.swift), drawn by the app when it opens: the
# icon without its wind strands, each strand on its own so it can blow in and
# drift off, and the shell's ribs above the hinge, which the ripple of light
# stays inside.
EGG="$ROOT/Resources/EasterEgg"
mkdir -p "$EGG"
perl -0pe 's/<g id="strands">.*?<\/g>//s' "$ROOT/Resources/AppIcon.svg" > "$EGG/icon.svg"
EGG="$EGG" perl -0ne '
    my $head = q{<svg viewBox="0 0 1024 1024" width="1024" height="1024" xmlns="http://www.w3.org/2000/svg">};
    my ($group) = m{<g id="strands">(.*?)</g>}s or die "No strands group in AppIcon.svg\n";
    my @strands = $group =~ m{(<path [^>]*/>)}g;
    @strands == 3 or die "Expected 3 strands in AppIcon.svg\n";
    for my $i (0 .. 2) {
        open my $file, ">", "$ENV{EGG}/strand-" . ($i + 1) . ".svg" or die "$!\n";
        print $file $head . $strands[$i] . "</svg>";
    }
    # The ribs meet at the hinge (y 724); below it are the ears.
    my ($shell) = m{<clipPath id="clip4"><path d="([^"]+)"/>}s or die "No shell outline in AppIcon.svg\n";
    open my $file, ">", "$ENV{EGG}/ribs.svg" or die "$!\n";
    print $file $head . q{<defs><clipPath id="above"><rect width="1024" height="724"/></clipPath></defs>}
        . qq{<path d="$shell" fill="#fff" clip-path="url(#above)"/></svg>};
' "$ROOT/Resources/AppIcon.svg"
echo "$EGG"
