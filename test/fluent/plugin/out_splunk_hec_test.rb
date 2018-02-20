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
    req = verify_sent_events { |r|
      expect(r.body.scan(/test message/).size).must_equal 2
    }
    expect(req).must_be_requested times: 1
  end

  describe "source" do
    it "should use event tags by default" do
      verify_sent_events() { |r|
	expect(r.body).must_match(/"source"\s*:\s*"tag.event1"/)
	expect(r.body).must_match(/"source"\s*:\s*"tag.event2"/)
      }
    end

    it "should support placeholder templates" do
      verify_sent_events(%q<source '${tag}_${tag_parts[0]}-${tag_parts[1]}_${hostname}_${time}_${record["id"]}'>) { |r|
	expect(r.body.scan(
	  /"source"\s*:\s*"
	  tag.event(?:1|2)_
	  tag-event(?:1|2)_
	  #{Socket.gethostname}_
	  #{Time.now.to_s.split(' ')[0]}[^"]*_
	  (?:1st|2nd)
	  "/x
	).size).must_equal 2
      }
    end

    it "should support ruby templates" do
      verify_sent_events(<<~CONF) { |r|
	template_engine ruby
        source "${
	  tag + '_' +
	  tag_parts.join('-') + '_' +
	  hostname + '_' +
	  time.to_s.split(' ')[0] + '_' +
	  (record['id'] == '1st' ? 'first' : 'second')
	}"
      CONF
	expect(r.body.scan(
	  /"source"\s*:\s*"
	  tag.event(?:1|2)_
	  tag-event(?:1|2)_
	  #{Socket.gethostname}_
	  #{Time.now.to_s.split(' ')[0]}_
	  (?:first|second)
	  "/x
	).size).must_equal 2
      }
    end

    it "should support jq tempalte" do
      verify_sent_events(<<~CONF) { |r|
	template_engine jq
        source "(.tag | split(\\".\\") | join(\\"-\\")) + \\"_\\" +
	  .hostname + \\"_\\" +
	  (.time | split(\\" \\") | .[0]) + \\"_\\" +
	  .record.id
	"
      CONF
	expect(r.body.scan(
	  /"source"\s*:\s*"
	  tag-event(?:1|2)_
	  #{Socket.gethostname}_
	  #{Time.now.to_s.split(' ')[0]}_
	  (?:1st|2nd)
	  "/x
	).size).must_equal 2
      }
    end
  end

  describe "host" do
    it "should use host machine's hostname by default" do
      verify_sent_events() { |r|
	expect(r.body).must_match(/"host"\s*:\s*"#{Socket.gethostname}"/)
      }
    end

    it "should support template" do
      verify_sent_events(%q<host "${tag_parts[0]}-${tag_parts[1]}">) { |r|
	expect(r.body).must_match(/"host"\s*:\s*"tag-event1"/)
	expect(r.body).must_match(/"host"\s*:\s*"tag-event2"/)
      }
    end
  end

  describe "sourcetype" do
    it "should not be set by default" do
      verify_sent_events() { |r|
	expect(r.body).wont_match(/"sourcetype"\s*:\s*"/)
	true # `wont_match` returns `false` which will make webmock think it fails
      }
    end

    it "should support tempaltes" do
      verify_sent_events(%q<sourcetype "${tag_parts[0]}-${tag_parts[1]}">) { |r|
	expect(r.body).must_match(/"sourcetype"\s*:\s*"tag-event1"/)
	expect(r.body).must_match(/"sourcetype"\s*:\s*"tag-event2"/)
      }
    end
  end

  it "should be able to disable tempalte" do
    verify_sent_events(<<~CONF) { |r|
      template_engine none
      host "${hostname}"
      source "${source}"
      sourcetype "${sourcetype}"
    CONF
      expect(r.body.scan(/"host"\s*:\s*"\${hostname}"/).size).must_equal 2
      expect(r.body.scan(/"source"\s*:\s*"\${source}"/).size).must_equal 2
      expect(r.body.scan(/"sourcetype"\s*:\s*"\${sourcetype}"/).size).must_equal 2
    }
  end

  it "should support use a formatter" do
    verify_sent_events(<<~CONF) { |r|
      <format>
        @type single_value
	message_key message
	add_newline false
      </format>
    CONF
      expect(r.body.scan(/"event"\s*:\s*"test message"/).size).must_equal 2
    }
  end

  def verify_sent_events(conf = '', &blk)
    host = "hec.splunk.com"
    d = create_output_driver("hec_host #{host}", conf)

    hec_req = stub_hec_request("https://#{host}:8088").with &blk

    d.run do
      d.feed("tag.event1", event_time, {"message" => "test message", "id" => "1st"})
      d.feed("tag.event2", event_time, {"message" => "test message", "id" => "2nd"})
    end

    hec_req
  end
end
