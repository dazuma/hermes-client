# frozen_string_literal: true

load_gem "toys-ci"

desc "CI target that runs CI jobs in this repo"

flag :bundle_update, "--update", "--bundle-update" do
  desc "Update instead of install bundles"
end
flag :integration_port, "--integration-port=PORT" do
  desc "Include integration tests run against the given port"
end
flag :integration_profile, "--integration-profile=PROFILE" do
  desc "Run the hermes test server for integration tests, against the given profile"
end

expand(Toys::CI::Template) do |ci|
  ci.only_flag = true
  ci.fail_fast_flag = true

  ci.before_run do
    if integration_port
      ::ENV["HERMES_CLIENT_INTEGRATION_PORT"] = integration_port
      ::ENV["HERMES_CLIENT_INTEGRATION_PROFILE"] = integration_profile if integration_profile
    end
  end

  ci.job("Bundle install", flag: :bundle) do
    cmd = bundle_update ? ["bundle", "update", "--all"] : ["bundle", "install"]
    exec(cmd, name: "Bundle").success?
  end
  ci.tool_job("Rubocop", ["rubocop"], flag: :rubocop)
  ci.tool_job("Tests", ["test"], flag: :test)
  ci.tool_job("Yardoc", ["yardoc"], flag: :yard)
  ci.tool_job("Gem build", ["build"], flag: :build)
end
