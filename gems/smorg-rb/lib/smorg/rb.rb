# frozen_string_literal: true

require "go-merge"
require "json-merge"
require "pathname"
require "plain-merge"

require_relative "rb/version"

module Smorg
  module RB
    EXIT_SUCCESS = 0
    EXIT_UNRESOLVED_CONFLICT = 1
    EXIT_USER_ERROR = 2
    EXIT_INTERNAL_ERROR = 3

    module_function

    def run(args, stdout: $stdout, stderr: $stderr)
      command, *rest = args
      case command
      when "merge-driver"
        run_merge_driver(rest, stderr)
      when "diff-driver"
        run_diff_driver(rest, stdout, stderr)
      when "conflicts"
        run_conflicts(rest, stdout, stderr)
      when "languages"
        run_languages(rest, stdout, stderr)
      when "help", "-h", "--help"
        print_usage(stdout)
        EXIT_SUCCESS
      else
        stderr.puts("unknown command #{command.inspect}") if command
        print_usage(stderr)
        EXIT_USER_ERROR
      end
    end

    def print_usage(out)
      out.puts("usage: smorg-rb merge-driver [--path-name PATH] [--output PATH] [--strict] [--fallback=none|line|local|full-file] %O %A %B [%P]")
      out.puts("       smorg-rb merge-driver --ancestor %O --current %A --other %B --path-name %P")
      out.puts("       smorg-rb diff-driver [--path-name PATH] OLD NEW")
      out.puts("       smorg-rb diff-driver PATH OLD-FILE OLD-HEX OLD-MODE NEW-FILE NEW-HEX NEW-MODE [OLD-PREFIX NEW-PREFIX]")
      out.puts("       smorg-rb conflicts diff [--path-name PATH] [--exit-code] FILE")
      out.puts("       smorg-rb languages --gitattributes")
    end

    def run_merge_driver(args, stderr)
      options = parse_merge_driver_options(args, stderr)
      return EXIT_USER_ERROR unless options

      ancestor_source = File.read(options[:ancestor])
      current_source = File.read(options[:current])
      other_source = File.read(options[:other])
      ancestor_source

      effective_path = options[:path_name] || options[:current]
      settings = load_path_settings(effective_path)
      result = merge_by_path(effective_path, settings[:language], other_source, current_source)
      output = result[:output]
      unless result[:ok] && output
        if options[:strict] || options[:fallback] == "none"
          print_diagnostics(stderr, result)
          return EXIT_UNRESOLVED_CONFLICT
        end
        output = current_source
      end

      if options[:check_only]
        return options[:exit_code] && output != current_source ? EXIT_UNRESOLVED_CONFLICT : EXIT_SUCCESS
      end

      File.write(options[:output] || options[:current], output)
      EXIT_SUCCESS
    rescue Errno::ENOENT, Errno::EACCES => e
      stderr.puts("file error: #{e.message}")
      EXIT_USER_ERROR
    rescue StandardError => e
      stderr.puts("internal error: #{e.message}")
      EXIT_INTERNAL_ERROR
    end

    def parse_merge_driver_options(args, stderr)
      options = { strict: false, fallback: "full-file", check_only: false, exit_code: false }
      positionals = []
      index = 0
      while index < args.length
        value = args[index]
        case value
        when "--ancestor"
          index += 1
          options[:ancestor] = args[index]
        when "--current"
          index += 1
          options[:current] = args[index]
        when "--other"
          index += 1
          options[:other] = args[index]
        when "--path-name"
          index += 1
          options[:path_name] = args[index]
        when "--output"
          index += 1
          options[:output] = args[index]
        when "--strict"
          options[:strict] = true
        when "--check-only"
          options[:check_only] = true
        when "--exit-code"
          options[:exit_code] = true
        when "--fallback"
          index += 1
          options[:fallback] = args[index]
        else
          if value.start_with?("--fallback=")
            options[:fallback] = value.delete_prefix("--fallback=")
          elsif value.start_with?("--")
            stderr.puts("unknown merge-driver option #{value.inspect}")
            return nil
          else
            positionals << value
          end
        end
        index += 1
      end

      options[:ancestor] ||= positionals[0]
      options[:current] ||= positionals[1]
      options[:other] ||= positionals[2]
      options[:path_name] ||= positionals[3]

      unless options[:ancestor] && options[:current] && options[:other]
        stderr.puts("merge-driver requires ancestor, current, and other paths")
        return nil
      end
      unless %w[none line local full-file].include?(options[:fallback])
        stderr.puts("unsupported fallback mode #{options[:fallback].inspect}")
        return nil
      end
      options
    end

    def run_diff_driver(args, stdout, stderr)
      options = parse_diff_driver_options(args, stderr)
      return EXIT_USER_ERROR unless options

      print_structured_diff(
        stdout,
        options[:path_name] || options[:new_path],
        File.read(options[:old_path]),
        File.read(options[:new_path])
      )
      EXIT_SUCCESS
    rescue Errno::ENOENT, Errno::EACCES => e
      stderr.puts("read diff input: #{e.message}")
      EXIT_USER_ERROR
    end

    def parse_diff_driver_options(args, stderr)
      options = {}
      positionals = []
      index = 0
      while index < args.length
        value = args[index]
        if value == "--path-name"
          index += 1
          options[:path_name] = args[index]
        elsif value.start_with?("--")
          stderr.puts("unknown diff-driver option #{value.inspect}")
          return nil
        else
          positionals << value
        end
        index += 1
      end

      case positionals.length
      when 2
        options.merge(old_path: positionals[0], new_path: positionals[1])
      when 7, 9
        options.merge(path_name: options[:path_name] || positionals[0], old_path: positionals[1], new_path: positionals[4])
      else
        stderr.puts("diff-driver requires either 2, 7, or 9 positional arguments")
        nil
      end
    end

    def print_structured_diff(stdout, path_name, old_source, new_source)
      stdout.puts("structured-diff #{path_name}")
      if old_source == new_source
        stdout.puts("status unchanged")
      else
        stdout.puts("status changed")
        stdout.puts("old-lines #{line_count(old_source)}")
        stdout.puts("new-lines #{line_count(new_source)}")
      end
    end

    def run_conflicts(args, stdout, stderr)
      subcommand, *rest = args
      return run_conflicts_diff(rest, stdout, stderr) if subcommand == "diff"

      stderr.puts("conflicts requires the diff subcommand")
      EXIT_USER_ERROR
    end

    def run_conflicts_diff(args, stdout, stderr)
      options = parse_conflicts_diff_options(args, stderr)
      return EXIT_USER_ERROR unless options

      effective_path = options[:path_name] || options[:file_path]
      settings = load_path_settings(effective_path)
      regions = find_conflict_regions(File.read(options[:file_path]), settings[:conflict_marker_size])
      print_conflict_diff(stdout, effective_path, regions)
      options[:exit_code] && !regions.empty? ? EXIT_UNRESOLVED_CONFLICT : EXIT_SUCCESS
    rescue Errno::ENOENT, Errno::EACCES => e
      stderr.puts("read conflicted file: #{e.message}")
      EXIT_USER_ERROR
    end

    def parse_conflicts_diff_options(args, stderr)
      options = { exit_code: false }
      positionals = []
      index = 0
      while index < args.length
        value = args[index]
        case value
        when "--path-name"
          index += 1
          options[:path_name] = args[index]
        when "--exit-code"
          options[:exit_code] = true
        else
          if value.start_with?("--")
            stderr.puts("unknown conflicts diff option #{value.inspect}")
            return nil
          end
          positionals << value
        end
        index += 1
      end
      if positionals.length != 1
        stderr.puts("conflicts diff requires exactly one file path")
        return nil
      end
      options.merge(file_path: positionals[0])
    end

    def run_languages(args, stdout, stderr)
      unless args == ["--gitattributes"]
        stderr.puts("languages currently requires --gitattributes")
        return EXIT_USER_ERROR
      end

      [
        "*.go merge=smorg-rb diff=smorg-rb smorg.language=go",
        "*.json merge=smorg-rb diff=smorg-rb smorg.language=json",
        "*.jsonc merge=smorg-rb diff=smorg-rb smorg.language=jsonc"
      ].each { |line| stdout.puts(line) }
      EXIT_SUCCESS
    end

    def merge_by_path(path_name, language, other_source, current_source)
      case normalize_language(language, path_name)
      when "go"
        Go::Merge.merge_go(other_source, current_source, "go")
      when "json"
        Json::Merge.merge_json(other_source, current_source, "json")
      when "jsonc"
        Json::Merge.merge_json(other_source, current_source, "jsonc")
      else
        Plain::Merge.merge_text(other_source, current_source)
      end
    end

    def normalize_language(language, path_name)
      case language.to_s.strip.downcase
      when "go", "golang"
        "go"
      when "json"
        "json"
      when "jsonc", "json with comments"
        "jsonc"
      when "plain", "text", "plaintext", "text/plain"
        "text"
      else
        case File.extname(path_name).downcase
        when ".go"
          "go"
        when ".json"
          "json"
        when ".jsonc"
          "jsonc"
        else
          "text"
        end
      end
    end

    def load_path_settings(path_name)
      settings = { conflict_marker_size: 7 }
      attribute_files_for_path(path_name).each do |attributes_path|
        next unless File.file?(attributes_path)

        apply_attributes(settings, path_name, File.read(attributes_path))
      end
      settings
    end

    def attribute_files_for_path(path_name)
      clean_path = File.expand_path(path_name, Dir.pwd).start_with?(Dir.pwd) ? Pathname.new(path_name).cleanpath.to_s : path_name
      dir = File.dirname(clean_path)
      return [".gitattributes"] if dir == "." || clean_path.start_with?("..") || Pathname.new(clean_path).absolute?

      files = [".gitattributes"]
      parts = dir.split(File::SEPARATOR).reject(&:empty?)
      parts.each_index do |index|
        files << File.join(*parts[0..index], ".gitattributes")
      end
      files
    end

    def apply_attributes(settings, path_name, source)
      source.each_line do |raw_line|
        line = raw_line.strip
        next if line.empty? || line.start_with?("#")

        pattern, *fields = line.split(/\s+/)
        next if fields.empty? || !attribute_pattern_matches?(pattern, path_name)

        fields.each do |field|
          key, value = field.split("=", 2)
          next unless value

          case key
          when "smorg.language", "linguist-language"
            settings[:language] = value
          when "conflict-marker-size"
            marker_size = value.to_i
            settings[:conflict_marker_size] = marker_size if marker_size.positive?
          end
        end
      end
    end

    def attribute_pattern_matches?(pattern, path_name)
      return true if pattern == path_name

      if !pattern.include?("/")
        File.fnmatch?(pattern, File.basename(path_name))
      else
        File.fnmatch?(pattern, path_name)
      end
    end

    def find_conflict_regions(source, marker_size)
      marker_size = [marker_size.to_i, 1].max
      start_prefix = "<" * marker_size
      separator_prefix = "=" * marker_size
      end_prefix = ">" * marker_size
      regions = []
      current = nil
      source.split("\n").each_with_index do |line, index|
        line_number = index + 1
        if line.start_with?(start_prefix)
          current = { start_line: line_number, separator_line: 0 }
        elsif current && current[:separator_line].zero? && line.start_with?(separator_prefix)
          current[:separator_line] = line_number
        elsif current && line.start_with?(end_prefix)
          regions << current.merge(end_line: line_number)
          current = nil
        end
      end
      regions
    end

    def print_conflict_diff(stdout, path_name, regions)
      stdout.puts("conflicts #{path_name}")
      stdout.puts("count #{regions.length}")
      regions.each_with_index do |region, index|
        stdout.puts("conflict #{index + 1} lines #{region[:start_line]}-#{region[:end_line]} separator #{region[:separator_line]}")
      end
    end

    def line_count(source)
      return 0 if source.empty?

      source.end_with?("\n") ? source.count("\n") : source.count("\n") + 1
    end

    def print_diagnostics(stderr, result)
      result.fetch(:diagnostics, []).each do |diagnostic|
        stderr.puts("#{diagnostic[:category]}: #{diagnostic[:message]}")
      end
    end
  end
end
