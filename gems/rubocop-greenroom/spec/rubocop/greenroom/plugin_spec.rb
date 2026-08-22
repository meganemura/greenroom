# frozen_string_literal: true

require "open3"
require "spec_helper"
require "tmpdir"

RSpec.describe RuboCop::Greenroom::Plugin do
  it "loads and enables all cops through the plugins setting" do
    Dir.mktmpdir do |directory|
      config_path = File.join(directory, ".rubocop.yml")
      File.write(config_path, "plugins:\n  - rubocop-greenroom\n")

      stdout, stderr, status = Open3.capture3(
        {"XDG_CACHE_HOME" => directory},
        Gem.ruby,
        "-S",
        "rubocop",
        "--config",
        config_path,
        "--show-cops"
      )

      expect(status).to be_success, stderr
      cop_names = %w[
        Greenroom/ScienceBlockShape
        Greenroom/UnsafeScienceBody
        Greenroom/CandidateIsPrivate
      ]
      cop_names.each do |cop_name|
        section = stdout[/^#{Regexp.escape(cop_name)}:$\n(?:^ .*$\n?)*/]
        expect(section).to include("Enabled: true")
      end
    end
  end
end
