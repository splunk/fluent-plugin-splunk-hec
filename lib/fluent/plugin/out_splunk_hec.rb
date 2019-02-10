# frozen_string_literal: true

require 'fluent/output'
require 'fluent/plugin/output'
require 'fluent/plugin/formatter'
require 'fluent/plugin/out_splunk'

require 'openssl'
require 'multi_json'
require 'net/http/persistent'

module Fluent::Plugin
  class SplunkHecOutput < SplunkOutput
    Fluent::Plugin.register_output('splunk_hec', self)

    MISSING_FIELD = Hash.new do |_h, k|
      $log.warn "expected field #{k} but it's missing" if defined?($log)
      MISSING_FIELD
    end.freeze

    desc 'Protocol to use to call HEC API.'
    config_param :protocol, :enum, list: %i[http https], default: :https

    desc 'The hostname/IP to HEC, or HEC load balancer.'
    config_param :hec_host, :string

    desc 'The port number to HEC, or HEC load balancer.'
    config_param :hec_port, :integer, default: 8088

    desc 'The HEC token.'
    config_param :hec_token, :string

    desc 'The path to a file containing a PEM-format CA certificate for this client.'
    config_param :client_cert, :string, default: nil

    desc 'The private key for this client.'
    config_param :client_key, :string, default: nil

    desc 'The path to a file containing a PEM-format CA certificate.'
    config_param :ca_file, :string, default: nil

    desc 'The path to a directory containing CA certificates in PEM format.'
    config_param :ca_path, :string, default: nil

    desc 'List of SSL ciphers allowed.'
    config_param :ssl_ciphers, :array, default: nil

    desc 'Indicates if insecure SSL connection is allowed.'
    config_param :insecure_ssl, :bool, default: false

    desc 'Type of data sending to Splunk, `event` or `metric`. `metric` type is supported since Splunk 7.0. To use `metric` type, make sure the index is a metric index.'
    config_param :data_type, :enum, list: %i[event metric], default: :event

    desc 'The Splunk index to index events. When not set, will be decided by HEC. This is exclusive with `index_key`'
    config_param :index, :string, default: nil

    desc 'Field name to contain Splunk index name. This is exclusive with `index`.'
    config_param :index_key, :string, default: nil

    desc 'When `data_type` is set to "metric", by default it will treat every key-value pair in the income event as a metric name-metric value pair. Set `metrics_from_event` to `false` to disable this behavior and use `metric_name_key` and `metric_value_key` to define metrics.'
    config_param :metrics_from_event, :bool, default: true

    desc 'Field name to contain metric name. This is exclusive with `metrics_from_event`, when this is set, `metrics_from_event` will be set to `false`.'
    config_param :metric_name_key, :string, default: nil

    desc 'Field name to contain metric value, this is required when `metric_name_key` is set.'
    config_param :metric_value_key, :string, default: nil

    def initialize
      super
      @default_host = Socket.gethostname
      @extra_fields = nil
    end

    def configure(conf)
      super

      check_metric_configs
      pick_custom_format_method
    end

    def format(tag, time, record)
      # this method will be replaced in `configure`
    end

    def multi_workers_ready?
      true
    end

    protected

    private

    def check_metric_configs
      return unless @data_type == :metric

      @metrics_from_event = false if @metric_name_key

      return if @metrics_from_event

      raise Fluent::ConfigError, '`metric_name_key` is required when `metrics_from_event` is `false`.' unless @metric_name_key

      raise Fluent::ConfigError, '`metric_value_key` is required when `metric_name_key` is set.' unless @metric_value_key
    end

    def format_metric(tag, time, record)
      payload = {
        host: @host ? @host.call(tag, record) : @default_host,
        # From the API reference
        # http://docs.splunk.com/Documentation/Splunk/latest/RESTREF/RESTinput#services.2Fcollector
        # `time` should be a string or unsigned integer.
        # That's why we use `to_s` here.
        time: time.to_f.to_s,
        event: 'metric'
      }
      payload[:index] = @index.call(tag, record) if @index
      payload[:source] = @source.call(tag, record) if @source
      payload[:sourcetype] = @sourcetype.call(tag, record) if @sourcetype

      unless @metrics_from_event
        fields = {
          metric_name: @metric_name.call(tag, record),
          _value: @metric_value.call(tag, record)
        }

        if @extra_fields
          fields.update @extra_fields.map { |name, field| [name, record[field]] }.to_h
        else
          fields.update record
        end

        fields.compact!

        payload[:fields] = convert_to_utf8 fields

        return MultiJson.dump(payload)
      end

      # when metrics_from_event is true, generate one metric event for each key-value in record
      payloads = record.map do |key, value|
        { fields: { metric_name: key, _value: value } }.merge! payload
      end

      payloads.map!(&MultiJson.method(:dump)).join
    end

    def construct_api
      URI("#{@protocol}://#{@hec_host}:#{@hec_port}/services/collector")
    rescue StandardError
      raise Fluent::ConfigError, "hec_host (#{@hec_host}) and/or hec_port (#{@hec_port}) are invalid."
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

    def write_to_splunk(chunk)
      post = Net::HTTP::Post.new @api.request_uri
      post.body = chunk.read
      log.debug { "[Sending] Chunk: #{dump_unique_id_hex(chunk.unique_id)}(#{post.body.bytesize}B)." }
      log.trace { "POST #{@api} body=#{post.body}" }

      t1 = Time.now
      response = @conn.request @api, post
      t2 = Time.now

      log.debug { "[Response] Chunk: #{dump_unique_id_hex(chunk.unique_id)} Size: #{post.body.bytesize} Response: #{response.inspect} Duration: #{t2 - t1}" }
      process_response(response, post.body)
    end
  end
end
