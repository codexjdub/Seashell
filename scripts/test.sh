#!/bin/bash
# Run the unit tests. Build output stays in ~/Library/Caches/Seashell, outside iCloud (see bundle.sh).
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)

# With only the Command Line Tools, a package that also has an executable target
# fails to load the Swift Testing macros ("plugin for module 'TestingMacros' not
# found"). Point the compiler at the plugin explicitly.
TESTING_PLUGINS="$(dirname "$(xcrun -f swift)")/../lib/swift/host/plugins/testing"

swift test --package-path "$ROOT" --scratch-path "$HOME/Library/Caches/Seashell/.build-Seashell" \
    -Xswiftc -plugin-path -Xswiftc "$TESTING_PLUGINS" "$@"
