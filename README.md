[![CircleCI](https://circleci.com/gh/git-lfs/git-lfs.svg?style=shield&circle-token=856152c2b02bfd236f54d21e1f581f3e4ebf47ad)](https://circleci.com/gh/splunk/fluent-plugin-splunk-hec)
# fluent-plugin-splunk-hec

[Fluentd](https://fluentd.org/) output plugin to send events and metrics to [Splunk](https://www.splunk.com) over the HEC (HTTP Event Collector) API.

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

# Configuration for Ingest API

* See also: [Output Plugin Overview](https://docs.fluentd.org/v1.0/articles/output-plugin-overview)

#### Example 1: Minimum Configuration

```
<match **>
  @type splunk_hec
  hec_host 12.34.56.78
  hec_port 8088
  hec_token 00000000-0000-0000-0000-000000000000
</match>
```

This example is very basic, it just tells the plugin to send events to Splunk HEC on `https://12.34.56.78:8088` (https is the default protocol), using the HEC token `00000000-0000-0000-0000-000000000000`. It will use whatever index, source, sourcetype are configured in HEC. And the `host` of each event is the hostname of the machine which running fluentd.


#### Example 2: Configuration example

```
<match **>
@type splunk_ingest_api
service_client_identifier xxxxxxxx
service_client_secret_key xxxx-xxxxx
token_endpoint ex: /system/identity/v2beta1/token
ingest_api_host ex: api.url.splunk.com
ingest_api_tenant ex: mytenant
ingest_api_events_endpoint ex: /ingest/mybuild/events
debug_http false
</match>
```

This example shows the API parameters that give you more control over the plugin beaviors.

#### Example 3: Overwrite HEC defaults

```
<match **>
  @type splunk_hec
  hec_host 12.34.56.78
  hec_port 8088
  hec_token 00000000-0000-0000-0000-000000000000

  index awesome
  source ${tag}
  sourcetype _json
</match>
```

This configuration will
* send all events to the `awesome` index, and
* set their source to the event tags. `${tag}` is a special value which will be replaced by the event tags, and
* set their sourcetype to `_json`.

Sometimes you want to use the values from the input event for these parameters, this is where the `*_key` parameters help.

```
<match **>
  ...omitting other parameters...

  source_key file_path
</match>
```

In this example (in order to keep it concise, we just omitted the repeating parameters, and we will keep doing so in the following examples), it uses the `source_key` config to set the source of event to the value of the event's `file_path` field. Given an input event like
```javascript
{"file_path": "/var/log/splunk.log", "message": "This is an exmaple.", "level": "info"}
```
Then the source for this event will be "/var/log/splunk.log". And the "file\_path" field will be removed from the input event, so what you will eventually get ingested in Splunk is:
```javascript
{"message": "This is an exmaple.", "level": "info"}
```
If you want to keep "file\_path" in the event, you can use `keep_keys`.

Besides `source_key` there are also other `*_key` parameters, check the parameters details below.

#### Example 4: Sending metrics

[Metrics](https://docs.splunk.com/Documentation/Splunk/latest/Metrics/Overview) is available since Splunk 7.0.0, you can use this output plugin to send events as metrics to a Splunk metric index by setting `data_type` to "metric".

```
<match **>
  @type splunk_hec
  data_type metric
  hec_host 12.34.56.78
  hec_port 8088
  hec_token 00000000-0000-0000-0000-000000000000
</match>
```

With this configuration, the plugin will treat each input event as a collection of metrics, i.e. each key-value pair in the event is a metric name-value pair. For example, given an input event like

```javascript
{"cpu/usage": 0.5, "cpu/rate": 10, "memory/usage": 100, "memory/rss": 90}
```

then 4 metrics will be sent to splunk.

If the input events are not like this, instead they have the metric name and metric value as properties of the event. Then you can use `metric_name_key` and `metric_value_key`. Given an input event like

```javascript
{"metric": "cpu/usage", "value": 0.5, "app": "web_ui"}
```

You should change the configuration to

```
<match **>
  @type splunk_hec
  data_type metric
  hec_host 12.34.56.78
  hec_port 8088
  hec_token 00000000-0000-0000-0000-000000000000

  metric_name_key metric
  metric_value_key value
</match>
```

All other properties of the input (in this example, "app"), will be sent as dimensions of the metric. You can use the `<fields>` section to customize the dimensions.

### Parameters

#### @type

This value must always be set to `splunk_hec`.

#### protocol (enum) (optional)

This is the protocol to use for calling the HEC API. Available values are: http, https. This parameter is 
set to `https` by default.

### hec_host (string) (required)

The hostname/IP for the HEC token or the HEC load balancer.

### hec_port (integer) (optional)

The port number for the HEC token or the HEC load balancer. The default value is `8088`.

### hec_token (string) (required)

Identifier for the HEC token.

### fields (init) (optional)

Lets you specify the index-time fields for the event data type, or metric dimensions for the metric data type. Null value fields are removed.

### index (string) (optional)

Identifier for the Splunk index to be used for indexing events. If this parameter is not set, 
the indexer is chosen by HEC. This parameter only works in conjunction with the `index_key` parameter.

### index_key (string) (optional)

The field name that contains the Splunk index name. This parameter works in conjunction with `index` and will 
not work if the `index` parameter is not set.

### host (string) (optional)

The host location for events. This parameter only works in conjunction with the `host_key` parameter. 
If the parameter is not set, the default value is the hostname of the machine runnning fluentd.

### host_key (string) (optional)

Key for the host location. This parameter only works in conjunction with the `host` parameter. If the `host`
parameter is not set, this parameter is ignored.

### keep_keys (boolean) (Optional)

When set to true, all fields defined in `index_key`, `host_key`, `source_key`, `sourcetype_key`, `metric_name_key`, and `metric_value_key` are saved in the original event.

### source (string) (optional)

The source field for events. If this parameter is not set, the source will be decided by HEC. This
parameter only works in conjunction with the `source_key` parameter.

### source_key (string) (optional)

Field name to contain source. This parameter only works in conjunction with the `source` parameter.

### sourcetype (string) (optional)

The sourcetype field for events. When not set, the sourcetype is decided by HEC. This parameter only works in 
conjunction with the `sourcetype_key` parameter.

### sourcetype_key (string) (optional)

Field name that contains the sourcetype. This parameter only works in conjunction with the `sourcetype` parameter.

### metrics_from_event (bool) (optional)

When `data_type` is set to "metric", the ingest API will treat every key-value pair in the input event as a metric name-value pair. Set `metrics_from_event` to `false` to disable this behavior and use `metric_name_key` and `metric_value_key` to define metrics. The default value is `true`.

### metric_name_key (string) (optional)

Field name that contains the metric name. This parameter only works in conjunction with the `metrics_from_event` paramter. When this prameter is set, the `metrics_from_event` parameter is automatically set to `false`.

### metric_value_key (string) (optional)

Field name that contains the metric value, this parameter is required when `metric_name_key` is configured.

### keep_keys (bool) (optional)

By default, all the fields used by the `*_key` parameters are removed from the original input events. To change this behavior, set this parameter to `true`. This parameter is set to `false` by default.

### service_client_identifier: (optional) (String) 

Splunk uses the client identifier to make authorized requests to the ingest API.

### service_client_secret_key: (String) 

The client identifier uses this authorization to make requests to the ingest API.

### token_endpoint: (String) 

This value indicates which endpoint Splunk should look to for the authorization token necessary for requests to the ingest API.

### ingest_api_host: (String) 

Indicates which url/hostname to use for requests to the ingest API.

### ingest_api_tenant: (String) 

Indicates which tenant Splnk should use for requests to the ingest API.

### ingest_api_events_endpoint: (String) 

Indicates which endpoint to use for requests to the ingest API.

### coerce_to_utf8 (bool) (optional)

Indicates whether to allow non-UTF-8 characters in user logs. If set to `true`, any non-UTF-8 character is replaced by the string specified in `non_utf8_replacement_string`. If set to `false`, the Ingest API errors out any non-UTF-8 characters. This parameter is set to `true` by default.

### non_utf8_replacement_string (string) (optional)

If `coerce_to_utf8` is set to `true`, any non-UTF-8 character is replaced by the string you specify in this parameter. The parameter is set to `' '` by default.

### &lt;fields&gt; section (optional) (single)

Depending on the value of `data_type` parameter, the parameters inside the `<fields>` section have different meanings. Despite the meaning, the syntax for parameters is unique.

debug_http: (Boolean) Set to True if you want to debug requests and responses to ingest API. Default is false.
#### When `data_type` is `event`

In this case, parameters inside `<fields>` are used as indexed fields and removed from the original input events. Please see the "Add a "fields" property at the top JSON level" [here](http://dev.splunk.com/view/event-collector/SP-CAAAFB6) for details. Given we have configuration like

```
<match **>
  @type splunk_hec
  ...omitting other parameters...

  <fields>
    file
    level
    app applicatioin
  </fields>
</match>
```

and an input event like

```javascript
{"application": "webServer", "file": "server.rb", "lineNo": 100, "level": "info", "message": "Request finished in 30ms."}
```

Then the HEC request JSON payload will be:

```javascript
{
   // omitting other fields
   // ...
   "event": "{\"lineNo\": 100, \"message\": \"Request finished in 30ms.\"}",
   "fields": {
     "file": "server.rb",
     "level": "info",
     "app": "webServer"
   }
}
```

As you can see, parameters inside `<fields>` section can be a key-value pair or just a key (a name).
If a parameter is a key-value, the key will be the name of the field inside the `"fields"` JSON object,
whereas the value is the field name of the input event. So a key-value pair is a rename.

If a parameter has just a key, it means its value is exactly the same as the key.

#### When `data_type` is `metric`

For metrics, parameters inside `<fields>` are used as dimensions. If `<fields>` is not presented, the original input event will be used as dimensions. If an empty `<fields></fields>` is presented, no dimension is sent. For example, given the following configuration: 

```
<match **>
  @type splunk_hec
  data_type metric
  ...omitting other parameters...

  metric_name_key name
  metric_value_key value
  <fields>
    file
    level
    app applicatioin
  </fields>
</match>
```

and the following input event:

```javascript
{"application": "webServer", "file": "server.rb", "value": 100, "status": "OK", "message": "Normal", "name": "CPU Usage"}
```

Then, a metric of "CPU Usage" with value=100, along with 3 dimensions file="server.rb", status="OK", and app="webServer" are sent to Splunk.

### &lt;format&gt; section (optional) (multiple)

The `<format>` section let you define which formatter to use to format events.
By default, it uses [the `json` formatter](https://docs.fluentd.org/v1.0/articles/formatter_jso://docs.fluentd.org/v1.0/articles/formatter_json).

Besides the `@type` parameter, you should define the other parameters for the formatter inside this section.

Multiple `<format>` sections can be defined to use different formatters for different tags. Each `<format>` section accepts an argument just like the `<match>` section does to define tag matching. By default, every event is formatted with `json`. For example:

```
<match **>
  @type splunk_hec
  ...

  <format sometag.**>
    @type single_value
    message_key log
  </format>

  <format some.othertag>
    @type csv
    fields ["some", "fields"]
  </format>
```

This example: 
- Formats events with tags that start with `sometag.` with the `single_value` formatter
- Formats events with tags `some.othertag` with the `csv` formatter
- Formats all other events with the `json` formatter (the default formatter)

If you want to use a different default formatter, you can add a `<format **>` (or `<format>`) section.

#### @type (string) (required)

Specifies which formatter to use.

### Net::HTTP::Persistent parameters (optional)

The following parameters can be used for tuning HTTP connections:

#### idle_timeout (integer)

The default is five seconds. If a connection has not been used for five seconds, it is automatically reset at next use, in order to avoid attempting to send to a closed connection. Specifiy `nil` to prohibit any timeouts. 

#### read_timeout (integer)
The amount of time allowed between reading two chunks from the socket. The default value is `nil`, which means no timeout. 

#### open_timeout (integer)

The amount of time to wait for a connection to be opened. The default is `nil`, which means no timeout.

### SSL parameters

The following optional parameters let you configure SSL for HTTPS protocol.

#### client_cert (string)

The path to a file containing a PEM-format CA certificate for this client.

#### client_key (string)

The private key for this client.

#### ca_file (string)

The path to a file containing a PEM-format CA certificate.

#### ca_path (string)

The path to a directory containing CA certificates in PEM format.

#### ciphers (array)

List of SSl ciphers allowed.

#### insecure_ssl (bool)

Specifies whether an insecure SSL connection is allowed. If set to false, Splunk does not verify an insecure server certificate. This parameter is set to `false` by default.

## About Buffer

This plugin sends events to HEC using [batch mode](https://docs.splunk.com/Documentation/Splunk/7.1.0/Data/FormateventsforHTTPEventCollector#Event_data).
It batches all events in a chunk in one request. So you need to configure the `<buffer>` section carefully to gain the best performance.
Here are some hints:

* Read through the [fluentd buffer document](https://docs.fluentd.org/v1.0/articles/buffer-section) to understand the buffer configurations.
* Use `chunk_limit_size` and/or `chunk_limit_records` to define how big a chunk can be. And remember that all events in a chunk will be sent in one request.
* Splunk has a limit on how big the payload of a HEC request can be. And it's defined with `max_content_length` in [the `[http_input]` section of `limits.conf`](https://docs.splunk.com/Documentation/Splunk/latest/Admin/Limitsconf#.5Bhttp_input.5D). In Splunk of version 6.5.0+, the default value is 800MiB, while in versions before 6.5.0, it's just 1MB. Make sure your chunk size won't exceed this limit, or you should change the limit on your Splunk deployment.
* Sending requests to HEC takes time, so if you flush your fluentd buffer too fast (for example, with a very small `flush_interval`), it's possible that the plugin cannot catch up with the buffer flushing. There are two ways you can handle this situation, one is to increase the `flush_interval` or use multiple flush threads by setting `flush_thread_count` to a number bigger than 1.

## Ingest API parameters

### service_client_identifier: (String) 
Splunk uses the client identifier to make authorized requests to the ingest API. 

### service_client_secret_key: (String) 
The client identifier uses this authorization to make requests to the ingest API. 

### token_endpoint: (String) 
This value indicates which endpoint Splunk should look to for the authorization token necessary for requests to the ingest API. 

### ingest_api_host: (String) 
Indicates which url/hostname to use for requests to the ingest API. 

### ingest_api_tenant: (String) 
Indicates which tenant Splnk should use for requests to the ingest API. 

### ingest_api_events_endpoint: (String) 
Indicates which endpoint to use for requests to the ingest API. 

### debug_http: (Boolean) 
Set to `True` if you want to debug requests and responses to ingest API. Default is `false`.

## License

Please see [LICENSE](LICENSE). 
