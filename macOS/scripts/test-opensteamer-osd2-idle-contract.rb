# Pure offline fixtures for the production library. No CoreAudio, child process,
# compiler, signing, host, phone, route, credentials, or deployment is involved.
require 'minitest/autorun'
require_relative 'opensteamer-osd2-idle-contract'

class OpensteamerOSD2IdleContractTests < Minitest::Test
  Contract = OpensteamerOSD2IdleContract

  def blank(schema)
    case schema
    when Hash then schema.map { |key, value| [key, blank(value)] }.to_h
    when Array then []
    when String then schema.dup
    when :boolean then false
    when :hex64 then '0000000000000000'
    else 0
    end
  end

  def idle_fixture(count = 70)
    value = blank(Contract::ROOT)
    value.merge!('readerSchema' => 2, 'snapshotSchemaVersion' => 2,
                 'visibleDeviceID' => 401, 'writerDeviceID' => 809,
                 'endpointReadsCoherent' => true, 'completeRegistryInventory' => true,
                 'allDeclaredInvariantsHold' => true, 'invariantFlags' => '000000000007ff01',
                 'registryRecordCount' => count, 'registryRecordSize' => 88,
                 'totalByteCount' => 3504 + count * 88, 'registryRevision' => 72,
                 'coreSlotCapacity' => 64, 'snapshotSequence' => 1, 'capturedHostTicks' => 100,
                 'driverInstanceGeneration' => 777, 'driverLifecycleSequence' => 73,
                 'coreLifecycleSequence' => 2, 'hostTicksPerSecond' => 1_000_000_000,
                 'driverRegisteredCount' => count,
                 'visibleDriverRegisteredCount' => (count + 1) / 2,
                 'hiddenDriverRegisteredCount' => count / 2,
                 'driverClientAddAttemptCount' => count + 9, 'driverClientAddCount' => count,
                 'globalStartAttemptCount' => 11, 'globalStartTransitionCount' => 7,
                 'globalStopAttemptCount' => 10, 'globalStopTransitionCount' => 7,
                 'seedCreateCount' => 3, 'seedClearCount' => 3,
                 'lastIssuedSeed' => 5, 'lastIssuedSessionID' => 99,
                 'lastClearedSeed' => 5, 'lastClearedSeedGeneration' => 5,
                 'lastClearedAnchorHostTicks' => 30)
    value['registry'] = count.times.map do |index|
      record = blank(Contract::REGISTRY)
      record.merge('registryIndex' => 64 + index * 3, 'generation' => count + 1000 - index,
                   'registrationHostTicks' => 40, 'startHostTicks' => 77,
                   'lastTransitionHostTicks' => 80, 'flags' => 1,
                   'deviceObjectID' => index.even? ? 2 : 6, 'clientID' => index,
                   'processID' => index.zero? ? Contract::I32_MIN : 0,
                   'endpointRole' => index.even? ? 1 : 2,
                   'coreClientSlot' => Contract::U32_MAX)
    end
    value['coreClientSlots'] = 64.times.map { |index| blank(Contract::CORE).merge('slotIndex' => index) }
    value['coreClientSlots'][63].merge!('clientID' => 999, 'timelineSeed' => 5, 'endpointRole' => 2)
    %w[zeroTimestamp io ioWorkLoop].each do |bank|
      schema = Contract::ROOT.fetch(bank).first
      value[bank] = [1, 2].map { |role| blank(schema).merge('endpointRole' => role) }
    end
    value['zeroTimestamp'][0].merge!('failedReturnCount' => 19, 'epochMappingUnavailableCount' => 8,
                                     'metadataDroppedUpdateCount' => 9, 'lastStatus' => -50)
    value['io'][1].merge!('coreFailureCount' => 11, 'leaseUnavailableCount' => 13,
                         'lastPublishedFrameSeed' => 5, 'lastPublishedSeedGeneration' => 5,
                         'lastPublishedFrameSession' => 99, 'lastStatus' => -50)
    value['ioWorkLoop'].each do |loop|
      loop.merge!('beginCount' => 31, 'endCount' => 31, 'underflowCount' => 4,
                  'metadataDroppedUpdateCount' => 3, 'metadataSequence' => 2, 'flags' => 5)
    end
    value
  end

  def active_fixture
    value = idle_fixture
    record = value['registry'].first
    record.merge!('flags' => 7, 'coreClientSlot' => 0, 'ioStartDepth' => 1,
                  'leaseSessionID' => 77, 'leaseTimelineSeed' => 9, 'startHostTicks' => 80)
    value['coreClientSlots'][0].merge!('sessionID' => 77,
      'clientID' => (record['deviceObjectID'] << 32) | record['clientID'],
      'timelineSeed' => 9, 'endpointRole' => 1)
    value.merge!('activeClientCount' => 1, 'coreActiveSlotCount' => 1,
                 'coreActiveSlotBitmap' => 1, 'visibleInputActiveCount' => 1,
                 'driverStartedCount' => 1, 'visibleDriverStartedCount' => 1,
                 'timelineSeed' => 9, 'currentSeedGeneration' => 9, 'anchorHostTicks' => 50,
                 'lastIssuedSeed' => 9, 'lastIssuedSessionID' => 77,
                 'globalStartTransitionCount' => 8, 'seedCreateCount' => 4,
                 'invariantFlags' => '000000000007ff03')
    value
  end

  def admit(value)
    Contract.admit_json(JSON.generate(value))
  end

  def reject(value, message = nil)
    error = assert_raises(Contract::InvalidObservation) { admit(value) }
    assert_includes error.message, message if message
    error
  end

  def advance(value, index)
    copy = Marshal.load(Marshal.dump(value))
    copy['snapshotSequence'] = index + 1
    copy['capturedHostTicks'] = 100 + index
    copy
  end

  def test_complete_idle_overflow_and_raw_retired_metadata_are_preserved
    snapshot = admit(idle_fixture)
    assert snapshot.quiescent_state?
    assert_equal 70, snapshot.admitted_state['registry'].length
    assert_equal 64, snapshot.admitted_state['coreClientSlots'].length
    assert_equal 5, snapshot.admitted_state['coreClientSlots'][63]['timelineSeed']
    assert_equal Contract::I32_MIN, snapshot.admitted_state['registry'].first['processID']
    assert_equal 77, snapshot.admitted_state['registry'].first['startHostTicks']
    assert_equal snapshot.admitted_state, JSON.parse(snapshot.canonical_json)
    assert snapshot.admitted_state.frozen?
    assert snapshot.admitted_state['registry'].last.frozen?
    assert_raises(FrozenError) { snapshot.admitted_state['registry'].last['generation'] = 0 }
  end

  def test_all_sixty_four_retired_slots_and_zero_registrations_are_valid
    snapshot = admit(idle_fixture(0))
    assert snapshot.quiescent_state?
    assert_empty snapshot.admitted_state['registry']
    assert_equal 64, snapshot.admitted_state['coreClientSlots'].length
  end

  def test_active_complete_state_is_admitted_but_never_quiescent
    snapshot = admit(active_fixture)
    refute snapshot.quiescent_state?
    assert snapshot.derived_invariants.values.all?
    assert_equal 77, snapshot.admitted_state['registry'].first['leaseSessionID']
    fence = Contract::SequenceFence.new
    assert_raises(Contract::InvalidObservation) { fence.accept(snapshot, before_ticks: 99, after_ticks: 101) }
    refute fence.complete?
  end

  def test_coherent_failed_invariants_are_raw_evidence_not_false_idle
    value = idle_fixture
    value['activeClientCount'] = 1
    flags = 0x7ff01 & ~(1 << 8) & ~(1 << 12)
    value['invariantFlags'] = '%016x' % flags
    value['allDeclaredInvariantsHold'] = false
    snapshot = admit(value)
    refute snapshot.quiescent_state?
    refute snapshot.derived_invariants[8]
    refute snapshot.derived_invariants[12]
  end

  def test_one_field_false_green_scalar_and_geometry_mutants
    mutants = {
      'readerSchema' => 1, 'snapshotSchemaVersion' => 1, 'registryRecordSize' => 80,
      'coreSlotCapacity' => 65, 'totalByteCount' => Contract::MAX_WIRE_BYTES + 1,
      'registryRecordCount' => 69, 'driverRegisteredCount' => 69,
      'visibleDeviceID' => 0, 'writerDeviceID' => 401,
      'snapshotSequence' => 0, 'capturedHostTicks' => 0,
      'driverInstanceGeneration' => 0, 'hostTicksPerSecond' => 0,
      'coreLifecycleSequence' => 3, 'activeClientCount' => 1,
      'anchorHostTicks' => 1, 'timelineSeed' => 1, 'currentSeedGeneration' => 1,
      'coreActiveSlotBitmap' => 1, 'globalStopTransitionCount' => 6,
      'seedClearCount' => 2, 'endpointReadsCoherent' => false,
      'completeRegistryInventory' => false, 'allDeclaredInvariantsHold' => false,
      'invariantFlags' => '00000000000fff01', 'mode' => 'self-test-v2-fixture',
      'capacityInvariantScope' => 'registrations-limited-to-64'
    }
    mutants.each do |key, bad|
      value = idle_fixture; value[key] = bad
      reject(value)
    end
  end

  def test_exact_field_sets_and_integer_types_widths_are_required
    value = idle_fixture; value.delete('lastIssuedSessionID'); reject(value, 'field set')
    value = idle_fixture; value['madeUpGreenFlag'] = true; reject(value, 'field set')
    ['70', 70.0, nil, true, -1, Contract::U64_MAX + 1].each do |bad|
      value = idle_fixture; value['driverRegisteredCount'] = bad; reject(value, 'scalar')
    end
    [Contract::I32_MIN - 1, Contract::I32_MAX + 1].each do |bad|
      value = idle_fixture; value['registry'].first['processID'] = bad; reject(value, 'scalar')
    end
    value = idle_fixture; value['registry'].first['clientID'] = Contract::U32_MAX + 1; reject(value, 'scalar')
    [1, 0, 'true', nil].each do |bad|
      value = idle_fixture; value['endpointReadsCoherent'] = bad; reject(value, 'scalar')
    end
    ['000000000007FF01', '000000000007ff0', '000000000007gg01'].each do |bad|
      value = idle_fixture; value['invariantFlags'] = bad; reject(value, 'scalar')
    end
  end

  def test_complete_arrays_cannot_be_truncated_reordered_or_projected
    value = idle_fixture; value['registry'].pop; reject(value, 'complete array')
    value = idle_fixture; value['coreClientSlots'].pop; reject(value, 'complete array')
    value = idle_fixture; value['io'].pop; reject(value, 'metadata bank')
    value = idle_fixture; value['zeroTimestamp'].reverse!; reject(value, 'metadata bank')
    value = idle_fixture; value['coreClientSlots'].reverse!; reject(value, 'core inventory')
    value = idle_fixture; value['registry'][0], value['registry'][1] = value['registry'][1], value['registry'][0]; reject(value, 'registry identity')
  end

  def test_duplicate_and_malformed_registry_identity_mutants
    mutants = {
      'registryIndex' => Contract::U64_MAX, 'generation' => 0,
      'registrationHostTicks' => 0, 'lastTransitionHostTicks' => 0,
      'deviceObjectID' => 999, 'endpointRole' => 2, 'flags' => 0,
      'leaseSessionID' => 1, 'leaseTimelineSeed' => 1, 'coreClientSlot' => 0,
      'ioStartDepth' => 1
    }
    mutants.each { |key, bad| value = idle_fixture; value['registry'].first[key] = bad; reject(value) }
    value = idle_fixture; value['registry'][1]['registryIndex'] = value['registry'][0]['registryIndex']; reject(value, 'duplicate')
    value = idle_fixture; value['registry'][1]['generation'] = value['registry'][0]['generation']; reject(value, 'duplicate')
    value = idle_fixture; value['registry'][2]['clientID'] = value['registry'][0]['clientID']; reject(value, 'duplicate')
  end

  def test_started_lease_wrong_epoch_core_reference_and_ring_mapping_fail
    mutants = { 'leaseSessionID' => 99, 'leaseTimelineSeed' => 5,
                'coreClientSlot' => 63, 'ioStartDepth' => 2, 'startHostTicks' => 0 }
    mutants.each { |key, bad| value = active_fixture; value['registry'].first[key] = bad; reject(value) }
    value = active_fixture; value['coreClientSlots'].first['clientID'] += 1; reject(value, 'derived')
    value = active_fixture; value['coreClientSlots'].first['timelineSeed'] = 5; reject(value, 'derived')
    value = active_fixture; value['io'][1]['lastPublishedFrameSeed'] = 9; reject(value, 'derived')
    value = active_fixture; value['io'][0]['lastConsumedSeedGeneration'] = 9; reject(value, 'derived')
  end

  def test_work_loop_truth_is_independent_of_all_declared_invariants
    %w[currentCount beginCount endCount].each do |key|
      value = idle_fixture; value['ioWorkLoop'].first[key] += 1
      snapshot = admit(value)
      refute snapshot.quiescent_state?
      assert_equal true, snapshot.admitted_state['allDeclaredInvariantsHold']
    end
    value = idle_fixture; value['lastClearedSeedGeneration'] += 1
    refute admit(value).quiescent_state?
  end

  def test_idle_lifecycle_ledgers_reject_contradictions_but_keep_failed_attempts
    value = idle_fixture
    value['driverClientAddCount'] += 4
    value['driverClientRemoveCount'] = 4
    value['driverClientRemoveAttemptCount'] = 9
    assert admit(value).quiescent_state?
    mutants = {
      'driverClientAddAttemptCount' => 69,
      'driverClientRemoveAttemptCount' => 3,
      'globalStartAttemptCount' => 6,
      'globalStopAttemptCount' => 6,
      'driverClientAddCount' => 73,
      'driverClientRemoveCount' => 75,
      'lastIssuedSeed' => 4
    }
    mutants.each do |key, bad|
      mutation = Marshal.load(Marshal.dump(value)); mutation[key] = bad
      snapshot = admit(mutation)
      assert_equal true, snapshot.admitted_state['allDeclaredInvariantsHold']
      refute snapshot.quiescent_state?, key
    end
    pristine = idle_fixture(0)
    %w[globalStartTransitionCount globalStopTransitionCount seedCreateCount seedClearCount lastIssuedSeed lastIssuedSessionID lastClearedSeed lastClearedSeedGeneration lastClearedAnchorHostTicks].each { |key| pristine[key] = 0 }
    assert admit(pristine).quiescent_state?
    pristine['lastClearedSeed'] = 1; pristine['lastClearedSeedGeneration'] = 1
    refute admit(pristine).quiescent_state?
  end

  def test_rt_metadata_geometry_rejects_unknown_bits_and_odd_sequences
    %w[zeroTimestamp io ioWorkLoop].each do |bank|
      value = idle_fixture; value[bank].first['metadataSequence'] = 1; reject(value, 'RT metadata')
      value = idle_fixture; value[bank].first['flags'] = bank == 'ioWorkLoop' ? 2 : 32; reject(value, 'RT metadata')
    end
    value = idle_fixture; value['lastCoreTransition']['type'] = 1; reject(value, 'transition')
    value = idle_fixture; value['lastDriverTransition']['slotIndex'] = 64; reject(value, 'transition')
    value = idle_fixture; value['coreClientSlots'].last['endpointRole'] = 3; reject(value, 'core inventory')
  end

  def test_harmless_lifetime_failure_record_and_exact_status_mapping
    value = idle_fixture
    failure = value['lastAdmissionFailure']
    failure.merge!('sequence' => 17, 'hostTicks' => 81, 'registryIndex' => Contract::U64_MAX,
                   'operation' => 1, 'reason' => 3, 'deviceObjectID' => 6,
                   'status' => Contract::UNSPECIFIED_ERROR)
    assert admit(value).quiescent_state?
    %w[sequence hostTicks registryIndex operation reason deviceObjectID status coreStatus].each do |key|
      mutation = Marshal.load(Marshal.dump(value))
      mutation['lastAdmissionFailure'][key] = case key
                                            when 'sequence' then 0
                                            when 'registryIndex' then 12345
                                            when 'status' then Contract::ILLEGAL_OPERATION
                                            when 'coreStatus' then 1
                                            else 0
                                            end
      reject(mutation, 'failure')
    end
    value['lastAdmissionFailure'].merge!('registryIndex' => 1_000_000,
      'driverClientGeneration' => 888, 'operation' => 3, 'reason' => 9,
      'coreStatus' => 11, 'status' => Contract::UNSPECIFIED_ERROR)
    assert admit(value).quiescent_state?
    value['lastAdmissionFailure']['status'] = Contract::ILLEGAL_OPERATION
    reject(value, 'status mapping')
  end

  def test_duplicate_keys_at_every_depth_and_escaped_duplicates_fail
    text = JSON.generate(idle_fixture)
    top = text.sub('{"readerSchema":2,', '{"readerSchema":2,"reader\\u0053chema":2,')
    assert_raises(Contract::InvalidObservation) { Contract.admit_json(top) }
    nested = text.sub('"generation":1070', '"generation":1070,"generation":1070')
    assert_raises(Contract::InvalidObservation) { Contract.admit_json(nested) }
    core = text.sub('"slotIndex":0,"sessionID":0', '"slotIndex":0,"slotIndex":0,"sessionID":0')
    assert_raises(Contract::InvalidObservation) { Contract.admit_json(core) }
  end

  def test_malformed_sensitive_bytes_are_never_echoed
    secret_like = 'secret-like-fixture-4f4f-never-echo'
    error = assert_raises(Contract::InvalidObservation) { Contract.admit_json('{"token":"' + secret_like + '",') }
    refute_includes error.message, secret_like
    refute_includes error.full_message, secret_like
    assert_nil error.cause
    assert_includes error.message, 'redacted'
    value = idle_fixture; value['driverRegisteredCount'] = secret_like
    refute_includes reject(value).message, secret_like
    ['', 'null', 'true', '[]', JSON.generate(idle_fixture) + JSON.generate(idle_fixture)].each do |text|
      assert_raises(Contract::InvalidObservation) { Contract.admit_json(text) }
    end
    [nil, 42, true].each do |nonstring|
      assert_raises(Contract::InvalidObservation) { Contract.admit_json(nonstring) }
    end
    error = assert_raises(Contract::InvalidObservation) { Contract.admit_json(JSON.generate(idle_fixture) + "\xff".b) }
    assert_includes error.message, 'encoding'
  end

  def test_full_wire_geometry_with_uint64_indices_and_derived_json_bounds
    assert_equal 11_875, Contract::MAX_REGISTRY_RECORDS
    value = idle_fixture(Contract::MAX_REGISTRY_RECORDS)
    value['registry'].each_with_index do |record, index|
      record.merge!('registryIndex' => Contract::U64_MAX - Contract::MAX_REGISTRY_RECORDS + index - 1,
                    'generation' => Contract::U64_MAX - index,
                    'registrationHostTicks' => Contract::U64_MAX,
                    'startHostTicks' => Contract::U64_MAX, 'lastTransitionHostTicks' => Contract::U64_MAX,
                    'clientID' => Contract::U32_MAX - index, 'processID' => Contract::I32_MIN)
    end
    text = JSON.generate(value)
    assert_operator text.bytesize, :>, 1_048_576
    assert_operator Contract::MAX_JSON_NODES, :>, 16_384
    assert_operator text.bytesize, :<=, Contract::MAX_JSON_BYTES
    snapshot = Contract.admit_json(text + "\n")
    assert snapshot.quiescent_state?
    assert_equal 11_875, snapshot.admitted_state['registry'].length
    assert_equal 1_048_504, snapshot.admitted_state['totalByteCount']
    assert_equal text, snapshot.canonical_json
    assert_equal value['registry'].last, snapshot.admitted_state['registry'].last
  end

  def test_oversized_geometry_bytes_nodes_and_depth_fail_closed
    reject(idle_fixture(Contract::MAX_REGISTRY_RECORDS + 1))
    valid = JSON.generate(idle_fixture)
    padded = valid + ' ' * (Contract::MAX_JSON_INPUT_BYTES + 1 - valid.bytesize)
    error = assert_raises(Contract::InvalidObservation) { Contract.admit_json(padded) }
    assert_includes error.message, 'byte bound'
    too_many_nodes = '[' + ('0,' * Contract::MAX_JSON_NODES) + '0]'
    assert_operator too_many_nodes.bytesize, :<, Contract::MAX_JSON_INPUT_BYTES
    error = assert_raises(Contract::InvalidObservation) { Contract.admit_json(too_many_nodes) }
    assert_includes error.message, 'node budget'
    error = assert_raises(Contract::InvalidObservation) { Contract.admit_json('[' * 6 + '0' + ']' * 6) }
    assert_includes error.message, 'redacted'
  end

  def test_four_fresh_stable_samples_allow_only_rt_history_to_advance
    value = idle_fixture; identity = admit(value).identity
    fence = Contract::SequenceFence.new(expected_identity: identity)
    4.times do |index|
      sample = advance(value, index)
      sample['io'][1]['operationCallCount'] = index + 100
      sample['zeroTimestamp'][0]['callCount'] = index + 50
      sample['ioWorkLoop'].each { |loop| loop['beginCount'] += index; loop['endCount'] += index }
      fence.accept_json(JSON.generate(sample), before_ticks: 99 + index, after_ticks: 101 + index)
    end
    assert fence.complete?
    assert_equal 4, fence.finish!.length
    assert_equal 103, fence.samples.last.admitted_state['io'][1]['operationCallCount']
  end

  def test_replay_stale_window_and_missing_samples_cannot_prove_idle
    value = idle_fixture
    fence = Contract::SequenceFence.new
    fence.accept_json(JSON.generate(value), before_ticks: 99, after_ticks: 101)
    assert_raises(Contract::InvalidObservation) { fence.finish! }
    assert_raises(Contract::InvalidObservation) { fence.accept_json(JSON.generate(value), before_ticks: 99, after_ticks: 101) }
    refute fence.complete?
    later = advance(value, 1)
    assert_raises(Contract::InvalidObservation) { fence.accept_json(JSON.generate(later), before_ticks: 100, after_ticks: 102) }
    [[101, 102], [98, 99], [101, 99], [-1, 101], [99, 101.0]].each do |before, after|
      new_fence = Contract::SequenceFence.new
      assert_raises(Contract::InvalidObservation) { new_fence.accept_json(JSON.generate(value), before_ticks: before, after_ticks: after) }
    end
  end

  def test_one_field_instance_epoch_registry_core_and_failure_fences
    base = idle_fixture
    mutations = [
      ->(value) { value['driverInstanceGeneration'] += 1 },
      ->(value) { value['writerDeviceID'] += 1 },
      ->(value) { value['driverLifecycleSequence'] += 1 },
      ->(value) { value['coreLifecycleSequence'] += 2 },
      ->(value) { value['registryRevision'] += 1 },
      ->(value) { value['lastIssuedSessionID'] += 1 },
      ->(value) { value['registry'].last['processID'] = 99 },
      ->(value) { value['coreClientSlots'].last['clientID'] += 1 },
      ->(value) { value['driverClientAddAttemptCount'] += 1 }
    ]
    mutations.each do |mutate|
      fence = Contract::SequenceFence.new
      fence.accept_json(JSON.generate(base), before_ticks: 99, after_ticks: 101)
      changed = advance(base, 1); mutate.call(changed)
      assert_raises(Contract::InvalidObservation) { fence.accept_json(JSON.generate(changed), before_ticks: 100, after_ticks: 102) }
      refute fence.complete?
    end
    identity = admit(base).identity.dup; identity['visibleDeviceID'] += 1
    assert_raises(Contract::InvalidObservation) { Contract::SequenceFence.new(expected_identity: identity).accept_json(JSON.generate(base), before_ticks: 99, after_ticks: 101) }
  end

  def test_valid_failure_evidence_cannot_change_across_idle_fence
    base = idle_fixture
    base['lastAdmissionFailure'].merge!('sequence' => 1, 'hostTicks' => 81,
      'registryIndex' => Contract::U64_MAX, 'operation' => 1, 'reason' => 3,
      'deviceObjectID' => 2, 'status' => Contract::UNSPECIFIED_ERROR)
    assert admit(base).quiescent_state?
    fence = Contract::SequenceFence.new
    fence.accept_json(JSON.generate(base), before_ticks: 99, after_ticks: 101)
    changed = advance(base, 1)
    changed['lastAdmissionFailure']['sequence'] = 2
    assert admit(changed).quiescent_state?
    error = assert_raises(Contract::InvalidObservation) { fence.accept_json(JSON.generate(changed), before_ticks: 100, after_ticks: 102) }
    assert_includes error.message, 'failure evidence changed'
    refute fence.complete?
    assert_raises(Contract::InvalidObservation) { fence.finish! }
  end

  def test_idle_fence_cannot_be_constructed_or_finished_with_weaker_proof
    [2, 3, 4].each do |count|
      assert_raises(ArgumentError) { Contract::SequenceFence.new(required_samples: count) }
    end
    [false, true].each do |require_idle|
      assert_raises(ArgumentError) { Contract::SequenceFence.new(require_quiescence: require_idle) }
    end
    fence = Contract::SequenceFence.new
    3.times do |index|
      fence.accept_json(JSON.generate(advance(idle_fixture, index)), before_ticks: 99 + index, after_ticks: 101 + index)
      assert_raises(Contract::InvalidObservation) { fence.finish! }
      refute fence.complete?
    end
    assert_raises(Contract::InvalidObservation) { fence.accept_json(JSON.generate(advance(active_fixture, 3)), before_ticks: 102, after_ticks: 104) }
    assert_raises(Contract::InvalidObservation) { fence.finish! }
    refute fence.complete?
    snapshot = admit(active_fixture)
    refute snapshot.quiescent_state?
    assert_equal 77, snapshot.admitted_state['registry'].first['leaseSessionID']
  end
end
