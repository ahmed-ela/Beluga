# Offline library for the complete osD2 JSON emitted by DiagnosticSnapshotReader
# --read-v2-once. Admission is not live provenance, an updater, or permission to
# deploy. Callers must independently pin the reader/driver and supply read windows.
require 'json'
require 'set'

module OpensteamerOSD2IdleContract
  class InvalidObservation < StandardError; end
  class DuplicateKey < StandardError; end

  class UniqueObject < Hash
    def []=(key, value)
      raise FrozenError, 'admitted osD2 object is immutable' if frozen?
      raise DuplicateKey, 'duplicate JSON member' if key?(key)
      super
    end
  end

  U32_MAX = (1 << 32) - 1
  U64_MAX = (1 << 64) - 1
  I32_MIN = -(1 << 31)
  I32_MAX = (1 << 31) - 1
  HEADER_BYTES = 3504
  REGISTRY_RECORD_BYTES = 88
  MAX_WIRE_BYTES = 1_048_576
  MAX_REGISTRY_RECORDS = (MAX_WIRE_BYTES - HEADER_BYTES) / REGISTRY_RECORD_BYTES
  CORE_CAPACITY = 64
  INVARIANT_MASK = 0x7ff00
  KNOWN_FLAGS = INVARIANT_MASK | 3
  ILLEGAL_OPERATION = 0x6e6f7065 # Core Audio FourCC 'nope'.
  UNSPECIFIED_ERROR = 0x77686174 # Core Audio FourCC 'what'.
  VISIBLE_UID = 'com.elamin.opensteamer.virtual-microphone.input'.freeze
  WRITER_UID = 'com.elamin.opensteamer.virtual-microphone.writer'.freeze

  TRANSITION = {
    'hostTicks' => :u64, 'clientID' => :u64, 'preGlobalActiveCount' => :u64,
    'postGlobalActiveCount' => :u64, 'driverClientGeneration' => :u64,
    'coreSessionID' => :u64, 'type' => :u32, 'endpointRole' => :u32,
    'slotIndex' => :u32, 'processID' => :i32
  }.freeze
  FAILURE = {
    'sequence' => :u64, 'hostTicks' => :u64, 'registryIndex' => :u64,
    'driverClientGeneration' => :u64, 'operation' => :u32, 'reason' => :u32,
    'deviceObjectID' => :u32, 'clientID' => :u32, 'processID' => :i32,
    'status' => :i32, 'coreStatus' => :i32
  }.freeze
  ZERO_TIMESTAMP = {
    'endpointRole' => :u32, 'sequence' => :u64, 'metadataSequence' => :u64,
    'metadataDroppedUpdateCount' => :u64, 'epochMappingUnavailableCount' => :u64,
    'callCount' => :u64, 'successfulReturnCount' => :u64, 'fallbackReturnCount' => :u64,
    'failedReturnCount' => :u64, 'lastCallHostTicks' => :u64, 'lastSampleFrame' => :u64,
    'lastHostTicks' => :u64, 'lastSeed' => :u64, 'lastSeedGeneration' => :u64,
    'lastCoreLifecycleSequence' => :u64, 'lastCallCoreLifecycleSequence' => :u64,
    'lastClientID' => :u32, 'lastStatus' => :i32, 'flags' => :u32
  }.freeze
  IO = {
    'endpointRole' => :u32, 'sequence' => :u64, 'metadataSequence' => :u64,
    'metadataDroppedUpdateCount' => :u64, 'operationCallCount' => :u64,
    'validCycleCount' => :u64, 'invalidCycleCount' => :u64, 'leaseUnavailableCount' => :u64,
    'epochMappingUnavailableCount' => :u64, 'coreOKCount' => :u64, 'coreRetryCount' => :u64,
    'coreFailureCount' => :u64, 'requestedFrameCount' => :u64, 'transferredFrameCount' => :u64,
    'gapFrameCount' => :u64, 'lastCycleSampleFrame' => :u64, 'lastCycleHostTicks' => :u64,
    'lastPublishedFrameSeed' => :u64, 'lastPublishedSeedGeneration' => :u64,
    'lastPublishedFrameSession' => :u64, 'lastPublishedAbsoluteFrame' => :u64,
    'lastConsumedFrameSeed' => :u64, 'lastConsumedSeedGeneration' => :u64,
    'lastConsumedFrameSession' => :u64, 'lastConsumedAbsoluteFrame' => :u64,
    'lastClientID' => :u32, 'lastStatus' => :i32, 'flags' => :u32
  }.freeze
  WORK_LOOP = {
    'endpointRole' => :u32, 'sequence' => :u64, 'metadataSequence' => :u64,
    'metadataDroppedUpdateCount' => :u64, 'currentCount' => :u64,
    'beginCount' => :u64, 'endCount' => :u64, 'underflowCount' => :u64,
    'lastTransitionHostTicks' => :u64, 'lastClientID' => :u32, 'flags' => :u32
  }.freeze
  REGISTRY = {
    'registryIndex' => :u64, 'generation' => :u64, 'registrationHostTicks' => :u64,
    'startHostTicks' => :u64, 'lastTransitionHostTicks' => :u64,
    'leaseSessionID' => :u64, 'leaseTimelineSeed' => :u64, 'flags' => :u32,
    'deviceObjectID' => :u32, 'clientID' => :u32, 'processID' => :i32,
    'endpointRole' => :u32, 'coreClientSlot' => :u32, 'ioStartDepth' => :u32
  }.freeze
  CORE = {
    'slotIndex' => :u32, 'sessionID' => :u64, 'clientID' => :u64,
    'timelineSeed' => :u64, 'endpointRole' => :u32
  }.freeze
  ROOT = {
    'readerSchema' => :u32, 'mode' => 'read-v2-once',
    'claim' => 'read-only-complete-virtual-driver-diagnostic-snapshot',
    'visibleDeviceUID' => VISIBLE_UID, 'visibleDeviceID' => :u32,
    'writerDeviceUID' => WRITER_UID, 'writerDeviceID' => :u32,
    'endpointReadsCoherent' => :boolean, 'snapshotSchemaVersion' => :u32,
    'totalByteCount' => :u64, 'registryRecordCount' => :u64, 'registryRecordSize' => :u64,
    'registryRevision' => :u64, 'completeRegistryInventory' => :boolean,
    'coreSlotCapacity' => :u32, 'capacityInvariantScope' => 'active-core-resources-only',
    'allDeclaredInvariantsHold' => :boolean, 'invariantFlags' => :hex64,
    'snapshotSequence' => :u64, 'capturedHostTicks' => :u64,
    'driverInstanceGeneration' => :u64, 'timelineSeed' => :u64,
    'currentSeedGeneration' => :u64, 'activeClientCount' => :u64,
    'driverRegisteredCount' => :u64, 'driverStartedCount' => :u64,
    'driverLifecycleSequence' => :u64, 'coreLifecycleSequence' => :u64,
    'hostTicksPerSecond' => :u64, 'anchorHostTicks' => :u64,
    'lastIssuedSeed' => :u64, 'lastIssuedSessionID' => :u64,
    'visibleInputActiveCount' => :u64, 'hiddenWriterActiveCount' => :u64,
    'coreActiveSlotCount' => :u64, 'coreActiveSlotBitmap' => :u64,
    'visibleDriverRegisteredCount' => :u64, 'hiddenDriverRegisteredCount' => :u64,
    'visibleDriverStartedCount' => :u64, 'hiddenDriverStartedCount' => :u64,
    'driverClientAddAttemptCount' => :u64, 'driverClientAddCount' => :u64,
    'driverClientRemoveAttemptCount' => :u64, 'driverClientRemoveCount' => :u64,
    'globalStartAttemptCount' => :u64, 'globalStartTransitionCount' => :u64,
    'globalStopAttemptCount' => :u64, 'globalStopTransitionCount' => :u64,
    'seedCreateCount' => :u64, 'seedClearCount' => :u64,
    'lastSeedCreateHostTicks' => :u64, 'lastSeedClearHostTicks' => :u64,
    'lastClearedSeed' => :u64, 'lastClearedSeedGeneration' => :u64,
    'lastClearedAnchorHostTicks' => :u64,
    'lastAdmissionFailure' => FAILURE, 'lastDriverTransition' => TRANSITION,
    'lastCoreTransition' => TRANSITION,
    'zeroTimestamp' => [ZERO_TIMESTAMP, 2], 'io' => [IO, 2],
    'ioWorkLoop' => [WORK_LOOP, 2], 'registry' => [REGISTRY, MAX_REGISTRY_RECORDS],
    'coreClientSlots' => [CORE, CORE_CAPACITY]
  }.freeze

  # Count complete JSON values and keys, not an obsolete 16,384-node ceiling.
  # Byte bounds use each fixed key/literal and the widest ABI decimal scalar.
  def self.bounds(schema)
    case schema
    when Hash
      children = schema.map { |key, type| [JSON.generate(key).bytesize, bounds(type)] }
      [2 + [children.length - 1, 0].max + children.sum { |key, value| key + 1 + value[0] },
       1 + children.sum { |_key, value| 1 + value[1] }]
    when Array
      bytes, nodes = bounds(schema[0]); count = schema[1]
      [2 + count * bytes + [count - 1, 0].max, 1 + count * nodes]
    when String then [JSON.generate(schema).bytesize, 1]
    else
      [{ u64: 20, u32: 10, i32: 11, boolean: 5, hex64: 18 }.fetch(schema), 1]
    end
  end
  MAX_JSON_BYTES, MAX_JSON_NODES = bounds(ROOT)
  MAX_JSON_INPUT_BYTES = MAX_JSON_BYTES + 1 # Exact reader newline.

  def self.require!(condition, message)
    raise InvalidObservation, message unless condition
  end

  def self.enforce_token_budget(text)
    nodes = 0; quoted = false; escaped = false; scalar = false
    text.each_byte do |byte|
      if quoted
        if escaped then escaped = false
        elsif byte == 92 then escaped = true
        elsif byte == 34 then quoted = false
        end
        next
      end
      delimiter = [9, 10, 13, 32, 44, 58, 93, 125].include?(byte)
      scalar = false if delimiter
      if byte == 34
        quoted = true; nodes += 1
      elsif byte == 91 || byte == 123
        nodes += 1; scalar = false
      elsif !delimiter && !scalar
        nodes += 1; scalar = true
      end
      require!(nodes <= MAX_JSON_NODES, 'osD2 JSON exceeds its derived node budget')
    end
  end

  def self.validate_shape(value, schema)
    case schema
    when Hash
      require!(value.is_a?(Hash) && value.keys.sort == schema.keys.sort, 'osD2 object field set differs from the complete reader schema')
      schema.each { |key, type| validate_shape(value[key], type) }
    when Array
      require!(value.is_a?(Array) && value.length <= schema[1], 'osD2 array exceeds its derived geometry bound')
      value.each { |entry| validate_shape(entry, schema[0]) }
    when String
      require!(value == schema, 'osD2 reader identity or claim is wrong')
    else
      valid = case schema
              when :u64 then value.is_a?(Integer) && (0..U64_MAX).cover?(value)
              when :u32 then value.is_a?(Integer) && (0..U32_MAX).cover?(value)
              when :i32 then value.is_a?(Integer) && (I32_MIN..I32_MAX).cover?(value)
              when :boolean then value == true || value == false
              when :hex64 then value.is_a?(String) && value.match?(/\A[0-9a-f]{16}\z/)
              end
      require!(valid, 'osD2 scalar type or ABI width is invalid')
    end
  end

  def self.deep_freeze(value)
    value.each { |key, entry| key.freeze; deep_freeze(entry) } if value.is_a?(Hash)
    value.each { |entry| deep_freeze(entry) } if value.is_a?(Array)
    value.freeze
  end

  def self.validate_transition(record, core)
    require!(record['type'] <= 6 && record['endpointRole'] <= 2 &&
             (record['slotIndex'] < CORE_CAPACITY || record['slotIndex'] == U32_MAX) &&
             (!core || ![1, 2].include?(record['type'])), 'osD2 transition metadata is invalid')
  end

  def self.validate_failure(record)
    if record['sequence'] == 0
      require!(record.values.all? { |value| value == 0 }, 'osD2 absent failure record is not zero')
      return
    end
    operation = record['operation']; reason = record['reason']; index = record['registryIndex']
    status = record['status']; core = record['coreStatus']
    require!(record['hostTicks'] > 0 && (1..4).cover?(operation) && (1..9).cover?(reason) &&
             [2, 6].include?(record['deviceObjectID']) && status != 0 &&
             (index == U64_MAX) == (record['driverClientGeneration'] == 0), 'osD2 failure provenance is invalid')
    valid = if reason == 9
              [3, 4].include?(operation) && index != U64_MAX && (1..15).cover?(core) &&
                status == ([1, 4, 5, 7, 8, 9, 10].include?(core) ? ILLEGAL_OPERATION : UNSPECIFIED_ERROR)
            elsif [3, 4].include?(reason)
              core == 0 && operation == 1 && index == U64_MAX && status == UNSPECIFIED_ERROR
            else
              core == 0 && status == ILLEGAL_OPERATION && case reason
              when 2 then operation == 1 && index != U64_MAX
              when 5 then operation != 1 && index == U64_MAX
              when 6 then operation == 3 && index != U64_MAX
              when 7 then operation == 4 && index != U64_MAX
              when 8 then operation == 2 && index != U64_MAX
              else true
              end
            end
    require!(valid, 'osD2 failure status mapping is invalid')
  end

  def self.validate_records(value)
    %w[zeroTimestamp io ioWorkLoop].each do |bank|
      records = value[bank]
      require!(records.length == 2 && records.map { |entry| entry['endpointRole'] } == [1, 2], 'osD2 endpoint metadata bank is incomplete or reordered')
      records.each do |record|
        mask = bank == 'ioWorkLoop' ? 5 : 31
        require!(record['flags'] & ~mask == 0 && record['metadataSequence'].even?, 'osD2 RT metadata flags or sequence is invalid')
      end
    end
    validate_transition(value['lastDriverTransition'], false)
    validate_transition(value['lastCoreTransition'], true)
    validate_failure(value['lastAdmissionFailure'])
  end

  def self.derive_invariants(value)
    core_count = [0, 0]; core_bitmap = 0; current_slots = true
    value['coreClientSlots'].each_with_index do |core, index|
      require!(core['slotIndex'] == index && core['endpointRole'] <= 2, 'osD2 fixed core inventory identity is invalid')
      next if core['sessionID'] == 0 # Retired metadata is intentionally preserved.
      require!(core['endpointRole'] > 0, 'osD2 active core role is absent')
      core_count[core['endpointRole'] - 1] += 1
      core_bitmap |= 1 << index
      current_slots &&= core['timelineSeed'] == value['timelineSeed']
    end
    registered = [0, 0]; started = [0, 0]; references = 0; leases_match = true
    previous_index = nil; generations = Set.new; keys = Set.new
    value['registry'].each do |record|
      index = record['registryIndex']; device = record['deviceObjectID']; role = record['endpointRole']
      require!(index != U64_MAX && (!previous_index || previous_index < index) &&
               record['generation'] > 0 && generations.add?(record['generation']) &&
               record['registrationHostTicks'] > 0 && record['lastTransitionHostTicks'] > 0 &&
               [1, 7].include?(record['flags']) && [2, 6].include?(device) &&
               role == (device == 2 ? 1 : 2) && keys.add?([device, record['clientID']]), 'osD2 complete registry identity is malformed, duplicate or unordered')
      previous_index = index; registered[role - 1] += 1
      if record['flags'] == 1
        require!(record['leaseSessionID'] == 0 && record['leaseTimelineSeed'] == 0 &&
                 record['coreClientSlot'] == U32_MAX && record['ioStartDepth'] == 0, 'osD2 stopped registration retains an active lease')
        next
      end
      require!(record['ioStartDepth'] == 1 && record['startHostTicks'] > 0 &&
               record['leaseSessionID'] > 0 && record['leaseTimelineSeed'] > 0 &&
               record['coreClientSlot'] < CORE_CAPACITY, 'osD2 started registration lease geometry is invalid')
      started[role - 1] += 1
      core = value['coreClientSlots'][record['coreClientSlot']]; bit = 1 << record['coreClientSlot']
      key = device << 32 | record['clientID']
      leases_match &&= references & bit == 0 && core['sessionID'] == record['leaseSessionID'] &&
        core['clientID'] == key && core['timelineSeed'] == record['leaseTimelineSeed'] && core['endpointRole'] == role
      references |= bit
    end
    require!(registered == [value['visibleDriverRegisteredCount'], value['hiddenDriverRegisteredCount']] &&
             started == [value['visibleDriverStartedCount'], value['hiddenDriverStartedCount']] &&
             started.sum == value['driverStartedCount'] && core_bitmap == value['coreActiveSlotBitmap'] &&
             core_count.sum == value['coreActiveSlotCount'], 'osD2 registry/core totals disagree with the complete inventory')
    leases_match &&= references == core_bitmap
    seed = value['timelineSeed']; generation = value['currentSeedGeneration']; active = value['activeClientCount']
    ring_matches = seed == 0 || (seed == generation &&
      (value['io'][1]['lastPublishedFrameSeed'] == seed) == (value['io'][1]['lastPublishedSeedGeneration'] == generation) &&
      (value['io'][0]['lastConsumedFrameSeed'] == seed) == (value['io'][0]['lastConsumedSeedGeneration'] == generation))
    {
      8 => active == value['coreActiveSlotCount'],
      9 => [value['visibleInputActiveCount'], value['hiddenWriterActiveCount']] == core_count,
      10 => leases_match,
      11 => active != 0 || (seed == 0 && generation == 0 && value['anchorHostTicks'] == 0),
      12 => active == 0 || (seed > 0 && generation > 0 && value['anchorHostTicks'] > 0),
      13 => value['coreActiveSlotCount'] <= CORE_CAPACITY && value['driverStartedCount'] <= CORE_CAPACITY,
      14 => active != 0 || value['globalStartTransitionCount'] == value['globalStopTransitionCount'],
      15 => active != 0 || value['seedCreateCount'] == value['seedClearCount'],
      16 => ring_matches, 17 => current_slots, 18 => true
    }
  end

  def self.admit_json(text)
    require!(text.is_a?(String) && text.bytesize <= MAX_JSON_INPUT_BYTES, 'osD2 JSON exceeds its derived complete inventory byte bound')
    encoded = text.dup.force_encoding(Encoding::UTF_8)
    require!(encoded.valid_encoding?, 'osD2 JSON encoding is invalid')
    enforce_token_budget(encoded)
    value = JSON.parse(encoded, object_class: UniqueObject, max_nesting: 4, allow_nan: false, create_additions: false)
    validate_shape(value, ROOT)
    count = value['registryRecordCount']
    require!(value['readerSchema'] == 2 && value['snapshotSchemaVersion'] == 2 &&
             value['registryRecordSize'] == REGISTRY_RECORD_BYTES && value['coreSlotCapacity'] == CORE_CAPACITY &&
             count <= MAX_REGISTRY_RECORDS && value['totalByteCount'] == HEADER_BYTES + count * REGISTRY_RECORD_BYTES &&
             value['totalByteCount'] <= MAX_WIRE_BYTES && value['registry'].length == count &&
             value['driverRegisteredCount'] == count && value['coreClientSlots'].length == CORE_CAPACITY, 'osD2 wire geometry or complete array length is invalid')
    require!(value['endpointReadsCoherent'] && value['completeRegistryInventory'] &&
             value['visibleDeviceID'] > 0 && value['writerDeviceID'] > 0 && value['visibleDeviceID'] != value['writerDeviceID'] &&
             value['snapshotSequence'] > 0 && value['capturedHostTicks'] > 0 &&
             value['driverInstanceGeneration'] > 0 && value['hostTicksPerSecond'] > 0 &&
             value['coreLifecycleSequence'].even?, 'osD2 coherence, instance or lifecycle metadata is invalid')
    flags = value['invariantFlags'].to_i(16)
    require!(flags & ~KNOWN_FLAGS == 0 && flags & 1 == 1 && flags & (1 << 18) != 0 &&
             (flags & 2 != 0) == (value['timelineSeed'] != 0), 'osD2 invariant flags or timeline activity are invalid')
    validate_records(value)
    derived = derive_invariants(value)
    require!(derived.all? { |bit, fact| (flags & (1 << bit) != 0) == fact } &&
             value['allDeclaredInvariantsHold'] == (flags & INVARIANT_MASK == INVARIANT_MASK), 'osD2 declared invariants disagree with independently derived state')
    Snapshot.send(:new, deep_freeze(value), deep_freeze(derived))
  rescue JSON::ParserError, JSON::NestingError, DuplicateKey
    raise InvalidObservation, 'osD2 JSON is malformed, nested or duplicate-keyed (contents redacted)', cause: nil
  end

  class Snapshot
    IDENTITY_FIELDS = %w[visibleDeviceUID visibleDeviceID writerDeviceUID writerDeviceID driverInstanceGeneration hostTicksPerSecond].freeze
    EPOCH_FIELDS = %w[driverLifecycleSequence coreLifecycleSequence timelineSeed currentSeedGeneration anchorHostTicks lastIssuedSeed lastIssuedSessionID].freeze
    attr_reader :admitted_state, :derived_invariants
    private_class_method :new

    def initialize(state, invariants)
      @admitted_state = state; @derived_invariants = invariants
      freeze
    end

    def identity
      IDENTITY_FIELDS.map { |key| [key, @admitted_state.fetch(key)] }.to_h.freeze
    end

    def epoch
      EPOCH_FIELDS.map { |key| [key, @admitted_state.fetch(key)] }.to_h.freeze
    end

    def inventory
      { 'registryRevision' => @admitted_state['registryRevision'],
        'registry' => @admitted_state['registry'], 'coreClientSlots' => @admitted_state['coreClientSlots'] }.freeze
    end

    def stable_state
      @admitted_state.reject { |key, _value| %w[snapshotSequence capturedHostTicks zeroTimestamp io ioWorkLoop].include?(key) }.freeze
    end

    def quiescent_state?
      value = @admitted_state
      @derived_invariants.values.all? && value['driverLifecycleSequence'] > 0 &&
        %w[activeClientCount visibleInputActiveCount hiddenWriterActiveCount coreActiveSlotCount coreActiveSlotBitmap driverStartedCount visibleDriverStartedCount hiddenDriverStartedCount timelineSeed currentSeedGeneration anchorHostTicks].all? { |key| value[key] == 0 } &&
        value['lastClearedSeed'] == value['lastClearedSeedGeneration'] &&
        quiescent_ledger? &&
        value['ioWorkLoop'].all? { |loop| loop['currentCount'] == 0 && loop['beginCount'] == loop['endCount'] }
    end

    # These non-RT ledgers share the driver's lifecycle lock. Failed attempts
    # remain harmless history; they need not equal successes. Raw admission above
    # deliberately preserves coherent failure evidence rather than asserting idle.
    def quiescent_ledger?
      value = @admitted_state
      attempts = %w[driverClientAddAttemptCount driverClientRemoveAttemptCount globalStartAttemptCount globalStopAttemptCount]
      successes = %w[driverClientAddCount driverClientRemoveCount globalStartTransitionCount globalStopTransitionCount]
      attempts.zip(successes).all? { |attempt, success| value[attempt] >= value[success] } &&
        value['driverClientAddCount'] >= value['driverClientRemoveCount'] &&
        value['driverClientAddCount'] - value['driverClientRemoveCount'] == value['driverRegisteredCount'] &&
        value['lastClearedSeed'] <= value['lastIssuedSeed']
    end

    def canonical_json
      result = JSON.generate(@admitted_state)
      OpensteamerOSD2IdleContract.require!(result.bytesize <= MAX_JSON_BYTES, 'osD2 output exceeds its derived byte bound')
      result
    end
  end

  # A stable four-sample idle proof, matching the host decoder's epoch/full-bank
  # fence. Caller-supplied windows are mandatory; the library reads no clocks,
  # processes, devices, credentials, or files. First-sample identity alone is not
  # independent live provenance, and fabricated windows do not establish freshness.
  # Consumers must obtain each window from their pinned current monotonic clock and
  # pin the externally expected identity. Non-quiescent raw states stay inspectable
  # through admit_json; there is no weakened idle-success entrypoint.
  class SequenceFence
    REQUIRED_SAMPLES = 4
    attr_reader :samples

    def initialize(expected_identity: nil)
      @expected_identity = expected_identity && OpensteamerOSD2IdleContract.deep_freeze(expected_identity.dup)
      @samples = [].freeze; @failed = false
    end

    def accept_json(text, before_ticks:, after_ticks:)
      accept(OpensteamerOSD2IdleContract.admit_json(text), before_ticks: before_ticks, after_ticks: after_ticks)
    rescue InvalidObservation
      @failed = true
      raise
    end

    def accept(snapshot, before_ticks:, after_ticks:)
      contract = OpensteamerOSD2IdleContract
      contract.require!(!@failed, 'osD2 fence was retired by a rejected observation')
      contract.require!(snapshot.is_a?(Snapshot) && @samples.length < REQUIRED_SAMPLES, 'osD2 sample was not admitted or fence is already complete')
      contract.require!([before_ticks, after_ticks].all? { |tick| tick.is_a?(Integer) && (0..U64_MAX).cover?(tick) } &&
                        before_ticks <= snapshot.admitted_state['capturedHostTicks'] &&
                        snapshot.admitted_state['capturedHostTicks'] <= after_ticks, 'osD2 observation is stale or outside its explicit read window')
      contract.require!(snapshot.quiescent_state?, 'osD2 independently derived state is not quiescent')
      contract.require!(!@expected_identity || snapshot.identity == @expected_identity, 'osD2 externally expected identity differs')
      unless @samples.empty?
        first = @samples.first; previous = @samples.last
        contract.require!(snapshot.identity == first.identity && snapshot.epoch == first.epoch && snapshot.inventory == first.inventory, 'osD2 instance, epoch, revision or complete inventory changed')
        contract.require!(snapshot.stable_state == first.stable_state, 'osD2 non-RT lifecycle or failure evidence changed')
        contract.require!(previous.admitted_state['snapshotSequence'] < snapshot.admitted_state['snapshotSequence'] &&
                          previous.admitted_state['capturedHostTicks'] < snapshot.admitted_state['capturedHostTicks'], 'osD2 sequence or captured tick did not advance')
      end
      @samples = (@samples + [snapshot]).freeze
      snapshot
    rescue InvalidObservation
      @failed = true
      raise
    end

    def complete?
      !@failed && @samples.length == REQUIRED_SAMPLES
    end

    def finish!
      OpensteamerOSD2IdleContract.require!(complete?, 'osD2 fresh stable sample set is incomplete')
      @samples
    end
  end
end
