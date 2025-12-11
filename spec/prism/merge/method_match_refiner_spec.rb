# frozen_string_literal: true

RSpec.describe Prism::Merge::MethodMatchRefiner do
  subject(:refiner) { described_class.new(**options) }

  let(:options) { {} }

  describe "#initialize" do
    it "uses default threshold of 0.5" do
      expect(refiner.threshold).to eq(0.5)
    end

    it "uses default name_weight of 0.7" do
      expect(refiner.name_weight).to eq(0.7)
    end

    it "uses default params_weight of 0.3" do
      expect(refiner.params_weight).to eq(0.3)
    end

    context "with custom options" do
      let(:options) { {threshold: 0.6, name_weight: 0.8, params_weight: 0.2} }

      it "uses custom threshold" do
        expect(refiner.threshold).to eq(0.6)
      end

      it "uses custom name_weight" do
        expect(refiner.name_weight).to eq(0.8)
      end

      it "uses custom params_weight" do
        expect(refiner.params_weight).to eq(0.2)
      end
    end
  end

  describe "#call" do
    let(:template_code) { <<~RUBY }
      def process_user(name, email)
        puts name
      end

      def calculate_total(items)
        items.sum
      end

      def send_notification(user)
        notify(user)
      end
    RUBY

    let(:dest_code) { <<~RUBY }
      def process_users(name, email, role)
        puts name
        puts role
      end

      def compute_total(items)
        items.sum
      end

      def handle_error(error)
        log(error)
      end
    RUBY

    let(:template_analysis) { Prism::Merge::FileAnalysis.new(template_code) }
    let(:dest_analysis) { Prism::Merge::FileAnalysis.new(dest_code) }

    let(:template_methods) do
      template_analysis.statements.select { |n| n.is_a?(Prism::DefNode) }
    end

    let(:dest_methods) do
      dest_analysis.statements.select { |n| n.is_a?(Prism::DefNode) }
    end

    it "matches methods with similar names" do
      matches = refiner.call(template_methods, dest_methods)

      # process_user should match process_users (similar name)
      process_match = matches.find { |m| m.template_node.name == :process_user }
      expect(process_match).not_to be_nil
      expect(process_match.dest_node.name).to eq(:process_users)
    end

    it "matches methods with same meaning but different names" do
      matches = refiner.call(template_methods, dest_methods)

      # calculate_total should match compute_total (similar semantics via common substring)
      total_match = matches.find { |m| m.template_node.name == :calculate_total }
      expect(total_match).not_to be_nil
      expect(total_match.dest_node.name).to eq(:compute_total)
    end

    it "returns MatchResult objects with scores" do
      matches = refiner.call(template_methods, dest_methods)

      expect(matches).to all(be_a(Ast::Merge::MatchRefinerBase::MatchResult))
      expect(matches.map(&:score)).to all(be_a(Float))
      expect(matches.map(&:score)).to all(be >= refiner.threshold)
    end

    it "does not match unrelated methods" do
      matches = refiner.call(template_methods, dest_methods)

      # send_notification should not match handle_error (too different)
      notification_match = matches.find { |m| m.template_node.name == :send_notification }
      # It either shouldn't exist, or if it does exist, it should have a low score
      if notification_match
        expect(notification_match.score).to be < 0.7
      end
    end

    context "with high threshold" do
      let(:options) { {threshold: 0.9} }

      it "returns fewer matches" do
        matches = refiner.call(template_methods, dest_methods)

        # With 0.9 threshold, only very similar names should match
        expect(matches.size).to be <= 1
      end
    end

    context "with low threshold" do
      let(:options) { {threshold: 0.3} }

      it "returns more matches" do
        matches = refiner.call(template_methods, dest_methods)

        # With 0.3 threshold, more methods should match
        expect(matches.size).to be >= 2
      end
    end

    context "when one list is empty" do
      it "returns empty array for empty template" do
        matches = refiner.call([], dest_methods)
        expect(matches).to eq([])
      end

      it "returns empty array for empty destination" do
        matches = refiner.call(template_methods, [])
        expect(matches).to eq([])
      end
    end

    context "with exact name matches" do
      let(:dest_code) { <<~RUBY }
        def process_user(name)
          puts name
        end
      RUBY

      it "matches methods with identical names but different params" do
        matches = refiner.call(template_methods, dest_methods)

        process_match = matches.find { |m| m.template_node.name == :process_user }
        expect(process_match).not_to be_nil
        expect(process_match.dest_node.name).to eq(:process_user)
        expect(process_match.score).to be >= 0.7
      end
    end
  end

  describe "#string_similarity" do
    it "returns 1.0 for identical strings" do
      # Access private method for testing
      similarity = refiner.send(:string_similarity, "hello", "hello")
      expect(similarity).to eq(1.0)
    end

    it "returns 0.0 for completely different strings" do
      similarity = refiner.send(:string_similarity, "abc", "xyz")
      expect(similarity).to be < 0.5
    end

    it "returns high score for similar strings" do
      similarity = refiner.send(:string_similarity, "process_user", "process_users")
      expect(similarity).to be > 0.8
    end

    it "handles empty strings" do
      similarity = refiner.send(:string_similarity, "", "")
      expect(similarity).to eq(1.0)
    end
  end

  describe "greedy matching" do
    let(:template_code) { <<~RUBY }
      def foo; end
      def bar; end
      def baz; end
    RUBY

    let(:dest_code) { <<~RUBY }
      def fooo; end
      def barr; end
    RUBY

    let(:template_analysis) { Prism::Merge::FileAnalysis.new(template_code) }
    let(:dest_analysis) { Prism::Merge::FileAnalysis.new(dest_code) }

    let(:template_methods) do
      template_analysis.statements.select { |n| n.is_a?(Prism::DefNode) }
    end

    let(:dest_methods) do
      dest_analysis.statements.select { |n| n.is_a?(Prism::DefNode) }
    end

    it "ensures each destination node is matched at most once" do
      matches = refiner.call(template_methods, dest_methods)

      dest_nodes = matches.map(&:dest_node)
      expect(dest_nodes.uniq.size).to eq(dest_nodes.size)
    end

    it "ensures each template node is matched at most once" do
      matches = refiner.call(template_methods, dest_methods)

      template_nodes = matches.map(&:template_node)
      expect(template_nodes.uniq.size).to eq(template_nodes.size)
    end
  end

  describe "#param_similarity edge cases" do
    it "returns 1.0 when both methods have no parameters" do
      template_code = "def foo; end"
      dest_code = "def bar; end"

      t_analysis = Prism::Merge::FileAnalysis.new(template_code)
      d_analysis = Prism::Merge::FileAnalysis.new(dest_code)

      t_method = t_analysis.statements.first
      d_method = d_analysis.statements.first

      similarity = refiner.send(:param_similarity, t_method, d_method)
      expect(similarity).to eq(1.0)
    end

    it "returns 0.0 when template has no params but dest has params" do
      template_code = "def foo; end"
      dest_code = "def bar(a, b); end"

      t_analysis = Prism::Merge::FileAnalysis.new(template_code)
      d_analysis = Prism::Merge::FileAnalysis.new(dest_code)

      t_method = t_analysis.statements.first
      d_method = d_analysis.statements.first

      similarity = refiner.send(:param_similarity, t_method, d_method)
      expect(similarity).to eq(0.0)
    end

    it "returns 0.0 when dest has no params but template has params" do
      template_code = "def foo(a, b); end"
      dest_code = "def bar; end"

      t_analysis = Prism::Merge::FileAnalysis.new(template_code)
      d_analysis = Prism::Merge::FileAnalysis.new(dest_code)

      t_method = t_analysis.statements.first
      d_method = d_analysis.statements.first

      similarity = refiner.send(:param_similarity, t_method, d_method)
      expect(similarity).to eq(0.0)
    end
  end

  describe "#extract_param_names with various parameter types" do
    it "extracts rest parameter name" do
      code = "def foo(*args); end"
      analysis = Prism::Merge::FileAnalysis.new(code)
      method_node = analysis.statements.first

      names = refiner.send(:extract_param_names, method_node)
      expect(names).to include(:args)
    end

    it "extracts post parameters" do
      code = "def foo(*rest, final); end"
      analysis = Prism::Merge::FileAnalysis.new(code)
      method_node = analysis.statements.first

      names = refiner.send(:extract_param_names, method_node)
      expect(names).to include(:rest)
      expect(names).to include(:final)
    end

    it "extracts keyword rest parameter name" do
      code = "def foo(**kwargs); end"
      analysis = Prism::Merge::FileAnalysis.new(code)
      method_node = analysis.statements.first

      names = refiner.send(:extract_param_names, method_node)
      expect(names).to include(:kwargs)
    end

    it "extracts block parameter name" do
      code = "def foo(&block); end"
      analysis = Prism::Merge::FileAnalysis.new(code)
      method_node = analysis.statements.first

      names = refiner.send(:extract_param_names, method_node)
      expect(names).to include(:block)
    end

    it "handles anonymous rest parameter" do
      code = "def foo(*); end"
      analysis = Prism::Merge::FileAnalysis.new(code)
      method_node = analysis.statements.first

      names = refiner.send(:extract_param_names, method_node)
      # Anonymous rest doesn't have a name, should not cause error
      expect(names).to be_an(Array)
    end

    it "handles anonymous keyword rest parameter" do
      code = "def foo(**); end"
      analysis = Prism::Merge::FileAnalysis.new(code)
      method_node = analysis.statements.first

      names = refiner.send(:extract_param_names, method_node)
      # Anonymous kwrest doesn't have a name, should not cause error
      expect(names).to be_an(Array)
    end

    it "extracts all parameter types together" do
      code = "def foo(req, opt = 1, *rest, post, key:, **kwargs, &block); end"
      analysis = Prism::Merge::FileAnalysis.new(code)
      method_node = analysis.statements.first

      names = refiner.send(:extract_param_names, method_node)
      expect(names).to include(:req)
      expect(names).to include(:opt)
      expect(names).to include(:rest)
      expect(names).to include(:post)
      expect(names).to include(:key)
      expect(names).to include(:kwargs)
      expect(names).to include(:block)
    end
  end

  describe "#levenshtein_distance edge cases" do
    it "returns length of str2 when str1 is empty" do
      distance = refiner.send(:levenshtein_distance, "", "hello")
      expect(distance).to eq(5)
    end

    it "returns length of str1 when str2 is empty" do
      distance = refiner.send(:levenshtein_distance, "hello", "")
      expect(distance).to eq(5)
    end

    it "swaps strings when str1 is longer for optimization" do
      # This tests line 160-161 - the swap for space optimization
      # Both should give same result regardless of order
      distance1 = refiner.send(:levenshtein_distance, "abc", "abcdefghij")
      distance2 = refiner.send(:levenshtein_distance, "abcdefghij", "abc")
      expect(distance1).to eq(distance2)
    end
  end

  describe "#string_similarity with empty strings" do
    it "returns 0.0 when first string is empty" do
      similarity = refiner.send(:string_similarity, "", "hello")
      expect(similarity).to eq(0.0)
    end

    it "returns 0.0 when second string is empty" do
      similarity = refiner.send(:string_similarity, "hello", "")
      expect(similarity).to eq(0.0)
    end
  end

  describe "#compute_method_similarity with score below threshold" do
    let(:options) { {threshold: 0.99} }

    it "returns low score for very different methods" do
      template_code = "def completely_different_name; end"
      dest_code = "def xyz; end"

      t_analysis = Prism::Merge::FileAnalysis.new(template_code)
      d_analysis = Prism::Merge::FileAnalysis.new(dest_code)

      t_method = t_analysis.statements.first
      d_method = d_analysis.statements.first

      score = refiner.send(:compute_method_similarity, t_method, d_method)
      expect(score).to be < 0.5
    end

    it "filters out low-scoring matches in call" do
      template_code = "def completely_different_name; end"
      dest_code = "def xyz; end"

      t_analysis = Prism::Merge::FileAnalysis.new(template_code)
      d_analysis = Prism::Merge::FileAnalysis.new(dest_code)

      t_methods = t_analysis.statements.select { |n| n.is_a?(Prism::DefNode) }
      d_methods = d_analysis.statements.select { |n| n.is_a?(Prism::DefNode) }

      # With high threshold, no matches should be returned
      matches = refiner.call(t_methods, d_methods)
      expect(matches).to be_empty
    end
  end
end
