#!/bin/bash
set -euo pipefail

if [[ $# -ne 0 ]]; then
  echo 'usage: test-opensteamer-diagnostic-property-negotiation.sh' >&2
  exit 64
fi
root="$(cd -- "$(dirname -- "$0")/../.." && /bin/pwd -P)"
clang='/Applications/Xcode-26.6.0.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/bin/clang'
sdk='/Applications/Xcode-26.6.0.app/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX.sdk'
probe="$root/macOS/Probes/opensteamer-diagnostic-property-negotiation.c"
test_source="$root/macOS/Probes/opensteamer-diagnostic-property-negotiation-tests.c"
evidence="$(/usr/bin/mktemp -d /private/tmp/opensteamer-property-negotiation.XXXXXX)"
echo "offline evidence: $evidence"
common=(-std=c17 -Wall -Wextra -Werror -pedantic -isysroot "$sdk" -mmacosx-version-min=14.0)

# These production binaries are linked and inspected, never invoked here.
for architecture in arm64 x86_64; do
  "$clang" "${common[@]}" -arch "$architecture" "$probe" \
    -framework CoreAudio -framework CoreFoundation -o "$evidence/probe-$architecture"
  /usr/bin/nm -u "$evidence/probe-$architecture" > "$evidence/imports-$architecture.txt"
  /usr/bin/ruby -e '
    imports = File.read(ARGV.fetch(0)).scan(/\b_(Audio\w+)/).flatten.uniq.sort
    expected = %w[AudioObjectGetPropertyData AudioObjectGetPropertyDataSize AudioObjectHasProperty]
    abort "unexpected Core Audio mutation or I/O dependency" unless imports == expected
  ' "$evidence/imports-$architecture.txt"
done

"$clang" "${common[@]}" -arch arm64 -fsanitize=address,undefined \
  "$test_source" -o "$evidence/pure-tests"
/usr/bin/nm -u "$evidence/pure-tests" > "$evidence/unit-imports.txt"
/usr/bin/ruby -e '
  abort "unit seam retains live HAL dependencies" if File.read(ARGV.fetch(0)).match?(/\b_(?:Audio\w+|CF\w+|mach_absolute_time|mach_timebase_info)\b/)
' "$evidence/unit-imports.txt"
"$evidence/pure-tests" | /usr/bin/tee "$evidence/tests.log"
"$evidence/pure-tests" --fixture-json legacy > "$evidence/legacy.json"
"$evidence/pure-tests" --fixture-json v2 > "$evidence/v2.json"
/usr/bin/ruby -rjson -e '
  expected = %w[schemaVersion scope classification reason pointerSizeBytes maximumDeclarationCount maximumWindowNanoseconds hostTicksBefore hostTicksAfter timebaseNumer timebaseDenom secondPassAttempted passes].sort
  ARGV.each_with_index do |path, index|
    bytes = File.binread(path)
    abort "JSON bound" unless bytes.bytesize.between?(1, 32768) && bytes.end_with?("\n")
    record = JSON.parse(bytes)
    abort "JSON schema" unless record.keys.sort == expected && record["schemaVersion"] == 1 && record["scope"] == "diagnostic-property-negotiation-only"
    abort "JSON classification" unless record["classification"] == %w[legacy-v1 v2-present][index] && record["secondPassAttempted"] == true
    abort "JSON geometry" unless record["pointerSizeBytes"] == 8 && record["maximumDeclarationCount"] == 32 && record["passes"].length == 2
    record["passes"].each do |pass|
      abort "endpoint inventory" unless pass.length == 2 && pass.map { |item| item["deviceID"] }.uniq.length == 2
      pass.each do |item|
        abort "UID evidence" unless item["uidBefore"]["matched"] == true && item["uidAfter"]["matched"] == true && item["uidBefore"]["observedUID"] == item["expectedUID"]
        abort "declaration inventory" unless item["declarations"]["count"] == item["declarations"]["items"].length
        item.values_at("v1", "v2").each do |property|
          abort "typed property evidence" unless [true, false].include?(property["hasProperty"]) && property["sizeStatus"].is_a?(Integer) && property["sizeBytes"].is_a?(Integer)
        end
      end
    end
  end
' "$evidence/legacy.json" "$evidence/v2.json"
