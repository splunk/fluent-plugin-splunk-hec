# Installation
 Run the command `./build.sh <version>`. This will create the `gem` file in the docker folder.
   This script will build the docker image. The docker image is built on centos8 with yuby 2.7 runtime.

# Testing
Run `docker run -it <ImageId> bin/bash`. Inside the container, create `fluent.conf` file in  `/fluentd/etc/`. 

Minimum HEC configuration:
```aidl
<match **>
  @type splunk_hec
  hec_host 12.34.56.78
  hec_port 8088
  hec_token 00000000-0000-0000-0000-000000000000
</match>
```

Check `https://github.com/splunk/fluent-plugin-splunk-hec/blob/develop/README.md` for creating the fluent.conf file.

Inside the container, run the command `bundle exec fluentd -c /fluentd/etc/fluent.conf`