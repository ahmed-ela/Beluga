#!/usr/bin/ruby
# Exercise the production release receipt hook without touching release caches,
# credentials, signing services, installed audio drivers, or physical devices.
require 'digest'
require 'fileutils'
require 'open3'
require 'tmpdir'

root = File.expand_path('..', __dir__)
wrapper = File.join(root, 'iOS/opensteamer/scripts/archive-upload-side-by-side-testflight.sh')
source = File.read(wrapper)
prefix, main = source.split(/^verify_static_contract\n/, 2)
raise 'production wrapper entry boundary is absent' unless main && prefix

def require!(condition, message)
  raise message unless condition
end

# Verify placement as well as behavior. The API-key mode may not read credentials
# before the all-feature gate, and source changes during archive invalidate evidence.
gate = 'verify_microphone_regression_receipt'
require!(main.index(gate) < main.index('verify_package_dependency_contract'), 'release gate is not early')
require!(main.index(gate) < main.index('pin_app_store_connect_api_key_identity'), 'credentials are accessed before the gate')
archive = prefix[/^function archive_side_by_side_app\(\) \{\n(.*?)^\}\n/m, 1]
upload = prefix[/^function run_authorized_upload\(\) \{\n(.*?)^\}\n/m, 1]
require!(archive && upload, 'release functions are absent')
require!(archive.index(gate) < archive.index('reserve_archive_exec_destinations'), 'archive allocation precedes gate')
require!(archive.rindex(gate) > archive.index('run_pinned_xcodebuild archive archive'), 'archive source/evidence is not rechecked')
require!(upload.index(gate) < upload.index('run_pinned_xcodebuild export -exportArchive'), 'export precedes evidence recheck')
%w[--archive-only --upload-authorized-side-by-side-testflight --upload-authorized-side-by-side-testflight-with-api-key].each do |mode|
  require!(main.split('verify_package_dependency_contract', 2).first.include?(mode), "ungated release mode: #{mode}")
end

Dir.mktmpdir('beluga-microphone-release-gate.') do |fixture|
  fixture = File.realpath(fixture)
  File.chmod(0o700, fixture)
  scripts = File.join(fixture, 'scripts')
  shell_scripts = File.join(fixture, 'iOS/opensteamer/scripts')
  FileUtils.mkdir_p([scripts, shell_scripts])
  verifier = File.join(scripts, 'validate-microphone-regressions.sh')
  File.write(verifier, <<~'BASH')
    #!/bin/bash
    set -euo pipefail
    [[ $# == 4 && $1 == --verify-receipt && $3 == --receipt-sha256 ]] || exit 1
    [[ $(/usr/bin/shasum -a 256 < "$2" | /usr/bin/awk '{print $1}') == "$4" ]] || exit 1
    [[ $(< "$2") == fixture-valid ]] || exit 1
    [[ -z ${FIXTURE_REJECT:-} ]] || exit 1
    if [[ -n ${FIXTURE_MUTATE_RECEIPT:-} ]]; then
      printf '%s' fixture-changed > "$2"
    fi
    if [[ -n ${FIXTURE_MUTATE_RUNNER:-} ]]; then
      printf '\n# changed during verification\n' >> "$0"
    fi
  BASH
  File.chmod(0o700, verifier)
  receipt = File.join(fixture, 'receipt with spaces.json')
  File.write(receipt, 'fixture-valid')
  digest = Digest::SHA256.file(receipt).hexdigest
  symlink = File.join(fixture, 'symlink-receipt.json')
  File.symlink(receipt, symlink)
  harness = File.join(shell_scripts, 'hook-test.zsh')
  body = <<~'ZSH'
    trap - EXIT ZERR HUP INT QUIT TERM
    function require_rejection() {
      if verify_microphone_regression_receipt; then
        print -u2 -- 'invalid release receipt was accepted'
        exit 1
      fi
    }
    function reset_pins() {
      TESTFLIGHT_MICROPHONE_RECEIPT_PATH=''
      TESTFLIGHT_MICROPHONE_RECEIPT_IDENTITY=''
      TESTFLIGHT_MICROPHONE_RECEIPT_SHA256=''
      TESTFLIGHT_MICROPHONE_RUNNER_IDENTITY=''
      TESTFLIGHT_MICROPHONE_RUNNER_SHA256=''
    }
    unset BELUGA_MICROPHONE_REGRESSION_RECEIPT BELUGA_MICROPHONE_REGRESSION_RECEIPT_SHA256
    require_rejection
    export BELUGA_MICROPHONE_REGRESSION_RECEIPT="$FIXTURE_RECEIPT"
    require_rejection
    export BELUGA_MICROPHONE_REGRESSION_RECEIPT_SHA256="$FIXTURE_DIGEST"
    verify_microphone_regression_receipt
    verify_microphone_regression_receipt
    export BELUGA_MICROPHONE_REGRESSION_RECEIPT_SHA256="${FIXTURE_DIGEST:u}"
    require_rejection
    export BELUGA_MICROPHONE_REGRESSION_RECEIPT_SHA256="$FIXTURE_DIGEST"
    export BELUGA_MICROPHONE_REGRESSION_RECEIPT="$FIXTURE_SYMLINK"
    require_rejection
    export BELUGA_MICROPHONE_REGRESSION_RECEIPT='receipt with spaces.json'
    require_rejection
    export BELUGA_MICROPHONE_REGRESSION_RECEIPT="$FIXTURE_RECEIPT"
    export FIXTURE_REJECT=1
    require_rejection
    unset FIXTURE_REJECT

    # Replacement with byte-identical evidence must not silently renew a pinned run.
    /bin/mv "$FIXTURE_RECEIPT" "$FIXTURE_RECEIPT.retired"
    /bin/cp "$FIXTURE_RECEIPT.retired" "$FIXTURE_RECEIPT"
    require_rejection
    reset_pins
    verify_microphone_regression_receipt

    # A retained digest cannot authorize changed bytes, even if the file still exists.
    print -rn -- fixture-changed > "$FIXTURE_RECEIPT"
    require_rejection
    /bin/cp "$FIXTURE_RECEIPT.retired" "$FIXTURE_RECEIPT"
    reset_pins
    export FIXTURE_MUTATE_RECEIPT=1
    require_rejection
    unset FIXTURE_MUTATE_RECEIPT
    /bin/cp "$FIXTURE_RECEIPT.retired" "$FIXTURE_RECEIPT"
    reset_pins
    export FIXTURE_MUTATE_RUNNER=1
    require_rejection
    unset FIXTURE_MUTATE_RUNNER
    reset_pins
    verify_microphone_regression_receipt
    /bin/chmod 600 "$MICROPHONE_REGRESSION_RUNNER"
    require_rejection
    print -- 'microphone release gate behavior tests passed'
  ZSH
  File.write(harness, prefix + "\n" + body)
  output, status = Open3.capture2e(
    { 'FIXTURE_RECEIPT' => receipt, 'FIXTURE_DIGEST' => digest, 'FIXTURE_SYMLINK' => symlink },
    '/bin/zsh', harness
  )
  require!(status.success?, "production release hook fixture failed:\n#{output}")
  print output
end
