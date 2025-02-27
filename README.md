# Flaky Test Terminator

A Ruby script to detect flaky tests in your RSpec test suite by running tests multiple times and analyzing the results.

## Overview

This tool helps you identify inconsistent (flaky) tests by:

1. Finding test files that have been changed compared to a base branch
2. Running each test file multiple times
3. Analyzing the results to detect any tests that pass sometimes and fail other times
4. Providing specific file and line number information about the flaky tests

## Installation

Clone this repository or copy the script to your project directory:

```bash
cp flaky_test_detector.rb /path/to/your/project/
```

## Usage

Run the script from your project root directory:

```bash
ruby flaky_test_detector.rb [options]
```

### Examples

Basic usage with default options:

```bash
ruby flaky_test_detector.rb
```

Run each test 10 times, comparing against the 'develop' branch:

```bash
ruby flaky_test_detector.rb -i 10 -b develop
```

Run comparing against the 'main' to 'develop' branch:

```bash
# diff master...develop
ruby flaky_test_detector.rb -b master -t develop
```

Show detailed error output for failing tests:

```bash
ruby flaky_test_detector.rb -v
```

## Options

| Option | Description | Default |
|--------|-------------|---------|
| `-i`, `--iterations N` | Number of times to run each test | 5 |
| `-b`, `--base-branch BRANCH` | Base branch to compare against for finding changed files | main |
| `-t`, `--target-branch BRANCH` | Target branch to compare against for finding changed files | git branch --show-current |
| `-p`, `--pattern PATTERN` | Pattern to match spec files | _spec.rb |
| `-v`, `--verbose` | Show detailed error output for failed runs | false |
| `-h`, `--help` | Show help message | - |

## Output

The script produces the following output:

- Console output showing which tests were run and which are flaky
- Detailed information about flaky test locations (file paths and line numbers)
- JSON file with complete test results saved to the output directory

Example console output:

```sh
⚠️  FLAKY TEST DETECTED: spec/models/user_spec.rb failed 2/5 runs
   Failure locations:
     - spec/models/user_spec.rb:25 (failed 2 times)

Summary:
1 flaky tests detected out of 3 changed spec files.

Flaky tests:
  - spec/models/user_spec.rb (40.0% failure rate)
    Failure locations:
      - spec/models/user_spec.rb:25 (failed 2 times)
```

## Requirements

- Ruby 3.4
- Git
- RSpec
