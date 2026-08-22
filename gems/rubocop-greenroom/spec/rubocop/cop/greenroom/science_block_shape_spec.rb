# frozen_string_literal: true

require "spec_helper"

RSpec.describe RuboCop::Cop::Greenroom::ScienceBlockShape, :config do
  it "accepts use, try, and compare in order" do
    expect_no_offenses(<<~RUBY)
      Scientist.run "price-v2" do |experiment|
        experiment.use { original }
        experiment.try { candidate }
        experiment.compare { |control, candidate| control == candidate }
      end
    RUBY
  end

  it "rejects a block that omits use" do
    expect_offense(<<~RUBY)
      Scientist.run "price-v2" do |experiment|
      ^^^^^^^^^^^^^^^^^^^^^^^^ A Scientist.run block must contain use, try, and compare once, in that order.
        experiment.try { candidate }
        experiment.compare { |control, candidate| control == candidate }
      end
    RUBY
  end

  it "rejects a block that omits try" do
    expect_offense(<<~RUBY)
      Scientist.run "price-v2" do |e|
      ^^^^^^^^^^^^^^^^^^^^^^^^ A Scientist.run block must contain use, try, and compare once, in that order.
        e.use { original }
        e.compare { |a, b| a == b }
      end
    RUBY
  end

  it "rejects a block that omits compare" do
    expect_offense(<<~RUBY)
      Scientist.run "price-v2" do |e|
      ^^^^^^^^^^^^^^^^^^^^^^^^ A Scientist.run block must contain use, try, and compare once, in that order.
        e.use { original }
        e.try { candidate }
      end
    RUBY
  end

  it "rejects calls in a different order" do
    expect_offense(<<~RUBY)
      Scientist.run "price-v2" do |e|
      ^^^^^^^^^^^^^^^^^^^^^^^^ A Scientist.run block must contain use, try, and compare once, in that order.
        e.try { candidate }
        e.use { original }
        e.compare { |a, b| a == b }
      end
    RUBY
  end

  it "rejects a duplicate science call" do
    expect_offense(<<~RUBY)
      Scientist.run "price-v2" do |e|
      ^^^^^^^^^^^^^^^^^^^^^^^^ A Scientist.run block must contain use, try, and compare once, in that order.
        e.use { original }
        e.try { candidate }
        e.try { another_candidate }
        e.compare { |a, b| a == b }
      end
    RUBY
  end

  it "rejects another expression" do
    expect_offense(<<~RUBY)
      Scientist.run "price-v2" do |e|
      ^^^^^^^^^^^^^^^^^^^^^^^^ A Scientist.run block must contain use, try, and compare once, in that order.
        prepare
        e.use { original }
        e.try { candidate }
        e.compare { |a, b| a == b }
      end
    RUBY
  end

  it "ignores another run block" do
    expect_no_offenses(<<~RUBY)
      Research.run "price-v2" do |e|
        return binding
      end
    RUBY
  end
end
