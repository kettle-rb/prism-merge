# frozen_string_literal: true

require "json"
require "fileutils"
require "optparse"

module Kettle
  module Jem
    module CLI
      USAGE = <<~USAGE.freeze
        Usage:
          kettle-jem plan [PROJECT_ROOT] [--json] [--report PATH] [--accept|--force|--interactive]
          kettle-jem apply [PROJECT_ROOT] [--json] [--report PATH] [--accept|--force|--interactive]
          kettle-jem template [PROJECT_ROOT] [--json] [--report PATH] [--accept|--force|--interactive]
          kettle-jem manifest [PROJECT_ROOT] [--json]
          kettle-jem version
      USAGE

      module_function

      def run(argv = ARGV, env: ENV, out: $stdout, err: $stderr)
        command, args = normalize_command(argv)
        return print_help(out) if command == "help"
        return print_version(out) if command == "version"

        options = parse_options(args)
        project_root = File.expand_path(options.fetch(:project_root) || Dir.pwd)
        result = execute(command, project_root: project_root, env: env, options: options)
        write_report(options[:report_path], result) if options[:report_path]
        print_result(command, result, options: options, out: out)
        0
      rescue OptionParser::ParseError, ArgumentError => error
        err.puts(error.message)
        err.puts(USAGE)
        2
      rescue StandardError => error
        err.puts("#{error.class}: #{error.message}")
        1
      end

      def normalize_command(argv)
        args = Array(argv).dup
        command = args.shift
        command = "help" if command.nil? || command == "help" || command == "--help" || command == "-h"
        command = "version" if command == "version" || command == "--version" || command == "-v"
        raise ArgumentError, "Unsupported kettle-jem command #{command.inspect}" unless command_allowed?(command)

        [command, args]
      end

      def command_allowed?(command)
        %w[plan apply template manifest help version].include?(command)
      end

      def parse_options(args)
        options = {
          json: false,
          run_options: {},
        }
        parser = OptionParser.new do |opts|
          opts.banner = USAGE
          opts.on("--json", "Print the full machine-readable result as JSON.") { options[:json] = true }
          opts.on("--report PATH", "Write the full machine-readable result to PATH as JSON.") do |path|
            options[:report_path] = path
          end
          opts.on("--accept", "Use non-interactive default decisions.") { options[:run_options][:accept] = true }
          opts.on("--force", "Alias for --accept.") { options[:run_options][:force] = true }
          opts.on("--interactive", "Use interactive decision mode when supported.") do
            options[:run_options][:interactive] = true
          end
        end
        remaining = parser.parse(args)
        raise ArgumentError, "Expected at most one PROJECT_ROOT" if remaining.length > 1

        options[:project_root] = remaining.first
        options
      end

      def execute(command, project_root:, env:, options:)
        case command
        when "plan"
          Kettle::Jem.plan_project(project_root, env: env, run_options: options.fetch(:run_options))
        when "apply", "template"
          Kettle::Jem.apply_project(project_root, env: env, run_options: options.fetch(:run_options))
        when "manifest"
          Kettle::Jem.template_manifest(project_root: project_root)
        else
          raise ArgumentError, "Unsupported kettle-jem command #{command.inspect}"
        end
      end

      def print_result(command, result, options:, out:)
        if options[:json]
          out.puts(JSON.pretty_generate(result))
          return
        end

        case command
        when "manifest"
          entries = result.fetch(:entries, [])
          out.puts("template manifest: #{entries.length} entr#{entries.length == 1 ? "y" : "ies"}")
        else
          changed_files = result.fetch(:changed_files, [])
          out.puts("#{result.fetch(:mode)}: #{changed_files.length} changed file#{changed_files.length == 1 ? "" : "s"}")
          changed_files.each { |path| out.puts("  #{path}") }
        end
      end

      def write_report(path, result)
        FileUtils.mkdir_p(File.dirname(File.expand_path(path)))
        File.write(path, "#{JSON.pretty_generate(result)}\n")
      end

      def print_help(out)
        out.puts(USAGE)
        0
      end

      def print_version(out)
        out.puts(Kettle::Jem::Version::VERSION)
        0
      end
    end
  end
end
