# encoding: utf-8
require 'json'
require 'logstash/inputs/base'
require 'logstash-input-oss_jars'

java_import com.aliyun.oss.OSS
java_import com.aliyun.oss.OSSClientBuilder
java_import com.aliyun.oss.ClientBuilderConfiguration
java_import com.aliyun.oss.model.GetObjectRequest
java_import java.io.InputStream
java_import java.io.InputStreamReader
java_import java.io.FileInputStream
java_import java.io.BufferedReader
java_import java.util.zip.GZIPInputStream
java_import java.util.zip.ZipException

#
# LogStash OSS Input Plugin
# Stream events from files from an OSS bucket.
# Each line from each file generates an event.
# Files end with `.gz` or `.gzip` are handled as gzip'ed files.
#
class LogStash::Inputs::OSS < LogStash::Inputs::Base
  require 'logstash/inputs/mns/message'
  require 'logstash/inputs/mns/request'
  require 'logstash/inputs/version'

  MAX_CONNECTIONS_TO_OSS_KEY = "max_connections_to_oss"

  SECURE_CONNECTION_ENABLED_KEY = "secure_connection_enabled"

  MNS_ENDPOINT = "endpoint"

  MNS_QUEUE = "queue"

  MNS_WAIT_SECONDS = "wait_seconds"

  MNS_POLL_INTERVAL_SECONDS = "poll_interval_seconds"

  config_name "oss"

  default :codec, "plain"

  # The name of OSS bucket.
  config :bucket, :validate => :string, :required => true

  # OSS endpoint to connect
  config :endpoint, :validate => :string, :required => true

  # access key id
  config :access_key_id, :validate => :string, :required => true

  # access secret key
  config :access_key_secret, :validate => :string, :required => true

  # If specified, the prefix of filenames in the bucket must match (not a regexp)
  config :prefix, :validate => :string, :default => nil

  # additional oss client configurations, valid keys are:
  # secure_connection_enabled(enable https or not)
  # max_connections_to_oss(max connections to oss)
  # TODO: add other oss configurations
  config :additional_oss_settings, :validate => :hash, :default => nil

  # Name of an OSS bucket to backup processed files to.
  config :backup_to_bucket, :validate => :string, :default => nil

  # Append a prefix to the key (full path including file name in OSS) after processing.
  # If backing up to another (or the same) bucket, this effectively lets you
  # choose a new 'folder' to place the files in
  config :backup_add_prefix, :validate => :string, :default => nil

  # Path of a local directory to backup processed files to.
  config :backup_to_dir, :validate => :string, :default => nil

  # Whether to delete processed files from the original bucket.
  config :delete, :validate => :boolean, :default => false

  # MNS configurations, valid keys are:
  # endpoint: MNS endpoint to connect to
  # queue: MNS queue to poll messages
  # wait_seconds: MNS max waiting time to receive messages, not required
  # poll_interval_seconds: Poll messages interval from MNS if there is no message this time, default 10 seconds
  config :mns_settings, :validate => :hash, :required => true

  # Ruby style regexp of keys to exclude from the bucket
  config :exclude_pattern, :validate => :string, :default => nil

  # Whether or not to include the OSS object's properties (last_modified, content_type, metadata)
  # into each Event at [@metadata][oss]. Regardless of this setting, [@metadata][oss][key] will always
  # be present.
  config :include_object_properties, :validate => :boolean, :default => false

  # For testing
  config :stop_for_test, :validate => :boolean, :default => false

  public
  def register
    @logger.info("Registering oss input", :bucket => @bucket)

    # initialize oss client
    @oss = initialize_oss_client

    unless @backup_to_bucket.nil?
      if @backup_to_bucket == @bucket
        raise LogStash::ConfigurationError, "Logstash Input OSS Plugin: backup bucket and source bucket should be different"
      end

      unless @oss.doesBucketExist(@backup_to_bucket)
        @oss.createBucket(@backup_to_bucket)
      end
    end

    unless @backup_to_dir.nil?
      Dir.mkdir(@backup_to_dir, 0700) unless File.exists?(@backup_to_dir)
    end

    if @mns_settings.include?(MNS_POLL_INTERVAL_SECONDS)
      @interval = @mns_settings[MNS_POLL_INTERVAL_SECONDS]
    else
      @interval = 10
    end

    @mns_endpoint = @mns_settings[MNS_ENDPOINT]
    @mns_queue = @mns_settings[MNS_QUEUE]
    @mns_wait_seconds = @mns_settings[MNS_WAIT_SECONDS]
  end

  public
  def run(queue)
    @current_thread = Thread.current
    Stud.interval(0.01) do
      @logger.info "Start to poll message from MNS queue #{@mns_queue}"
      process_objects(queue)
      stop if stop?
      if @stop_for_test and not @fetched
        do_stop
      end
      sleep @interval unless @fetched
    end
  end

  public
  def stop
    # @current_thread is initialized in the `#run` method,
    # this variable is needed because the `#stop` is a called in another thread
    # than the `#run` method and requiring us to call stop! with a explicit thread.
    @logger.info("Logstash OSS Input Plugin is shutting down...")
    Stud.stop!(@current_thread)
  end

  private
  def process_objects(queue)
    message = receive_message
    if message.nil?
      @fetched = false
    else
      @fetched = true
      process(LogStash::Inputs::MNS::Message.new(@mns_queue, message), queue)
    end
  end

  private
  def receive_message
    request_opts = {}
    request_opts = { waitseconds: @mns_wait_seconds } if @mns_wait_seconds
    opts = {
      log: @logger,
      method: 'GET',
      endpoint: @mns_endpoint,
      path: "/queues/#{@mns_queue}/messages",
      access_key_id: @access_key_id,
      access_key_secret: @access_key_secret
    }
    LogStash::Inputs::MNS::Request.new(opts, {}, request_opts).execute
  end

  private
  def process(message, queue)
    objects = get_objects(message)
    objects.each do |object|
      key = object.key
      if key.end_with?("/")
        @logger.info("Skip directory " + key)
      elsif @prefix and @prefix != "" and not key.start_with?(@prefix)
        @logger.info("Skip object " + key + " because object name does not match " + @prefix)
      elsif @exclude_pattern and key =~ Regexp.new(@exclude_pattern)
        @logger.info("Skip object " + key + " because object name matches exclude_pattern")
      else
        metadata = {}
        begin
          read_object(key) do |line, object_meta|
            @codec.decode(line) do |event|
              if event_is_metadata?(event)
                @logger.debug('Event is metadata, updating the current cloudfront metadata', :event => event)
                update_metadata(metadata, event)
              else
                decorate(event)

                event.set("cloudfront_version", metadata[:cloudfront_version]) unless metadata[:cloudfront_version].nil?
                event.set("cloudfront_fields", metadata[:cloudfront_fields]) unless metadata[:cloudfront_fields].nil?

                if @include_object_properties
                  object_meta.each do |key, value|
                    event.set("[@metadata][oss][" + key + "]", value.to_s)
                  end
                else
                  event.set("[@metadata][oss]", {})
                end

                event.set("[@metadata][oss][key]", key)
                queue << event
              end
            end

            @codec.flush do |event|
              queue << event
            end
          end
          backup_to_bucket(key)
          backup_to_dir(key)
          delete_file_from_bucket(key)
        rescue Exception => e
          # skip any broken file
          @logger.error("Failed to read object. Skip processing.", :key => key, :exception => e.message)
        end
      end
    end
    delete_message(message)
  end

  private
  def event_is_metadata?(event)
    return false unless event.get("message").class == String
    line = event.get("message")
    version_metadata?(line) || fields_metadata?(line)
  end

  private
  def version_metadata?(line)
    line.start_with?('#Version: ')
  end

  private
  def fields_metadata?(line)
    line.start_with?('#Fields: ')
  end

  private
  def update_metadata(metadata, event)
    line = event.get('message').strip

    if version_metadata?(line)
      metadata[:cloudfront_version] = line.split(/#Version: (.+)/).last
    end

    if fields_metadata?(line)
      metadata[:cloudfront_fields] = line.split(/#Fields: (.+)/).last
    end
  end

  private
  def read_object(key, &block)
    @logger.info("Processing object " + key)
    object = @oss.getObject(@bucket, key)
    meta = object.getObjectMetadata.getRawMetadata
    input = object.getObjectContent
    content = input
    if gzip?(key)
      content = GZIPInputStream.new(input)
    end

    decoder = InputStreamReader.new(content, "UTF-8")
    buffered = BufferedReader.new(decoder)

    while (line = buffered.readLine)
      block.call(line, meta)
    end
  ensure
    buffered.close unless buffered.nil?
    decoder.close unless decoder.nil?
    content.close unless content.nil?
    input.close unless input.nil?
  end

  private
  def gzip?(filename)
    filename.end_with?('.gz','.gzip')
  end

  private
  def backup_to_bucket(key)
    unless @backup_to_bucket.nil?
      backup_key = "#{@backup_add_prefix}#{key}"
      @oss.copyObject(@bucket, key, @backup_to_bucket, backup_key)
    end
  end

  private
  def backup_to_dir(key)
    unless @backup_to_dir.nil?
      file = @backup_to_dir + '/' + key

      dirname = File.dirname(file)
      unless File.directory?(dirname)
        FileUtils.mkdir_p(dirname)
      end

      @oss.getObject(GetObjectRequest.new(@bucket, key), java.io.File.new(file))
    end
  end

  private
  def delete_file_from_bucket(key)
    if @delete
      @oss.deleteObject(@bucket, key)
    end
  end

  private
  def get_objects(message)
    objects = []
    events = JSON.parse(Base64.decode64(message.body))['events']
    events.each do |event|
      objects.push(OSSObject.new(event['eventName'],
                                 @bucket,
                                 event['oss']['object']['key'],
                                 event['oss']['object']['size'],
                                 event['oss']['object']['eTag']))
    end
    objects
  end

  private
  def delete_message(message)
    request_opts = { ReceiptHandle: message.receipt_handle }
    opts = {
      log: @logger,
      method: 'DELETE',
      endpoint: @mns_endpoint,
      path: "/queues/#{@mns_queue}/messages",
      access_key_id: @access_key_id,
      access_key_secret: @access_key_secret
    }
    LogStash::Inputs::MNS::Request.new(opts, {}, request_opts).execute
  end

  # OSS Object class from MNS events
  class OSSObject
    attr_reader :event_name, :bucket, :key, :size, :etag
    def initialize(event_name, bucket, key, size, etag)
      @event_name = event_name
      @bucket = bucket
      @key = key
      @size = size
      @etag = etag
    end
  end

  private
  def initialize_oss_client
    clientConf = ClientBuilderConfiguration.new
    unless @additional_oss_settings.nil?
      if @additional_oss_settings.include?(SECURE_CONNECTION_ENABLED_KEY)
        clientConf.setProtocol(@additional_oss_settings[SECURE_CONNECTION_ENABLED_KEY] ?
          com.aliyun.oss.common.comm.Protocol::HTTPS : com.aliyun.oss.common.comm.Protocol::HTTP)
      end

      if @additional_oss_settings.include?(MAX_CONNECTIONS_TO_OSS_KEY)
        if @additional_oss_settings[MAX_CONNECTIONS_TO_OSS_KEY] <= 0
          raise LogStash::ConfigurationError, "Logstash OSS Input plugin must have positive " + MAX_CONNECTIONS_TO_OSS_KEY
        end
        clientConf.setMaxConnections(@additional_oss_settings[MAX_CONNECTIONS_TO_OSS_KEY])
      else
        clientConf.setMaxConnections(1024)
      end
    end

    clientConf.setUserAgent(clientConf.getUserAgent() + ", Logstash-oss/" + Version.version)
    OSSClientBuilder.new().build(@endpoint, @access_key_id, @access_key_secret, clientConf)
  end
end
