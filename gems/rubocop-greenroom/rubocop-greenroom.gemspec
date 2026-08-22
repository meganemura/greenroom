# frozen_string_literal: true

require_relative "lib/rubocop/greenroom/version"

Gem::Specification.new do |spec|
  spec.name = "rubocop-greenroom"
  spec.version = RuboCop::Greenroom::VERSION
  spec.authors = ["Greenroom contributors"]
  spec.summary = "RuboCop rules for Greenroom science blocks"
  spec.description = "Checks the single-file structure of Greenroom science blocks."
  spec.license = "MIT"
  spec.required_ruby_version = ">= 3.2.0"
  spec.files = Dir["config/**/*.yml", "lib/**/*.rb", "LICENSE.txt", "README.md"]
  spec.require_paths = ["lib"]
  spec.metadata["default_lint_roller_plugin"] = "RuboCop::Greenroom::Plugin"
  spec.metadata["homepage_uri"] = "https://github.com/meganemura/greenroom"

  spec.add_dependency "rubocop", "~> 1.88"
end
