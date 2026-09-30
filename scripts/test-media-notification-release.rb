#!/usr/bin/env ruby
# Exercise the production guard's pure parsers with synthetic, non-secret artifacts. No signing,
# device, host, credentials, provisioning registration, archive, or upload operations are invoked.
require 'json'
require 'open3'
require 'fileutils'
require 'tmpdir'
require 'shellwords'

root = File.expand_path('..', __dir__)
wrapper = File.join(root, 'iOS/opensteamer/scripts/archive-upload-side-by-side-testflight.sh')
build = File.read(wrapper).match(/^readonly EXPECTED_BUILD_NUMBER="([1-9][0-9]*)"$/)[1]
scratch = Dir.mktmpdir('beluga-notification-release-tests.', '/Volumes/t7')
File.chmod(0700, scratch)
archive = File.join(scratch, 'fixture.xcarchive')
app = File.join(archive, 'Products/Applications/Beluga.app')
extension = File.join(app, 'PlugIns/MediaNotificationContent.appex')
framework = File.join(app, 'Frameworks/LiveKitWebRTC.framework')
FileUtils.mkdir_p([extension, framework])
{ app => 'Beluga', extension => 'MediaNotificationContent', framework => 'LiveKitWebRTC' }.each do |path, name|
  FileUtils.cp('/usr/bin/true', File.join(path, name))
end
group = 'group.com.elamin.opensteamer.media'
team = 'MSMG8CJLB3'
main_id = 'com.elamin.opensteamer'
extension_id = main_id + '.MediaNotificationContent'

def plist(value)
  output, error, status = Open3.capture3('/usr/bin/plutil', '-convert', 'xml1', '-o', '-', '-',
                                       stdin_data: JSON.generate(value))
  raise "fixture plist conversion failed: #{error}" unless status.success?
  output
end

app_info = { 'CFBundleIdentifier' => main_id, 'CFBundleExecutable' => 'Beluga',
             'CFBundleVersion' => build, 'CFBundleShortVersionString' => '0.1.0', 'BelugaMediaAppGroup' => group }
extension_info = {
  'CFBundleIdentifier' => extension_id, 'CFBundleExecutable' => 'MediaNotificationContent',
  'CFBundlePackageType' => 'XPC!', 'CFBundleVersion' => build, 'CFBundleShortVersionString' => '0.1.0',
  'BelugaMediaAppGroup' => group,
  'NSExtension' => {
    'NSExtensionPointIdentifier' => 'com.apple.usernotifications.content-extension',
    'NSExtensionPrincipalClass' => 'MediaNotificationContent.NotificationViewController',
    'NSExtensionAttributes' => {
      'UNNotificationExtensionCategory' => 'BelugaMediaControls',
      'UNNotificationExtensionUserInteractionEnabled' => true,
      'UNNotificationExtensionDefaultContentHidden' => true
    }
  }
}
File.write(File.join(app, 'Info.plist'), plist(app_info))
File.write(File.join(extension, 'Info.plist'), plist(extension_info))
File.write(File.join(framework, 'Info.plist'), plist({ 'CFBundleIdentifier' => 'io.livekit.LiveKitWebRTC',
                                                    'CFBundleExecutable' => 'LiveKitWebRTC' }))
checks = 0
run = lambda do |name, expression, expected|
  command = 'source <(/usr/bin/sed \'/^verify_static_contract$/,$d\' "$WRAPPER_PATH"); ' \
            'trap - EXIT ZERR HUP INT QUIT TERM; ' + expression
  output, error, status = Open3.capture3({ 'WRAPPER_PATH' => wrapper }, '/bin/zsh', '-c', command)
  raise "#{name}: expected #{expected}, got #{status.exitstatus}: #{output} #{error}" unless status.success? == expected
  checks += 1
end
manifest = 'verify_reviewed_archive_product_manifest ' + Shellwords.escape(archive)
run.call('exact three-code payload', manifest, true)
[
  ['wrong bundle', ['CFBundleIdentifier'], main_id],
  ['wrong executable', ['CFBundleExecutable'], 'Other'],
  ['wrong version', ['CFBundleVersion'], (build.to_i + 1).to_s],
  ['wrong group', ['BelugaMediaAppGroup'], 'group.org.example.AudioStreamer.dev.media'],
  ['wrong category', ['NSExtension', 'NSExtensionAttributes', 'UNNotificationExtensionCategory'], 'Other'],
  ['wrong entry', ['NSExtension', 'NSExtensionPrincipalClass'], 'Other.Entry'],
  ['inactive controls', ['NSExtension', 'NSExtensionAttributes', 'UNNotificationExtensionUserInteractionEnabled'], false]
].each do |name, keys, value|
  mutated = Marshal.load(Marshal.dump(extension_info))
  destination = keys[0...-1].inject(mutated) { |item, key| item.fetch(key) }
  destination[keys.last] = value
  File.write(File.join(extension, 'Info.plist'), plist(mutated))
  run.call(name, manifest, false)
end
File.write(File.join(extension, 'Info.plist'), plist(extension_info))
%w[Other.appex Other.bundle Other.app Other.framework Other.xpc].each do |name|
  path = File.join(app, name)
  Dir.mkdir(path)
  run.call('unreviewed ' + name, manifest, false)
  Dir.rmdir(path)
end
%w[helper unexpected.dylib].each do |name|
  path = File.join(app, name)
  FileUtils.cp('/usr/bin/true', path)
  run.call('unreviewed code ' + name, manifest, false)
  File.unlink(path)
end
link = File.join(app, 'unexpected-link')
File.symlink('Info.plist', link)
run.call('symlink', manifest, false)
File.unlink(link)
run.call('restored exact payload', manifest, true)

load_commands_path = File.join(scratch, 'load-commands.txt')
framework_name = '/System/Library/Frameworks/UserNotificationsUI.framework/UserNotificationsUI'
strong_load = "Load command 0\n          cmd LC_LOAD_DYLIB\n      cmdsize 112\n         name #{framework_name} (offset 24)\n"
expression = 'verify_media_notification_framework_load_commands "$(<' + Shellwords.escape(load_commands_path) + ')"'
[
  ['normal strong framework load', strong_load, true],
  ['no framework load', '', false],
  ['wrong framework name', strong_load.sub('UserNotificationsUI.framework', 'UserNotifications.framework'), false],
  ['weak framework load', strong_load.sub('LC_LOAD_DYLIB', 'LC_LOAD_WEAK_DYLIB'), false],
  ['reexport is not a direct strong load', strong_load.sub('LC_LOAD_DYLIB', 'LC_REEXPORT_DYLIB'), false],
  ['duplicate framework load', strong_load + strong_load, false],
  ['malformed framework name record', strong_load.sub('(offset 24)', '(offset unknown)'), false]
].each do |name, commands, expected|
  File.write(load_commands_path, commands)
  run.call(name, expression, expected)
end

settings_path = File.join(scratch, 'extension-settings.json')
settings = {
  'ACTION' => 'archive', 'CONFIGURATION' => 'TestFlight', 'PLATFORM_NAME' => 'iphoneos',
  'PRODUCT_TYPE' => 'com.apple.product-type.app-extension', 'PRODUCT_NAME' => 'MediaNotificationContent',
  'EXECUTABLE_NAME' => 'MediaNotificationContent', 'WRAPPER_EXTENSION' => 'appex',
  'PRODUCT_BUNDLE_IDENTIFIER' => extension_id, 'SKIP_INSTALL' => 'YES',
  'APPLICATION_EXTENSION_API_ONLY' => 'YES', 'CODE_SIGN_STYLE' => 'Automatic',
  'CODE_SIGN_ENTITLEMENTS' => 'Sources/Support/MediaNotification.entitlements',
  'INFOPLIST_FILE' => 'MediaNotificationContent/Info.plist', 'BELUGA_MEDIA_APP_GROUP' => group,
  'DEVELOPMENT_TEAM' => team, 'CURRENT_PROJECT_VERSION' => build, 'MARKETING_VERSION' => '0.1.0',
  'CODE_SIGN_IDENTITY' => 'Apple Development'
}
settings_record = { 'target' => 'MediaNotificationContent', 'buildSettings' => settings }
expression = 'verify_media_notification_effective_settings_document ' + Shellwords.escape(settings_path)
File.write(settings_path, JSON.generate([settings_record]))
run.call('exact effective extension settings', expression, true)
settings.keys.each do |key|
  mutated = Marshal.load(Marshal.dump(settings_record))
  mutated.fetch('buildSettings')[key] = 'unreviewed'
  File.write(settings_path, JSON.generate([mutated]))
  run.call('effective extension rejects ' + key, expression, false)
end
[ [], [settings_record, settings_record], [{ 'target' => 'opensteamer', 'buildSettings' => settings }] ].each do |records|
  File.write(settings_path, JSON.generate(records))
  run.call('ambiguous or wrong settings target', expression, false)
end

argument_setup = 'TESTFLIGHT_DERIVED_DATA_DIRECTORY=/isolated/DerivedData; ' \
                 'TESTFLIGHT_XCODEBUILD_PINNED_ARGUMENTS=(-project "$PROJECT_PATH" -scheme "$EXPECTED_SCHEME" ' \
                 '-configuration "$EXPECTED_CONFIGURATION" -sdk iphoneos -derivedDataPath "$TESTFLIGHT_DERIVED_DATA_DIRECTORY" ' \
                 '-onlyUsePackageVersionsFromResolvedFile -skipPackageUpdates); ' \
                 'typeset -a reply=(); media_extension_settings_arguments || exit 1; '
run.call('exact read-only extension command', argument_setup +
         'verify_xcodebuild_action_arguments media-extension-settings "${reply[@]}"', true)
[
  ['wrong target', 'reply[4]=opensteamer; '],
  ['build substitution', 'reply[-3]=build; '],
  ['archive mutation without settings flag', 'reply[-2]=-archivePath; '],
  ['archive mutation appended', 'reply+=(-archivePath /unexpected.xcarchive); '],
  ['wrong configuration', 'reply[6]=Release; '],
  ['non-json output', 'reply[-1]=-verbose; '],
  ['DVT override', 'reply+=(-DVTUnreviewedOverride); ']
].each do |name, mutation|
  run.call(name, argument_setup + mutation +
           'verify_xcodebuild_action_arguments media-extension-settings "${reply[@]}"', false)
end
run.call('unknown extension command mode', argument_setup +
         'verify_xcodebuild_action_arguments extension-build "${reply[@]}"', false)

document_path = File.join(scratch, 'entitlements.plist')
[main_id, extension_id].each do |identifier|
  entitlements = { 'application-identifier' => team + '.' + identifier,
                   'com.apple.developer.team-identifier' => team, 'get-task-allow' => true,
                   'com.apple.security.application-groups' => [group] }
  profile = { 'ApplicationIdentifierPrefix' => [team], 'TeamIdentifier' => [team],
              'Entitlements' => entitlements.merge('keychain-access-groups' => [team + '.*', 'com.apple.token']) }
  [ ['signed', 'verify_media_signed_entitlement_document', entitlements],
    ['provisioning', 'verify_media_provisioning_identity', profile] ].each do |label, function, original|
    expression = function + ' "$(<' + Shellwords.escape(document_path) + ')" ' + Shellwords.escape(team + '.' + identifier)
    File.write(document_path, plist(original))
    run.call(label + ' exact ' + identifier, expression, true)
    [ ['wildcard app', 'application-identifier', team + '.*'],
      ['wrong team', 'com.apple.developer.team-identifier', 'OTHER'],
      ['wrong group', 'com.apple.security.application-groups', ['group.other']],
      ['extra group', 'com.apple.security.application-groups', [group, 'group.other']],
      ['missing group', 'com.apple.security.application-groups', []],
      ['not development archive', 'get-task-allow', false] ].each do |name, key, value|
      mutated = Marshal.load(Marshal.dump(original))
      (label == 'signed' ? mutated : mutated.fetch('Entitlements'))[key] = value
      File.write(document_path, plist(mutated))
      run.call(label + ' rejects ' + name, expression, false)
    end
  end
end
puts "PASS: #{checks} exact notification release checks. Synthetic evidence: #{scratch}"
