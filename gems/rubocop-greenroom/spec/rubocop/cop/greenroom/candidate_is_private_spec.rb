# frozen_string_literal: true

require "spec_helper"

RSpec.describe RuboCop::Cop::Greenroom::CandidateIsPrivate, :config do
  it "rejects a public candidate" do
    expect_offense(<<~RUBY)
      class Pricing
        def compute
          Scientist.run "price-v2" do |e|
            e.try { compute_v2 }
            ^^^^^^^^^^^^^^^^^^^^ A candidate method must be private.
          end
        end

        def compute_v2
        end
      end
    RUBY
  end

  it "rejects a protected candidate" do
    expect_offense(<<~RUBY)
      class Pricing
        Scientist.run "price-v2" do |e|
          e.try { compute_v2 }
          ^^^^^^^^^^^^^^^^^^^^ A candidate method must be private.
        end

        protected

        def compute_v2
        end
      end
    RUBY
  end

  it "accepts a candidate after private" do
    expect_no_offenses(<<~RUBY)
      class Pricing
        def compute
          Scientist.run("price-v2") { |e| e.try { compute_v2 } }
        end

        private

        def compute_v2
        end
      end
    RUBY
  end

  it "accepts a candidate named by private" do
    expect_no_offenses(<<~RUBY)
      class Pricing
        def compute
          Scientist.run("price-v2") { |e| e.try { compute_v2 } }
        end

        def compute_v2
        end
        private :compute_v2
      end
    RUBY
  end

  it "accepts an inline private candidate" do
    expect_no_offenses(<<~RUBY)
      class Pricing
        def compute
          Scientist.run("price-v2") { |e| e.try { self.compute_v2 } }
        end

        private def compute_v2
        end
      end
    RUBY
  end

  it "ignores a try body with multiple expressions" do
    expect_no_offenses(<<~RUBY)
      class Pricing
        Scientist.run "price-v2" do |e|
          e.try do
            prepare
            compute_v2
          end
        end

        def compute_v2
        end
      end
    RUBY
  end

  it "ignores a call with another receiver" do
    expect_no_offenses(<<~RUBY)
      class Pricing
        Scientist.run("price-v2") { |e| e.try { helper.compute_v2 } }

        def compute_v2
        end
      end
    RUBY
  end

  it "ignores a missing candidate definition" do
    expect_no_offenses(<<~RUBY)
      class Pricing
        Scientist.run("price-v2") { |e| e.try { compute_v2 } }
      end
    RUBY
  end

  it "ignores another run block" do
    expect_no_offenses(<<~RUBY)
      class Pricing
        Research.run { |e| e.try { compute_v2 } }

        def compute_v2
        end
      end
    RUBY
  end
end
