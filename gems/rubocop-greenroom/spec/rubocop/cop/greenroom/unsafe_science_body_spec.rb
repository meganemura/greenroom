# frozen_string_literal: true

require "spec_helper"

RSpec.describe RuboCop::Cop::Greenroom::UnsafeScienceBody, :config do
  shared_examples "an unsafe return" do |call|
    it "rejects return in #{call}" do
      expect_offense(<<~RUBY)
        Scientist.run "price-v2" do |e|
          e.#{call} { return 1 }
                  ^^^^^^^^ A return in a science body bypasses comparison and publication.
        end
      RUBY
    end
  end

  include_examples "an unsafe return", "use"
  include_examples "an unsafe return", "try"

  it "rejects binding in use" do
    expect_offense(<<~RUBY)
      Scientist.run "price-v2" do |e|
        e.use { binding }
                ^^^^^^^ A binding in a science body observes the block scope.
      end
    RUBY
  end

  # This example pins deliberate over-rejection rather than correct behaviour.
  # A binding inside a nested def reads that def's scope, and it reads the same
  # scope before and after the body moves, so a precise cop would stay quiet
  # here. This one reports it, because the check for return earns its
  # complexity and this shape does not: a def written inside a science body is
  # not a shape anyone needs to write. A change that makes this example pass by
  # staying quiet is loosening the cop, so decide that on purpose. Reporting
  # too much sends the change to a human reviewer, which is the safe direction.
  it "rejects binding in a nested def, by design" do
    expect_offense(<<~RUBY)
      Scientist.run "price-v2" do |e|
        e.use do
          def helper
            binding
            ^^^^^^^ A binding in a science body observes the block scope.
          end
        end
      end
    RUBY
  end

  it "accepts return in a nested def" do
    expect_no_offenses(<<~RUBY)
      Scientist.run "price-v2" do |e|
        e.use do
          def helper
            return 1
          end
        end
      end
    RUBY
  end

  it "accepts return in a nested singleton def" do
    expect_no_offenses(<<~RUBY)
      Scientist.run "price-v2" do |e|
        e.use do
          def self.helper
            return 1
          end
        end
      end
    RUBY
  end

  it "accepts return in an arrow lambda" do
    expect_no_offenses(<<~RUBY)
      Scientist.run "price-v2" do |e|
        e.use { -> { return 1 } }
      end
    RUBY
  end

  it "accepts return in a lambda call" do
    expect_no_offenses(<<~RUBY)
      Scientist.run "price-v2" do |e|
        e.use { lambda { return 1 } }
      end
    RUBY
  end

  it "rejects return in a proc" do
    expect_offense(<<~RUBY)
      Scientist.run "price-v2" do |e|
        e.use { proc { return 1 } }
                       ^^^^^^^^ A return in a science body bypasses comparison and publication.
      end
    RUBY
  end

  it "rejects return in an ordinary block" do
    expect_offense(<<~RUBY)
      Scientist.run "price-v2" do |e|
        e.use { items.each { return 1 } }
                             ^^^^^^^^ A return in a science body bypasses comparison and publication.
      end
    RUBY
  end

  it "accepts the measured safe constructs" do
    expect_no_offenses(<<~RUBY)
      def compute
        Scientist.run "price-v2" do |e|
          e.use do
            local = VALUE
            yield local
            __method__
          rescue StandardError
            local
          ensure
            cleanup
          end
        end
      end
    RUBY
  end

  it "ignores another block" do
    expect_no_offenses(<<~RUBY)
      Research.run do |e|
        e.use { return binding }
      end
    RUBY
  end
end
