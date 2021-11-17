# frozen_string_literal: true
$LOAD_PATH.unshift(File.expand_path('..', __dir__))
require 'fluent/env'
require 'fluent/output'
require 'fluent/plugin/output'
require 'fluent/plugin/formatter'
require 'fluent/plugin/out_splunk'

require 'openssl'
require 'multi_json'
require 'net/http/persistent'
require 'securerandom'

module Fluent::Plugin
  class SplunkHecOutput < SplunkOutput
    Fluent::Plugin.register_output('splunk_hec', self)

    helpers :formatter
    helpers :timer

    autoload :VERSION, "fluent/plugin/out_splunk_hec/version"
    autoload :MatchFormatter, "fluent/plugin/out_splunk_hec/match_formatter"

    KEY_FIELDS = %w[index time host source sourcetype metric_name metric_value].freeze
    TAG_PLACEHOLDER = '${tag}'.freeze

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

    desc 'If a connection has not been used for this number of seconds it will automatically be reset upon the next use to avoid attempting to send to a closed connection. nil means no timeout.'
    config_param :idle_timeout, :integer, default: 5

    desc 'The amount of time allowed between reading two chunks from the socket.'
    config_param :read_timeout, :integer, default: nil

    desc 'The amount of time to wait for a connection to be opened.'
    config_param :open_timeout, :integer, default: nil

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

    desc 'When set to true, TLS version 1.1 and above is required.'
    config_param :require_ssl_min_version, :bool, default: true

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

    desc 'When set to true, all fields defined in `index_key`, `host_key`, `source_key`, `sourcetype_key`, `metric_name_key`, `metric_value_key` will not be removed from the original event.'
    config_param :keep_keys, :bool, default: false

    desc 'App name'
    config_param :app_name, :string, default: "hec_plugin_gem"

    desc 'App version'
    config_param :app_version, :string, default: (VERSION).to_s

    desc 'Define index-time fields for event data type, or metric dimensions for metric data type. Null value fields will be removed.'
    config_section :fields, init: false, multi: false, required: false do
      # this is blank on purpose
    end

    config_section :format do
      config_set_default :usage, '**'
      config_set_default :@type, 'json'
      config_set_default :add_newline, false
    end

    desc <<~DESC
    Whether to allow non-UTF-8 characters in user logs. If set to true, any
    non-UTF-8 character would be replaced by the string specified by
    `non_utf8_replacement_string`. If set to false, any non-UTF-8 character
    would trigger the plugin to error out.
    DESC
    config_param :coerce_to_utf8, :bool, :default => true

    desc <<~DESC
    If `coerce_to_utf8` is set to true, any not-UTF-8 char's would be
    replaced by the string specified here.
    DESC
    config_param :non_utf8_replacement_string, :string, :default => ' '

    desc 'Use the HEC acknowledgment feature'
    config_param :hec_ack_enabled, :bool, default: false

    desc 'The HEC channel to use with the acknowledgment feature'
    config_param :hec_channel, :string, default: SecureRandom.uuid

    def initialize
      super
      @default_host = Socket.gethostname
      @extra_fields = nil
    end

    def configure(conf)
      super
      @hec_api_ack = construct_ack_api
      check_metric_configs
      pick_custom_format_method
    end

    def start
      super

      @conn = Net::HTTP::Persistent.new.tap do |c|
        c.verify_mode = @insecure_ssl ? OpenSSL::SSL::VERIFY_NONE : OpenSSL::SSL::VERIFY_PEER
        c.cert = OpenSSL::X509::Certificate.new File.read(@client_cert) if @client_cert
        c.key = OpenSSL::PKey::RSA.new File.read(@client_key) if @client_key
        c.ca_file = @ca_file
        c.ca_path = @ca_path
        c.ciphers = @ssl_ciphers
        c.proxy   = :ENV
        c.min_version = OpenSSL::SSL::TLS1_1_VERSION if @require_ssl_min_version

        c.override_headers['Content-Type'] = 'application/json'
        c.override_headers['User-Agent'] = "fluent-plugin-splunk_hec_out/#{VERSION}"
        c.override_headers['Authorization'] = "Splunk #{@hec_token}"
        c.override_headers['__splunk_app_name'] = @app_name
        c.override_headers['__splunk_app_version'] = @app_version
        c.override_headers['X-Splunk-Request-Channel'] = @hec_channel
      end
      start_ack_checker if @hec_ack_enabled
    end

    def shutdown
      super
      @conn.shutdown
    end

    def format(tag, time, record)
      # this method will be replaced in `configure`
    end

    def multi_workers_ready?
      true
    end

    def prefer_delayed_commit
      @hec_ack_enabled
    end

    def try_write(chunk)
      log.trace { "#{self.class}: Received new chunk for delayed commit, size=#{chunk.read.bytesize}" }

#      t = Benchmark.realtime do
#        ack_id = write_to_splunk(chunk)
#      end

      ack_id = write_to_splunk(chunk)
      ack_checker_create_entry(chunk.unique_id, ack_id)

 #     @metrics[:record_counter].increment(metric_labels, chunk.size_of_events)
 #     @metrics[:bytes_counter].increment(metric_labels, chunk.bytesize)
 #     @metrics[:write_records_histogram].observe(metric_labels, chunk.size_of_events)
 #     @metrics[:write_bytes_histogram].observe(metric_labels, chunk.bytesize)
 #     @metrics[:write_latency_histogram].observe(metric_labels, t)
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

    def format_event(tag, time, record)
      d = {
        host: @host ? @host.(tag, record) : @default_host,
        # From the API reference
        # http://docs.splunk.com/Documentation/Splunk/latest/RESTREF/RESTinput#services.2Fcollector
        # `time` should be a string or unsigned integer.
        # That's why we use the to_string function here.
        time: time.to_f.to_s
        }.tap { |payload|
        if @time
          time_value = @time.(tag, record)
          # if no value is found don't override and use fluentd's time
          payload[:time] = time_value unless time_value.nil?
        end

          payload[:index] = @index.(tag, record) if @index
          payload[:source] = @source.(tag, record) if @source
          payload[:sourcetype] = @sourcetype.(tag, record) if @sourcetype

          # delete nil fields otherwise will get formet error from HEC
          %i[host index source sourcetype].each { |f| payload.delete f if payload[f].nil? }

          if @extra_fields
            payload[:fields] = @extra_fields.map { |name, field| [name, record[field]] }.to_h
            payload[:fields].delete_if { |_k,v| v.nil? }
            # if a field is already in indexed fields, then remove it from the original event
            @extra_fields.values.each { |field| record.delete field }
          end
          if formatter = @formatters.find { |f| f.match? tag }
            record = formatter.format(tag, time, record)
          end
          payload[:event] = convert_to_utf8 record
      }
      if d[:event] == "{}"
        log.warn { "Event after formatting was blank, not sending" }
        return ""
      end
      MultiJson.dump(d)
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
      }.tap do |payload|
        if @time
          time_value = @time.(tag, record)
          # if no value is found don't override and use fluentd's time
          payload[:time] = time_value unless time_value.nil?
        end
      end
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
          fields.delete_if { |_k,v| v.nil? }
        else
          fields.update record
        end

        fields.delete_if { |_k,v| v.nil? }

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

    def construct_ack_api
      URI("#{@protocol}://#{@hec_host}:#{@hec_port}/services/collector/ack")
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
        c.proxy   = :ENV
        c.idle_timeout = @idle_timeout
        c.read_timeout = @read_timeout
        c.open_timeout = @open_timeout
        c.min_version = OpenSSL::SSL::TLS1_1_VERSION if @require_ssl_min_version

        c.override_headers['Content-Type'] = 'application/json'
        c.override_headers['User-Agent'] = "fluent-plugin-splunk_hec_out/#{VERSION}"
        c.override_headers['Authorization'] = "Splunk #{@hec_token}"
        c.override_headers['__splunk_app_name'] = @app_name.to_s
        c.override_headers['__splunk_app_version'] = @app_version.to_s

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

      raise_err = response.code.to_s.start_with?('5') || (!@consume_chunk_on_4xx_errors && response.code.to_s.start_with?('4'))

      # raise Exception to utilize Fluentd output plugin retry mechanism
      raise "Server error (#{response.code}) for POST #{@api}, response: #{response.body}" if raise_err

      # For both success response (2xx) we will consume the chunk.
      unless response.code.start_with?('2')
        log.error "Failed POST to #{@api}, response: #{response.body}"
        log.debug { "Failed request body: #{post.body}" }
      end

      log.debug { "[Response] Chunk: #{dump_unique_id_hex(chunk.unique_id)} Size: #{post.body.bytesize} Response: #{response.inspect} Duration: #{t2 - t1}" }
      process_response(response, post.body)
      # example response body {"text":"Success","code":0,"ackId":6}
      return MultiJson.load(response.body).fetch('ackId', nil)
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

    def start_ack_checker
      @AckEntry = Struct.new(:chunk_id, :ack_id, :insert_time, :timeout) do
        def expired?(now = Fluent::Clock.now)
          now > insert_time + timeout
        end
      end

      @ack_queue_mutex = Mutex.new
      @ack_queue = []

      timer_execute(:ack_checker, 5) do
        #       ack_work = ack_checker_get_work
        ack_work = @ack_queue_mutex.synchronize { @ack_queue.dup }

        #return if ack_work.empty?
        #
        ack_ids_to_check = []
        unless ack_work.empty?
          ack_work.each do |ack_entry|
            ack_ids_to_check.push(ack_entry.ack_id) unless ack_entry.nil?
          end
          saved_time = Fluent::Clock.now
          log.debug { "checking ack_ids: #{ack_ids_to_check}" }
          succsessful_ack_ids = get_successful_ack_ids(ack_ids_to_check)
          log.debug("Of #{ack_ids_to_check.count} to check #{succsessful_ack_ids.count} were successfully acknowledged.")
          ack_work.each do |ack_entry|
            if succsessful_ack_ids.include? ack_entry.ack_id
              log.debug("Ack id #{ack_entry.ack_id} successfully acknowledged.")
              commit_write(ack_entry.chunk_id)
              ack_checker_remove_entry(ack_entry)
            elsif ack_entry.expired?(saved_time)
              log.warn("Ack id #{ack_entry.ack_id} not acknowledged and timeout reached. Rolling back the commit.")
              ## TODO is this rollback_commit or rollback_count ?
              rollback_count(ack_entry.chunk_id)
              ack_checker_remove_entry(ack_entry)
            else
              log.debug("Ack id #{ack_entry.ack_id} not yet successful. Retrying.")
            end
          end
        end
      end
    end

    # @return [Array<AckEntry>] List of AckEntry objects
    def ack_checker_get_work
      @ack_queue_mutex.synchronize { @ack_queue.dup }
    end

    # Adds work to the ack_checker work queue
    #
    # @param chunk_id [Binary] Id of the chunk, retrievable by chunk.chunk_id
    # @param ack_id [Integer] Id received from Splunk HEC when the chunk was submitted
    # @param insert_time [UnixTime] Defaults to now
    # @param timeout [Integer] Timeout in seconds, defaults to `delayed_commit_timeout`
    def ack_checker_create_entry(chunk_id, ack_id, insert_time = Fluent::Clock.now, timeout = @delayed_commit_timeout)
      @ack_queue_mutex.synchronize do
        @ack_queue.push(@AckEntry.new(
          chunk_id,
          ack_id,
          insert_time,
          timeout
        ))
      end
    end

    # Removes an entry from the ack_checker work queue
    #
    # @param ack_entry [AckEntry] The entry to be removed
    def ack_checker_remove_entry(ack_entry)
      @ack_queue_mutex.synchronize do
        @ack_queue.delete(ack_entry)
      end
    end

    # @param ack_ids [Array<Integer>]] Array of ack IDs to validate
    # @return Array<Integer> List of successful acknowledgments
    def get_successful_ack_ids(ack_ids)
      successful_acks = []
      if ack_ids.empty?
        return successful_acks
      end
      post = Net::HTTP::Post.new @hec_api_ack.request_uri
      post.body = MultiJson.dump({ 'acks' => ack_ids })
      log.debug { "Sending #{post.body.bytesize} bytes to Splunk." }

      log.trace { "POST #{@hec_api_ack} body=#{get.body}" }
      ## TODO remove
      log.debug { "Sending #{@conn.request} to Splunk." }
      response = @conn.request @hec_api_ack.to_s, post
      log.debug { "[Response] POST #{@hec_api_ack}: #{response.inspect}" }

      # raise Exception to utilize Fluentd output plugin retry mechanism
      raise "Server error (#{response.code}) for POST #{@hec_api_ack}, response: #{response.body}" if response.code.start_with?('5')

      # For both success response (2xx) and client errors (4xx), we will consume the chunk.
      # Because there probably a bug in the code if we POST 4xx errors, retry won't do any good.
      unless response.code.start_with?('2')
        log.error "Failed POST from #{@hec_api_ack}, response: #{response.body}"
        log.debug { "Failed request body: #{post.body}" }
        return successful_acks
      end

      MultiJson.load("#{response.body}")['acks'].each do |ack_id_str, bool|
        successful_acks.push(ack_id_str.to_i) if bool
      end

      return successful_acks
    end
  end
end
