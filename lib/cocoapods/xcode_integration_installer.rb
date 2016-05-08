module Pod
  class XcodeIntegrationInstaller < Installer
    autoload :UserProjectIntegrator, 'cocoapods/xcode_integration_installer/user_project_integrator'

    # @return [Pod::Project] the `Pods/Pods.xcodeproj` project.
    #
    attr_reader :pods_project
    
    #-------------------------------------------------------------------------#
    
    private
    
    # @!group Integration Steps

    def perform_integration_steps
      generate_pods_project
      integrate_user_project if installation_options.integrate_targets?
    end

    def generate_pods_project
      UI.section 'Generating Pods project' do
        prepare_pods_project
        install_file_references
        install_libraries
        set_target_dependencies
        run_podfile_post_install_hooks
        write_pod_project
        share_development_pod_schemes
      end
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

    #-------------------------------------------------------------------------#

    private 

    # @!group Pods Project

    # Creates the Pods project from scratch if it doesn't exists.
    #
    # @return [void]
    #
    # @todo   Clean and modify the project if it exists.
    #
    def prepare_pods_project
    end

    # Installs the file references in the Pods project. This is done once per
    # Pod as the same file reference might be shared by multiple aggregate
    # targets.
    #
    # @return [void]
    #
    def install_file_references
    end

    # Installs the aggregate targets of the Pods projects and generates their
    # support files.
    #
    # @return [void]
    #
    def install_libraries
    end
   
    # Adds a target dependency for each pod spec to each aggregate target and
    # links the pod targets among each other.
    #
    # @return [void]
    #
    def set_target_dependencies
    end

    # Writes the Pods project to the disk.
    #
    # @return [void]
    #
    def write_pod_project
    end

    # Shares schemes of development Pods.
    #
    # @return [void]
    #
    def share_development_pod_schemes
      development_pod_targets.select(&:should_build?).each do |pod_target|
        Xcodeproj::XCScheme.share_scheme(pods_project.path, pod_target.label)
      end
    end
  end
end
