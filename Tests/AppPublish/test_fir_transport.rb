# Exercise the installed fir-cli transport with no network or credentials.
require_relative '../../.agents/skills/fir-publish/scripts/fir_cli'

module OfflineFirRequest
  class << self
    attr_accessor :calls
  end
  self.calls = 0
  def execute(_request)
    OfflineFirRequest.calls += 1
    response = Struct.new(:body, :code).new('offline injected server error', 500)
    raise RestClient::InternalServerError.new(response)
  end
end
RestClient::Request.singleton_class.prepend(OfflineFirRequest)

[FIR, FIR::AppUploader.new({}, {}, {}, {})].each do |client|
  settings = client.default_options
  raise 'TLS not enabled' unless settings.dig(:other_base_execute_option, :verify_ssl) == OpenSSL::SSL::VERIFY_PEER
  OfflineFirRequest.calls = 0
  begin
    client.post('https://example.invalid/no-network', {})
    raise 'Expected injected request failure'
  rescue RestClient::InternalServerError
    raise 'Ambiguous write request retried' unless OfflineFirRequest.calls == 1
  end
end
puts 'FIR API and uploader callback: one attempt on failure; TLS verification enabled.'
