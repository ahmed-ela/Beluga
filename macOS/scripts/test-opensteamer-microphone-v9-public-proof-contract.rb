#!/usr/bin/env ruby
require 'minitest/autorun'
require_relative 'opensteamer-microphone-v9-public-proof'

FIXTURE_ROOT = File.realpath(ARGV.shift || raise('supply the actual offline native build directory'))

class PublicProofContractTest < Minitest::Test
  Proof = OpensteamerMicrophoneV9PublicProof
  NONCE = 'a' * 64
  ROUTES = Digest::SHA256.hexdigest([Proof::VISIBLE, 'BuiltInSpeakerDevice', 'BuiltInSpeakerDevice'].join("\0"))

  def setup
    orders = Proof::ORDERS.each_with_index.map do |order, index|
      # This is explicitly an offline parser fixture, not a live receipt.
      waveform = JSON.parse(File.binread(File.join(FIXTURE_ROOT, order + '.json')))
      waveform['mode'] = 'real-dual-audioqueue'; waveform['realQueuePathImplemented'] = true
      active_seed = 8 + index * 3
      epochs = Proof::PHASES.each_with_index.flat_map do |phase, phase_index|
        [Proof::VISIBLE, Proof::HIDDEN].each_with_index.map do |uid, endpoint|
          idle = [0, 4].include?(phase_index)
          { 'phase' => phase, 'deviceUID' => uid, 'deviceID' => endpoint == 0 ? 101 : 202,
            'schema' => 2, 'instance' => 42, 'sequence' => 10 + index * 20 + phase_index * 2 + endpoint,
            'capturedHostTicks' => 100 + index * 20 + phase_index * 2 + endpoint,
            'driverLifecycle' => 3 + index * 20 + phase_index,
            'coreLifecycle' => 10 + index * 20 + phase_index * 2,
            'timelineSeed' => idle ? 0 : active_seed, 'seedGeneration' => idle ? 0 : active_seed,
            'anchorHostTicks' => idle ? 0 : 1000 + index, 'lastIssuedSeed' => phase_index == 0 ? active_seed - 1 : active_seed,
            'lastIssuedSessionID' => index * 3 + (phase_index < 2 ? 11 : 12), 'idle' => idle,
            'active' => idle ? 0 : phase_index == 1 ? 1 : 2,
            'activeCore' => idle ? 0 : phase_index == 1 ? 1 : 2,
            'started' => idle ? 0 : phase_index == 1 ? 1 : 2,
            'visible' => idle ? 0 : phase_index == 1 && order == 'hidden-first' ? 0 : 1,
            'visibleStarted' => idle ? 0 : phase_index == 1 && order == 'hidden-first' ? 0 : 1,
            'hidden' => idle ? 0 : phase_index == 1 && order == 'visible-first' ? 0 : 1,
            'hiddenStarted' => idle ? 0 : phase_index == 1 && order == 'visible-first' ? 0 : 1 }
        end
      end
      { 'order' => order, 'nonce' => NONCE + ':' + order, 'waveform' => waveform, 'epochs' => epochs }
    end
    @record = { 'schema' => 'beluga.microphone.public-both-order.v1', 'nonce' => NONCE, 'expectedInstance' => 42,
                'effectiveUID' => 501, 'status' => 'passed', 'failureCode' => '', 'orders' => orders }
  end

  def verify(record = @record)
    Proof.verify!(record, nonce: NONCE, instance: 42, routes_fingerprint: ROUTES)
  end

  def test_complete_offline_fixture_and_independent_native_challenge_hashes
    assert verify
    @record['orders'].each do |order|
      assert_equal order['waveform']['challenge']['expectedPCMHash'], Proof.challenge_hash(order['nonce'])
    end
  end

  def test_binding_mutants
    %w[schema nonce expectedInstance effectiveUID status failureCode].each do |field|
      mutant = Marshal.load(Marshal.dump(@record)); mutant[field] = 'wrong'
      assert_raises(Proof::Refused) { verify(mutant) }
    end
    mutant = @record.merge('unreviewed' => true)
    assert_raises(Proof::Refused) { verify(mutant) }
    %w[expectedInstance effectiveUID].each do |field|
      mutant = Marshal.load(Marshal.dump(@record)); mutant[field] = mutant[field].to_f
      assert_raises(Proof::Refused) { verify(mutant) }
    end
  end

  def test_actual_first_role_and_unowned_active_consumer_mutants
    %w[active activeCore started visible visibleStarted hidden hiddenStarted schema deviceID].each do |field|
      changed = Marshal.load(Marshal.dump(@record))
      changed['orders'][1]['epochs'][2][field] = changed['orders'][1]['epochs'][2][field].to_f
      assert_raises(Proof::Refused) { verify(changed) }
    end
    %w[active activeCore started visible visibleStarted hidden hiddenStarted].each do |field|
      changed = Marshal.load(Marshal.dump(@record))
      [2, 3].each { |sample| changed['orders'][1]['epochs'][sample][field] += 1 }
      assert_raises(Proof::Refused) { verify(changed) }
    end
    changed = Marshal.load(Marshal.dump(@record))
    [2, 3].each do |sample|
      %w[visible visibleStarted].each { |field| changed['orders'][1]['epochs'][sample][field] = 1 }
      %w[hidden hiddenStarted].each { |field| changed['orders'][1]['epochs'][sample][field] = 0 }
    end
    assert_raises(Proof::Refused) { verify(changed) }
    %w[lastIssuedSeed lastIssuedSessionID driverLifecycle coreLifecycle].each do |field|
      changed = Marshal.load(Marshal.dump(@record))
      [0, 1].each { |sample| changed['orders'][1]['epochs'][sample][field] = 0 }
      assert_raises(Proof::Refused) { verify(changed) }
    end
  end

  def test_every_order_requires_a_fresh_real_full_waveform
    mutations = [
      ['order', 'hidden-first'], ['nonce', 'b' * 64],
      ['waveform', 'mode', 'synthetic-self-test'], ['waveform', 'realQueuePathImplemented', false],
      ['waveform', 'challenge', 'nonceFingerprint', 'f' * 64],
      ['waveform', 'challenge', 'expectedPCMHash', 'f' * 64],
      ['waveform', 'challenge', 'capturedAlignedPCMHash', 'f' * 64],
      ['waveform', 'pcm', 'matchedFrameCount', 95_999],
      ['waveform', 'pcm', 'postRollNonzeroSampleCount', 1],
      ['waveform', 'defaults', 'notificationCount', 1],
      ['waveform', 'defaults', 'afterFingerprint', 'f' * 64],
      ['waveform', 'teardown', 'listenersRemoved', false],
      ['waveform', 'queueContract', 'writerQueueVolumeScalar', 0.9],
      ['waveform', 'queueContract', 'captureDevicePhysicalFormat', 'formatFlags', 12],
      ['waveform', 'timestamps', 'projection', 'claimedProjectedLastFrame', 0],
      ['waveform', 'timestamps', 'projection', 'requiredHeadroomFrames', 1],
      ['waveform', 'timestamps', 'nonAdvancingDeviceTimeCount', 1],
      ['waveform', 'endpointPair', 'hidden', 'resolvedUID', Proof::VISIBLE],
      ['waveform', 'endpointPair', 'deviceChangeNotificationCount', 1],
      ['waveform', 'lifecycle', 'seedChangeClaimed', true],
    ]
    mutations.each do |mutation|
      changed = Marshal.load(Marshal.dump(@record))
      path = mutation[0...-2]; field, value = mutation[-2..-1]
      destination = path.inject(changed['orders'][0]) { |node, key| node.fetch(key) }
      destination[field] = value
      assert_raises(Proof::Refused, mutation.inspect) { verify(changed) }
    end
    @record['orders'].pop
    assert_raises(Proof::Refused) { verify }
  end

  def test_epoch_seed_join_drain_and_cross_order_mutants
    [
      [0, 2, 'timelineSeed', 7], [0, 4, 'anchorHostTicks', 999],
      [0, 8, 'idle', false], [0, 8, 'coreLifecycle', 10],
      [0, 3, 'lastIssuedSessionID', 99], [1, 0, 'sequence', 10],
      [1, 1, 'instance', 43], [1, 9, 'schema', 1], [1, 4, 'deviceID', 303],
    ].each do |order, sample, field, value|
      changed = Marshal.load(Marshal.dump(@record)); changed['orders'][order]['epochs'][sample][field] = value
      assert_raises(Proof::Refused) { verify(changed) }
    end
  end

  def test_json_duplicate_and_size_refusals
    assert_raises(Proof::Refused) { Proof.parse('{"nonce":"first","nonce":"second"}') }
    assert_raises(Proof::Refused) { Proof.parse('{"epoch":{"seed":1,"seed":2}}') }
    assert_raises(Proof::Refused) { Proof.parse('x' * 1_048_577) }
    assert_raises(Proof::Refused) { Proof.parse('{"n":NaN}') }
    assert_equal @record, Proof.parse(JSON.generate(@record))
  end

  def test_callback_delivery_residual_remains_telemetry_not_source_clock_verdict
    @record['orders'][0]['waveform']['timestamps']['hostDeltaMismatchCount'] = 2
    assert verify
    @record['orders'][0]['waveform']['timestamps']['hostDeltaMismatchCount'] = 2.0
    assert_raises(Proof::Refused) { verify }
  end
end
