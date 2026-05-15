# frozen_string_literal: true

require_relative "spec_helper"

RSpec.describe Smorg::RB do
  def write_file(dir, name, source)
    path = File.join(dir, name)
    File.write(path, source)
    path
  end

  around do |example|
    Dir.mktmpdir("smorg-rb-test-") do |dir|
      @dir = dir
      Dir.chdir(dir) { example.run }
    end
  end

  it "updates the current file in merge-driver mode" do
    ancestor = write_file(@dir, "ancestor.json", '{"name":"structuredmerge"}')
    current = write_file(@dir, "current.tmp", '{"name":"structuredmerge","current":true}')
    other = write_file(@dir, "other.tmp", '{"name":"structuredmerge","other":true}')
    stdout = StringIO.new
    stderr = StringIO.new

    exit_code = described_class.run(["merge-driver", "--path-name", "package.json", ancestor, current, other], stdout: stdout, stderr: stderr)

    expect(exit_code).to eq(described_class::EXIT_SUCCESS), stderr.string
    merged = File.read(current)
    expect(merged).to include('"current":true')
    expect(merged).to include('"other":true')
    expect(stdout.string).to eq("")
  end

  it "uses smorg.language from gitattributes" do
    File.write(".gitattributes", "*.data smorg.language=json\n")
    ancestor = write_file(@dir, "ancestor.tmp", '{"name":"structuredmerge"}')
    current = write_file(@dir, "current.tmp", '{"name":"structuredmerge","current":true}')
    other = write_file(@dir, "other.tmp", '{"name":"structuredmerge","other":true}')
    stdout = StringIO.new
    stderr = StringIO.new

    exit_code = described_class.run(["merge-driver", ancestor, current, other, "package.data"], stdout: stdout, stderr: stderr)

    expect(exit_code).to eq(described_class::EXIT_SUCCESS), stderr.string
    merged = File.read(current)
    expect(merged).to include('"current":true')
    expect(merged).to include('"other":true')
  end

  it "returns conflict exit code for strict merge failures" do
    ancestor = write_file(@dir, "ancestor.json", '{"name":"structuredmerge"}')
    current = write_file(@dir, "current.json", '{"name":')
    other = write_file(@dir, "other.json", '{"other":true}')
    stdout = StringIO.new
    stderr = StringIO.new

    exit_code = described_class.run(["merge-driver", "--strict", ancestor, current, other, "package.json"], stdout: stdout, stderr: stderr)

    expect(exit_code).to eq(described_class::EXIT_UNRESOLVED_CONFLICT)
    expect(stderr.string).to include("destination_parse_error")
  end

  it "supports check-only exit-code without writing" do
    ancestor = write_file(@dir, "ancestor.json", '{"name":"structuredmerge"}')
    current = write_file(@dir, "current.json", '{"name":"structuredmerge","current":true}')
    other = write_file(@dir, "other.json", '{"name":"structuredmerge","other":true}')
    stdout = StringIO.new
    stderr = StringIO.new

    exit_code = described_class.run(["merge-driver", "--check-only", "--exit-code", ancestor, current, other, "package.json"], stdout: stdout, stderr: stderr)

    expect(exit_code).to eq(described_class::EXIT_UNRESOLVED_CONFLICT)
    expect(File.read(current)).not_to include('"other":true')
  end

  it "supports diff-driver git arities" do
    [7, 9].each do |argument_count|
      old_path = write_file(@dir, "old-#{argument_count}.json", '{"old":true}')
      new_path = write_file(@dir, "new-#{argument_count}.json", '{"new":true}')
      args = ["diff-driver", "package.json", old_path, "abc123", "100644", new_path, "def456", "100644"]
      args += ["a/", "b/"] if argument_count == 9
      stdout = StringIO.new
      stderr = StringIO.new

      exit_code = described_class.run(args, stdout: stdout, stderr: stderr)

      expect(exit_code).to eq(described_class::EXIT_SUCCESS), stderr.string
      expect(stdout.string).to include("structured-diff package.json")
    end
  end

  it "reports conflict regions" do
    conflicted = write_file(@dir, "conflicted.go", "package main\n<<<<<<< ours\nfunc Current() {}\n=======\nfunc Other() {}\n>>>>>>> theirs\n")
    stdout = StringIO.new
    stderr = StringIO.new

    exit_code = described_class.run(["conflicts", "diff", "--path-name", "main.go", "--exit-code", conflicted], stdout: stdout, stderr: stderr)

    expect(exit_code).to eq(described_class::EXIT_UNRESOLVED_CONFLICT)
    expect(stdout.string).to include("conflicts main.go")
    expect(stdout.string).to include("conflict 1 lines 2-6 separator 4")
  end

  it "prints gitattributes" do
    stdout = StringIO.new
    stderr = StringIO.new

    exit_code = described_class.run(["languages", "--gitattributes"], stdout: stdout, stderr: stderr)

    expect(exit_code).to eq(described_class::EXIT_SUCCESS), stderr.string
    expect(stdout.string).to include("*.go merge=smorg-rb diff=smorg-rb smorg.language=go")
  end
end
