# frozen_string_literal: true

lib = ::File.expand_path("lib", __dir__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
require "hermes_agent/client/version"

::Gem::Specification.new do |spec|
  spec.name = "hermes-client"
  spec.version = ::HermesAgent::Client::VERSION
  spec.authors = ["Daniel Azuma"]
  spec.email = ["dazuma@gmail.com"]

  spec.summary = "A client for the Hermes Agent API Server."
  spec.description =
    "This is a basic client library for the API Server that ships with the " \
    "Hermes AI Agent."
  spec.license = "MIT"
  spec.homepage = "https://github.com/dazuma/hermes-client"

  spec.files = ::Dir.glob("lib/**/*.rb") +
               (::Dir.glob("*.md") - ["CLAUDE.md", "AGENTS.md"]) +
               [".yardopts"]
  spec.require_paths = ["lib"]

  spec.add_dependency "http", "~> 6.0"
  spec.add_dependency "ld-eventsource", "~> 2.6"
  spec.required_ruby_version = ">= 2.7"

  spec.metadata["bug_tracker_uri"] = "https://github.com/dazuma/hermes-client/issues"
  spec.metadata["changelog_uri"] = "https://rubydoc.info/gems/hermes-client/#{::HermesAgent::Client::VERSION}/file/CHANGELOG.md"
  spec.metadata["documentation_uri"] = "https://rubydoc.info/gems/hermes-client/#{::HermesAgent::Client::VERSION}"
  spec.metadata["homepage_uri"] = "https://github.com/dazuma/hermes-client"
end
