#!/bin/zsh -f
set -euo pipefail

export LC_ALL=en_US.UTF-8
export LANG=en_US.UTF-8
umask 077
script_path="${0:A}"

fail() {
    print -u2 -- "$1"
    exit 65
}

usage() {
    print -u2 "usage: $0 output-root app-cert-sha1 installer-cert-sha1 notary-profile binding-request-path binding-request-sha256"
    exit 64
}

atomic_publish_candidate() {
    (( $# == 5 )) || return 64
    /usr/bin/python3 -I -S -B - "$@" <<'PY'
import ctypes
import os
import stat
import sys

parent, staging_leaf, output_leaf, expected_parent, expected_staging = sys.argv[1:]
if "/" in staging_leaf or "/" in output_leaf:
    raise SystemExit("candidate publication leaf is malformed")

parent_fd = os.open(parent, os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW)
try:
    parent_stat = os.fstat(parent_fd)
    observed_parent = (
        f"{parent_stat.st_dev}:{parent_stat.st_ino}:"
        f"{parent_stat.st_uid}:{stat.S_IMODE(parent_stat.st_mode):o}"
    )
    if observed_parent != expected_parent:
        raise SystemExit("candidate output parent identity changed")
    staging_stat = os.stat(staging_leaf, dir_fd=parent_fd, follow_symlinks=False)
    observed_staging = (
        f"{staging_stat.st_dev}:{staging_stat.st_ino}:"
        f"{staging_stat.st_uid}:{stat.S_IMODE(staging_stat.st_mode):o}"
    )
    if observed_staging != expected_staging or not stat.S_ISDIR(staging_stat.st_mode):
        raise SystemExit("candidate staging identity changed")

    staging_path = os.path.join(parent, staging_leaf)
    directories = []
    for current, names, files in os.walk(staging_path, topdown=False, followlinks=False):
        directories.append(current)
        for name in names:
            child = os.path.join(current, name)
            if not stat.S_ISDIR(os.lstat(child).st_mode):
                raise SystemExit("candidate staging tree contains a non-directory child")
        for name in files:
            child = os.path.join(current, name)
            if not stat.S_ISREG(os.lstat(child).st_mode):
                raise SystemExit("candidate staging tree contains a non-regular file")
            child_fd = os.open(child, os.O_RDONLY | os.O_NOFOLLOW)
            try:
                os.fsync(child_fd)
            finally:
                os.close(child_fd)
    for directory in directories:
        directory_fd = os.open(
            directory,
            os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW,
        )
        try:
            os.fsync(directory_fd)
        finally:
            os.close(directory_fd)
    os.fsync(parent_fd)

    libc = ctypes.CDLL(None, use_errno=True)
    renameatx_np = libc.renameatx_np
    renameatx_np.argtypes = [
        ctypes.c_int,
        ctypes.c_char_p,
        ctypes.c_int,
        ctypes.c_char_p,
        ctypes.c_uint,
    ]
    renameatx_np.restype = ctypes.c_int
    rename_excl = 0x00000004
    result = renameatx_np(
        parent_fd,
        os.fsencode(staging_leaf),
        parent_fd,
        os.fsencode(output_leaf),
        rename_excl,
    )
    if result != 0:
        error = ctypes.get_errno()
        raise OSError(error, os.strerror(error), output_leaf)
    os.fsync(parent_fd)
finally:
    os.close(parent_fd)
PY
}

publication_self_test_root=""
cleanup_publication_self_test() {
    [[ -n "$publication_self_test_root" ]] || return 0
    case "$publication_self_test_root" in
        /private/tmp/opensteamer-candidate-publication-v9.*) ;;
        *) return 73 ;;
    esac
    if [[ -d "$publication_self_test_root" ]] && [[ ! -L "$publication_self_test_root" ]]; then
        /usr/bin/find "$publication_self_test_root" -type d -exec /bin/chmod 0700 {} +
        /bin/rm -rf -- "$publication_self_test_root"
    fi
}

verify_publication_source_contract() {
    /usr/bin/python3 -I -S -B - "$script_path" <<'PY'
import sys

text = open(sys.argv[1], "r", encoding="utf-8").read()
marker = '\n(( $# == 6 )) || usage\n'
if text.count(marker) != 1:
    raise SystemExit("candidate preparer main marker is not unique")
main = text.split(marker, 1)[1]
ordered = [
    '[[ ! -e "$output_root" ]] && [[ ! -L "$output_root" ]]',
    'prepublication_verification="$build_root/verification.txt"',
    'manifest="$build_root/candidate-manifest.txt"',
    'staging_root="$(/usr/bin/mktemp -d "$output_parent/.production-driver-v9.stage.XXXXXX")"',
    'final_verification="$staging_root/verification.txt"',
    '>"$final_verification"',
    'expected_top_level="$(',
    '/bin/chmod 0500 "$staging_root"',
    'atomic_publish_candidate',
    'staging_root=""',
    'published production driver candidate identity is not exact',
]
position = -1
for token in ordered:
    found = main.find(token, position + 1)
    if found < 0:
        raise SystemExit(f"candidate preparer publication contract is missing: {token}")
    position = found
for forbidden in [
    '/bin/mkdir -m 0700 "$output_root"',
    '/usr/bin/ditto --noqtn "$production_bundle" "$output_root',
    '/bin/mv "$staging_root" "$output_root"',
]:
    if forbidden in main:
        raise SystemExit(f"candidate preparer exposes a partial or clobbering publication: {forbidden}")
if main.count("atomic_publish_candidate") != 1:
    raise SystemExit("candidate preparer atomic publication call is not unique")
PY
}

publication_self_test() {
    local test_root parent canonical staging parent_identity staging_identity
    local collision_parent collision_staging collision_identity collision_marker
    local symlink_parent symlink_staging symlink_identity identity_parent identity_staging
    test_root="$(/usr/bin/mktemp -d /private/tmp/opensteamer-candidate-publication-v9.XXXXXX)"
    case "$test_root" in
        /private/tmp/opensteamer-candidate-publication-v9.*) ;;
        *) fail "unsafe candidate publication self-test root" ;;
    esac
    publication_self_test_root="$test_root"
    trap cleanup_publication_self_test EXIT INT TERM HUP
    verify_publication_source_contract || \
        fail "candidate publication source integration contract failed"

    parent="$test_root/success"
    /bin/mkdir -m 0700 "$parent"
    canonical="$parent/production-driver-v9"
    staging="$parent/.production-driver-v9.stage.success"
    /bin/mkdir -m 0700 "$staging"
    /bin/mkdir -m 0755 "$staging/bundle"
    print -rn -- "candidate-bytes" >"$staging/bundle/payload" || \
        fail "unable to write candidate publication success fixture"
    /bin/chmod 0400 "$staging/bundle/payload"
    /bin/chmod 0500 "$staging"
    [[ ! -e "$canonical" ]] && [[ ! -L "$canonical" ]] || \
        fail "candidate publication self-test canonical unexpectedly exists"
    parent_identity="$(/usr/bin/stat -f '%d:%i:%u:%Lp' "$parent")"
    staging_identity="$(/usr/bin/stat -f '%d:%i:%u:%Lp' "$staging")"
    atomic_publish_candidate \
        "$parent" "${staging:t}" "${canonical:t}" "$parent_identity" "$staging_identity" || \
        fail "candidate publication self-test rejected a complete staging root"
    [[ ! -e "$staging" ]] && [[ ! -L "$staging" ]] && \
        [[ "$(/usr/bin/stat -f '%d:%i:%u:%Lp' "$canonical")" == "$staging_identity" ]] && \
        [[ "$(/usr/bin/stat -f '%HT:%Lp' "$canonical/bundle/payload")" == "Regular File:400" ]] && \
        [[ "$(<"$canonical/bundle/payload")" == "candidate-bytes" ]] || \
        fail "candidate publication self-test changed the complete staged tree"

    collision_parent="$test_root/collision"
    /bin/mkdir -m 0700 "$collision_parent"
    /bin/mkdir -m 0700 "$collision_parent/production-driver-v9"
    collision_marker="$collision_parent/production-driver-v9/existing"
    print -rn -- "existing-destination" >"$collision_marker" || \
        fail "unable to write candidate publication collision fixture"
    /bin/chmod 0400 "$collision_marker"
    collision_staging="$collision_parent/.production-driver-v9.stage.collision"
    /bin/mkdir -m 0700 "$collision_staging"
    collision_identity="$(/usr/bin/stat -f '%d:%i:%u:%Lp' "$collision_staging")"
    if atomic_publish_candidate \
        "$collision_parent" "${collision_staging:t}" "production-driver-v9" \
        "$(/usr/bin/stat -f '%d:%i:%u:%Lp' "$collision_parent")" "$collision_identity" \
        >/dev/null 2>&1; then
        fail "candidate publication self-test overwrote a preexisting destination"
    fi
    [[ -d "$collision_staging" ]] && \
        [[ "$(<"$collision_marker")" == "existing-destination" ]] || \
        fail "candidate publication self-test changed a preexisting destination"

    symlink_parent="$test_root/symlink"
    /bin/mkdir -m 0700 "$symlink_parent"
    symlink_staging="$symlink_parent/.production-driver-v9.stage.symlink"
    /bin/mkdir -m 0700 "$symlink_staging"
    /bin/ln -s /private/tmp "$symlink_staging/redirect"
    /bin/chmod 0500 "$symlink_staging"
    symlink_identity="$(/usr/bin/stat -f '%d:%i:%u:%Lp' "$symlink_staging")"
    if atomic_publish_candidate \
        "$symlink_parent" "${symlink_staging:t}" "production-driver-v9" \
        "$(/usr/bin/stat -f '%d:%i:%u:%Lp' "$symlink_parent")" "$symlink_identity" \
        >/dev/null 2>&1; then
        fail "candidate publication self-test accepted a staged symlink"
    fi
    [[ ! -e "$symlink_parent/production-driver-v9" ]] && \
        [[ ! -L "$symlink_parent/production-driver-v9" ]] || \
        fail "candidate publication self-test published the staged symlink mutant"

    identity_parent="$test_root/identity"
    /bin/mkdir -m 0700 "$identity_parent"
    identity_staging="$identity_parent/.production-driver-v9.stage.identity"
    /bin/mkdir -m 0700 "$identity_staging"
    if atomic_publish_candidate \
        "$identity_parent" "${identity_staging:t}" "production-driver-v9" \
        "$(/usr/bin/stat -f '%d:%i:%u:%Lp' "$identity_parent")" \
        "$(/usr/bin/stat -f '%d:%i:%u:%Lp' "$identity_staging")-mutant" \
        >/dev/null 2>&1; then
        fail "candidate publication self-test accepted a changed staging identity"
    fi
    [[ ! -e "$identity_parent/production-driver-v9" ]] && \
        [[ ! -L "$identity_parent/production-driver-v9" ]] || \
        fail "candidate publication self-test published the identity mutant"

    print "PASS atomic no-clobber candidate publication rejected collision, symlink, and identity mutants"
    cleanup_publication_self_test
    publication_self_test_root=""
    trap - EXIT INT TERM HUP
}


# BEGIN v9 receipt and input boundary functions
candidate_input_identity() {
    /usr/bin/env -i PATH=/usr/bin:/bin:/usr/sbin:/sbin HOME=/var/empty LANG=en_US.UTF-8 LC_ALL=en_US.UTF-8 \
        /usr/bin/ruby /dev/fd/3 "$@" 3<<'RUBY'
require 'digest'
require 'json'
require 'open3'

def identity(value)
  [value.dev, value.ino, value.uid, value.gid, value.mode, value.nlink,
   value.size, value.mtime.to_i * 1_000_000_000 + value.mtime.nsec,
   value.ctime.to_i * 1_000_000_000 + value.ctime.nsec]
end

def pin(path, expected = nil, source = true, allow_empty = false)
  raise unless path.is_a?(String) && path.start_with?('/') && !path.match?(/[\x00-\x1f\x7f]/)
  before = File.lstat(path)
  canonical = File.realpath(path)
  if expected == 'directory0700' || expected == 'directory'
    raise unless canonical == path && before.directory? && (before.mode & 0022).zero? &&
                 (expected != 'directory0700' || (before.uid == Process.uid && (before.mode & 0777) == 0700))
    return { 'path' => path, 'stat' => identity(before) }
  end
  raise unless (!source || canonical == path) && (before.mode & 0022).zero?
  target = File.lstat(canonical)
  raise unless target.file? && target.size.between?(allow_empty ? 0 : 1, 1024 * 1024 * 1024) &&
               (target.mode & 0022).zero? && (!source || target.nlink == 1)
  digest = Digest::SHA256.new
  File.open(canonical, File::RDONLY | File::NOFOLLOW) do |file|
    raise unless identity(file.stat) == identity(target)
    count = 0
    while (bytes = file.read(65_536))
      count += bytes.bytesize; raise if count > target.size
      digest.update(bytes)
    end
    raise unless identity(file.stat) == identity(target)
  end
  raise unless File.realpath(path) == canonical && identity(File.lstat(path)) == identity(before) &&
               identity(File.lstat(canonical)) == identity(target)
  raise if expected && digest.hexdigest != expected
  { 'path' => path, 'stat' => identity(before), 'canonical' => canonical,
    'targetStat' => identity(target), 'sha256' => digest.hexdigest }
end

def command(argv, environment, directory)
  output, error, status = Open3.capture3(environment, *argv, chdir: directory, unsetenv_others: true)
  raise unless status.success? && output.bytesize <= 16 * 1024 * 1024 && error.bytesize <= 65_536
  output
end

begin
  mode = ARGV.shift
  if %w[files artifacts].include?(mode)
    raise unless ARGV.length.even?
    values = ARGV.each_slice(2).map { |path, digest| pin(path, digest.empty? ? nil : digest, true, mode == 'artifacts') }
    print JSON.generate(values)
  elsif mode == 'tree'
    raise unless ARGV.length == 1
    nodes = {}
    walk = lambda do |path|
      raise if nodes.length >= 200
      if File.lstat(path).directory?
        nodes[path] = pin(path, 'directory')
        Dir.children(path).sort.each { |leaf| walk.call(path + '/' + leaf) }
      else
        nodes[path] = pin(path, nil, true, true)
      end
    end
    walk.call(ARGV[0]); print JSON.generate(nodes)
  else
    raise unless mode == 'closure' && ARGV.empty?
    text = STDIN.read(8 * 1024 * 1024 + 1)
    raise if text.bytesize > 8 * 1024 * 1024
    record = JSON.parse(text, max_nesting: 16, create_additions: false)
    request = record.fetch('request'); inputs = record.fetch('inputs')
    developer = request.fetch('developerDirectory')
    environment = { 'PATH' => '/usr/bin:/bin:/usr/sbin:/sbin', 'HOME' => '/var/empty',
      'LC_ALL' => 'en_US.UTF-8', 'LANG' => 'en_US.UTF-8', 'DEVELOPER_DIR' => developer, 'GIT_CONFIG_NOSYSTEM' => '1',
      'GIT_CONFIG_SYSTEM' => '/dev/null', 'GIT_CONFIG_GLOBAL' => '/dev/null',
      'GIT_OPTIONAL_LOCKS' => '0', 'GIT_TERMINAL_PROMPT' => '0' }
    git = inputs.fetch('developerGit').fetch('path')
    git_prefix = [git, '--no-optional-locks', '-c', 'core.fsmonitor=false', '-c', 'core.hooksPath=/dev/null']
    source_files = {}; source_directories = {}
    roots = [
      [request.fetch('productRoot'), request.fetch('productTree'), ['macOS/VirtualAudioDriver']],
      [request.fetch('toolingRoot'), request.fetch('toolingTree'), [
        'macOS/scripts/opensteamer-microphone-receipt-binding.rb',
        'macOS/VirtualAudioDriver/scripts/prepare-production-driver-candidate-v9.sh',
        'macOS/VirtualAudioDriver/scripts/verify-production-driver-package-v9.sh',
        'macOS/VirtualAudioDriver/scripts/beluga-production-driver-plist.py',
        'macOS/VirtualAudioDriver/scripts/parse-installer-signature-v8.sh']]
    ]
    roots.each do |root, tree, paths|
      rows = command(git_prefix + ['-C', root, 'ls-tree', '-r', '-z', tree, '--'] + paths, environment, root).split("\0")
      raise if rows.empty?
      observed = []
      rows.each do |row|
        match = /\A(100644|100755) blob ([0-9a-f]{40})\t([^\x00-\x1f\x7f]+)\z/.match(row)
        raise unless match
        relative = match[3]; observed << relative
        bytes = command(git_prefix + ['-C', root, 'cat-file', 'blob', match[2]], environment, root)
        node = pin(root + '/' + relative, Digest::SHA256.hexdigest(bytes))
        raise unless (node['stat'][4] & 0777) == (match[1] == '100755' ? 0755 : 0644)
        source_files[node['path']] = node.merge('gitBlob' => match[2])
        directory = File.dirname(node['path'])
        loop do
          source_directories[directory] ||= pin(directory, 'directory')
          break if directory == root
          directory = File.dirname(directory)
        end
      end
      raise if paths.length > 1 && observed.sort != paths.sort
      if paths.length == 1
        %w[scripts/build-driver.sh scripts/verify-driver-bundle.sh Driver/Info.plist Driver/OpensteamerVirtualMicrophone.c src/OpensteamerVirtualAudioCore.c Driver/OpensteamerVirtualMicrophone.exports APPLE_SAMPLE_LICENSE.txt Resources/en.lproj/Localizable.strings].each do |leaf|
          raise unless observed.include?('macOS/VirtualAudioDriver/' + leaf)
        end
        raise unless observed.any? { |path| path.start_with?('macOS/VirtualAudioDriver/include/') }
      end
    end
    tools = inputs.fetch('receiptTools').transform_values { |node| pin(node.fetch('path'), node.fetch('sha256'), false) }
    %w[/usr/bin/ruby /bin/zsh /usr/bin/git /usr/bin/python3 /usr/bin/security /usr/bin/codesign /usr/bin/xcrun /usr/sbin/pkgutil /usr/sbin/spctl /usr/bin/plutil /usr/bin/openssl /usr/bin/ditto /usr/bin/install /usr/bin/shasum /usr/bin/awk /usr/bin/find /usr/bin/stat /usr/bin/sort /usr/bin/cmp /bin/mkdir /bin/chmod /bin/rm /bin/ln /usr/bin/mktemp /usr/bin/id /usr/bin/printf /usr/bin/nm /usr/bin/lipo /usr/bin/otool /usr/bin/vtool].each do |path|
      tools[path] ||= pin(path, nil, false)
    end
    %w[clang lipo python3 pkgbuild productsign notarytool stapler].each do |name|
      path = command(['/usr/bin/xcrun', '--find', name], environment, request.fetch('productRoot'))
      raise unless path.end_with?("\n") && path.count("\n") == 1
      path = path.chomp
      tools[path] ||= pin(path, nil, false)
    end
    print JSON.generate({ 'schema' => 'opensteamer.production-driver-inputs.v9',
      'sources' => source_files.sort.to_h, 'directories' => source_directories.sort.to_h,
      'tools' => tools.sort.to_h })
  end
rescue StandardError
  warn 'candidate source/tool identity refused (details redacted)'
  exit 65
end
RUBY
}

invoke_receipt_binding() {
    /usr/bin/env -i PATH=/usr/bin:/bin:/usr/sbin:/sbin HOME=/var/empty LANG=en_US.UTF-8 LC_ALL=en_US.UTF-8 \
        /usr/bin/ruby "$binding_adapter" --request "$binding_request" --request-sha256 "$binding_request_sha256"
}

revalidate_candidate_inputs() {
    local fresh_record fresh_boundary fresh_closure
    fresh_boundary="$(candidate_input_identity files "${entry_boundary_files[@]}")" || \
        fail "candidate entry input identity changed"
    [[ "$fresh_boundary" == "$entry_boundary" ]] || fail "candidate entry input identity changed"
    fresh_record="$(invoke_receipt_binding)" || fail "mandatory microphone receipt binding refused"
    [[ "$fresh_record" == "$binding_record" ]] || fail "microphone receipt binding changed during preparation"
    fresh_closure="$(candidate_input_identity closure <<< "$fresh_record")" || fail "candidate source/tool closure changed"
    [[ "$fresh_closure" == "$candidate_closure" ]] || fail "candidate source/tool closure changed"
    [[ "$(candidate_input_identity files "${entry_boundary_files[@]}")" == "$entry_boundary" ]] || \
        fail "candidate entry input identity changed during revalidation"
}
# END v9 receipt and input boundary functions

# Production has no self-test/skip/executor CLI. The offline harness sources only
# the function section above, never this six-argument preparation path.
(( $# == 6 )) || usage
output_root="$1"
app_certificate_sha1="${2:u}"
installer_certificate_sha1="${3:u}"
notary_profile="$4"
binding_request="$5"
binding_request_sha256="$6"
(( EUID != 0 && UID != 0 && EUID == UID )) || fail "candidate preparation requires an unelevated caller"
for candidate_environment_name in ${(k)parameters}; do
    if [[ "${(tP)candidate_environment_name}" == *export* ]] &&
        [[ "$candidate_environment_name" == RUBY* || "$candidate_environment_name" == GEM_* ||
           "$candidate_environment_name" == BUNDLE_* || "$candidate_environment_name" == GIT_* ||
           "$candidate_environment_name" == DYLD_* || "$candidate_environment_name" == PYTHON* ||
           "$candidate_environment_name" == LD_PRELOAD || "$candidate_environment_name" == LD_LIBRARY_PATH ]]; then
        fail "inherited interpreter, loader or Git overrides are forbidden"
    fi
done
export PATH=/usr/bin:/bin:/usr/sbin:/sbin
[[ "$binding_request" == /* ]] && [[ "${binding_request:A}" == "$binding_request" ]] &&
    [[ "$binding_request_sha256" =~ '^[0-9a-f]{64}$' ]] || fail "mandatory binding request path or independent SHA-256 is malformed"
[[ "$output_root" == /* ]] && [[ "${output_root:t}" == "production-driver-v9" ]] || \
    fail "output root must be an absolute path ending in production-driver-v9"
[[ ! -e "$output_root" ]] && [[ ! -L "$output_root" ]] || \
    fail "refusing to overwrite production driver output root"
output_parent="${output_root:h}"
[[ -d "$output_parent" ]] && [[ ! -L "$output_parent" ]] || \
    fail "production driver output parent must be an existing non-symlink directory"
[[ "${output_parent:A}" == "$output_parent" ]] || \
    fail "production driver output parent must be canonical"
output_parent_owner_mode="$(/usr/bin/stat -f '%u:%Lp' "$output_parent")" || \
    fail "unable to inspect production driver output parent"
[[ "$output_parent_owner_mode" == "$(/usr/bin/id -u):700" ]] || \
    fail "production driver output parent must be current-user-owned mode 0700"
output_parent_identity="$(/usr/bin/stat -f '%d:%i:%u:%Lp' "$output_parent")" || \
    fail "unable to bind production driver output parent"
[[ "$app_certificate_sha1" =~ '^[0-9A-F]{40}$' ]] || \
    fail "Developer ID Application SHA-1 is malformed"
[[ "$installer_certificate_sha1" =~ '^[0-9A-F]{40}$' ]] || \
    fail "Developer ID Installer SHA-1 is malformed"
[[ "$notary_profile" =~ '^[A-Za-z0-9._-]{1,128}$' ]] || \
    fail "notary keychain profile name is malformed"

script_dir="${0:A:h}"
tooling_repo="${script_dir:h:h:h}"
binding_adapter="$tooling_repo/macOS/scripts/opensteamer-microphone-receipt-binding.rb"
production_verifier="$script_dir/verify-production-driver-package-v9.sh"
plist_helper="$script_dir/beluga-production-driver-plist.py"
installer_signature_parser="$script_dir/parse-installer-signature-v8.sh"
# Independently reviewed helper pins are checked before executing the adapter.
entry_boundary_files=(
    "$script_path" ""
    "$binding_request" "$binding_request_sha256"
    "${binding_request:h}" "directory0700"
    "$binding_adapter" "c8736c354f54b8ca782bbdf68be6183623a6e3252d76499c65950d1547dd1090"
    "$production_verifier" "3a8d420ec2428b22832d8cfc54315fa9e1adcc3dce5ff8cbb2d6f3c5f71acf90"
    "$plist_helper" "d449934961077b74a7c307d69fd92eddcc0c202c3fc441919efd5c37e498ea94"
    "$installer_signature_parser" "25293a4c83b5c6a6e1c95a95388d596f56057e5c5a54add0756017cfc6b0deac"
)
entry_boundary="$(candidate_input_identity files "${entry_boundary_files[@]}")" || fail "candidate entry input identity refused"
binding_record="$(invoke_receipt_binding)" || fail "mandatory microphone receipt binding refused"
[[ "$(candidate_input_identity files "${entry_boundary_files[@]}")" == "$entry_boundary" ]] || \
    fail "candidate entry input identity changed during binding"
binding_summary="$(/usr/bin/env -i PATH=/usr/bin:/bin:/usr/sbin:/sbin HOME=/var/empty LANG=en_US.UTF-8 LC_ALL=en_US.UTF-8 \
    /usr/bin/ruby /dev/fd/3 "$script_path" 3<<'RUBY' <<< "$binding_record"
require 'json'
require 'etc'
begin
  text = STDIN.read(8 * 1024 * 1024 + 1); raise if text.bytesize > 8 * 1024 * 1024
  value = JSON.parse(text, max_nesting: 16, create_additions: false)
  raise unless value['schema'] == 'opensteamer.microphone-receipt-binding.unprivileged.v1' &&
               value['scope'] == 'unprivileged-original-product-cli-source-preflight-only' &&
               value['deploymentAuthority'] == false && value['callerUid'] == Process.uid
  request = value.fetch('request'); inputs = value.fetch('inputs')
  raise unless Process.uid != 0 && Process.uid == Process.euid &&
               request['callerUid'] == Process.uid &&
               ARGV[0] == request['toolingRoot'] + '/macOS/VirtualAudioDriver/scripts/prepare-production-driver-candidate-v9.sh'
  %w[product tooling].each do |prefix|
    node = inputs.fetch(prefix)
    raise unless node['path'] == request[prefix + 'Root'] &&
                 node['commit'] == request[prefix + 'Commit'] && node['tree'] == request[prefix + 'Tree']
  end
  fields = %w[productRoot toolingRoot productCommit productTree toolingCommit toolingTree developerDirectory receiptSha256].map { |key| request.fetch(key) }
  fields << Etc.getpwuid(Process.uid).dir
  raise unless fields.all? { |item| item.is_a?(String) && !item.empty? && !item.match?(/[\x00-\x1f\x7f]/) }
  puts fields
rescue StandardError
  warn 'successful binding record has no safe candidate source identity (details redacted)'
  exit 65
end
RUBY
)" || fail "successful microphone binding record is not exact"
binding_fields=("${(@f)binding_summary}")
(( ${#binding_fields} == 9 )) || fail "microphone binding source identity is incomplete"
repo="$binding_fields[1]"
[[ "$binding_fields[2]" == "$tooling_repo" ]] || fail "bound tooling root differs from this producer"
source_commit="$binding_fields[3]"
source_tree="$binding_fields[4]"
tooling_commit="$binding_fields[5]"
tooling_tree="$binding_fields[6]"
developer_dir="$binding_fields[7]"
receipt_sha256="$binding_fields[8]"
candidate_home="$binding_fields[9]"
local_builder="$repo/macOS/VirtualAudioDriver/scripts/build-driver.sh"
local_verifier="$repo/macOS/VirtualAudioDriver/scripts/verify-driver-bundle.sh"
export DEVELOPER_DIR="$developer_dir"
candidate_closure="$(candidate_input_identity closure <<< "$binding_record")" || fail "candidate source/tool closure refused"

build_root=""
build_root_identity=""
candidate_run() {
    local candidate_working_directory="$repo"
    if [[ -n "${build_root:-}" ]]; then
        [[ -d "$build_root" ]] && [[ ! -L "$build_root" ]] && [[ "${build_root:A}" == "$build_root" ]] &&
            [[ "$(/usr/bin/stat -f '%d:%i:%u:%Lp' "$build_root")" == "$build_root_identity" ]] || \
            fail "private build root identity changed"
        candidate_working_directory="$build_root"
    fi
    [[ -d "$candidate_working_directory" ]] && [[ ! -L "$candidate_working_directory" ]] &&
        [[ "${candidate_working_directory:A}" == "$candidate_working_directory" ]] || fail "candidate working directory is unsafe"
    (
        builtin cd -- "$candidate_working_directory" || exit 65
        /usr/bin/env -i PATH=/usr/bin:/bin:/usr/sbin:/sbin HOME="$candidate_home" ZDOTDIR=/var/empty LANG=en_US.UTF-8 LC_ALL=en_US.UTF-8 \
            DEVELOPER_DIR="$developer_dir" "$@"
    )
}
candidate_git() {
    candidate_run /usr/bin/git -c core.fsmonitor=false -c core.hooksPath=/dev/null \
        -c core.untrackedCache=false -c core.ignoreStat=false "$@"
}
for candidate_repo in "$repo" "$tooling_repo"; do
    candidate_branch="$(candidate_git -C "$candidate_repo" symbolic-ref --quiet --short HEAD)" || \
        fail "candidate sources must be on named branches"
    candidate_remote="$(candidate_git -C "$candidate_repo" config --get remote.origin.url)"
    [[ "$candidate_remote" == "https://github.com/ahmedelami/opensteamer.git" ]] || fail "candidate source remote is not exact"
    candidate_remote_commit="$(candidate_git -C "$candidate_repo" ls-remote --exit-code origin "refs/heads/$candidate_branch" | /usr/bin/awk 'NF == 2 { print $1}')" || \
        fail "unable to prove candidate source pushed"
    if [[ "$candidate_repo" == "$repo" ]]; then
        [[ "$candidate_remote_commit" == "$source_commit" ]] || fail "product source commit is not the exact pushed branch tip"
        source_branch="$candidate_branch"; remote_url="$candidate_remote"
    else
        [[ "$candidate_remote_commit" == "$tooling_commit" ]] || fail "tooling source commit is not the exact pushed branch tip"
        tooling_branch="$candidate_branch"
    fi
done
for tool in "$local_builder" "$local_verifier" "$production_verifier" "$installer_signature_parser"; do
    [[ -f "$tool" ]] && [[ ! -L "$tool" ]] && [[ -x "$tool" ]] || fail "required driver tool is unavailable"
done
revalidate_candidate_inputs

identity_output="$(candidate_run /usr/bin/security find-identity -v 2>/dev/null)" || \
    fail "unable to enumerate signing identities"
app_matches="$(/usr/bin/awk -v hash="$app_certificate_sha1" '
    index($0, hash) && index($0, "Developer ID Application:") && index($0, "(MSMG8CJLB3)") { count++ }
    END { print count + 0 }
' <<< "$identity_output")"
installer_matches="$(/usr/bin/awk -v hash="$installer_certificate_sha1" '
    index($0, hash) && index($0, "Developer ID Installer:") && index($0, "(MSMG8CJLB3)") { count++ }
    END { print count + 0 }
' <<< "$identity_output")"
[[ "$app_matches" == "1" ]] || fail "exact Developer ID Application identity is unavailable"
[[ "$installer_matches" == "1" ]] || fail "exact Developer ID Installer identity is unavailable"

[[ -d "$developer_dir" ]] && [[ ! -L "$developer_dir" ]] || \
    fail "bound Xcode developer directory is unavailable"
candidate_run /usr/bin/xcrun notarytool history \
    --keychain-profile "$notary_profile" --output-format json >/dev/null || \
    fail "notarytool keychain profile is unavailable or unauthorized"

build_root=""
staging_root=""
build_root="$(/usr/bin/mktemp -d /private/tmp/opensteamer-production-driver-v9.XXXXXX)"
case "$build_root" in
    /private/tmp/opensteamer-production-driver-v9.*) ;;
    *) fail "unsafe production driver build root" ;;
esac
build_root_identity="$(/usr/bin/stat -f '%d:%i:%u:%Lp' "$build_root")" || fail "unable to bind private build root"
[[ "$(/usr/bin/stat -f '%u:%Lp' "$build_root")" == "$UID:700" ]] || fail "private build root is not caller-owned mode 0700"
cleanup() {
    if [[ -d "$build_root" ]] && [[ ! -L "$build_root" ]]; then
        /bin/rm -rf -- "$build_root"
    fi
    if [[ -n "$staging_root" ]] && [[ -d "$staging_root" ]] && [[ ! -L "$staging_root" ]]; then
        case "$staging_root" in
            "$output_parent"/.production-driver-v9.stage.*)
                /bin/chmod 0700 "$staging_root"
                /bin/rm -rf -- "$staging_root"
                ;;
            *)
                print -u2 "refusing to clean unrecognized production driver staging root"
                ;;
        esac
    fi
}
trap cleanup EXIT INT TERM HUP

local_output="$build_root/local"
/bin/mkdir -m 0755 "$local_output"
build_invocation="$build_root/build-invocation.json"
build_stdout="$build_root/build-stdout.txt"
build_stderr="$build_root/build-stderr.txt"
/usr/bin/env -i PATH=/usr/bin:/bin:/usr/sbin:/sbin HOME=/var/empty LANG=en_US.UTF-8 LC_ALL=en_US.UTF-8 \
    /usr/bin/ruby -rjson -e 'puts JSON.generate({schema: "opensteamer.driver-build-invocation.v9", argv: [ARGV[0],ARGV[1]], cwd: ARGV[4], environment: {PATH: "/usr/bin:/bin:/usr/sbin:/sbin", HOME: ARGV[2], ZDOTDIR: "/var/empty", LC_ALL: "en_US.UTF-8", LANG: "en_US.UTF-8", DEVELOPER_DIR: ARGV[3]}, stdout: "build-stdout.txt", stderr: "build-stderr.txt"})' \
    "$local_builder" "$local_output/OpensteamerVirtualMicrophone.driver" "$candidate_home" "$developer_dir" "$build_root" >"$build_invocation"
candidate_run "$local_builder" "$local_output/OpensteamerVirtualMicrophone.driver" >"$build_stdout" 2>"$build_stderr" || \
    fail "bound product driver build failed"
local_bundle="$(<"$build_stdout")"
[[ "$local_bundle" == "$local_output/OpensteamerVirtualMicrophone.driver" ]] || \
    fail "local driver builder returned an unexpected path"
candidate_run "$local_verifier" "$local_bundle" >"$build_root/local-verification.txt"
revalidate_candidate_inputs

production_bundle="$build_root/OpensteamerVirtualMicrophone.driver"
/usr/bin/ditto --noqtn "$local_bundle" "$production_bundle"
candidate_run /usr/bin/codesign --force \
    --sign "$app_certificate_sha1" \
    --identifier com.elamin.opensteamer.VirtualMicrophoneDriver \
    --options runtime \
    --timestamp \
    "$production_bundle" >/dev/null

payload_root="$build_root/payload-root"
payload_driver="$payload_root/Library/Audio/Plug-Ins/HAL/OpensteamerVirtualMicrophone.driver"
/bin/mkdir -p "${payload_driver:h}"
/usr/bin/ditto --noqtn "$production_bundle" "$payload_driver"

unsigned_package="$build_root/OpensteamerVirtualMicrophone-v9.unsigned.pkg"
signed_package="$build_root/OpensteamerVirtualMicrophone-v9.pkg"
candidate_run /usr/bin/xcrun pkgbuild \
    --root "$payload_root" \
    --install-location / \
    --identifier com.elamin.opensteamer.VirtualMicrophoneDriver.pkg \
    --version 0.1.0 \
    --ownership recommended \
    "$unsigned_package" >/dev/null
candidate_run /usr/bin/xcrun productsign \
    --sign "$installer_certificate_sha1" \
    --timestamp \
    "$unsigned_package" "$signed_package" >/dev/null

notary_record="$build_root/notary-result.json"
candidate_run /usr/bin/xcrun notarytool submit "$signed_package" \
    --keychain-profile "$notary_profile" \
    --wait --output-format json >"$notary_record"
/usr/bin/python3 -I -S -B - "$notary_record" <<'PY' || fail "notary service did not accept the production driver package"
import json
import sys

with open(sys.argv[1], "r", encoding="utf-8") as stream:
    value = json.load(stream)
if value.get("status") != "Accepted":
    raise SystemExit("notarization status is not Accepted")
submission_id = value.get("id")
if not isinstance(submission_id, str) or len(submission_id) != 36:
    raise SystemExit("notarization submission identifier is malformed")
PY
candidate_run /usr/bin/xcrun stapler staple -v "$signed_package" >/dev/null
candidate_run /usr/bin/xcrun stapler validate -v "$signed_package" >/dev/null

expected_regular_files=(
    "Contents/Info.plist"
    "Contents/MacOS/OpensteamerVirtualMicrophone"
    "Contents/Resources/APPLE_SAMPLE_LICENSE.txt"
    "Contents/Resources/en.lproj/Localizable.strings"
    "Contents/_CodeSignature/CodeResources"
)
bundle_tree_sha256() {
    local bundle="$1"
    {
        while IFS= read -r -d '' relative; do
            if [[ "$relative" == "." ]]; then
                display="."
                absolute="$bundle"
            else
                display="${relative#./}"
                absolute="$bundle/$display"
            fi
            /usr/bin/printf '%s|%s\0' \
                "$(/usr/bin/stat -f '%HT|%Lp' "$absolute")" "$display"
        done < <(cd "$bundle" && /usr/bin/find -s . -print0)
        for relative in "${expected_regular_files[@]}"; do
            digest="$(/usr/bin/shasum -a 256 "$bundle/$relative" | /usr/bin/awk '{print $1}')"
            /usr/bin/printf '%s\0%s\0' "$relative" "$digest"
        done
    } | /usr/bin/shasum -a 256 | /usr/bin/awk '{print $1}'
}

actual_tree_sha256="$(bundle_tree_sha256 "$production_bundle")"
actual_executable_sha256="$(/usr/bin/shasum -a 256 "$production_bundle/Contents/MacOS/OpensteamerVirtualMicrophone" | /usr/bin/awk '{print $1}')"
actual_package_sha256="$(/usr/bin/shasum -a 256 "$signed_package" | /usr/bin/awk '{print $1}')"

package_signature_path="$build_root/package-signature.txt"
/usr/sbin/pkgutil --check-signature "$signed_package" >"$package_signature_path" 2>&1 || \
    fail "unable to inspect candidate installer signature"
installer_leaf_sha256="$(candidate_run "$installer_signature_parser" "$package_signature_path" MSMG8CJLB3)"
[[ "$installer_leaf_sha256" =~ '^[0-9A-F]{64}$' ]] || \
    fail "candidate installer leaf SHA-256 could not be extracted"

prepublication_verification="$build_root/verification.txt"
candidate_run "$production_verifier" \
    "$production_bundle" \
    "$signed_package" \
    "$app_certificate_sha1" \
    "$installer_leaf_sha256" \
    "$actual_tree_sha256" \
    "$actual_executable_sha256" \
    "$actual_package_sha256" \
    >"$prepublication_verification"
[[ -s "$prepublication_verification" ]] && [[ ! -L "$prepublication_verification" ]] || \
    fail "production driver verifier did not emit exact evidence"

notary_submission_id="$(/usr/bin/python3 -I -S -B -c 'import json,sys; print(json.load(open(sys.argv[1], encoding="utf-8"))["id"])' "$notary_record")"
[[ "$notary_submission_id" =~ '^[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}$' ]] || \
    fail "notary submission identifier is not exact"
binding_record_path="$build_root/microphone-binding.json"
candidate_inputs_path="$build_root/candidate-inputs.json"
candidate_entry_path="$build_root/candidate-entry-inputs.json"
print -r -- "$binding_record" >"$binding_record_path"
print -r -- "$candidate_closure" >"$candidate_inputs_path"
print -r -- "$entry_boundary" >"$candidate_entry_path"
manifest="$build_root/candidate-manifest.txt"
{
    print -r -- "schema=opensteamer.production-driver-candidate.v9"
    print -r -- "source_commit=$source_commit"
    print -r -- "source_tree=$source_tree"
    print -r -- "product_root=$repo"
    print -r -- "tooling_root=$tooling_repo"
    print -r -- "tooling_commit=$tooling_commit"
    print -r -- "tooling_tree=$tooling_tree"
    print -r -- "tooling_branch=$tooling_branch"
    print -r -- "microphone_receipt_sha256=$receipt_sha256"
    print -r -- "binding_request_path=$binding_request"
    print -r -- "binding_request_sha256=$binding_request_sha256"
    for provenance in "$binding_record_path" "$candidate_inputs_path" "$candidate_entry_path" "$build_invocation" "$build_stdout" "$build_stderr"; do
        print -r -- "${provenance:t}_sha256=$(/usr/bin/shasum -a 256 "$provenance" | /usr/bin/awk '{print $1}')"
    done
    print -r -- "source_branch=$source_branch"
    print -r -- "remote=$remote_url"
    print -r -- "developer_id_application_sha1=$app_certificate_sha1"
    print -r -- "developer_id_installer_identity_sha1=$installer_certificate_sha1"
    print -r -- "developer_id_installer_leaf_sha256=$installer_leaf_sha256"
    print -r -- "bundle_tree_sha256=$actual_tree_sha256"
    print -r -- "executable_sha256=$actual_executable_sha256"
    print -r -- "package_sha256=$actual_package_sha256"
    print -r -- "notary_submission_id=$notary_submission_id"
} >"$manifest"

provenance_files=("$manifest" "" "$notary_record" "" "$prepublication_verification" "" "$binding_record_path" ""
    "$candidate_inputs_path" "" "$candidate_entry_path" "" "$build_invocation" ""
    "$build_stdout" "" "$build_stderr" "")
provenance_identity="$(candidate_input_identity artifacts "${provenance_files[@]}")" || fail "candidate provenance identity refused"
revalidate_candidate_inputs
staging_root="$(/usr/bin/mktemp -d "$output_parent/.production-driver-v9.stage.XXXXXX")" || \
    fail "unable to create same-filesystem production driver staging root"
case "$staging_root" in
    "$output_parent"/.production-driver-v9.stage.*) ;;
    *) fail "unsafe production driver staging root" ;;
esac
[[ -d "$staging_root" ]] && [[ ! -L "$staging_root" ]] && \
    [[ "$(/usr/bin/stat -f '%u:%Lp' "$staging_root")" == "$(/usr/bin/id -u):700" ]] || \
    fail "production driver staging root identity is not exact"
[[ "$(/usr/bin/stat -f '%d:%i:%u:%Lp' "$output_parent")" == "$output_parent_identity" ]] || \
    fail "production driver output parent changed before staging"

final_bundle="$staging_root/OpensteamerVirtualMicrophone.driver"
final_package="$staging_root/OpensteamerVirtualMicrophone-v9.pkg"
final_notary_record="$staging_root/notary-result.json"
final_manifest="$staging_root/candidate-manifest.txt"
final_verification="$staging_root/verification.txt"
/usr/bin/ditto --noqtn "$production_bundle" "$final_bundle"
/usr/bin/install -m 0600 "$signed_package" "$final_package"
/usr/bin/install -m 0400 "$notary_record" "$final_notary_record"
/usr/bin/install -m 0400 "$manifest" "$final_manifest"
for provenance in "$binding_record_path" "$candidate_inputs_path" "$candidate_entry_path" "$build_invocation" "$build_stdout" "$build_stderr" "$binding_request"; do
    if [[ "$provenance" == "$binding_request" ]]; then
        destination="$staging_root/binding-request.json"
    else
        destination="$staging_root/${provenance:t}"
    fi
    /usr/bin/install -m 0400 "$provenance" "$destination"
    /usr/bin/cmp -s "$provenance" "$destination" || fail "staged candidate provenance differs from its validated source"
done

[[ "$(bundle_tree_sha256 "$final_bundle")" == "$actual_tree_sha256" ]] || \
    fail "staged production driver tree differs from its verified source"
[[ "$(/usr/bin/shasum -a 256 "$final_bundle/Contents/MacOS/OpensteamerVirtualMicrophone" | /usr/bin/awk '{print $1}')" == "$actual_executable_sha256" ]] || \
    fail "staged production driver executable differs from its verified source"
[[ "$(/usr/bin/shasum -a 256 "$final_package" | /usr/bin/awk '{print $1}')" == "$actual_package_sha256" ]] || \
    fail "staged production driver package differs from its verified source"
/usr/bin/cmp -s "$notary_record" "$final_notary_record" || \
    fail "staged notary record differs from its accepted source"
/usr/bin/cmp -s "$manifest" "$final_manifest" || \
    fail "staged candidate manifest differs from its validated source"

candidate_run "$production_verifier" \
    "$final_bundle" \
    "$final_package" \
    "$app_certificate_sha1" \
    "$installer_leaf_sha256" \
    "$actual_tree_sha256" \
    "$actual_executable_sha256" \
    "$actual_package_sha256" \
    >"$final_verification"
/usr/bin/cmp -s "$prepublication_verification" "$final_verification" || \
    fail "staged production driver verification evidence is not reproducible"
/bin/chmod 0400 "$final_verification"

expected_top_level="$(
    print -r -l -- \
        "./OpensteamerVirtualMicrophone.driver" \
        "./OpensteamerVirtualMicrophone-v9.pkg" \
        "./candidate-manifest.txt" \
        "./microphone-binding.json" \
        "./binding-request.json" \
        "./candidate-inputs.json" \
        "./candidate-entry-inputs.json" \
        "./build-invocation.json" \
        "./build-stdout.txt" \
        "./build-stderr.txt" \
        "./notary-result.json" \
        "./verification.txt" | /usr/bin/sort
)"
actual_top_level="$(cd "$staging_root" && /usr/bin/find -s . -mindepth 1 -maxdepth 1 -print | /usr/bin/sort)"
[[ "$actual_top_level" == "$expected_top_level" ]] || \
    fail "production driver staging root contains unexpected top-level nodes"
/bin/chmod 0500 "$staging_root"

staging_identity="$(/usr/bin/stat -f '%d:%i:%u:%Lp' "$staging_root")" || \
    fail "unable to bind complete production driver staging root"
staging_leaf="${staging_root:t}"
output_leaf="${output_root:t}"
staged_tree_identity="$(candidate_input_identity tree "$staging_root")" || fail "staged candidate identity refused"
revalidate_candidate_inputs
[[ "$(candidate_input_identity artifacts "${provenance_files[@]}")" == "$provenance_identity" ]] || \
    fail "candidate provenance changed before publication"
[[ "$(candidate_input_identity tree "$staging_root")" == "$staged_tree_identity" ]] || \
    fail "staged candidate changed during final receipt verification"
[[ "$(bundle_tree_sha256 "$final_bundle")" == "$actual_tree_sha256" ]] &&
    [[ "$(/usr/bin/shasum -a 256 "$final_package" | /usr/bin/awk '{print $1}')" == "$actual_package_sha256" ]] || \
    fail "staged production artifacts changed before publication"
[[ "$(cd "$staging_root" && /usr/bin/find -s . -mindepth 1 -maxdepth 1 -print | /usr/bin/sort)" == "$expected_top_level" ]] || \
    fail "staged candidate top-level inventory changed before publication"
for provenance in "$notary_record" "$manifest" "$binding_record_path" "$candidate_inputs_path" "$candidate_entry_path" "$build_invocation" "$build_stdout" "$build_stderr" "$binding_request" "$prepublication_verification"; do
    case "$provenance" in
        "$binding_request") destination="$staging_root/binding-request.json" ;;
        "$prepublication_verification") destination="$final_verification" ;;
        *) destination="$staging_root/${provenance:t}" ;;
    esac
    /usr/bin/cmp -s "$provenance" "$destination" || fail "staged candidate provenance changed before publication"
done
atomic_publish_candidate \
    "$output_parent" \
    "$staging_leaf" \
    "$output_leaf" \
    "$output_parent_identity" \
    "$staging_identity" || fail "atomic no-clobber production driver publication failed"
staging_root=""
[[ -d "$output_root" ]] && [[ ! -L "$output_root" ]] && \
    [[ "$(/usr/bin/stat -f '%d:%i:%u:%Lp' "$output_root")" == "$staging_identity" ]] || \
    fail "published production driver candidate identity is not exact"

print "$output_root"
