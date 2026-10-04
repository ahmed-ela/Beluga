#!/usr/bin/ruby
# frozen_string_literal: true
# Builds one explicitly admitted validation slot. No feed packaging or publication.
require_relative 'build-beluga-mac-client'

if $PROGRAM_NAME == __FILE__
  begin
    options = {}
    names = {
      '--profile PATH' => :profile, '--profile-sha256 SHA256' => :sha256,
      '--slot old|new' => :slot, '--approved-namespace HTTPS_URL' => :namespace,
      '--approved-public-key BASE64' => :public_key,
      '--output EMPTY0700' => :output, '--scratch EMPTY0700' => :scratch,
      '--identity DEVELOPER_ID_SHA1' => :identity
    }
    OptionParser.new do |parser|
      parser.banner = 'ruby build-beluga-update-trial.rb --profile PATH --profile-sha256 SHA256 --slot old|new --approved-namespace HTTPS_URL --approved-public-key BASE64 --output EMPTY0700 --scratch EMPTY0700 --identity SHA1'
      names.each do |flag, key|
        parser.on(flag) do |value|
          BelugaMacClient.require!(!options.key?(key), 'duplicate trial build option')
          options[key] = value
        end
      end
    end.parse!
    BelugaMacClient.require!(ARGV.empty? && options.keys.sort == names.values.sort, 'all trial build options are required')
    binding = BelugaMacClient::AdmittedUpdateTrial.open(options[:profile], options[:sha256],
      slot: options[:slot], approved_namespace: options[:namespace], approved_public_key: options[:public_key])
    build_options = options.select { |key, _| %i[output scratch identity].include?(key) }
    puts JSON.pretty_generate(BelugaMacClient::Builder.build(build_options, trial_binding: binding))
  rescue BelugaMacClient::Refusal, OptionParser::ParseError, SystemCallError, JSON::ParserError => error
    warn "build-beluga-update-trial: #{error.message}"
    exit 1
  end
end
