module Pod
  class XcodeIntegrationInstaller < Installer
    autoload :UserProjectIntegrator, 'cocoapods/xcode_integration_installer/user_project_integrator'
    autoload :PodsProjectManager, 'cocoapods/xcode_integration_installer/pods_project_manager'

    # @return [Pod::Project] the `Pods/Pods.xcodeproj` project.
    #
    attr_reader :pods_project
    
    def perform_integration_steps
      generate_pods_project
      run_plugins_post_install_hooks
      @pods_project_manager.write
      integrate_user_project if installation_options.integrate_targets?
    end

    private
   
    attr_reader :pods_project_manager

    def generate_pods_project
      @pods_project_manager = PodsProjectManager.new(aggregate_targets, sandbox, pod_targets, analysis_result)
      @pods_project_manager.generate!
      @pods_project = project_manager.project
    end

    # Integrates the user projects adding the dependencies on the CocoaPods
    # libraries, setting them up to use the xcconfigs and performing other
    # actions. This step is also responsible of creating the workspace if
    # needed.
    #
    # @return [void]
    #
    # @todo   [#397] The libraries should be cleaned and the re-added on every
    #         installation. Maybe a clean_user_project phase should be added.
    #         In any case it appears to be a good idea store target definition
    #         information in the lockfile.
    #
    def integrate_user_project
      UI.section "Integrating client #{'project'.pluralize(aggregate_targets.map(&:user_project_path).uniq.count)}" do
        installation_root = config.installation_root
        integrator = UserProjectIntegrator.new(podfile, sandbox, installation_root, aggregate_targets)
        integrator.integrate!
      end
    end
  end
end
