# frozen_string_literal: true

require "fluent/plugin/output"
require "fluent/plugin/formatter_nil"

require 'openssl'
require 'multi_json'
require 'net/http/persistent'

module Fluent::Plugin
  class SplunkHecOutput < Fluent::Plugin::Output
    Fluent::Plugin.register_output('splunk_hec', self)

    JQ_PLACEHOLDER = /{%(.*?)%}/

    helpers :formatter

    autoload :VERSION, "fluent/plugin/out_splunk_hec/version"

    desc <<~DESC
    Specify which template engine to use to parse config values which support templates.
    There are four options:
    * `placeholder` - uses the placeholder expander comes with the fluentd built-in [`filter_record_transformer`](https://docs.fluentd.org/v1.0/articles/filter_record_transformer) filter plugin to support `${}` placeholders. Please check [the <record> directive document](https://docs.fluentd.org/v1.0/articles/filter_record_transformer#%3Crecord%3E-directive) for details.
    * `ruby` - works exactly the same way when `enable_ruby` is set to `true` in [`filter_record_transformer`](https://docs.fluentd.org/v1.0/articles/filter_record_transformer). Please read [the `enable_ruby` document]([`filter_record_transformer`](https://docs.fluentd.org/v1.0/articles/filter_record_transformer#enable_ruby) for details.
    * `jq` - uses the fast (written in C) and powerful [jq engine](https://stedolan.github.io/jq/) to render the value. Jq filters should be wrapped inside `{% %}`, e.g. `{% .tag %}`. The following variables are available:
      - `.tag` refers to the whole tag.
      - `.record` refers to the whole record(event).
      - `.time` refers to stringanized event time.
      - `.hostname` refers to machine’s hostname. The actual value is result of Socket.gethostname.
      If you have lots of events to handle, using `jq` is recommended. To use this engine, you need to install the `ruby-jq` rubygem on your machine first.
    * `none` - do not use any tempalte engine. All config values will just remain as what they are configured in the config file.
    DESC
    config_param :template_engine, :enum, list: %i[placeholder ruby jq none], default: :placeholder

    desc 'Which protocol to use to call HEC api, "http" or "https", default "https".'
    config_param :protocol, :enum, list: %i[http https], default: :https

    desc 'The hostname/IP of the Splunk instance which has HTTP input enabled, or a HEC load balancer.'
    config_param :hec_host, :string

    desc 'The port number of the HTTP input, or the HEC load balancer.'
    config_param :hec_port, :integer, default: 8088

    desc 'The HEC token.'
    config_param :hec_token, :string

    desc "The path to a file containing a PEM-format CA certificate for this client."
    config_param :client_cert, :string, default: nil

    desc "The private key for this client."
    config_param :client_key, :string, default: nil

    desc 'The path to a file containing a PEM-format CA certificate.'
    config_param :ca_file, :string, default: nil

    desc 'The path to a directory containing CA certificates in PEM format.'
    config_param :ca_path, :string, default: nil

    desc 'List of SSL ciphers allowed.'
    config_param :ssl_ciphers, :array, default: nil

    desc "Indicates if insecure SSL connection is allowed."
    config_param :insecure_ssl, :bool, default: false

    desc 'The Splunk index indexs events, by default it is not set, and will use what is configured in the HTTP input. Template is supported.'
    config_param :index, :string, default: nil

    desc "Set the host field for events, by default it's the hostname of the machine that runnning fluentd. Template is supported."
    config_param :host, :string, default: nil

    desc "The source will be applied to the events, by default it uses the event's tag. Template is supported."
    config_param :source, :string, default: nil

    desc 'The sourcetype will be applied to the events, by default it is not set, and leave it to Splunk to figure it out. Template is supported.'
    config_param :sourcetype, :string, default: nil

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
      @template_fields = %w[@index @host @source @sourcetype]
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
      event = @formatter ? @formatter.format(tag, time, record) : record

      MultiJson.dump({
	host: @host ? @host.(tag, time, record) : @default_host,
	source: @source ? @source.(tag, time, record) : tag,
        event: convert_to_utf8(event),
	time: time.to_i
      }.tap { |payload|
	payload.update sourcetype: @sourcetype.(tag, time, record) if @sourcetype
	payload.update index: @index.(tag, time, record) if @index
      })
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
      case @template_engine
      when :jq
	use_jq_template
      when :ruby, :placeholder
	use_placeholder_template
      else # none
	use_none_template
      end
    end

    def use_jq_template
      begin
	require 'jq'
      rescue LoadError
	raise Fluent::ConfigError, "`template_engine` is set to `jq`, but `ruby-jq` is not installed. Run `gem install ruby-jq` to install it."
      end

      @template_fields.each { |field|
	v = instance_variable_get field
	if v
	  programs = v.scan JQ_PLACEHOLDER
	  if programs.empty?
	    # just simply return the value if no jq program is in the value
	    instance_variable_set field,  ->(tag, time, record) { v }
	    next
	  end

	  programs = programs.flatten!.map! { |p|
	    begin
	      JQ::Core.new p
	    rescue JQ::Error
	      raise Fluent::ConfigError, "Invalid jq filter for #{field}: #{p}"
	    end
	  }
	  instance_variable_set field, ->(tag, time, record) {
	    json = MultiJson.dump(
	      'tag'.freeze      => tag,
	      'time'.freeze     => Time.at(time).to_s,
	      'record'.freeze   => record,
	      'hostname'.freeze => @default_host
	    )
	    p = programs.each
	    v.gsub JQ_PLACEHOLDER do |_|
	      [].tap { |buf|
		p.next.update(json, false) { |r| buf << MultiJson.load("[#{r}]").first }
	      }.first
	    end
	  }
	end
      }
    end

    def use_placeholder_template
      require 'fluent/plugin/filter_record_transformer'
      expander =
	if @template_engine == :ruby
	  # require utilities which would be used in ruby placeholders
	  require 'pathname'
	  require 'uri'
	  require 'cgi'
	  Fluent::Plugin::RecordTransformerFilter::RubyPlaceholderExpander
	else
	  Fluent::Plugin::RecordTransformerFilter::PlaceholderExpander
	end \
	  .new(log: log, auth_typecast: true)

      @template_fields.each { |field|
	v = instance_variable_get field
	if v
	  v = expander.preprocess_map(v)
	  instance_variable_set field, ->(tag, time, record) {
	    expander.expand(v, expander.prepare_placeholders(
	      'tag'.freeze       => tag,
	      'tag_parts'.freeze => tag.split('.'),
	      'time'.freeze      => expander.time_value(time),
	      'hostname'.freeze  => @default_host,
	      'record'.freeze    => record
	    ))
	  }
	end
      }
    end

    def use_none_template
      @template_fields.each { |field|
	v = instance_variable_get field
	instance_variable_set field, ->(tag, time, record) { v } if v
      }
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
	c.verify_mode = @insecure_ssl ? OpenSSL::SSL::VERIFY_NONE : OpenSSL::SSL::VERIFY_PEER
	c.cert = OpenSSL::X509::Certificate.new File.read(@client_cert) if @client_cert
	c.key = OpenSSL::PKey::RSA.new File.read(@client_key) if @client_key
	c.ca_file = @ca_file
	c.ca_path = @ca_path
	c.ciphers = @ssl_ciphers

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
