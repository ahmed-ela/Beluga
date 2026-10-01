#!/usr/bin/ruby
# Exercise the actual host-builder receipt boundary without building/signing an
# app, reading credentials, or touching installed audio/device/runtime state.
require 'digest'
require 'fileutils'
require 'open3'
require 'tmpdir'

def require!(condition, message)
  raise message unless condition
end

root = File.expand_path('..', __dir__)
builder = File.join(root, 'macOS/scripts/build-beluga-host-app.sh')
source = File.read(builder)
entry = 'verify_microphone_regression_receipt || fail "current microphone regression receipt is required"'
prefix, main = source.split(/^#{Regexp.escape(entry)}\n/, 2)
require!(prefix && main, 'host builder mandatory entry gate is absent')
require!(!prefix.include?('/bin/mkdir "$APP_OUTPUT_DIR"'), 'host output allocation precedes the gate')
require!(!prefix.include?('/usr/bin/security find-identity'), 'host signing identity is accessed before the gate')
require!(!prefix.include?('/usr/bin/swift build'), 'host build precedes the gate')
require!(source.lines.count { |line| line.start_with?('verify_microphone_regression_receipt || fail ') } == 3,
         'host entry/signing/handoff checks must all be mandatory')
signing_gate = 'verify_microphone_regression_receipt || fail "microphone regression evidence changed before signing"'
handoff_gate = 'verify_microphone_regression_receipt || fail "microphone regression evidence changed before artifact handoff"'
require!(main.index(signing_gate) < main.index('/usr/bin/codesign --force'), 'signing precedes evidence recheck')
require!(main.index(handoff_gate) > main.index('run_bundle_verifier "${VERIFY_ARGUMENTS[@]}"'), 'handoff gate precedes artifact verification')
require!(main.index(handoff_gate) < main.index('print -r -- "$APP_DIR"'), 'artifact is handed off before evidence recheck')

Dir.mktmpdir('beluga-microphone-host-release-gate.') do |fixture|
  fixture = File.realpath(fixture)
  File.chmod(0o700, fixture)
  scripts = File.join(fixture, 'scripts')
  host_scripts = File.join(fixture, 'macOS/scripts')
  FileUtils.mkdir_p([scripts, host_scripts])
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
  actual_builder = File.join(host_scripts, 'build-beluga-host-app.sh')
  File.write(actual_builder, source)

  # Every supported normal/prebuilt/release configuration must refuse missing
  # evidence before output creation or the signing/build path is reached.
  %w[0 1].each do |fresh|
    output_dir = File.join(fixture, "forbidden-output-#{fresh}")
    output, status = Open3.capture2e(
      { 'BELUGA_MICROPHONE_REGRESSION_RECEIPT' => nil,
        'BELUGA_MICROPHONE_REGRESSION_RECEIPT_SHA256' => nil,
        'OPENSTEAMER_HOST_APP_OUTPUT_DIR' => output_dir,
        'OPENSTEAMER_REQUIRE_FRESH_RELEASE' => fresh,
        'OPENSTEAMER_ALLOW_PREBUILT_FOR_TESTS' => '1',
        'OPENSTEAMER_HOST_PREBUILT_BIN_DIR' => File.join(fixture, 'no-prebuilt-products') },
      '/bin/zsh', actual_builder
    )
    require!(!status.success? && output.include?('current microphone regression receipt is required'),
             'host builder did not refuse missing receipt at entry')
    require!(!File.exist?(output_dir), 'host builder allocated output before refusing evidence')
  end

  harness = File.join(host_scripts, 'hook-test.zsh')
  body = <<~'ZSH'
    REJECTION_INDEX=0
    function require_rejection() {
      (( REJECTION_INDEX += 1 ))
      if verify_microphone_regression_receipt; then
        print -u2 -- "invalid host release receipt was accepted at negative case $REJECTION_INDEX"
        exit 1
      fi
    }
    function reset_pins() {
      HOST_MICROPHONE_RECEIPT_PATH=''
      HOST_MICROPHONE_RECEIPT_IDENTITY=''
      HOST_MICROPHONE_RECEIPT_SHA256=''
      HOST_MICROPHONE_RUNNER_IDENTITY=''
      HOST_MICROPHONE_RUNNER_SHA256=''
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

    # Same bytes at a new inode do not renew a builder's pinned receipt.
    /bin/mv "$FIXTURE_RECEIPT" "$FIXTURE_RECEIPT.retired"
    /bin/cp "$FIXTURE_RECEIPT.retired" "$FIXTURE_RECEIPT"
    require_rejection
    reset_pins
    verify_microphone_regression_receipt
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
    /bin/mv "$MICROPHONE_REGRESSION_RUNNER" "$MICROPHONE_REGRESSION_RUNNER.retired"
    /bin/cp "$MICROPHONE_REGRESSION_RUNNER.retired" "$MICROPHONE_REGRESSION_RUNNER"
    require_rejection
    reset_pins
    verify_microphone_regression_receipt
    /bin/chmod 600 "$MICROPHONE_REGRESSION_RUNNER"
    require_rejection
    print -- 'microphone host release gate behavior tests passed'
  ZSH
  File.write(harness, prefix + "\n" + body)
  output, status = Open3.capture2e(
    { 'FIXTURE_RECEIPT' => receipt, 'FIXTURE_DIGEST' => digest, 'FIXTURE_SYMLINK' => symlink },
    '/bin/zsh', harness
  )
  require!(status.success?, "production host release hook fixture failed:\n#{output}")
  print output
end
