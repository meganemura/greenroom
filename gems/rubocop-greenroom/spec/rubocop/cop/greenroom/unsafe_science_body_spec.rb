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
