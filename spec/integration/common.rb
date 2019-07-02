# encoding: UTF-8

require 'logstash/devutils/rspec/spec_helper'
require 'logstash/logging/logger'
require 'logstash/inputs/oss'

java_import 'com.aliyun.oss.model.GetObjectRequest'

# This file contains the common logic used by integration tests
shared_context "plugin initialize" do
  let(:endpoint) { ENV['OSS_ENDPOINT'] }
  let(:bucket) { ENV['OSS_BUCKET'] }
  let(:access_key_id) { ENV['OSS_ACCESS_KEY'] }
  let(:access_key_secret) { ENV['OSS_SECRET_KEY'] }
  let(:backup_add_prefix) { 'input-oss/' }
  let(:backup_to_bucket) { ENV['BACKUP_BUCKET'] }
  let(:backup_to_dir) { ENV['BACKUP_DIR'] }
  let(:common_configurations) do
    {
        "endpoint" => endpoint,
        "bucket" => bucket,
        "access_key_id" => access_key_id,
        "access_key_secret" => access_key_secret,
        "stop_for_test" => true,
        "include_object_properties" => true,
        "mns_settings" => {
          "endpoint" => ENV['MNS_ENDPOINT'],
          "queue" => ENV['MNS_QUEUE'],
          "poll_interval_seconds" => 3,
          "wait_seconds" => 3
        }
    }
  end

  LogStash::Logging::Logger::configure_logging("debug") if ENV["DEBUG"]

  let(:oss) { OSSClientBuilder.new().build(endpoint, access_key_id, access_key_secret) }
end

def fetch_events(settings, size)
  queue = []
  input = LogStash::Inputs::OSS.new(settings)
  input.register
  thread = Thread.start do
    input.run(queue)
  end

  thread.join

  expect(queue.size).to eq(size)
end

# remove object with `prefix`
def clean_bucket(bucket)
  oss.listObjects(bucket, "").getObjectSummaries().each do |objectSummary|
    oss.deleteObject(bucket, objectSummary.getKey())
  end
end

def delete_bucket(bucket)
  oss.deleteBucket(bucket)
end

def list_remote_files(bucket, prefix)
  oss.listObjects(bucket, prefix).getObjectSummaries().collect(&:getKey)
end

def upload_local_file(local_file, remote_file_name)
  file = File.join(File.dirname(__FILE__), local_file)
  oss.putObject(bucket, remote_file_name, java.io.File.new(file))
end

def upload(prefix)
  upload_local_file('../sample/uncompressed.log', "uncompressed.log/")
  upload_local_file('../sample/uncompressed.log', "uncompressed.log")
  upload_local_file('../sample/uncompressed.log', "uncompressed.log.1.gz")
  upload_local_file('../sample/uncompressed.log', "#{prefix}uncompressed.log")
  upload_local_file('../sample/uncompressed.log.1.gz', "#{prefix}exclude/uncompressed.log.1.gz")
end