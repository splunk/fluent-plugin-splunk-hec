# fluent-plugin-splunk-hec

[Fluentd](https://fluentd.org/) output plugin to send events to [Splunk](https://www.splunk.com) over the HEC (HTTP Event Collector) API.

## Installation

### RubyGems

```
$ gem install fluent-plugin-splunk-hec
```

### Bundler

Add following line to your Gemfile:

```ruby
gem "fluent-plugin-splunk-hec"
```

And then execute:

```
$ bundle
```

## Configuration

* See also: [Output Plugin Overview](https://docs.fluentd.org/v1.0/articles/output-plugin-overview)

### protocol (enum) (optional)

Which protocol to use to call HEC api, "http" or "https", default "https".

Available values: http, https

Default value: `https`.

### hec_host (string) (required)

The hostname/IP of the Splunk instance which has HTTP input enabled, or a HEC load balancer.

### hec_port (integer) (optional)

The port number of the HTTP input, or the HEC load balancer.

Default value: `8088`.

### hec_token (string) (required)

The HEC token.

### index (string) (optional)

The Splunk index indexs events, by default it is not set, and will use what is configured in the HTTP input. Liquid template is supported.

### host (string) (optional)

Set the host field for events, by default it's the hostname of the machine that runnning fluentd. Liquid template is supported.

### source (string) (optional)

The source will be applied to the events, by default it uses the event's tag. Liquid template is supported.

### sourcetype (string) (optional)

The sourcetype will be applied to the events, by default it is not set, and leave it to Splunk to figure it out. Liquid template is supported.

### disable_template (bool) (optional)

Disable Liquid template support. Once disabled, it cannot use Liquid templates in the `host`, `index`, `source`, `sourcetype` fields.

### coerce_to_utf8 (bool) (optional)



Default value: `true`.

### non_utf8_replacement_string (string) (optional)



Default value: ` `.


### \<ssl\> section (optional) (single)

#### client_cert (string) (optional)

The path to a file containing a PEM-format CA certificate for this client.

#### ca_file (string) (optional)

The path to a file containing a PEM-format CA certificate.

#### ca_path (string) (optional)

The path to a directory containing CA certificates in PEM format.

#### ciphers (array) (optional)

List of SSl ciphers allowed.

#### client_pkey (string) (optional)

The client's SSL private key.

#### insecure (bool) (optional)

If `insecure` is set to true, it will not verify the server's certificate. If `ca_file` or `ca_path` is set, `insecure` will be ignored.



### \<format\> section (optional) (single)

#### @type (string) (required)


## Copyright

* Copyright(c) 2018- Gimi Liang @ Splunk Inc.
* License
  * Apache License, Version 2.0
