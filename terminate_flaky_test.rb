#!/usr/bin/env ruby
# frozen_string_literal: true

require 'open3'
require 'fileutils'
require 'json'
require 'optparse'

class TerminateFlakyTest
  DEFAULT_ITERATIONS = 5
  DEFAULT_SPEC_PATTERN = '_spec.rb'

  def initialize(options = {})
    @iterations = options[:iterations] || DEFAULT_ITERATIONS
    @spec_pattern = options[:spec_pattern] || DEFAULT_SPEC_PATTERN
    @base_branch = options[:base_branch] || 'main'
    @output_dir = options[:output_dir] || 'flaky_test_results'
    @verbose = options[:verbose] || false

    FileUtils.mkdir_p(@output_dir)
  end

  def run
    changed_spec_files = find_changed_spec_files

    if changed_spec_files.empty?
      puts 'No spec files changed.'
      return
    end

    puts "Found #{changed_spec_files.size} changed spec files:"
    changed_spec_files.each { |file| puts "  - #{file}" }

    results = {}
    flaky_locations = {}

    changed_spec_files.each do |spec_file|
      puts "\nRunning #{spec_file} #{@iterations} times..."
      file_results = run_spec_multiple_times(spec_file)
      results[spec_file] = file_results

      # 失敗した実行から場所の情報を抽出
      failure_locations = extract_failure_locations(file_results)
      flaky_locations[spec_file] = failure_locations if failure_locations.any?

      # 実行結果の分析
      failure_count = file_results.count { |r| !r[:success] }
      if failure_count.positive?
        puts "⚠️  FLAKY TEST DETECTED: #{spec_file} failed #{failure_count}/#{@iterations} runs"

        # 失敗場所を表示
        if failure_locations.any?
          puts '   Failure locations:'
          failure_locations.each do |location, count|
            puts "     - #{location} (failed #{count} times)"
          end
        end
      else
        puts "✅ All runs passed for: #{spec_file}"
      end
    end

    save_results(results, flaky_locations)
    print_summary(results, flaky_locations)
  end

  private

  def find_changed_spec_files
    puts @base_branch
    cmd = "git diff --name-only #{@base_branch} -- '**/*#{@spec_pattern}'"
    stdout, stderr, status = Open3.capture3(cmd)
    puts stdout

    raise "Error getting changed files: #{stderr}" unless status.success?

    stdout.split("\n").select { |file| File.exist?(file) }
  end

  def run_spec_multiple_times(spec_file)
    results = []

    @iterations.times do |i|
      print "  Run #{i + 1}/#{@iterations}: "
      start_time = Time.now

      # RSpec実行結果を詳細に取得するためのフォーマット指定
      cmd = "bundle exec rspec #{spec_file} --format documentation"
      stdout, stderr, status = Open3.capture3(cmd)

      duration = Time.now - start_time
      success = status.success?

      print success ? '✓' : '✗'
      puts " (#{duration.round(2)}s)"

      # エラー出力を保存
      if (@verbose || !success) && !success
        puts '    Error output:' if @verbose
        error_lines = stderr.split("\n")
        error_lines.each { |line| puts "      #{line}" } if @verbose
      end

      results << {
        run: i + 1,
        success: success,
        duration: duration,
        exit_code: status.exitstatus,
        timestamp: Time.now.iso8601,
        stdout: stdout,
        stderr: stderr
      }
    end

    results
  end

  def extract_failure_locations(file_results)
    failure_locations = Hash.new(0)

    file_results.each do |result|
      next if result[:success]

      # エラー出力から失敗箇所を抽出
      locations = extract_locations_from_output(result[:stdout], result[:stderr])

      locations.each do |location|
        failure_locations[location] += 1
      end
    end

    failure_locations
  end

  def extract_locations_from_output(stdout, stderr)
    locations = []

    # RSpec出力から失敗箇所を見つけるパターン
    # 例: "./spec/models/user_spec.rb:25"
    combined_output = "#{stdout}\n#{stderr}"

    # 行番号を含むファイルパスを検索
    location_patterns = [
      %r{(?:\./)?([^:\s]+_spec\.rb):(\d+)}, # 標準的なRSpecの失敗出力パターン
      /# ([^:\s]+):(\d+):/, # バックトレースからの行番号パターン
      %r{Failure/Error: (.+?):(\d+)} # 別の失敗パターン
    ]

    location_patterns.each do |pattern|
      combined_output.scan(pattern) do |file, line|
        # フルパスを構築
        locations << if file.start_with?('./')
                     end
        "#{file}:#{line}"
      end
    end

    # 重複を削除
    locations.uniq
  end

  def save_results(results, flaky_locations)
    timestamp = Time.now.strftime('%Y%m%d_%H%M%S')
    filename = File.join(@output_dir, "flaky_test_results_#{timestamp}.json")

    # ファイルサイズを小さくするため、stdout と stderr は保存しない
    compact_results = {}
    results.each do |file, runs|
      compact_results[file] = runs.map do |run|
        run.except(:stdout, :stderr)
      end
    end

    output = {
      results: compact_results,
      flaky_locations: flaky_locations
    }

    File.write(filename, JSON.pretty_generate(output))

    puts "\nResults saved to #{filename}"
  end

  def print_summary(results, flaky_locations)
    flaky_tests = []

    results.each do |file, runs|
      failure_count = runs.count { |r| !r[:success] }
      next unless failure_count.positive? && failure_count < @iterations

      flaky_tests << {
        file: file,
        failure_rate: (failure_count.to_f / @iterations * 100).round(2),
        locations: flaky_locations[file] || {}
      }
    end

    puts "\nSummary:"
    puts "#{flaky_tests.size} flaky tests detected out of #{results.size} changed spec files."

    return if flaky_tests.empty?

    puts "\nFlaky tests:"
    flaky_tests.sort_by { |t| -t[:failure_rate] }.each do |test|
      puts "  - #{test[:file]} (#{test[:failure_rate]}% failure rate)"

      next unless test[:locations].any?

      puts '    Failure locations:'
      test[:locations].sort_by { |_, count| -count }.each do |location, count|
        puts "      - #{location} (failed #{count} times)"
      end
    end
  end
end

# コマンドラインオプションの処理
options = {}
OptionParser.new do |opts|
  opts.banner = 'Usage: ruby flaky_test_detector.rb [options]'

  opts.on('-i', '--iterations N', Integer,
          "Number of times to run each spec (default: #{TerminateFlakyTest::DEFAULT_ITERATIONS})") do |n|
    options[:iterations] = n
  end

  opts.on('-b', '--base-branch BRANCH', 'Base branch to compare against (default: main)') do |branch|
    options[:base_branch] = branch
  end

  opts.on('-p', '--pattern PATTERN',
          "Pattern to match spec files (default: #{TerminateFlakyTest::DEFAULT_SPEC_PATTERN})") do |pattern|
    options[:spec_pattern] = pattern
  end

  opts.on('-o', '--output-dir DIR', 'Directory to save results (default: flaky_test_results)') do |dir|
    options[:output_dir] = dir
  end

  opts.on('-v', '--verbose', 'Show detailed error output for failed runs') do |v|
    options[:verbose] = v
  end

  opts.on('-h', '--help', 'Show this help message') do
    puts opts
    exit
  end
end.parse!

TerminateFlakyTest.new(options).run
