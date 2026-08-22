# frozen_string_literal: true

require "fileutils"
require "json"
require "open3"
require "tmpdir"
require_relative "../../test_helper"

class GreenroomCLICheckTest < Minitest::Test
  ORIGINAL = <<~RUBY
    class Pricing
      def compute(order)
        order.subtotal * rate(order)
      end
    end
  RUBY

  WRAPPED = <<~RUBY
    class Pricing
      def compute(order)
        Scientist.run "price-v2" do |experiment|
          experiment.use { order.subtotal * rate(order) }
          experiment.try { compute_v2(order) }
          experiment.compare { |control, candidate| control == candidate }
        end
      end

      private

      def compute_v2(order)
        order.subtotal * new_rate(order)
      end
    end
  RUBY

  def test_accepts_one_wrapped_method
    in_repository do |repository|
      write_and_commit(repository, "pricing.rb", ORIGINAL)
      commit = write_and_commit(repository, "pricing.rb", WRAPPED)

      stdout, stderr, status = run_check(repository, commit)

      assert_predicate status, :success?
      assert_equal "Accepted experiment price-v2 with candidate compute_v2.\n", stdout
      assert_empty stderr
    end
  end

  def test_accepts_unchanged_methods_and_classes
    before = ORIGINAL.sub("  def compute", "  def label = \"price\"\n\n  def compute") + <<~RUBY

      class Tax
        def rate = 0.1
      end
    RUBY
    after = WRAPPED.sub("  def compute", "  def label = \"price\"\n\n  def compute") + <<~RUBY

      class Tax
        def rate = 0.1
      end
    RUBY

    assert_accepted(before, after)
  end

  def test_accepts_comment_and_blank_line_changes
    after = WRAPPED.sub("experiment.use", "# The control stays unchanged.\n      experiment.use")
      .sub("experiment.try", "\n      experiment.try")

    assert_accepted(ORIGINAL, after)
  end

  def test_rejects_a_changed_use_body
    assert_rejected(ORIGINAL, WRAPPED.sub("rate(order)", "rate(order) + 1"), "The use block must match the old method body.")
  end

  def test_rejects_two_changed_methods
    before = ORIGINAL.sub("end\n", "end\n\n  def total(order) = order.total\n")
    after = WRAPPED.sub("  private", <<~RUBY.chomp)
      def total(order)
        Scientist.run "total-v2" do |experiment|
          experiment.use { order.total }
          experiment.try { total_v2(order) }
          experiment.compare { |control, candidate| control == candidate }
        end
      end

      private
    RUBY
      .sub("  def compute_v2", "  def total_v2(order) = order.new_total\n\n  def compute_v2")

    assert_rejected(before, after, "Exactly one existing method must change.")
  end

  def test_rejects_a_change_to_another_method
    before = ORIGINAL.sub("end\n", "end\n\n  def label = \"price\"\n")
    after = WRAPPED.sub("  private", "  def label = \"new price\"\n\n  private")

    assert_rejected(before, after, "Exactly one existing method must change.")
  end

  def test_rejects_a_second_changed_file
    in_repository do |repository|
      write_files_and_commit(repository, {"pricing.rb" => ORIGINAL, "tax.rb" => "class Tax; end\n"})
      commit = write_files_and_commit(repository, {"pricing.rb" => WRAPPED, "tax.rb" => "class Tax; VALUE = 1; end\n"})

      assert_check_rejected(repository, commit, "The commit must modify one Ruby file.")
    end
  end

  def test_rejects_a_rename
    in_repository do |repository|
      unchanged = (1..10).map { |number| "  def value_#{number} = #{number}\n" }.join
      before = ORIGINAL.sub("  def compute", "#{unchanged}\n  def compute")
      after = WRAPPED.sub("  def compute", "#{unchanged}\n  def compute")
      write_and_commit(repository, "pricing.rb", before)
      FileUtils.mv(File.join(repository, "pricing.rb"), File.join(repository, "prices.rb"))
      File.write(File.join(repository, "prices.rb"), after)
      git(repository, "add", "--all")
      git(repository, "commit", "--quiet", "-m", "fixture")

      assert_check_rejected(repository, "HEAD", "The changed file must have status M.")
    end
  end

  def test_rejects_a_missing_compare_block
    after = WRAPPED.sub("      experiment.compare { |control, candidate| control == candidate }\n", "")

    assert_rejected(ORIGINAL, after, "The changed method body must contain one Scientist.run call.")
  end

  def test_rejects_a_public_candidate
    assert_rejected(ORIGINAL, WRAPPED.sub("\n  private\n", ""), "The candidate method must be private.")
  end

  def test_rejects_two_candidate_methods
    after = WRAPPED.sub("  def compute_v2", "  def helper = 1\n\n  def compute_v2")

    assert_rejected(ORIGINAL, after, "Exactly one candidate method must be added.")
  end

  def test_rejects_return_in_the_use_block
    before = ORIGINAL.sub("order.subtotal * rate(order)", "return order.subtotal * rate(order)")
    after = WRAPPED.sub("experiment.use { order.subtotal", "experiment.use { return order.subtotal")

    assert_rejected(before, after, "A return in a use or try block is unsafe.")
  end

  def test_rejects_binding_in_the_try_block
    after = WRAPPED.sub("experiment.try { compute_v2(order) }", "experiment.try { [compute_v2(order), binding] }")

    assert_rejected(ORIGINAL, after, "A binding in a use or try block is unsafe.")
  end

  def test_allows_return_in_a_nested_lambda
    before = ORIGINAL.sub("order.subtotal * rate(order)", "-> { return order.subtotal * rate(order) }.call")
    after = WRAPPED.sub("order.subtotal * rate(order)", "-> { return order.subtotal * rate(order) }.call")

    assert_accepted(before, after)
  end

  def test_rejects_return_in_a_nested_proc
    before = ORIGINAL.sub("order.subtotal * rate(order)", "proc { return order.subtotal * rate(order) }.call")
    after = WRAPPED.sub("order.subtotal * rate(order)", "proc { return order.subtotal * rate(order) }.call")

    assert_rejected(before, after, "A return in a use or try block is unsafe.")
  end

  def test_rejects_a_merge_commit
    in_repository do |repository|
      write_and_commit(repository, "pricing.rb", ORIGINAL)
      git(repository, "checkout", "--quiet", "-b", "candidate")
      write_and_commit(repository, "pricing.rb", WRAPPED)
      git(repository, "checkout", "--quiet", "-b", "other", "HEAD^")
      write_and_commit(repository, "tax.rb", "class Tax; end\n")
      git(repository, "merge", "--quiet", "--no-ff", "candidate", "-m", "merge")

      assert_check_rejected(repository, "HEAD", "The commit is a merge commit.")
    end
  end

  def test_rejects_a_new_class_body_statement
    after = WRAPPED.sub("class Pricing\n", "class Pricing\n  NEW_RATE = 2\n")

    assert_rejected(ORIGINAL, after, "Another class body statement changed.")
  end

  def test_rejects_a_changed_method_signature
    after = WRAPPED.sub("def compute(order)", "def compute(order, currency = nil)")

    assert_rejected(ORIGINAL, after, "The changed method signature must stay the same.")
  end

  def test_rejects_a_visibility_change_to_an_existing_method
    before = ORIGINAL.sub("end\n", "end\n\n  def label = \"price\"\n")
    after = WRAPPED.sub("  private", "  private\n\n  def label = \"price\"\n\n  private")

    assert_rejected(before, after, "An existing method visibility changed.")
  end

  def test_uses_head_when_the_commit_is_omitted
    in_repository do |repository|
      write_and_commit(repository, "pricing.rb", ORIGINAL)
      write_and_commit(repository, "pricing.rb", WRAPPED)

      _stdout, _stderr, status = run_check(repository)

      assert_predicate status, :success?
    end
  end

  def test_library_boot_does_not_load_the_parser
    script = "require 'greenroom'; abort if defined?(RuboCop::AST)"
    _stdout, stderr, status = Open3.capture3({"RUBYOPT" => nil}, RbConfig.ruby, "-Ilib", "-e", script, chdir: File.expand_path("../../..", __dir__))

    assert_predicate status, :success?, stderr
  end

  def test_outputs_one_json_object
    in_repository do |repository|
      write_and_commit(repository, "pricing.rb", ORIGINAL)
      commit = write_and_commit(repository, "pricing.rb", WRAPPED)

      stdout, _stderr, status = run_check(repository, "--json", commit)
      result = JSON.parse(stdout)

      assert_predicate status, :success?
      assert_equal true, result.fetch("accepted")
      assert_equal "price-v2", result.fetch("experiment")
      assert_equal "compute_v2", result.fetch("candidate")
      assert_equal 1, stdout.lines.length
    end
  end

  private

  def in_repository
    Dir.mktmpdir("greenroom-check") do |directory|
      git(directory, "init", "--quiet")
      git(directory, "config", "user.email", "test@example.com")
      git(directory, "config", "user.name", "Greenroom Test")
      yield directory
    end
  end

  def write_and_commit(repository, path, source)
    write_files_and_commit(repository, path => source)
  end

  def write_files_and_commit(repository, files)
    files.each do |path, source|
      absolute_path = File.join(repository, path)
      FileUtils.mkdir_p(File.dirname(absolute_path))
      File.write(absolute_path, source)
    end
    git(repository, "add", *files.keys)
    git(repository, "commit", "--quiet", "-m", "fixture")
    git(repository, "rev-parse", "HEAD").strip
  end

  def run_check(repository, *arguments)
    executable = File.expand_path("../../../exe/greenroom", __dir__)
    Open3.capture3({"RUBYOPT" => nil}, RbConfig.ruby, executable, "check", *arguments, chdir: repository)
  end

  def git(repository, *arguments)
    stdout, stderr, status = Open3.capture3("git", *arguments, chdir: repository)
    raise stderr unless status.success?

    stdout
  end

  def assert_accepted(before, after)
    in_repository do |repository|
      write_and_commit(repository, "pricing.rb", before)
      commit = write_and_commit(repository, "pricing.rb", after)
      _stdout, _stderr, status = run_check(repository, commit)

      assert_predicate status, :success?
    end
  end

  def assert_rejected(before, after, reason)
    in_repository do |repository|
      write_and_commit(repository, "pricing.rb", before)
      commit = write_and_commit(repository, "pricing.rb", after)

      assert_check_rejected(repository, commit, reason)
    end
  end

  def assert_check_rejected(repository, commit, reason)
    stdout, stderr, status = run_check(repository, commit)

    assert_equal 1, status.exitstatus
    assert_equal "#{reason}\n", stdout
    assert_empty stderr
  end
end
