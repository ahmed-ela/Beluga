require 'digest'
require 'json'

# Unprivileged independent consumption of the sealed native oracle's result.
# An artifact or this parser alone cannot attest loaded-driver provenance.
module OpensteamerMicrophoneV9PublicProof
  class Refused < StandardError; end
  class UniqueObject < Hash
    def []=(key, value)
      raise Refused, 'duplicate JSON field' if key?(key)
      super
    end
  end
  VISIBLE = 'com.elamin.opensteamer.virtual-microphone.input'.freeze
  HIDDEN = 'com.elamin.opensteamer.virtual-microphone.writer'.freeze
  MODEL = 'com.elamin.opensteamer.virtual-microphone.model'.freeze
  ORDERS = %w[visible-first hidden-first].freeze
  PHASES = %w[before-start first-started both-started proof-complete drained].freeze
  MASK = (1 << 64) - 1

  def self.require!(condition, label)
    raise Refused, label unless condition
  end

  def self.keys!(record, expected)
    require!(record.is_a?(Hash) && record.keys.sort == expected.sort, 'proof fields differ')
  end

  def self.integer!(value, minimum = 0)
    require!(value.is_a?(Integer) && value >= minimum && value <= MASK, 'proof integer differs')
    value
  end

  def self.challenge_hash(nonce)
    seed = 14_695_981_039_346_656_037
    (nonce + ':mirror:mono').bytes.each { |byte| seed = ((seed ^ byte) * 1_099_511_628_211) & MASK }
    seed ^= 0xA5A5D3C47E291B6F
    seed = 0xD1B54A32D192ED03 if seed.zero?
    samples = Array.new(96_000) do |frame|
      if frame < 256
        12_000 + (frame * 257 + 73) % 8_001
      else
        seed = (seed + 0x9E3779B97F4A7C15) & MASK
        value = seed
        value = ((value ^ (value >> 30)) * 0xBF58476D1CE4E5B9) & MASK
        value = ((value ^ (value >> 27)) * 0x94D049BB133111EB) & MASK
        sample = (value ^ (value >> 31)) % 48_001 - 24_000
        sample.zero? ? 1 : sample
      end
    end
    Digest::SHA256.hexdigest(samples.pack('s<*'))
  end

  def self.parse(bytes)
    require!(bytes.is_a?(String) && bytes.bytesize.between?(1, 1_048_576), 'proof byte bound differs')
    JSON.parse(bytes, object_class: UniqueObject, max_nesting: 16, allow_nan: false)
  rescue JSON::ParserError, JSON::NestingError => error
    raise Refused, error.class.name
  end

  def self.verify!(record, nonce:, instance:, routes_fingerprint:)
    require!(nonce.is_a?(String) && nonce.match?(/\A[0-9a-f]{64}\z/) &&
             routes_fingerprint.is_a?(String) && routes_fingerprint.match?(/\A[0-9a-f]{64}\z/), 'proof independent challenge binding differs')
    integer!(instance, 1)
    keys!(record, %w[schema nonce expectedInstance effectiveUID status failureCode orders])
    integer!(record['expectedInstance'], 1); integer!(record['effectiveUID'], 1)
    require!(record['schema'] == 'beluga.microphone.public-both-order.v1' && record['nonce'] == nonce &&
             record['expectedInstance'] == instance && record['effectiveUID'] == 501 &&
             record['status'] == 'passed' && record['failureCode'] == '', 'public proof binding/result differs')
    require!(record['orders'].is_a?(Array) && record['orders'].size == 2, 'both waveform orders required')
    previous = nil
    endpoint_ids = nil
    record['orders'].zip(ORDERS).each do |order, expected_order|
      keys!(order, %w[order nonce waveform epochs])
      order_nonce = nonce + ':' + expected_order
      require!(order['order'] == expected_order && order['nonce'] == order_nonce, 'waveform order/challenge differs')
      waveform = order['waveform']
      keys!(waveform, %w[schema status mode realQueuePathImplemented challenge endpointPair queueContract pcm timestamps defaults lifecycle teardown failureCode failureReasons])
      require!(waveform['schema'] == 'opensteamer.virtual-microphone-mirror-loopback.v2' &&
               waveform['status'] == 'passed' && waveform['mode'] == 'real-dual-audioqueue' &&
               waveform['realQueuePathImplemented'] == true && waveform['failureCode'] == 'none' &&
               waveform['failureReasons'] == [], 'real waveform path/result differs')
      challenge = waveform['challenge']
      keys!(challenge, %w[algorithm version nonceFingerprint frameCount sampleCount sentinelFrameCount expectedPCMHash capturedAlignedPCMHash])
      expected_hash = challenge_hash(order_nonce)
      %w[version frameCount sampleCount sentinelFrameCount].each { |key| integer!(challenge[key]) }
      require!(challenge['algorithm'] == 'nonce-splitmix64-mono-sentinel-prbs' && challenge['version'] == 2 &&
               challenge['nonceFingerprint'] == Digest::SHA256.hexdigest(order_nonce) &&
               challenge['frameCount'] == 96_000 && challenge['sampleCount'] == 96_000 && challenge['sentinelFrameCount'] == 256 &&
               challenge['expectedPCMHash'] == expected_hash && challenge['capturedAlignedPCMHash'] == expected_hash,
               'independent nonce PCM differs')
      pair = waveform.fetch('endpointPair')
      require!(pair['objectIDsDistinct'] == true && pair['modelUIDsMatch'] == true && pair['clockDomainsMatch'] == true &&
               pair['deviceChangeNotificationCount'] == 0, 'endpoint pair differs')
      ids = %w[visible hidden].zip([VISIBLE, HIDDEN]).map do |role, uid|
        endpoint = pair.fetch(role)
        require!(endpoint['expectedUID'] == uid && endpoint['resolvedUID'] == uid && endpoint['translatedByExactUID'] == true &&
                 endpoint['alive'] == true && endpoint['hidden'] == (role == 'hidden') &&
                 endpoint['inputChannels'] == (role == 'visible' ? 1 : 0) && endpoint['outputChannels'] == (role == 'hidden' ? 1 : 0) &&
                 endpoint['nominalSampleRate'] == 48_000 && endpoint['clockDomain'] == 0x6F73564D &&
                 endpoint['modelUIDMatchesExpected'] == true && endpoint['modelUIDFingerprint'] == Digest::SHA256.hexdigest(MODEL), 'endpoint topology differs')
        integer!(endpoint['objectID'], 1)
      end
      require!(ids.uniq.size == 2 && (!endpoint_ids || endpoint_ids == ids), 'endpoint identity changed between orders')
      endpoint_ids = ids
      verify_waveform!(waveform, routes_fingerprint)
      observations = order['epochs']
      require!(observations.is_a?(Array) && observations.size == 10, 'complete epoch samples required')
      prior_order = previous
      observations.each_with_index do |sample, index|
        keys!(sample, %w[phase deviceUID deviceID schema sequence capturedHostTicks instance driverLifecycle coreLifecycle timelineSeed seedGeneration anchorHostTicks lastIssuedSeed lastIssuedSessionID idle active visible hidden activeCore started visibleStarted hiddenStarted])
        require!(sample['phase'] == PHASES[index / 2] && sample['deviceUID'] == [VISIBLE, HIDDEN][index % 2] &&
                 sample['deviceID'] == ids[index % 2] && sample['schema'] == 2 && sample['instance'] == instance,
                 'complete v2 epoch identity differs')
        %w[deviceID schema sequence capturedHostTicks instance driverLifecycle].each { |key| integer!(sample[key], 1) }
        %w[coreLifecycle timelineSeed seedGeneration anchorHostTicks lastIssuedSeed lastIssuedSessionID active visible hidden activeCore started visibleStarted hiddenStarted].each { |key| integer!(sample[key]) }
        require!([true, false].include?(sample['idle']) && sample['coreLifecycle'].even?, 'epoch type/lifecycle differs')
        idle_phase = [0, 4].include?(index / 2)
        first_phase = index / 2 == 1
        active_count = idle_phase ? 0 : first_phase ? 1 : 2
        visible_count = idle_phase ? 0 : first_phase ? (expected_order == 'visible-first' ? 1 : 0) : 1
        hidden_count = idle_phase ? 0 : first_phase ? (expected_order == 'hidden-first' ? 1 : 0) : 1
        require!(%w[active activeCore started].all? { |key| sample[key] == active_count } &&
                 %w[visible visibleStarted].all? { |key| sample[key] == visible_count } &&
                 %w[hidden hiddenStarted].all? { |key| sample[key] == hidden_count }, 'actual first role/active consumers differ')
        if previous
          require!(sample['sequence'] > previous['sequence'] && sample['capturedHostTicks'] > previous['capturedHostTicks'], 'stale epoch samples')
        end
        previous = sample
      end
      observations.each_slice(2) do |left, right|
        ignored = %w[deviceUID deviceID sequence capturedHostTicks]
        require!(left.reject { |key, _| ignored.include?(key) } == right.reject { |key, _| ignored.include?(key) }, 'mirrored epochs differ')
      end
      baseline, active, drained = observations.values_at(0, 2, 8)
      if prior_order
        require!(%w[lastIssuedSeed lastIssuedSessionID driverLifecycle coreLifecycle].all? { |key| baseline[key] >= prior_order[key] },
                 'inter-order history regressed')
      end
      require!(observations.first(2).all? { |sample| idle?(sample) } &&
               active['timelineSeed'] > baseline['lastIssuedSeed'] && active['seedGeneration'] == active['timelineSeed'] && active['anchorHostTicks'] > 0 &&
               observations[2...8].all? { |sample| sample['idle'] == false && %w[timelineSeed seedGeneration anchorHostTicks].all? { |key| sample[key] == active[key] } } &&
               observations.last(2).all? { |sample| idle?(sample) && sample['lastIssuedSeed'] == active['timelineSeed'] &&
                 sample['lastIssuedSessionID'] > baseline['lastIssuedSessionID'] && sample['coreLifecycle'] > baseline['coreLifecycle'] && sample['driverLifecycle'] > baseline['driverLifecycle'] }, 'seed join/drain differs')
    end
    true
  rescue KeyError, TypeError, NoMethodError => error
    raise Refused, 'proof shape differs: ' + error.class.name
  end

  def self.idle?(sample)
    sample['idle'] == true && %w[timelineSeed seedGeneration anchorHostTicks].all? { |key| sample[key] == 0 }
  end

  def self.verify_waveform!(waveform, routes_fingerprint)
    queue = waveform.fetch('queueContract')
    require!(queue['captureQueueUIDReadback'] == VISIBLE && queue['writerQueueUIDReadback'] == HIDDEN &&
             %w[captureQueueUIDMatches writerQueueUIDMatches captureFormatMatches writerFormatMatches captureDeviceFormatMatches writerDeviceFormatMatches signalControlsMatch writerQueueVolumeMatches writerChallengeFullySubmitted].all? { |key| queue[key] == true } &&
             queue['visibleInputMuted'] == false && queue['hiddenOutputMuted'] == false &&
             %w[visibleInputVolumeScalar hiddenOutputVolumeScalar writerQueueVolumeScalar].all? { |key| queue[key] == 1.0 } &&
             queue['writerSubmittedChallengeFrameCount'] == 96_000 && integer!(queue['writerCallbackCount'], 1) > 0, 'queue contract differs')
    %w[requestedFormat captureReadbackFormat writerReadbackFormat captureDeviceVirtualFormat captureDevicePhysicalFormat writerDeviceVirtualFormat writerDevicePhysicalFormat].each do |key|
      format = queue.fetch(key)
      float = key.include?('Device')
      require!(format['sampleRate'] == 48_000 && format['formatID'] == 'lpcm' && format['formatFlags'] == (float ? 9 : 12) &&
               format['floatingPoint'] == float && format['signedInteger'] == !float && format['packed'] == true &&
               format['nativeEndian'] == true && format['interleaved'] == true && format['channelsPerFrame'] == 1 &&
               format['bitsPerChannel'] == (float ? 32 : 16) && format['bytesPerPacket'] == (float ? 4 : 2) &&
               format['bytesPerFrame'] == (float ? 4 : 2) && format['framesPerPacket'] == 1 && format['reserved'] == 0, 'actual/native format differs')
    end
    pcm = waveform.fetch('pcm')
    require!(%w[comparisonAvailable exactPCMMatches signedInt16Compatible postRollSilenceMatches].all? { |key| pcm[key] == true } && pcm['capturedOverflow'] == false &&
             pcm['alignmentCount'] == 1 && integer!(pcm['alignedStartFrame']) <= 48_000 &&
             pcm['comparedFrameCount'] == 96_000 && pcm['matchedFrameCount'] == 96_000 &&
             %w[mismatchSampleCount missingFrameCount postRollNonzeroSampleCount postRollAbsolutePeak unexpectedTrailingFrameCount].all? { |key| pcm[key] == 0 } &&
             pcm['requiredPostRollFrameCount'] == 1920 && pcm['capturedPostRollFrameCount'] == 1920, 'exact waveform/drain differs')
    defaults = waveform.fetch('defaults')
    require!(defaults['beforeFingerprint'] == routes_fingerprint && defaults['afterFingerprint'] == routes_fingerprint && defaults['notificationCount'] == 0 && defaults['mutated'] == false &&
             %w[inputBeforeAfterEqual outputBeforeAfterEqual systemOutputBeforeAfterEqual hiddenEndpointNeverDefault virtualEndpointsNeverOutputDefault].all? { |key| defaults[key] == true }, 'sticky defaults differ')
    teardown = waveform.fetch('teardown')
    require!(%w[cleanupEvidenceComplete queuesOpened callbackGatesDrained runningStateRestored defaultListenerInstalled deviceListenerInstalled listenersRemoved contextsReleased].all? { |key| teardown[key] == true } &&
             %w[inputStopStatus outputStopStatus inputDisposeStatus outputDisposeStatus].all? { |key| teardown[key] == 0 } &&
             integer!(teardown['postCloseCallbackCount']) >= 0, 'cleanup/teardown differs')
    lifecycle = waveform.fetch('lifecycle')
    require!(lifecycle['requiredStartOrders'] == ORDERS && lifecycle['cycles'].is_a?(Array) && lifecycle['cycles'].size == 2 &&
             lifecycle['zeroTimestampSeedObservableViaPublicAPI'] == false && lifecycle['seedChangeClaimed'] == false, 'public clock/seed claim differs')
    lifecycle['cycles'].zip(ORDERS).each do |cycle, order|
      require!(cycle['startOrder'] == order && %w[quiescentBefore quiescentAfter nearZeroSharedClock timelinesAdvanced queuesStoppedAndDisposed].all? { |key| cycle[key] == true } &&
               integer!(cycle['initialVisibleSampleFrame']) <= 48_000 && integer!(cycle['initialHiddenSampleFrame']) <= 48_000 &&
               integer!(cycle['finalVisibleSampleFrame']) > cycle['initialVisibleSampleFrame'] &&
               integer!(cycle['finalHiddenSampleFrame']) > cycle['initialHiddenSampleFrame'], 'both restart clocks differ')
    end
    timestamps = waveform.fetch('timestamps')
    # Callback delivery residual is telemetry, not proof of a source clock
    # fault. Preserve the production oracle's device-time and source-rate gates.
    integer!(timestamps['hostDeltaMismatchCount'])
    errors = %w[sampleTimeMissingCount hostTimeMissingCount nonIntegralSampleTimeCount nonMonotonicSampleTimeCount sampleFrameDiscontinuityCount nonMonotonicHostTimeCount deviceTimeSampleFlagMissingCount deviceTimeHostFlagMissingCount nonIntegralDeviceSampleTimeCount nonAdvancingDeviceTimeCount deviceTimeRateMismatchCount mirrorDeviceTimeMismatchCount]
    require!(errors.all? { |key| timestamps[key] == 0 } && timestamps['alignedEvidenceAvailable'] == true && timestamps['timestampFrameCount'] == 96_000 &&
             timestamps['sourceSampleRateMatches'] == true && integer!(timestamps['callbackCount'], 1) > 0 && integer!(timestamps['deviceTimePairCount'], 2) >= 2, 'clock observations differ')
    projection = timestamps.fetch('projection')
    first = integer!(timestamps['firstRawSampleFrame']); last = integer!(timestamps['lastRawSampleFrame'])
    require!(last > first && projection['schema'] == 'opensteamer.facetime-timestamp-projection.v1' && projection['signedMinimum'] == -2_147_483_648 && projection['signedMaximum'] == 2_147_483_647 &&
             projection['sourceSampleRate'] == 48_000 && projection['consumerSampleRate'] == 24_000 &&
             projection['ratioNumerator'] == 1 && projection['ratioDenominator'] == 2 && projection['rounding'] == 'conservative-ceiling' &&
             projection['projectedFirstFrame'] == (first + 1) / 2 && projection['projectedLastFrame'] == (last + 1) / 2 &&
             projection['claimedProjectedLastFrame'] == (last + 1) / 2 && projection['requiredHeadroomSeconds'] == 60 &&
             projection['requiredHeadroomFrames'] == 1_440_000 && projection['remainingHeadroomFrames'] == 2_147_483_647 - (last + 1) / 2 &&
             projection['remainingHeadroomFrames'] >= 1_440_000 && %w[claimMatchesCalculation signed32Compatible headroomSatisfied].all? { |key| projection[key] == true }, 'independent clock headroom differs')
  end
end
