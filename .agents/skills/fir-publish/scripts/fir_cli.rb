# Local compatibility wrapper; does not modify the installed fir-cli gem.
# fir-cli 2.0.25 returns nil from default_options when UPLOAD_VERIFY_SSL is set.
ENV['UPLOAD_VERIFY_SSL'] = 'true'
require 'fir'
module KeepUpFirTLS
  def default_options
    settings = super || @default_options || {}
    transport = settings.fetch(:other_base_execute_option, {}).merge(verify_ssl: OpenSSL::SSL::VERIFY_PEER)
    # api_tools counts total attempts, including POST release callbacks.
    settings.merge(retry_times: 1, other_base_execute_option: transport)
  end
end
FIR.singleton_class.prepend(KeepUpFirTLS)
FIR::AppUploader.prepend(KeepUpFirTLS)
load ARGV.shift if $PROGRAM_NAME == __FILE__
