# frozen_string_literal: true
# UID501 byte-copy preparation only. No subprocess, audio, service or authority.
require 'digest'
require 'fiddle'
require_relative 'opensteamer-microphone-v9-transaction-contract'

module BelugaMicrophoneV9InputStaging
  class Refused < StandardError; end
  Contract = OpensteamerMicrophoneV9TransactionContract
  DEPENDENCY_ROLES = %w[tools/opensteamer-microphone-v9-host-gate.rb
    tools/product/opensteamer-host-v91-cutover-controller.rb
    tools/product/opensteamer-host-successor-inputs.rb
    tools/product/opensteamer-host-successor-contract.rb
    tools/product/verify-v91-secondary-viewer-readiness.sh
    tools/observers/SwitchAudioSource tools/observers/probe-worldwide-lock-v23
    tools/observers/verify-live-display-topology-v23].freeze
  RELEASE_ROLES = (Contract::ARTIFACT_FILES.keys.map { |name| 'producer/' + name } +
    Contract::BUNDLE_NODES.select { |type, _, _| type == 'Regular File' }.map { |_, _, name| 'candidate/' + name }).freeze
  MAX_FILE = 256 * 1024 * 1024

  # Constants and signatures from the pinned Darwin SDK sys/acl.h. A copied
  # root-readable object must not carry inherited or explicit extended entries.
  module EmptyACL
    GET = Fiddle::Function.new(Fiddle::Handle::DEFAULT['acl_get_fd_np'], [Fiddle::TYPE_INT, Fiddle::TYPE_INT], Fiddle::TYPE_VOIDP)
    ENTRY = Fiddle::Function.new(Fiddle::Handle::DEFAULT['acl_get_entry'], [Fiddle::TYPE_VOIDP, Fiddle::TYPE_INT, Fiddle::TYPE_VOIDP], Fiddle::TYPE_INT)
    FREE = Fiddle::Function.new(Fiddle::Handle::DEFAULT['acl_free'], [Fiddle::TYPE_VOIDP], Fiddle::TYPE_INT)
    def self.check!(file)
      Fiddle.last_error = 0
      acl = GET.call(file.fileno, 0x100)
      error = Fiddle.last_error
      return true if acl.to_i.zero? && error == 2
      raise Refused, 'internal ACL absence unproved' if acl.to_i.zero?
      entry = Fiddle::Pointer.malloc(Fiddle::SIZEOF_VOIDP, Fiddle::RUBY_FREE)
      ENTRY.call(acl, 0, entry)
      raise Refused, 'internal extended ACL refused'
    ensure
      raise Refused, 'internal ACL release failed' if acl && !acl.to_i.zero? && FREE.call(acl) != 0
    end
  end

  def self.require!(condition, message)
    raise Refused, message unless condition
  end

  def self.identity(stat)
    [stat.dev, stat.ino, stat.uid, stat.gid, stat.mode, stat.nlink, stat.size,
     stat.mtime.to_i, stat.mtime.nsec, stat.ctime.to_i, stat.ctime.nsec]
  end

  def self.deadline
    Process.clock_gettime(Process::CLOCK_MONOTONIC) + Contract::PREPARATION_SECONDS
  end

  def self.check_deadline!(value)
    require!(Process.clock_gettime(Process::CLOCK_MONOTONIC) < value, 'capsule monotonic deadline exceeded')
  end

  def self.record!(path, expected: nil, empty: false, internal: false, deadline: self.deadline)
    check_deadline!(deadline)
    require!(path.is_a?(String) && path.start_with?('/') && File.realpath(path) == path, 'copy input alias refused')
    before = File.lstat(path)
    require!(before.file? && before.uid == 501 && before.nlink == 1 && (before.mode & 07022).zero? &&
             before.size.between?(empty ? 0 : 1, MAX_FILE), 'copy input metadata refused')
    sha = Digest::SHA256.new
    File.open(path, File::RDONLY | File::NOFOLLOW) do |file|
      require!(identity(file.stat) == identity(before), 'copy input changed at open')
      EmptyACL.check!(file) if internal
      count = 0
      loop do
        check_deadline!(deadline); chunk = file.read(65_536); break unless chunk
        count += chunk.bytesize
        require!(count <= before.size, 'copy input grew while reading'); sha.update(chunk)
      end
      require!(count == before.size, 'copy input truncated while reading')
      require!(identity(file.stat) == identity(before), 'copy input changed at read')
      EmptyACL.check!(file) if internal
    end
    value = { 'path' => path, 'sha256' => sha.hexdigest, 'identity' => identity(before) }
    check_deadline!(deadline)
    require!(File.realpath(path) == path && identity(File.lstat(path)) == identity(before) && (!expected || value == expected),
             'copy input identity or bytes changed')
    value
  rescue SystemCallError, IOError
    raise Refused, 'copy input unavailable'
  end

  # Hold each destination directory across all EXCL/non-following copies.
  # Only destination FDs are chmod'ed; original evidence is never modified.
  class Capsule
    def initialize(root, deadline: BelugaMicrophoneV9InputStaging.deadline)
      BelugaMicrophoneV9InputStaging.require!(Process.uid == 501 && Process.euid == 501 &&
        root.is_a?(String) && root.match?(%r{\A/private/tmp/beluga-microphone-v9-guards\.[a-zA-Z0-9_-]+\z}) &&
        File.realpath(root) == root, 'capsule root/UID refused')
      @root = root; @deadline = deadline; @directories = {}; @device = File.lstat('/private/tmp').dev
      hold_directory!(root, 0700)
    end

    def hold_directory!(path, mode)
      BelugaMicrophoneV9InputStaging.check_deadline!(@deadline)
      stat = File.lstat(path)
      BelugaMicrophoneV9InputStaging.require!(File.realpath(path) == path && stat.directory? && stat.uid == 501 && stat.dev == @device &&
        stat.mode & 07777 == mode, 'capsule directory metadata refused')
      file = File.open(path, File::RDONLY | File::NOFOLLOW)
      BelugaMicrophoneV9InputStaging.require!(directory_identity(file.stat) == directory_identity(stat), 'capsule directory changed at open')
      EmptyACL.check!(file)
      @directories[path] = [file, directory_identity(stat)]
    rescue Exception
      file&.close unless @directories.key?(path)
      raise
    end

    def directory_identity(stat)
      [stat.dev, stat.ino, stat.uid, stat.gid, stat.mode]
    end

    def fence!
      BelugaMicrophoneV9InputStaging.check_deadline!(@deadline)
      @directories.each do |path, (file, expected)|
        BelugaMicrophoneV9InputStaging.require!(File.realpath(path) == path && directory_identity(File.lstat(path)) == expected &&
          directory_identity(file.stat) == expected, 'capsule held directory changed')
        EmptyACL.check!(file)
      end
    end

    def directory!(relative, mode = 0700)
      BelugaMicrophoneV9InputStaging.require!(relative.is_a?(String) && relative.match?(%r{\A[a-zA-Z0-9_.-]+(?:/[a-zA-Z0-9_.-]+)*\z}) &&
        relative.split('/').none? { |part| %w[. ..].include?(part) }, 'capsule relative directory refused')
      path = @root + '/' + relative
      BelugaMicrophoneV9InputStaging.require!(@directories.key?(File.dirname(path)), 'capsule parent not held')
      fence!; Dir.mkdir(path, mode); File.open(path, File::RDONLY | File::NOFOLLOW) { |file| file.chmod(mode); file.fsync }
      hold_directory!(path, mode); fence!; path
    end

    def copy!(original, relative)
      BelugaMicrophoneV9InputStaging.require!(original.is_a?(Hash) && original.keys.sort == %w[identity path sha256] &&
        relative.is_a?(String) && relative.match?(%r{\A[a-zA-Z0-9_.-]+(?:/[a-zA-Z0-9_.-]+)*\z}) &&
        relative.split('/').none? { |part| %w[. ..].include?(part) }, 'capsule copy descriptor refused')
      destination = @root + '/' + relative
      BelugaMicrophoneV9InputStaging.require!(@directories.key?(File.dirname(destination)), 'capsule copy parent not held')
      fence!
      BelugaMicrophoneV9InputStaging.record!(original.fetch('path'), expected: original, deadline: @deadline)
      written_identity = nil
      File.open(original.fetch('path'), File::RDONLY | File::NOFOLLOW) do |input|
        BelugaMicrophoneV9InputStaging.require!(BelugaMicrophoneV9InputStaging.identity(input.stat) == original.fetch('identity'), 'copy source FD changed')
        File.open(destination, File::WRONLY | File::CREAT | File::EXCL | File::NOFOLLOW, 0600) do |output|
          output.chmod(original.fetch('identity')[4] & 07777)
          EmptyACL.check!(output)
          sha = Digest::SHA256.new
          count = 0
          loop do
            BelugaMicrophoneV9InputStaging.check_deadline!(@deadline)
            chunk = input.read(65_536); break unless chunk
            count += chunk.bytesize
            BelugaMicrophoneV9InputStaging.require!(count <= original.fetch('identity')[6], 'copy source grew during copy')
            sha.update(chunk); output.write(chunk)
          end
          BelugaMicrophoneV9InputStaging.require!(count == original.fetch('identity')[6], 'copy source truncated during copy')
          BelugaMicrophoneV9InputStaging.require!(sha.hexdigest == original.fetch('sha256') &&
            BelugaMicrophoneV9InputStaging.identity(input.stat) == original.fetch('identity'), 'copy source changed during copy')
          output.flush; output.fsync; EmptyACL.check!(output)
          written_identity = BelugaMicrophoneV9InputStaging.identity(output.stat)
          BelugaMicrophoneV9InputStaging.require!(output.stat.file? && output.stat.uid == 501 && output.stat.nlink == 1 &&
            output.stat.dev == @device && output.stat.size == count, 'copy destination FD differs')
        end
      end
      BelugaMicrophoneV9InputStaging.record!(original.fetch('path'), expected: original, deadline: @deadline)
      copied = BelugaMicrophoneV9InputStaging.record!(destination, internal: true, deadline: @deadline)
      BelugaMicrophoneV9InputStaging.require!(copied.fetch('identity') == written_identity &&
        copied.fetch('sha256') == original.fetch('sha256') && copied.fetch('identity')[0] == @device &&
        copied.fetch('identity')[4] & 07777 == original.fetch('identity')[4] & 07777 &&
        copied.fetch('identity')[0, 2] != original.fetch('identity')[0, 2], 'copy bytes/mode or distinct identity differs')
      fence!; @directories.fetch(File.dirname(destination))[0].fsync
      copied
    rescue SystemCallError, IOError, KeyError, TypeError
      raise Refused, 'capsule copy refused'
    end

    def close
      @directories.each_value { |file, _| file.close }
    end
  end

  # The unchanged producer oracle uses two packed nanosecond timestamps (9
  # fields). Manifest v2 uses split seconds/nanoseconds (11 fields). Retain all
  # original values losslessly, then verify the projection against the actual
  # bounded FD/path/SHA record; this is not a metadata rebind or permission fix.
  def self.contract_record!(original, deadline: self.deadline)
    require!(original.is_a?(Hash) && original.keys.sort == %w[identity path sha256] &&
      original['identity'].is_a?(Array) && original['identity'].size == 9 &&
      original['identity'].all? { |value| value.is_a?(Integer) } && original['sha256'].is_a?(String) &&
      original['sha256'].match?(/\A[0-9a-f]{64}\z/), 'contract file record shape differs')
    identity = original.fetch('identity')
    projected = identity.first(7) + identity[7].divmod(1_000_000_000) + identity[8].divmod(1_000_000_000)
    roundtrip = projected.first(7) + [projected[7] * 1_000_000_000 + projected[8], projected[9] * 1_000_000_000 + projected[10]]
    require!(roundtrip == identity, 'contract timestamp projection is not lossless')
    converted = { 'path' => original.fetch('path'), 'sha256' => original.fetch('sha256'), 'identity' => projected }
    record!(converted.fetch('path'), expected: converted, deadline: deadline)
  rescue KeyError, TypeError, NoMethodError
    raise Refused, 'contract file record refused'
  end

  def self.original_records!(dependencies, deadline: self.deadline)
    check_deadline!(deadline)
    require!(Process.uid == 501 && Process.euid == 501, 'original input audit UID refused')
    require!(dependencies.is_a?(Hash) && dependencies.keys.sort == DEPENDENCY_ROLES.sort, 'dependency role set differs')
    artifacts, = Contract.verify_artifacts!(deadline: deadline)
    records = dependencies.dup
    Contract::ARTIFACT_FILES.each_key { |name| records['producer/' + name] = contract_record!(artifacts.fetch(name), deadline: deadline) }
    Contract::BUNDLE_NODES.select { |type, _, _| type == 'Regular File' }.each do |_, _, name|
      records['candidate/' + name] = contract_record!(artifacts.fetch('bundle').fetch(name), deadline: deadline)
    end
    records.each_value { |record| record!(record.fetch('path'), expected: record, deadline: deadline) }
    records
  rescue Contract::Refusal, SystemCallError, KeyError
    raise Refused, 'original release input refused'
  end

  def self.internal_relative(role)
    'inputs/' + (role.start_with?('candidate/') ? role.sub('candidate/', 'candidate.driver/') : role)
  end

  def self.stage!(root, dependencies)
    deadline = self.deadline
    capsule = Capsule.new(root, deadline: deadline)
    originals = original_records!(dependencies, deadline: deadline)
    %w[inputs inputs/tools inputs/tools/product inputs/tools/observers inputs/producer].each { |path| capsule.directory!(path) }
    Contract::BUNDLE_NODES.select { |type, _, _| type == 'Directory' }.each do |_, mode, name|
      capsule.directory!('inputs/candidate.driver' + (name == '.' ? '' : '/' + name), mode)
    end
    copies = originals.to_h { |role, record| [role, capsule.copy!(record, internal_relative(role))] }
    require!(original_records!(dependencies, deadline: deadline) == originals, 'original inputs changed during staging')
    capsule.fence!
    [originals, copies.select { |role, _| DEPENDENCY_ROLES.include?(role) }, copies.select { |role, _| RELEASE_ROLES.include?(role) }]
  ensure
    capsule&.close
  end

  def self.audit!(root, dependencies, originals, sealed, release)
    deadline = self.deadline
    capsule = Capsule.new(root, deadline: deadline)
    require!(originals == original_records!(dependencies, deadline: deadline) && sealed.is_a?(Hash) &&
      sealed.keys.sort == (DEPENDENCY_ROLES + ['tools/gate_inputs.txt']).sort && release.is_a?(Hash) &&
      release.keys.sort == RELEASE_ROLES.sort, 'capsule provenance or role set differs')
    originals.each do |role, original|
      copy = DEPENDENCY_ROLES.include?(role) ? sealed.fetch(role) : release.fetch(role)
      require!(copy['path'] == root + '/' + internal_relative(role) && copy['sha256'] == original['sha256'] &&
        copy['identity'][0] == File.lstat(root).dev &&
        copy['identity'][4] & 07777 == original['identity'][4] & 07777 && copy['identity'][0, 2] != original['identity'][0, 2],
        'capsule copy crosslink differs')
      record!(copy.fetch('path'), expected: copy, internal: true, deadline: deadline)
    end
    require!(sealed.fetch('tools/gate_inputs.txt')['path'] == root + '/gate_inputs.txt', 'capsule gate path differs')
    record!(root + '/gate_inputs.txt', expected: sealed.fetch('tools/gate_inputs.txt'), internal: true, deadline: deadline)
    Contract.verify_bundle_bytes!(root + '/inputs/candidate.driver', deadline: deadline)
    expected_files = originals.keys.map { |role| internal_relative(role).delete_prefix('inputs/') }.sort
    expected_directories = ['', 'tools', 'tools/product', 'tools/observers', 'producer'] +
      Contract::BUNDLE_NODES.select { |type, _, _| type == 'Directory' }.map { |_, _, name| 'candidate.driver' + (name == '.' ? '' : '/' + name) }
    files = []; directories = []; nodes = 0
    walk = lambda do |relative|
      check_deadline!(deadline); nodes += 1
      require!(nodes <= expected_files.size + expected_directories.size, 'capsule node count exceeds exact layout')
      path = root + '/inputs' + (relative.empty? ? '' : '/' + relative)
      stat = File.lstat(path)
      if stat.directory?
        require!(expected_directories.include?(relative), 'capsule extra directory refused')
        mode = relative == 'candidate.driver' || relative.start_with?('candidate.driver/') ? 0755 : 0700
        require!(File.realpath(path) == path && stat.dev == File.lstat(root).dev && stat.uid == 501 && stat.mode & 07777 == mode,
          'capsule input directory differs')
        capsule.hold_directory!(path, mode); directories << relative
        children = Dir.children(path).sort
        require!(children.size <= expected_files.size + expected_directories.size, 'capsule directory count exceeds bound')
        children.each { |name| walk.call(relative.empty? ? name : relative + '/' + name) }
      else
        require!(stat.file? && expected_files.include?(relative), 'capsule extra/non-file entry refused'); files << relative
      end
    end
    walk.call('')
    require!(files.sort == expected_files && directories.sort == expected_directories.sort, 'capsule input layout differs')
    capsule.fence!; true
  rescue Contract::Refusal, KeyError, TypeError, NoMethodError, SystemCallError, IOError
    raise Refused, 'capsule audit refused'
  ensure
    capsule&.close
  end
end
