#!/usr/bin/env bash
#
# Regenerates the SVG fixtures in Tests/SVGPDFKitTests/Resources from the tune
# checked in beside them, so the tests run against real engraved-music SVG
# rather than a hand-written approximation.
#
# Requires abcm2ps (brew install abcm2ps).
#
# abcm2ps stamps the current date into both a comment and the rendered footer,
# so its output is normalised here to a fixed date — otherwise every regeneration
# would produce a diff that is all timestamp and no content.
#
# Two fixtures come out of one render:
#   no-page-number.svg — as engraved, with no page-number placeholder
#   test-tune.svg      — the same document plus the placeholder element that
#                        ABCKit emits and PageNumberInjector rewrites

set -euo pipefail

RESOURCES="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/Tests/SVGPDFKitTests/Resources"
TUNE="hanas_wedding.abc"
FIXED_DATE="1 January 2026 00:00"
FIXED_STAMP="Jan 1, 2026 00:00"

cd "$RESOURCES"

# A relative path keeps absolute home directories out of the fixture's <title>.
abcm2ps -v "$TUNE" -O generated.svg >/dev/null
trap 'rm -f generated001.svg' EXIT

sed -E \
    -e "s|^<!-- CreationDate: .* -->|<!-- CreationDate: ${FIXED_STAMP} -->|" \
    -e "s|(>Generated: ).*(</text>)|\1${FIXED_DATE}\2|" \
    generated001.svg > no-page-number.svg

# The placeholder sits on the footer baseline, centred, the way ABCKit emits it.
awk '
    /^<\/svg>/ && !done {
        print "<g stroke-width=\"0.70\" style=\"font:16.00px serif\">"
        print "<text id=\"svgpdfkit-page-number\" x=\"408.00\" y=\"1002.20\" text-anchor=\"middle\">0</text>"
        print "</g>"
        done = 1
    }
    { print }
' no-page-number.svg > test-tune.svg

echo "Wrote $(wc -c < test-tune.svg | tr -d ' ') bytes to test-tune.svg"
echo "Wrote $(wc -c < no-page-number.svg | tr -d ' ') bytes to no-page-number.svg"
