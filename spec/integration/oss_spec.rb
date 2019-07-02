# encoding: utf-8
require 'rspec'
require_relative 'common'

describe 'integration tests', :integration => true do
  include_context 'plugin initialize'

  before do
    Thread.abort_on_exception = true
  end

  after do
    clean_bucket(bucket)
    FileUtils.rm_rf(backup_to_dir)
  end

  it "backup to another bucket" do
    prefix = rand(999999).to_s + '/'
    upload(prefix)
    fetch_events(common_configurations.merge(
        { "backup_to_bucket" => backup_to_bucket,
          "backup_add_prefix" => backup_add_prefix,
          "prefix" => prefix,
        }), 74)
    expect(list_remote_files(backup_to_bucket, backup_add_prefix).size).to eq(2)
    expect(list_remote_files(bucket, prefix).size).to eq(2)
    clean_bucket(backup_to_bucket)
    delete_bucket(backup_to_bucket)
  end

  it "delete after backup" do
    prefix = rand(999999).to_s + '/'
    upload(prefix)
    fetch_events(common_configurations.merge(
        { "backup_to_bucket" => backup_to_bucket,
          "backup_add_prefix" => backup_add_prefix,
          "prefix" => prefix,
          "delete" => true
        }), 74)
    expect(list_remote_files(backup_to_bucket, backup_add_prefix).size).to eq(2)
    expect(list_remote_files(bucket, prefix).size).to eq(0)
    clean_bucket(backup_to_bucket)
    delete_bucket(backup_to_bucket)
  end

  it "backup to local dir" do
    prefix = rand(999999).to_s + '/'
    upload(prefix)
    fetch_events(common_configurations.merge(
        {
            "backup_to_dir" => backup_to_dir,
            "prefix" => prefix,
            "delete" => true
        }), 74)
    expect(list_remote_files(bucket, prefix).size).to eq(0)
    expect(Dir.glob("#{backup_to_dir}/**/*").size).to eq(4)
  end

  it "exclude pattern" do
    prefix = rand(999999).to_s + '/'
    upload(prefix)
    fetch_events(common_configurations.merge(
        { "backup_to_bucket" => backup_to_bucket,
          "backup_add_prefix" => backup_add_prefix,
          "prefix" => prefix,
          "exclude_pattern" => "^" + prefix + "exclude"
        }), 37)
    expect(list_remote_files(backup_to_bucket, backup_add_prefix).size).to eq(1)
    expect(list_remote_files(bucket, prefix).size).to eq(2)
    clean_bucket(backup_to_bucket)
    delete_bucket(backup_to_bucket)
  end
end