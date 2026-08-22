# frozen_string_literal: true

require_relative "lib/greenroom/version"

Gem::Specification.new do |spec|
  spec.name = "greenroom"
  spec.version = Greenroom::VERSION
  spec.authors = ["meganemura"]
  spec.email = ["meganemura@users.noreply.github.com"]

  spec.summary = "Judge a Scientist experiment by a nightly full-table census."
  spec.description = "Greenroom gives a Rails application the parts that turn a Scientist " \
    "experiment into evidence. An experiment stays inactive until a census job starts a " \
    "recorder, so a team can merge agent-written code early and run nothing new. The recorder " \
    "counts the rows, the comparisons, the mismatches, and the candidate errors. At the end of " \
    "the run it sends one aggregate event and a limited number of sample events. A sample " \
    "carries an identifier and a digest, and never the value itself."
  spec.homepage = "https://github.com/meganemura/greenroom"
  spec.license = "MIT"
  spec.required_ruby_version = ">= 3.2.0"
  spec.metadata["allowed_push_host"] = "https://rubygems.org"
  spec.metadata["homepage_uri"] = spec.homepage
  spec.metadata["source_code_uri"] = spec.homepage
  spec.metadata["changelog_uri"] = "#{spec.homepage}/blob/main/gems/greenroom/CHANGELOG.md"
  spec.metadata["rubygems_mfa_required"] = "true"

  # Specify which files should be added to the gem when it is released.
  # The `git ls-files -z` loads the files in the RubyGem that have been added into git.
  gemspec = File.basename(__FILE__)
  spec.files = IO.popen(%w[git ls-files -z], chdir: __dir__, err: IO::NULL) do |ls|
    ls.readlines("\x0", chomp: true).reject do |f|
      (f == gemspec) ||
        f.start_with?(*%w[bin/ Gemfile .gitignore test/ .standard.yml])
    end
  end
  spec.bindir = "exe"
  spec.executables = spec.files.grep(%r{\Aexe/}) { |f| File.basename(f) }
  spec.require_paths = ["lib"]

  # Scientist runs the experiment itself: it holds the two behaviours, it shuffles
  # their order, and it hands the result to the methods this gem ships. A pessimistic
  # constraint rather than an exact pin, because an exact pin in a library breaks the
  # dependency resolution of every host application that carries its own constraint.
  spec.add_dependency "scientist", "~> 1.6", ">= 1.6.5"
end
