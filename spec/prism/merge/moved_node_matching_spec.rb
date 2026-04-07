# frozen_string_literal: true

# Comprehensive spec matrix for moved-node / orphan-node matching.
#
# Tests how TopLevelMergeRunner handles:
# 1. Renamed methods with identical bodies
# 2. Renamed methods with slightly changed bodies
# 3. 6-method files with rearrangement, renames, and body edits
# 4. Nodes wrapped in conditionals (the original eval_gemfile scenario)
# 5. Performance-relevant: whether unmatched-set pruning is viable
#
# Each scenario captures .merge output and counts occurrences to detect
# undesirable duplication or loss.
RSpec.describe Prism::Merge::TopLevelMergeRunner, "moved-node matching" do
  def build_merger(template, dest, preference: :destination, add_template_only_nodes: true, **options)
    Prism::Merge::SmartMerger.new(
      template,
      dest,
      preference: preference,
      add_template_only_nodes: add_template_only_nodes,
      **options,
    )
  end

  def merge_result(template:, dest:, **options)
    merger = build_merger(template, dest, **options)
    described_class.new(merger: merger).merge.to_s
  end

  def method_names_in(source)
    source.scan(/def (\w+)/).flatten
  end

  def method_count(source, name)
    source.scan(/def #{Regexp.escape(name)}\b/).size
  end

  # -------------------------------------------------------------------
  # Scenario 1: Renamed method, identical body
  # -------------------------------------------------------------------
  describe "renamed method with identical body" do
    let(:template) do
      <<~RUBY
        def bar
          puts "hello"
          [1, 2, 3].map { |x| x * 2 }
        end
      RUBY
    end

    let(:dest) do
      <<~RUBY
        def foo
          puts "hello"
          [1, 2, 3].map { |x| x * 2 }
        end
      RUBY
    end

    it "currently emits both methods (no body-based matching)" do
      result = merge_result(template: template, dest: dest)
      # Without body-Jaccard matching, these are unrelated by signature.
      # Template-only `bar` gets added; dest-only `foo` is kept.
      expect(method_names_in(result)).to include("foo")
      # bar may or may not appear depending on add_template_only_nodes
    end

    it "with add_template_only_nodes: true, duplicates the body under two names" do
      result = merge_result(template: template, dest: dest, add_template_only_nodes: true)
      expect(method_count(result, "foo")).to eq(1)
      expect(method_count(result, "bar")).to eq(1)
      # Both bodies are identical — a Jaccard matcher could recognize this.
      # This test documents current behavior; a future improvement would
      # pair these as a "rename match" and emit only the dest version.
    end
  end

  # -------------------------------------------------------------------
  # Scenario 2: Renamed method, slightly changed body
  # -------------------------------------------------------------------
  describe "renamed method with slightly changed body" do
    let(:template) do
      <<~RUBY
        def process_users(data)
          data.each do |user|
            validate_user(user)
            save_to_database(user)
          end
        end
      RUBY
    end

    let(:dest) do
      <<~RUBY
        def handle_users(data)
          data.each do |user|
            validate_user(user)
            persist_user(user)
          end
        end
      RUBY
    end

    it "treats them as unrelated by signature" do
      result = merge_result(template: template, dest: dest)
      expect(method_count(result, "handle_users")).to eq(1)
      # process_users added as template-only
      expect(method_count(result, "process_users")).to eq(1)
    end
  end

  # -------------------------------------------------------------------
  # Scenario 3: Six methods — rearranged, some renamed, some bodies changed
  # -------------------------------------------------------------------
  describe "six methods with rearrangement, renames, and body edits" do
    # Template: alpha, beta, gamma, delta, epsilon, zeta
    # Dest:     zeta, gamma_v2 (renamed from gamma, same body),
    #           epsilon (body changed), alpha, new_method (dest-only),
    #           delta (identical)
    # Missing from dest: beta (template-only)
    let(:template) do
      <<~RUBY
        def alpha
          :alpha_result
        end

        def beta
          :beta_result
        end

        def gamma
          calculate(1, 2, 3)
          transform(:data)
        end

        def delta
          :shared_logic
        end

        def epsilon
          original_work
          more_work
        end

        def zeta
          :zeta_result
        end
      RUBY
    end

    let(:dest) do
      <<~RUBY
        def zeta
          :zeta_result
        end

        def gamma_v2
          calculate(1, 2, 3)
          transform(:data)
        end

        def epsilon
          original_work
          extra_step
          more_work
        end

        def alpha
          :alpha_result
        end

        def new_method
          :dest_only
        end

        def delta
          :shared_logic
        end
      RUBY
    end

    context "with preference: :destination" do
      it "matches exact-signature methods regardless of order" do
        result = merge_result(template: template, dest: dest, preference: :destination)

        # These match by signature: alpha, delta, epsilon, zeta
        %w[alpha delta epsilon zeta].each do |name|
          expect(method_count(result, name)).to eq(1),
            "Expected exactly 1 '#{name}' but got #{method_count(result, name)} in:\n#{result}"
        end
      end

      it "keeps dest-only methods" do
        result = merge_result(template: template, dest: dest, preference: :destination)
        expect(method_count(result, "new_method")).to eq(1)
      end

      it "adds template-only methods (beta)" do
        result = merge_result(template: template, dest: dest, preference: :destination)
        expect(method_count(result, "beta")).to eq(1)
      end

      it "does not match gamma to gamma_v2 (different signatures)" do
        result = merge_result(template: template, dest: dest, preference: :destination)
        # gamma (template-only) added; gamma_v2 (dest-only) kept
        expect(method_count(result, "gamma")).to eq(1)
        expect(method_count(result, "gamma_v2")).to eq(1)
      end

      it "never duplicates any method" do
        result = merge_result(template: template, dest: dest, preference: :destination)
        all_methods = method_names_in(result)
        duplicates = all_methods.select { |m| all_methods.count(m) > 1 }.uniq
        expect(duplicates).to be_empty,
          "Found duplicated methods: #{duplicates.inspect}\n#{result}"
      end
    end

    context "with preference: :template" do
      it "uses template bodies for matched methods" do
        result = merge_result(template: template, dest: dest, preference: :template)
        # epsilon matched by signature — template body used (no extra_step)
        expect(result).to include("original_work")
        expect(result).not_to include("extra_step")
      end
    end

    context "with remove_template_missing_nodes: true" do
      it "removes dest-only methods not in template" do
        result = merge_result(
          template: template,
          dest: dest,
          preference: :destination,
          remove_template_missing_nodes: true,
        )
        # new_method is dest-only and not in template → removed
        expect(method_count(result, "new_method")).to eq(0)
        # gamma_v2 is also dest-only → removed
        expect(method_count(result, "gamma_v2")).to eq(0)
      end
    end
  end

  # -------------------------------------------------------------------
  # Scenario 4: Cross-depth matching (original eval_gemfile scenario)
  # -------------------------------------------------------------------
  describe "cross-depth: template top-level inside dest conditional" do
    it "does not duplicate eval_gemfile wrapped in if block" do
      template = <<~RUBY
        source "https://rubygems.org"
        gemspec

        # Templating
        eval_gemfile "gemfiles/modular/templating.gemfile"
      RUBY

      dest = <<~RUBY
        source "https://rubygems.org"
        gemspec

        if ENV.fetch("CI", "false").casecmp("false").zero?
          # Templating
          eval_gemfile "gemfiles/modular/templating.gemfile"
        end
      RUBY

      result = merge_result(template: template, dest: dest)
      count = result.scan('eval_gemfile "gemfiles/modular/templating.gemfile"').size
      expect(count).to eq(1),
        "Expected eval_gemfile once, got #{count}:\n#{result}"
    end
  end

  # -------------------------------------------------------------------
  # Scenario 5: Pruning viability — unmatched sets
  # -------------------------------------------------------------------
  describe "unmatched set sizes for pruning" do
    # When there are many matched methods, only the unmatched ones need
    # expensive similarity checks. This test verifies the signature map
    # correctly identifies the residual unmatched sets.
    let(:template) do
      <<~RUBY
        def matched_a
          :a
        end

        def matched_b
          :b
        end

        def matched_c
          :c
        end

        def template_only_x
          compute_something
          transform_result
        end

        def template_only_y
          :unique
        end
      RUBY
    end

    let(:dest) do
      <<~RUBY
        def matched_a
          :a
        end

        def matched_b
          :b
        end

        def matched_c
          :c
        end

        def dest_only_x
          compute_something
          transform_result
        end

        def dest_only_y
          :different
        end
      RUBY
    end

    it "matched methods don't need orphan analysis" do
      merger = build_merger(template, dest)
      template_map = merger.send(:build_signature_map, merger.template_analysis)
      dest_map = merger.send(:build_signature_map, merger.dest_analysis)

      template_sigs = Set.new(template_map.keys)
      dest_sigs = Set.new(dest_map.keys)

      matched_sigs = template_sigs & dest_sigs
      unmatched_template_sigs = template_sigs - dest_sigs
      unmatched_dest_sigs = dest_sigs - template_sigs

      # 3 methods match, 2 on each side don't
      expect(matched_sigs.size).to eq(3)
      expect(unmatched_template_sigs.size).to eq(2)
      expect(unmatched_dest_sigs.size).to eq(2)
    end

    it "body-identical unmatched methods could be paired by Jaccard" do
      # template_only_x and dest_only_x have identical bodies.
      # A Jaccard comparison of their body text would score 1.0.
      t_body = <<~RUBY.strip
        compute_something
        transform_result
      RUBY
      d_body = <<~RUBY.strip
        compute_something
        transform_result
      RUBY

      t_tokens = Ast::Merge::JaccardSimilarity.extract_tokens(t_body, stopwords: Set.new, min_length: 2)
      d_tokens = Ast::Merge::JaccardSimilarity.extract_tokens(d_body, stopwords: Set.new, min_length: 2)
      score = Ast::Merge::JaccardSimilarity.jaccard(t_tokens, d_tokens)

      expect(score).to eq(1.0)
    end

    it "body-different unmatched methods have low Jaccard score" do
      t_body = ":unique"
      d_body = ":different"

      t_tokens = Ast::Merge::JaccardSimilarity.extract_tokens(t_body, stopwords: Set.new, min_length: 2)
      d_tokens = Ast::Merge::JaccardSimilarity.extract_tokens(d_body, stopwords: Set.new, min_length: 2)
      score = Ast::Merge::JaccardSimilarity.jaccard(t_tokens, d_tokens)

      expect(score).to eq(0.0)
    end
  end

  # -------------------------------------------------------------------
  # Scenario 6: Methods where only the name differs (body Jaccard = 1.0)
  # -------------------------------------------------------------------
  describe "Jaccard-based body matching across node types" do
    it "computes high Jaccard for identical multi-line method bodies" do
      template_body = <<~RUBY
        results = data.map { |item| transform(item) }
        results.each { |r| validate(r) }
        persist_all(results)
      RUBY

      dest_body = <<~RUBY
        results = data.map { |item| transform(item) }
        results.each { |r| validate(r) }
        persist_all(results)
      RUBY

      t_tokens = Ast::Merge::JaccardSimilarity.extract_tokens(template_body, stopwords: Set.new, min_length: 2)
      d_tokens = Ast::Merge::JaccardSimilarity.extract_tokens(dest_body, stopwords: Set.new, min_length: 2)

      expect(Ast::Merge::JaccardSimilarity.jaccard(t_tokens, d_tokens)).to eq(1.0)
    end

    it "computes moderate Jaccard for similar method bodies with one change" do
      template_body = <<~RUBY
        results = data.map { |item| transform(item) }
        results.each { |r| validate(r) }
        persist_all(results)
      RUBY

      dest_body = <<~RUBY
        results = data.map { |item| transform(item) }
        results.each { |r| check(r) }
        persist_all(results)
      RUBY

      t_tokens = Ast::Merge::JaccardSimilarity.extract_tokens(template_body, stopwords: Set.new, min_length: 2)
      d_tokens = Ast::Merge::JaccardSimilarity.extract_tokens(dest_body, stopwords: Set.new, min_length: 2)

      score = Ast::Merge::JaccardSimilarity.jaccard(t_tokens, d_tokens)
      # "validate" vs "check" — one token differs; most tokens shared
      expect(score).to be > 0.7
      expect(score).to be < 1.0
    end

    it "computes low Jaccard for completely different method bodies" do
      template_body = <<~RUBY
        connect_to_database
        execute_query("SELECT * FROM users")
        parse_results
      RUBY

      dest_body = <<~RUBY
        render_template(:home)
        set_flash_message("Welcome")
        redirect_to(root_path)
      RUBY

      t_tokens = Ast::Merge::JaccardSimilarity.extract_tokens(template_body, stopwords: Set.new, min_length: 2)
      d_tokens = Ast::Merge::JaccardSimilarity.extract_tokens(dest_body, stopwords: Set.new, min_length: 2)

      score = Ast::Merge::JaccardSimilarity.jaccard(t_tokens, d_tokens)
      expect(score).to be < 0.2
    end
  end

  # -------------------------------------------------------------------
  # Scenario 7: Emoji in method bodies (multi-byte safety)
  # -------------------------------------------------------------------
  describe "multi-byte safety with emoji in bodies" do
    let(:template) do
      <<~RUBY
        def greet
          puts "Hello 🌍 World"
          "✅ Done"
        end
      RUBY
    end

    let(:dest) do
      <<~RUBY
        def greet
          puts "Hello 🌍 World"
          "✅ Complete"
        end
      RUBY
    end

    it "merges without errors when bodies contain emoji" do
      result = merge_result(template: template, dest: dest)
      expect(result).to include("🌍")
      expect(method_count(result, "greet")).to eq(1)
    end
  end
end
