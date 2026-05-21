# frozen_string_literal: true

expand :clean do |t|
  t.paths = :gitignore
  t.preserve = [".claude/plans", ".claude/settings.local.json"]
end

expand :minitest, libs: ["lib", "test"], bundler: true

tool "test" do
  flag :integration_port, "--integration-port=PORT" do
    desc "Include integration tests run against the given port"
  end
  flag :integration_profile, "--integration-profile=PROFILE" do
    desc "Run the hermes test server for integration tests, against the given profile"
  end

  to_run :run_with_integration

  def run_with_integration
    if integration_port
      ENV["HERMES_CLIENT_INTEGRATION_PORT"] = integration_port
      ENV["HERMES_CLIENT_INTEGRATION_PROFILE"] = integration_profile if integration_profile
    end
    run
  end
end

expand :rubocop, bundler: true

expand :yardoc do |t|
  t.generate_output_flag = true
  t.fail_on_warning = true
  t.fail_on_undocumented_objects = true
  t.bundler = true
end

expand :gem_build

expand :gem_build, name: "install", install_gem: true
