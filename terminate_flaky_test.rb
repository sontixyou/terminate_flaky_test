#!/usr/bin/env ruby
# frozen_string_literal: true

require 'open3'
require 'fileutils'
require 'json'
require 'optparse'

class TerminateFlakyTest
  DEFAULT_ITERATIONS = 5
  DEFAULT_SPEC_PATTERN = '_spec\.rb$'

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

    changed_spec_files.each do |spec_file|
      puts "\nRunning #{spec_file} #{@iterations} times..."
      file_results = run_spec_multiple_times(spec_file)
      results[spec_file] = file_results

      # 実行結果の分析
      failure_count = file_results.count { |r| !r[:success] }
      if failure_count.positive?
        puts "⚠️  FLAKY TEST DETECTED: #{spec_file} failed #{failure_count}/#{@iterations} runs"
      else
        puts "✅ All runs passed for: #{spec_file}"
      end
    end

    save_results(results)
    print_summary(results)
  end

  private

  def find_changed_spec_files
    cmd = "git diff --name-only #{@base_branch} -- '**/*#{@spec_pattern}'"
    stdout, stderr, status = Open3.capture3(cmd)

    raise "Error getting changed files: #{stderr}" unless status.success?

    stdout.split("\n").select { |file| File.exist?(file) }
  end

  def run_spec_multiple_times(spec_file)
    results = []

    @iterations.times do |i|
      print "  Run #{i + 1}/#{@iterations}: "
      start_time = Time.zone.now

      cmd = "bundle exec rspec #{spec_file} --format documentation"
      _, stderr, status = Open3.capture3(cmd)

      duration = Time.zone.now - start_time
      success = status.success?

      print success ? '✓' : '✗'
      puts " (#{duration.round(2)}s)"

      if @verbose && !success
        puts '    Error output:'
        stderr.split("\n").each { |line| puts "      #{line}" }
      end

      results << {
        run: i + 1,
        success: success,
        duration: duration,
        exit_code: status.exitstatus,
        timestamp: Time.now.iso8601
      }
    end

    results
  end

  def save_results(results)
    timestamp = Time.zone.now.strftime('%Y%m%d_%H%M%S')
    filename = File.join(@output_dir, "flaky_test_results_#{timestamp}.json")

    File.write(filename, JSON.pretty_generate(results))

    puts "\nResults saved to #{filename}"
  end

  def print_summary(results)
    flaky_tests = []

    results.each do |file, runs|
      failure_count = runs.count { |r| !r[:success] }
      next unless failure_count.positive? && failure_count < @iterations

      flaky_tests << {
        file: file,
        failure_rate: (failure_count.to_f / @iterations * 100).round(2)
      }
    end

    puts "\nSummary:"
    puts "#{flaky_tests.size} flaky tests detected out of #{results.size} changed spec files."

    return if flaky_tests.empty?

    puts "\nFlaky tests:"
    flaky_tests.sort_by { |t| -t[:failure_rate] }.each do |test|
      puts "  - #{test[:file]} (#{test[:failure_rate]}% failure rate)"
    end
  end
end

# コマンドラインオプションの処理
options = {}
OptionParser.new do |opts|
  opts.banner = 'Usage: ruby rspec_rerunner.rb [options]'

  opts.on('-i', '--iterations N', Integer, 'Number of times to run each spec (default: 5)') do |n|
    options[:iterations] = n
  end

  opts.on('-b', '--base-branch BRANCH', 'Base branch to compare against (default: main)') do |branch|
    options[:base_branch] = branch
  end

  opts.on('-p', '--pattern PATTERN', 'Pattern to match spec files (default: _spec.rb$)') do |pattern|
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
