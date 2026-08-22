# frozen_string_literal: true

require_relative "lib/rubocop/greenroom/version"

Gem::Specification.new do |spec|
  spec.name = "rubocop-greenroom"
  spec.version = RuboCop::Greenroom::VERSION
  spec.authors = ["meganemura"]
  spec.email = ["meganemura@users.noreply.github.com"]
  spec.summary = "RuboCop rules for Greenroom science blocks"
  spec.description = "Checks the single-file structure of Greenroom science blocks."
  spec.homepage = "https://github.com/meganemura/greenroom"
  spec.license = "MIT"
  spec.required_ruby_version = ">= 3.3.0"
  spec.files = Dir["config/**/*.yml", "lib/**/*.rb", "CHANGELOG.md", "LICENSE.txt", "README.md"]
  spec.require_paths = ["lib"]
  spec.metadata["default_lint_roller_plugin"] = "RuboCop::Greenroom::Plugin"
  spec.metadata["allowed_push_host"] = "https://rubygems.org"
  spec.metadata["homepage_uri"] = spec.homepage
  spec.metadata["source_code_uri"] = spec.homepage
  spec.metadata["changelog_uri"] = "#{spec.homepage}/blob/main/gems/rubocop-greenroom/CHANGELOG.md"

  spec.add_dependency "rubocop", "~> 1.88"
end
