require "test_helper"

describe Fluent::Plugin::SplunkHecOutput do
  include Fluent::Test::Helpers
  include PluginTestHelper

  before { Fluent::Test.setup } # setup router and others
    
  it { expect(::Fluent::Plugin::SplunkHecOutput::VERSION).wont_be_nil }

  describe "hec_host validation" do
    describe "invalid host" do
      it "should require hec_host" do
	expect{ create_output_driver }.must_raise Fluent::ConfigError
      end

      it { expect{ create_output_driver('hec_host %bad-host%') }.must_raise Fluent::ConfigError }
    end

    describe "good host" do
      it {
	expect(create_output_driver('hec_host splunk.com').instance.hec_host).must_equal "splunk.com"
      }
    end
  end

  it "should send request to Splunk" do
    req = verify_sent_events { |batch|
      expect(batch.size).must_equal 2
    }
    expect(req).must_be_requested times: 1
  end

  it "should use host machine's hostname for event host by default" do
    verify_sent_events { |batch|
      batch.each do |item|
	expect(item['host']).must_equal Socket.gethostname
      end
    }
  end

  %w[index source sourcetype].each do |field|
    it "should not set #{field} by default" do
      verify_sent_events { |batch|
	batch.each do |item|
	  expect(item).wont_include field
	end
      }
    end
  end

  it "should support ${tag}" do
    verify_sent_events(<<~CONF) { |batch|
    index ${tag}
    host ${tag}
    source ${tag}
    sourcetype ${tag}
    CONF
      batch.each do |item|
	%w[index host source sourcetype].each { |field|
	  expect(%w[tag.event1 tag.event2]).must_include item[field]
	}
      end
    }
  end

  it "should support *_key" do
    verify_sent_events(<<~CONF) { |batch|
      index_key      level
      host_key       from
      source_key     file
      sourcetype_key agent.name
    CONF
      batch.each { |item|
	expect(item['index']).must_equal 'info'
	expect(item['host']).must_equal 'my_machine'
	expect(item['source']).must_equal 'cool.log'
	expect(item['sourcetype']).must_equal 'test'

	JSON.load(item['event']).tap do |event|
	  %w[level from file].each { |field| expect(event).wont_include field }
	  expect(event['agent']).wont_include 'name'
	end
      }
    }
  end

  it "should remove nil fileds." do
    verify_sent_events(<<~CONF) { |batch|
      index_key      nonexist
      host_key       nonexist
      source_key     nonexist
      sourcetype_key nonexist
    CONF
      batch.each { |item|
	expect(item).wont_be :has_key?, 'index'
	expect(item).wont_be :has_key?, 'host'
	expect(item).wont_be :has_key?, 'source'
	expect(item).wont_be :has_key?, 'sourcetype'
      }
    }
  end

  describe 'formatter' do
    it "should support replace the default json formater" do
      verify_sent_events(<<~CONF) { |batch|
	<format>
	  @type single_value
	  message_key log
	  add_newline false
	</format>
      CONF
	batch.map { |item| item['event'] }
	     .each { |event| expect(event).must_equal "everything is good" }
      }
    end

    it "should support multiple formatters" do
      verify_sent_events(<<~CONF) { |batch|
	source ${tag}
	<format tag.event1>
	  @type single_value
	  message_key log
	  add_newline false
	</format>
      CONF
	expect(batch.find { |item| item['source'] == 'tag.event1' }['event']).must_equal "everything is good"
	expect(batch.find { |item| item['source'] == 'tag.event2' }['event']).must_be_instance_of Hash
      }
    end
  end

  it "should support fields for indexed field extraction" do
    d = verify_sent_events(<<~CONF) { |batch|
    <fields>
      from
      logLevel level
    </fields>
    CONF
      batch.each do |item|
	JSON.load(item['event']).tap { |event|
	  expect(event).wont_include 'from'
	  expect(event).wont_include 'level'
	}

	expect(item['fields']['from']).must_equal 'my_machine'
	expect(item['fields']['logLevel']).must_equal 'info'
      end
    }
  end

  describe 'metric'do
    it 'should require metric_name_key and metric_value_key' do
      expect{ create_output_driver('hec_host somehost', 'data_type metric') }.must_raise Fluent::ConfigError

      expect{
	create_output_driver('hec_host somehost', 'data_type metric', 'metric_name_key x')
      }.must_raise Fluent::ConfigError

      expect{
	create_output_driver('hec_host somehost', 'data_type metric', 'metric_value_key x')
      }.must_raise Fluent::ConfigError

      expect(
	create_output_driver('hec_host somehost', 'data_type metric', 'metric_name_key x', 'metric_value_key y')
      ).wont_be_nil
    end

    it 'should have "metric" as event, and have proper fields' do
      verify_sent_events(<<~CONF) { |batch|
	data_type metric
	metric_name_key from
	metric_value_key value
      CONF
        batch.each do |item|
	  expect(item['event']).must_equal 'metric'
	  expect(item['fields']['metric_name']).must_equal 'my_machine'
	  expect(item['fields']['_value']).must_equal 100
	  expect(item['fields']['log']).must_equal 'everything is good'
	  expect(item['fields']['level']).must_equal 'info'
	  expect(item['fields']['file']).must_equal 'cool.log'
	end
      }
    end

    it 'should handle empty fields' do
      verify_sent_events(<<~CONF) { |batch|
	data_type metric
	metric_name_key from
	metric_value_key value
	<fields>
	</fields>
      CONF
        batch.each do |item|
	  expect(item['fields'].keys.size).must_equal 2
	end
      }
    end

    it 'should handle custom fields' do
      verify_sent_events(<<~CONF) { |batch|
	data_type metric
	metric_name_key from
	metric_value_key value
	<fields>
	  level
	  filePath file
	</fields>
      CONF
        batch.each do |item|
	  expect(item['fields'].keys.size).must_equal 4
	  expect(item['fields']['level']).must_equal 'info'
	  expect(item['fields']['filePath']).must_equal 'cool.log'
	end
      }
    end
  end

  def verify_sent_events(conf = '', &blk)
    host = "hec.splunk.com"
    d = create_output_driver("hec_host #{host}", conf)

    hec_req = stub_hec_request("https://#{host}:8088").with { |r|
      blk.call r.body.split(/(?={)\s*(?<=})/).map { |item| JSON.load item }
    }

    d.run do
      event = {
	"log"   => "everything is good",
	"level" => "info",
	"from"  => "my_machine",
	"file"  => "cool.log",
	"value" => 100,
	"agent" => {
	  "name"    => "test",
	  "version" => "1.0.0"
	}
      }
      d.feed("tag.event1", event_time, {"id" => "1st"}.merge(Marshal.load(Marshal.dump(event))))
      d.feed("tag.event2", event_time, {"id" => "2nd"}.merge(Marshal.load(Marshal.dump(event))))
    end

    hec_req
  end
end
