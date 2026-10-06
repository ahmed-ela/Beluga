#!/usr/bin/env ruby
require_relative 'artifact_support'

BelugaCoreArtifact.verify_source!
work = BelugaCoreArtifact.work_directory
mutants = [
  ['visibility-coupled-to-target', 'src/lib.rs', 'policy', 'visible: snapshot.has_started as u32,',
   'visible: (snapshot.has_started && snapshot.target_present) as u32,',
   'stable_visibility_survives_missing_target_and_session_churn'],
  ['unknown-flags-ignored', 'src/lib.rs', 'policy', 'flags & !KNOWN_FLAGS != 0', 'false',
   'every_unknown_bit_fails_closed'],
  ['command-admission-removed', 'src/lib.rs', 'policy', '!self.command_installed', 'false',
   'each_original_enabled_guard_is_required'],
  ['availability-departure-clears-media', 'src/host_lifecycle.rs', 'host_lifecycle',
   '(Self::Paired { active: None, media }, Applied),',
   '(Self::Paired { active: None, media: None }, Applied),',
   'availability_reconnect_does_not_replace_or_clear_old_media_owner'],
  ['stale-media-end-clears-owner', 'src/host_lifecycle.rs', 'host_lifecycle',
   'Some(token)) if media == token =>', 'Some(token)) if true =>',
   'stale_media_end_preserves_current_media_owner']
]
mutants.each do |name, path, suite, original, changed, test|
  production = File.binread(File.join(BelugaCoreArtifact::CRATE, path))
  raise "Mutation anchor not unique: #{name}" unless production.scan(original).size == 1
  Dir.mktmpdir("mutant-#{name}-", work) do |copy|
    %w[Cargo.toml Cargo.lock rust-toolchain.toml src tests].each do |path|
      FileUtils.cp_r(File.join(BelugaCoreArtifact::CRATE, path), File.join(copy, path))
    end
    File.binwrite(File.join(copy, path), production.sub(original, changed))
    env = BelugaCoreArtifact.environment(File.join(copy, 'target'))
    output, error, status = Open3.capture3(env, BelugaCoreArtifact::CARGO, 'test', '--offline', '--locked',
      '--test', suite, test, '--', '--exact', '--test-threads=1', chdir: copy)
    combined = output + error
    puts combined
    raise "Mutant #{name} compiled unsuccessfully; not a behavioral oracle" if combined.include?('could not compile')
    raise "Mutant #{name} survived or lacked an assertion failure" unless status.exitstatus == 101 &&
      combined.include?('assertion `left == right` failed') && combined.include?("#{test} ... FAILED") &&
      combined.include?('1 failed')
    puts "Behavioral mutation rejected: #{name}"
    puts "BELUGA_CORE_MUTANT_REJECTED #{name} assertion-failed"
  end
end
puts 'BelugaCore mutation oracles PASS: 5 assertion-failing mutants'
puts 'BELUGA_CORE_MUTATIONS_PASS cases=5'
