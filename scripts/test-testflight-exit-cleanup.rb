#!/usr/bin/env ruby
# Exercise the real release-shell trap/call chain with in-memory stand-ins for every external
# cleanup/build operation. Never attach/detach a disk, read a credential, compile, or upload.
require 'open3'

root = File.expand_path('..', __dir__)
wrapper = File.join(root, 'iOS/opensteamer/scripts/archive-upload-side-by-side-testflight.sh')
definitions, dispatch = File.read(wrapper).split(/^verify_static_contract\n/, 2)
raise 'release entrypoint delimiter changed' unless definitions && dispatch

stand_ins = <<~'ZSH'
  function terminate_processing_query() { print -u2 -r -- TEST_TERMINATE_QUERY }
  function remove_processing_tmp_directory() { print -u2 -r -- TEST_REMOVE_PROCESSING_TMP }
  function cleanup_private_build_volume() {
    print -u2 -r -- "TEST_PRIVATE_CLEANUP:${ZSH_SUBSHELL}"
    if (( ${TEST_SIGNAL_DURING_CLEANUP:-0} == 1 )); then
      /bin/kill -INT $$
      print -u2 -r -- TEST_CLEANUP_SIGNAL_MASKED
    fi
    return ${TEST_CLEANUP_STATUS:-0}
  }
  function failing_stage() { return 65 }
  function nested_stage() { failing_stage; print -u2 -r -- TEST_UNREACHABLE }
ZSH

checks = 0
run = lambda do |name, body, expected_status, expected_output = [], source = definitions|
  output, error, status = Open3.capture3('/bin/zsh', '-f', stdin_data: source + stand_ins + body + "\n")
  raise "#{name}: expected status #{expected_status}, got #{status.exitstatus}: #{output} #{error}" unless status.exitstatus == expected_status
  lines = error.lines.map(&:strip)
  unless lines.count('TEST_PRIVATE_CLEANUP:0') == 1 && lines.grep(/^TEST_PRIVATE_CLEANUP:/).length == 1
    raise "#{name}: cleanup must run once, only in the owner: #{error}"
  end
  raise "#{name}: continued after fatal failure: #{error}" if lines.include?('TEST_UNREACHABLE')
  expected_output.each { |value| raise "#{name}: missing #{value}: #{output} #{error}" unless lines.include?(value) }
  checks += 1
end

run.call('normal completion', 'true', 0)
run.call('explicit failure', 'exit 65', 65)
run.call('nested function return with errexit', 'nested_stage', 65)
run.call('nested builtin failure with errexit', 'function nested_stage() { false; }; nested_stage', 1)
run.call('unhandled command substitution', 'value=$(nested_stage)', 65)
run.call('unhandled subshell', '( nested_stage )', 65)
run.call('unhandled pipeline worker', 'nested_stage | /usr/bin/true', 65)
run.call('nested handled failure', <<~'ZSH', 0, ['TEST_HANDLED:65', 'TEST_OWNER_CONTINUES'])
  function handles_failure() {
    local failure=0
    failing_stage || failure=$?
    print -u2 -r -- "TEST_HANDLED:${failure}"
  }
  handles_failure
  print -u2 -r -- TEST_OWNER_CONTINUES
ZSH
run.call('handled command substitution', <<~'ZSH', 0, ['TEST_HANDLED:65', 'TEST_OWNER_CONTINUES'])
  if value=$(failing_stage); then
    print -u2 -r -- TEST_UNREACHABLE
  else
    print -u2 -r -- "TEST_HANDLED:$?"
  fi
  print -u2 -r -- TEST_OWNER_CONTINUES
ZSH
run.call('handled background child', <<~'ZSH', 0, ['TEST_HANDLED:65', 'TEST_OWNER_CONTINUES'])
  failing_stage &
  child=$!
  if wait ${child}; then
    print -u2 -r -- TEST_UNREACHABLE
  else
    print -u2 -r -- "TEST_HANDLED:$?"
  fi
  print -u2 -r -- TEST_OWNER_CONTINUES
ZSH
run.call('unhandled background wait', <<~'ZSH', 65)
  failing_stage &
  child=$!
  wait ${child}
  print -u2 -r -- TEST_UNREACHABLE
ZSH
run.call('handled background child termination', <<~'ZSH', 0, ['TEST_HANDLED:143', 'TEST_OWNER_CONTINUES'])
  function terminated_child() {
    /bin/kill -TERM ${sysparams[pid]}
    print -u2 -r -- TEST_UNREACHABLE
  }
  terminated_child &
  child=$!
  if wait ${child}; then
    print -u2 -r -- TEST_UNREACHABLE
  else
    print -u2 -r -- "TEST_HANDLED:$?"
  fi
  print -u2 -r -- TEST_OWNER_CONTINUES
ZSH
run.call('handled command substitution termination', <<~'ZSH', 0, ['TEST_HANDLED:143', 'TEST_OWNER_CONTINUES'])
  function terminated_child() {
    /bin/kill -TERM ${sysparams[pid]}
    print -u2 -r -- TEST_UNREACHABLE
  }
  if value=$(terminated_child); then
    print -u2 -r -- TEST_UNREACHABLE
  else
    print -u2 -r -- "TEST_HANDLED:$?"
  fi
  print -u2 -r -- TEST_OWNER_CONTINUES
ZSH
run.call('normal cleanup is idempotent across EXIT', <<~'ZSH', 0)
  cleanup_private_build_volume_signal_masked
  cleanup_private_build_volume_signal_masked
ZSH
run.call('failed cleanup wins over original failure', 'TEST_CLEANUP_STATUS=1; nested_stage', 1)
run.call('cleanup masks repeated termination', 'TEST_SIGNAL_DURING_CLEANUP=1; nested_stage', 65,
         ['TEST_CLEANUP_SIGNAL_MASKED'])
{ 'HUP' => 129, 'INT' => 130, 'QUIT' => 131, 'TERM' => 143 }.each do |signal, status|
  run.call("nested #{signal} exit", "function signal_stage() { /bin/kill -#{signal} $$; }; signal_stage", status)
end

# Traverse the actual API-key-upload -> upload -> archive chain and its caught pipeline status.
# Only effectful boundaries are replaced; the production propagation and traps remain exact.
archive_failure = <<~'ZSH'
  function pin_app_store_connect_api_key_identity() { return 0 }
  function verify_xcodebuild_authentication_contract() { return 0 }
  function create_safe_output_directory() { TESTFLIGHT_OUTPUT_DIRECTORY=/fixture/output }
  function verify_output_directory_identity() { return 0 }
  function reserve_archive_exec_destinations() {
    TESTFLIGHT_ARCHIVE_PATH=/fixture/archive
    exec {TESTFLIGHT_ARCHIVE_LOG_FD}>/dev/null
  }
  function initialize_private_testflight_build_volume() { print -u2 -r -- TEST_INITIALIZE_STUB }
  function print_release_stage_timing() { return 0 }
  function resolve_pinned_package_dependencies() { return 0 }
  function verify_effective_archive_build_roots() { return 0 }
  function run_pinned_xcodebuild() { return 65 }
  run_authorized_api_key_upload
  print -u2 -r -- TEST_UNREACHABLE
ZSH
run.call('actual archive failure call chain', archive_failure, 65, ['TEST_INITIALIZE_STUB'])

# The same synthetic archive failure reproduces the production leak when the new hook is removed.
without_error_hook = definitions.sub(/^trap cleanup_on_exit ZERR\n/, '')
raise 'missing error-hook mutation target' if without_error_hook == definitions
output, error, status = Open3.capture3('/bin/zsh', '-f',
  stdin_data: without_error_hook + stand_ins + archive_failure)
unless status.exitstatus == 65 && !error.include?('TEST_PRIVATE_CLEANUP:') && error.include?('TEST_INITIALIZE_STUB')
  raise "missing-hook mutation did not reproduce skipped cleanup: #{status.exitstatus}: #{output} #{error}"
end
checks += 1

without_owner_guard = definitions.sub(/^  \(\( ZSH_SUBSHELL == 0 \)\) \|\| return \$\{original_status\}\n/, '')
raise 'missing owner-guard mutation target' if without_owner_guard == definitions
output, error, status = Open3.capture3('/bin/zsh', '-f',
  stdin_data: without_owner_guard + stand_ins + "value=$(nested_stage)\n")
unless status.exitstatus == 65 && error.include?('TEST_PRIVATE_CLEANUP:1') && error.include?('TEST_PRIVATE_CLEANUP:0')
  raise "missing-owner-guard mutation did not expose child cleanup: #{status.exitstatus}: #{output} #{error}"
end
checks += 1

puts "TestFlight exit cleanup: #{checks} checks passed (no disk/build/credential operations)"
