require "manageiq/cross_repo/repository"
require "active_support/core_ext/object/blank"

module ManageIQ::CrossRepo
  class Runner
    attr_reader :test_repo, :core_repo, :gem_repos

    def initialize(test_repo, core_repo, gem_repos)
      @test_repo = Repository.new(test_repo || "ManageIQ/manageiq@master")
      if @test_repo.core?
        raise ArgumentError, "You cannot pass a CORE_REPO when running a core test"          if core_repo.present?
        raise ArgumentError, "You must pass at least one GEM_REPOS when running a core test" if gem_repos.blank?

        @core_repo = @test_repo
      else
        raise ArgumentError, "You must pass either a CORE_REPO or at least one GEM_REPOS when running a plugin test" if core_repo.blank? && gem_repos.blank?

        @core_repo = Repository.new(core_repo || "ManageIQ/manageiq@master")
      end

      @gem_repos = gem_repos.to_a.map { |repo| Repository.new(repo) }
    end

    def run
      test_repo.ensure_clone
      test_repo.core? ? run_core : run_plugin
    end

    private

    def run_core
      prepare_gem_repos

      with_test_env do
        system!({"TRAVIS_BUILD_DIR" => test_repo.path.to_s}, "bash", "tools/ci/before_install.sh") if ENV["CI"]
        system!("bin/setup")
        system!("bundle exec rake")
      end
    end

    def run_plugin
      core_repo.ensure_clone
      symlink_core_repo_spec
      prepare_gem_repos

      with_test_env do
        system!("bin/setup")
        system!("bundle exec rake spec")
      end
    end

    def with_test_env
      Dir.chdir(test_repo.path) do
        Bundler.with_clean_env do
          yield
        end
      end
    end

    def system!(*args)
      exit($CHILD_STATUS.exitstatus) unless system(*args)
    end

    def generate_bundler_d
      bundler_d_path = core_repo.path.join("bundler.d")
      override_path  = bundler_d_path.join("overrides.rb")

      if gem_repos.empty?
        FileUtils.rm_f override_path
      else
        content = gem_repos.map { |gem| "override_gem \"#{gem.repo}\", :path => \"#{gem.path}\"" }.join("\n")
        FileUtils.mkdir_p(bundler_d_path)

        File.write(override_path, content)
      end
    end

    def prepare_gem_repos
      gem_repos.each { |gem_repo| gem_repo.ensure_clone }
      generate_bundler_d
    end

    def symlink_core_repo_spec
      core_spec_symlink = test_repo.path.join("spec", "manageiq")
      FileUtils.rm_f(core_spec_symlink)
      FileUtils.ln_s(core_repo.path, core_spec_symlink)
    end
  end
end
