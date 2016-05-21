require 'cocoapods/xcode/installer/user_project_integrator'
require 'cocoapods/xcode/pods_project_generator'

module Pod
  class Xcode
    # The Installer is responsible of taking a Podfile and transform it in the
    # Pods libraries. It also integrates the user project so the Pods
    # libraries can be used out of the box.
    #
    # The Installer is capable of doing incremental updates to an existing Pod
    # installation.
    #
    # The Installer gets the information that it needs mainly from 3 files:
    #
    #   - Podfile: The specification written by the user that contains
    #     information about targets and Pods.
    #   - Podfile.lock: Contains information about the pods that were previously
    #     installed and in concert with the Podfile provides information about
    #     which specific version of a Pod should be installed. This file is
    #     ignored in update mode.
    #   - Manifest.lock: A file contained in the Pods folder that keeps track of
    #     the pods installed in the local machine. This files is used once the
    #     exact versions of the Pods has been computed to detect if that version
    #     is already installed. This file is not intended to be kept under source
    #     control and is a copy of the Podfile.lock.
    #
    # The Installer is designed to work in environments where the Podfile folder
    # is under source control and environments where it is not. The rest of the
    # files, like the user project and the workspace are assumed to be under
    # source control.
    #
    class Installer < Pod::Installer
      # @return [Pod::Project] the `Pods/Pods.xcodeproj` project.
      #
      attr_reader :pods_project

      def perform_integration_steps
        verify_no_duplicate_framework_names
        verify_no_static_framework_transitive_dependencies
        verify_framework_usage
        generate_pods_project
        run_plugins_post_install_hooks
        @generator.write
        integrate_user_project if installation_options.integrate_targets?
      end

      private

      # @return [Pod::Xcode::PodsProjectGenerator] the 'Pods/Pods.xcodeproj' generator.
      #
      attr_reader :generator

      def create_generator
        PodsProjectGenerator.new(aggregate_targets, sandbox, pod_targets, analysis_result, installation_options, config)
      end

      # Generate the 'Pods/Pods.xcodeproj' project.
      #
      def generate_pods_project
        @generator ||= create_generator
        @generator.generate!
        @pods_project = @generator.project
      end

      # Integrates the user projects by adding the dependencies on the CocoaPods
      # libraries, setting them up to use the xcconfigs and performing other
      # actions. This step is also responsible for creating the workspace if
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

      #------------------------------------------------------------------------#

      # @!group Validation

      def verify_no_duplicate_framework_names
        aggregate_targets.each do |aggregate_target|
          aggregate_target.user_build_configurations.keys.each do |config|
            pod_targets = aggregate_target.pod_targets_for_build_configuration(config)
            vendored_frameworks = pod_targets.flat_map(&:file_accessors).flat_map(&:vendored_frameworks).uniq
            frameworks = vendored_frameworks.map { |fw| fw.basename('.framework') }
            frameworks += pod_targets.select { |pt| pt.should_build? && pt.requires_frameworks? }.map(&:product_module_name)

            duplicates = frameworks.group_by { |f| f }.select { |_, v| v.size > 1 }.keys
            unless duplicates.empty?
              raise Informative, "The '#{aggregate_target.label}' target has " \
              "frameworks with conflicting names: #{duplicates.to_sentence}."
            end
          end
        end
      end

      def verify_no_static_framework_transitive_dependencies
        aggregate_targets.each do |aggregate_target|
          next unless aggregate_target.requires_frameworks?

          aggregate_target.user_build_configurations.keys.each do |config|
            pod_targets = aggregate_target.pod_targets_for_build_configuration(config)

            dependencies = pod_targets.select(&:should_build?).flat_map(&:dependencies)
            dependended_upon_targets = pod_targets.select { |t| dependencies.include?(t.pod_name) && !t.should_build? }

            static_libs = dependended_upon_targets.flat_map(&:file_accessors).flat_map(&:vendored_static_artifacts)
            unless static_libs.empty?
              raise Informative, "The '#{aggregate_target.label}' target has " \
              "transitive dependencies that include static binaries: (#{static_libs.to_sentence})"
            end
          end
        end
      end

      def verify_framework_usage
        aggregate_targets.each do |aggregate_target|
          next if aggregate_target.requires_frameworks?

          aggregate_target.user_build_configurations.keys.each do |config|
            pod_targets = aggregate_target.pod_targets_for_build_configuration(config)

            swift_pods = pod_targets.select(&:uses_swift?)
            unless swift_pods.empty?
              raise Informative, 'Pods written in Swift can only be integrated as frameworks; ' \
              'add `use_frameworks!` to your Podfile or target to opt into using it. ' \
              "The Swift #{swift_pods.size == 1 ? 'Pod being used is' : 'Pods being used are'}: " +
                  swift_pods.map(&:name).to_sentence
            end
          end
        end
      end
    end
  end
end
