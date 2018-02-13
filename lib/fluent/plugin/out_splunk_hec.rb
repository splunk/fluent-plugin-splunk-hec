require "fluent/plugin/output"

require 'openssl'
require 'net/http/persistent'

module Fluent::Plugin
  class SplunkHecOutput < Fluent::Plugin::Output
    Fluent::Plugin.register_output('splunk_hec', self)

    helpers :formatter

    autoload :VERSION, "fluent/plugin/out_splunk_hec/version"

    desc 'Which protocol to use to call HEC api, "http" or "https", default "https".'
    config_param :protocol, :enum, list: %i[http https], default: :https

    desc 'The hostname/IP of the Splunk instance which has HTTP input enabled, or a HEC load balancer.'
    config_param :hec_host, :string

    desc 'The port number of the HTTP input, or the HEC load balancer.'
    config_param :hec_port, :integer, default: 8088

    desc 'The HEC token.'
    config_param :hec_token, :string

    desc 'SSL configurations.'
    config_section :ssl, param_name: 'ssl', required: false, multi: false, init: true do
      desc "The path to a file containing a PEM-format CA certificate for this client."
      config_param :client_cert, :string, default: nil

      desc 'The path to a file containing a PEM-format CA certificate.'
      config_param :ca_file, :string, default: nil

      desc 'The path to a directory containing CA certificates in PEM format.'
      config_param :ca_path, :string, default: nil

      desc 'List of SSl ciphers allowed.'
      config_param :ciphers, :array, default: nil

      desc "The client's SSL private key."
      config_param :client_pkey, :string, default: nil

      desc "If `insecure` is set to true, it will not verify the server's certificate. If `ca_file` or `ca_path` is set, `insecure` will be ignored."
      config_param :insecure, :bool, default: false
    end

    desc 'The Splunk index indexs events, by default it is not set, and will use what is configured in the HTTP input. Liquid template is supported.'
    config_param :index, :string, default: nil

    desc "Set the host field for events, by default it's the hostname of the machine that runnning fluentd. Liquid template is supported."
    config_param :host, :string, default: nil

    desc "The source will be applied to the events, by default it uses the event's tag. Liquid template is supported."
    config_param :source, :string, default: nil

    desc 'The sourcetype will be applied to the events, by default it is not set, and leave it to Splunk to figure it out. Liquid template is supported.'
    config_param :sourcetype, :string, default: nil

    desc 'Disable Liquid template support. Once disabled, it cannot use Liquid templates in the `host`, `index`, `source`, `sourcetype` fields.'
    config_param :disable_template, :bool, default: false

    # Whether to allow non-UTF-8 characters in user logs. If set to true, any
    # non-UTF-8 character would be replaced by the string specified by
    # 'non_utf8_replacement_string'. If set to false, any non-UTF-8 character
    # would trigger the plugin to error out.
    config_param :coerce_to_utf8, :bool, :default => true

    # If 'coerce_to_utf8' is set to true, any non-UTF-8 character would be
    # replaced by the string specified here.
    config_param :non_utf8_replacement_string, :string, :default => ' '
    
    config_section :format do
      # the format section defined in formatter plugin help requires init.
      # just defined a useless formatter as a placeholder.
      config_param :@type, :string, default: 'nil'
    end

    def initialize
      super
      @default_host = Socket.gethostname
      @chunk_queue = SizedQueue.new 1
    end

    def configure(conf)
      super
      prepare_templates
      construct_api

      @formatter = formatter_create
      @formatter = nil if @formatter.is_a?(::Fluent::Plugin::NilFormatter)
    end

    def start
      super
      start_worker_threads
    end

    def format(tag, time, record)
      values = {
	'tag' => tag,
	'record' => record
      }
      event = @formatter ? @formatter.format(tag, time, record) : record

      {
	host: @host ? @host.render(values) : @default_host,
	source: @source ? @source.render(values) : tag,
        event: convert_to_utf8(event),
	time: time.to_i
      }.tap { |payload|
	payload.update sourcetype: @sourcetype.render(values) if @sourcetype
	payload.update index: @index.render(values) if @index
      }.to_json
    end

    def try_write(chunk)
      log.debug { "Received new chunk, size=#{chunk.read.bytesize}" }
      @chunk_queue << chunk
    end

    def stop
      @chunk_queue.close
      super
    end

    def multi_workers_ready?
      true
    end

    private

    def prepare_templates
      template_fields = %w[@index @host @source @sourcetype]

      if @disable_template
	# provides `render` method when template is diabled, so that
	# we can handle the fields in the same ways no matter if templating
	# is enabled or not.
	self_render = Module.new {
	  def render(*args) self end
	}
	template_fields.each { |field|
	  v = instance_variable_get field
	  v.extend self_render if v
	}
      else
	require 'liquid'
	template_fields.each { |field|
	  v = instance_variable_get field
	  instance_variable_set field, Liquid::Template.parse(v) if v
	}
      end
    end

    def construct_api
      @hec_api = URI("#{@protocol}://#{@hec_host}:#{@hec_port}/services/collector")
    rescue
      raise Fluent::ConfigError, "hec_host (#{@hec_host}) and/or hec_port (#{@hec_port}) are invalid."
    end

    def start_worker_threads
      thread_create :"hec_worker_#{@hec_api}" do
	http = new_connection
	while chunk = get_next_chunk
	  send_to_hec http, chunk
	end
      end
    end

    def get_next_chunk
      @chunk_queue.pop @chunk_queue.closed?
    rescue ThreadError # see SizedQueue#pop doc
      nil
    end

    def new_connection
      Net::HTTP::Persistent.new.tap do |c|
	c.verify_mode = @ssl.insecure ? OpenSSL::SSL::VERIFY_NONE : OpenSSL::SSL::VERIFY_PEER
	c.cert = OpenSSL::X509::Certificate.new File.read(@ssl.client_cert) if @ssl.client_cert
	c.key = OpenSSL::PKey::RSA.new File.read(@ssl.client_pkey) if @ssl.client_pkey
	c.ca_file = @ssl.ca_file
	c.ca_path = @ssl.ca_path
	c.ciphers = @ssl.ciphers

	c.override_headers['Content-Type'] = 'application/json'
	c.override_headers['User-Agent'] = "fluent-plugin-splunk_hec_out/#{VERSION}"
	c.override_headers['Authorization'] = "Splunk #{@hec_token}"
      end
    end

    def send_to_hec(http, chunk)
      post = Net::HTTP::Post.new @hec_api.request_uri
      post.body = chunk.read
      log.debug { "Sending #{post.body.bytesize} bytes to Splunk." }

      log.trace { "POST #{@hec_api} body=#{post.body}" }
      response = http.request @hec_api, post
      log.debug { "[Response] POST #{@hec_api}: #{response.inspect}" }

      # raise Exception to utilize Fluentd output plugin retry machanism
      raise "Server error for POST #{@hec_api}, response: #{response.body}" if response.code.start_with?('5')

      # For both success response (2xx) and client errors (4xx), we will consume the chunk.
      # Because there probably a bug in the code if we get 4xx errors, retry won't do any good.
      commit_write(chunk.unique_id)
      log.error "Failed POST to #{@hec_api}, response: #{response.body}" if not response.code.start_with?('2')
    end

    # Encode as UTF-8. If 'coerce_to_utf8' is set to true in the config, any
    # non-UTF-8 character would be replaced by the string specified by
    # 'non_utf8_replacement_string'. If 'coerce_to_utf8' is set to false, any
    # non-UTF-8 character would trigger the plugin to error out.
    # Thanks to
    # https://github.com/GoogleCloudPlatform/fluent-plugin-google-cloud/blob/dbc28575/lib/fluent/plugin/out_google_cloud.rb#L1284
    def convert_to_utf8(input)
      if input.is_a?(Hash)
	record = {}
	input.each do |key, value|
	  record[convert_to_utf8(key)] = convert_to_utf8(value)
	end

	return record
      end
      return input.map { |value| convert_to_utf8(value) } if input.is_a?(Array)
      return input unless input.respond_to?(:encode)

      if @coerce_to_utf8
	input.encode(
	  'utf-8',
	  invalid: :replace,
	  undef: :replace,
	  replace: @non_utf8_replacement_string)
      else
	begin
	  input.encode('utf-8')
	rescue EncodingError
	  log.error { 'Encountered encoding issues potentially due to non ' \
		     'UTF-8 characters. To allow non-UTF-8 characters and ' \
		     'replace them with spaces, please set "coerce_to_utf8" ' \
		     'to true.' }
	  raise
	end
      end
    end
  end
end
