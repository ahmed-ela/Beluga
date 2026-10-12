#!/usr/bin/ruby
# frozen_string_literal: true
# Trial-only artifact preparation. No production fallback, resume, or publication.
require_relative 'package-beluga-mac-client'

if $PROGRAM_NAME == __FILE__
  begin
    options = {}
    names = {
      '--profile PATH' => :trial_profile, '--profile-sha256 SHA256' => :sha256,
      '--slot old|new' => :slot, '--approved-namespace HTTPS_URL' => :namespace,
      '--approved-public-key BASE64' => :public_key,
      '--app PATH' => :app, '--output EMPTY0700' => :output, '--identity SHA1' => :identity,
      '--notary-profile NAME' => :profile, '--sparkle-tools PATH' => :tools,
      '--keychain-account TRIAL_UUID_ACCOUNT' => :account
    }
    OptionParser.new do |parser|
      parser.banner = 'ruby package-beluga-update-trial.rb --profile PATH --profile-sha256 SHA256 --slot old|new --approved-namespace HTTPS_URL --approved-public-key BASE64 --app APP --output EMPTY0700 --identity SHA1 --notary-profile NAME --sparkle-tools DIRECTORY --keychain-account beluga-update-trial-UUID'
      names.each do |flag, key|
        parser.on(flag) do |value|
          BelugaMacClient.require!(!options.key?(key), 'duplicate trial package option')
          options[key] = value
        end
      end
    end.parse!
    BelugaMacClient.require!(ARGV.empty? && options.keys.sort == names.values.sort, 'all trial package options are required')
    binding = BelugaMacClient::AdmittedUpdateTrial.open(options[:trial_profile], options[:sha256],
      slot: options[:slot], approved_namespace: options[:namespace], approved_public_key: options[:public_key])
    package_options = options.select { |key, _| %i[account app identity output profile tools].include?(key) }
    puts JSON.pretty_generate(BelugaMacClient::Packager.package(package_options, trial_binding: binding))
  rescue BelugaMacClient::Refusal, OptionParser::ParseError, SystemCallError, JSON::ParserError => error
    warn "package-beluga-update-trial: #{error.message}"
    exit 1
  end
end
