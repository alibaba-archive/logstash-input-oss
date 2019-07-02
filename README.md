# Logstash OSS Input Plugin

This is a plugin for [Logstash](https://github.com/elastic/logstash).

It is fully free and fully open source. The license is Apache 2.0, meaning you are pretty much free to use it however you want in whatever way.

## Documentation

This plugin reads data from OSS periodically.

This plugin uses MNS on the same region of the OSS bucket. We must setup MNS and OSS event notification before using this plugin.

[This document](https://help.aliyun.com/document_detail/52656.html) shows how to setup MNS and OSS event notification.

This plugin will poll events from MNS queue and extract object keys from these events, and then will read those objects from OSS.

### Usage:
This is an example of logstash config:

```
input {
  oss {
    "endpoint" => "OSS endpoint to connect to"                     (required)
    "bucket" => "Your bucket name"                                 (required)
    "access_key_id" => "Your access key id"                        (required)
    "access_key_secret" => "Your secret key"                       (required)
    "backup_to_bucket" => "Your backup bucket name"                (optional, default = nil)
    "prefix" => "sample"                                           (optional, default = nil)
    "delete" => false                                              (optional, default = false)
    "exclude_pattern" => "^sample-logstash"                        (optional, default = nil)
    "backup_add_prefix" => "logstash-input/"                       (optional, default = nil)
    "include_object_properties" => true                            (optional, default = false)
    "additional_oss_settings" => {
      "max_connections_to_oss" => 1024                             (optional, default = 1024)
      "secure_connection_enabled" => false                         (optional, default = false)
    }
    "mns_settings" => {                                            (required)
      "endpoint" => "MNS endpoint to connect to"                   (required)
      "queue" => "MNS queue name"                                  (required)
      "poll_interval_seconds" => 10                                (optional, default = 10)
      "wait_seconds" => 3                                          (optional, default = nil)
    }
    codec => json {
      charset => "UTF-8"
    }
  }
}
```
### Logstash OSS Input Configuration Options
This plugin supports the following configuration options

Note: Files end with `.gz` or `.gzip` are handled as gzip'ed files, others are handled as plain files.

|Configuration|Type|Required|Comments|
|:---:|:---:|:---:|:---|
|endpoint|string|Yes|OSS endpoint to connect|
|bucket|string|Yes|Your OSS bucket name|
|access_key_id|string|Yes|Your access key id|
|access_key_secret|string|Yes|Your access secret key|
|prefix|string|No|If specified, the prefix of filenames in the bucket must match (not a regexp)|
|additional_oss_settings|hash|No|Additional oss client configurations, valid keys are: `secure_connection_enabled` and `max_connections_to_oss`|
|delete|boolean|No|Whether to delete processed files from the original bucket|
|backup_to_bucket|string|No|Name of an OSS bucket to backup processed files to|
|backup_to_dir|string|No|Path of a local directory to backup processed files to|
|backup_add_prefix|string|No|Append a prefix to the key (full path including file name in OSS) after processing(If backing up to another (or the same) bucket, this effectively lets you choose a new 'folder' to place the files in)|
|include_object_properties|boolean|No|Whether or not to include the OSS object's properties (last_modified, content_type, metadata) into each Event at [@metadata][oss]. Regardless of this setting, [@metadata][oss][key] will always be present|
|exclude_pattern|string|No|Ruby style regexp of keys to exclude from the bucket|
|mns_settings|hash|Yes|MNS settings, valid keys are: `endpoint`, `queue`, `poll_interval_seconds`, `wait_seconds`|

#### mns_settings

[MNS consume messages](https://help.aliyun.com/document_detail/35136.html)

* endpoint
* queue
* wait_seconds
* poll_interval_seconds Poll messages interval from MNS if there is no message this time, default 10 seconds

For more details about mns configurations, please view MNS documentation in the link above.

## Need Help?

Need help? Try #logstash on freenode IRC or the https://discuss.elastic.co/c/logstash discussion forum.

## Developing

### 1. Plugin Development and Testing

#### Code
- To get started, you'll need JRuby with the Bundler gem installed.

- Install dependencies
```sh
bundle install
```

#### Test

- Update your dependencies

```sh
bundle install
```

- Run tests

```sh
bundle exec rspec
```

### 2. Running your unpublished Plugin in Logstash

#### 2.1 Run in an installed Logstash

you can build the gem and install it using:

- Build your plugin gem

```sh
gem build logstash-input-oss.gemspec
```

- Install the plugin from the Logstash home

```sh
bin/logstash-plugin install /path/to/logstash-input-oss-0.0.1-java.gem
```

- Start Logstash and proceed to test the plugin

```bash
./bin/logstash -f config/logstash-sample.conf
```

## Contributing

All contributions are welcome: ideas, patches, documentation, bug reports, complaints, and even something you drew up on a napkin.

Programming is not a required skill. Whatever you've seen about open source and maintainers or community members  saying "send patches or die" - you will not see that here.

It is more important to the community that you are able to contribute.

For more information about contributing, see the [CONTRIBUTING](https://github.com/elastic/logstash/blob/master/CONTRIBUTING.md) file.