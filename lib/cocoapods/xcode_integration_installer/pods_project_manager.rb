module Pod
  class XcodeIntegrationInstaller
    # The {PodsProjectManager} handles configuration of the Pods/Pods.xcodeproj
    #
    class PodsProjectManager
      autoload :FileReferencesInstaller, 'cocoapods/installer/file_references_installer'

      # @return [Pod::Project] the `Pods/Pods.xcodeproj` project.
      #
      attr_reader :pods_project

      attr_reader :aggregate_targets
      attr_reader :sandbox
      attr_reader :pod_targets
      attr_reader :analysis_result
      attr_reader :installation_options
      attr_reader :config

      def initialize(aggregate_targets, sandbox, pod_targets, analysis_result, installation_options, config)
        @aggregate_targets = aggregate_targets
        @sandbox = sandbox
        @pod_targets = pod_targets
        @analysis_result = analysis_result
        @installation_options = installation_options
        @config = config
      end

      def generate!
        prepare
        install_file_references
        install_libraries
        add_system_framework_dependencies
        set_target_dependencies
      end

      def write
        UI.message "- Writing Xcode project file to #{UI.path sandbox.project_path}" do
          pods_project.pods.remove_from_project if pods_project.pods.empty?
          pods_project.development_pods.remove_from_project if pods_project.development_pods.empty?
          pods_project.sort(:groups_position => :below)
          if installation_options.deterministic_uuids?
            UI.message('- Generating deterministic UUIDs') { pods_project.predictabilize_uuids }
          end
          pods_project.recreate_user_schemes(false)
          pods_project.save
        end
      end

      private

      # Creates the Pods project from scratch if it doesn't exist.
      #
      # @return [void]
      #
      # @todo   Clean and modify the project if it exists.
      #
      def prepare
        UI.message '- Creating Pods project' do
          @pods_project = if object_version = aggregate_targets.map(&:user_project).compact.map { |p| p.object_version.to_i }.min
                            Pod::Project.new(sandbox.project_path, false, object_version)
                          else
                            Pod::Project.new(sandbox.project_path)
                          end

          analysis_result.all_user_build_configurations.each do |name, type|
            @pods_project.add_build_configuration(name, type)
          end

          pod_names = pod_targets.map(&:pod_name).uniq
          pod_names.each do |pod_name|
            local = sandbox.local?(pod_name)
            path = sandbox.pod_dir(pod_name)
            was_absolute = sandbox.local_path_was_absolute?(pod_name)
            @pods_project.add_pod_group(pod_name, path, local, was_absolute)
          end

          if config.podfile_path
            @pods_project.add_podfile(config.podfile_path)
          end

          sandbox.project = @pods_project
          platforms = aggregate_targets.map(&:platform)
          osx_deployment_target = platforms.select { |p| p.name == :osx }.map(&:deployment_target).min
          ios_deployment_target = platforms.select { |p| p.name == :ios }.map(&:deployment_target).min
          watchos_deployment_target = platforms.select { |p| p.name == :watchos }.map(&:deployment_target).min
          tvos_deployment_target = platforms.select { |p| p.name == :tvos }.map(&:deployment_target).min
          @pods_project.build_configurations.each do |build_configuration|
            build_configuration.build_settings['MACOSX_DEPLOYMENT_TARGET'] = osx_deployment_target.to_s if osx_deployment_target
            build_configuration.build_settings['IPHONEOS_DEPLOYMENT_TARGET'] = ios_deployment_target.to_s if ios_deployment_target
            build_configuration.build_settings['WATCHOS_DEPLOYMENT_TARGET'] = watchos_deployment_target.to_s if watchos_deployment_target
            build_configuration.build_settings['TVOS_DEPLOYMENT_TARGET'] = tvos_deployment_target.to_s if tvos_deployment_target
            build_configuration.build_settings['STRIP_INSTALLED_PRODUCT'] = 'NO'
            build_configuration.build_settings['CLANG_ENABLE_OBJC_ARC'] = 'YES'
          end
        end
      end

      def install_file_references
        installer = FileReferencesInstaller.new(sandbox, pod_targets, pods_project)
        installer.install!
      end

      def install_libraries
        UI.message '- Installing targets' do
          pod_targets.sort_by(&:name).each do |pod_target|
            target_installer = PodTargetInstaller.new(sandbox, pod_target)
            target_installer.install!
          end

          aggregate_targets.sort_by(&:name).each do |target|
            target_installer = AggregateTargetInstaller.new(sandbox, target)
            target_installer.install!
          end

          add_system_framework_dependencies
        end
      end

      def add_system_framework_dependencies
        pod_targets.sort_by(&:name).each do |pod_target|
          pod_target.file_accessors.each do |file_accessor|
            file_accessor.spec_consumer.frameworks.each do |framework|
              if pod_target.should_build?
                pod_target.native_target.add_system_framework(framework)
              end
            end
          end
        end
      end

      def set_target_dependencies
        frameworks_group = pods_project.frameworks_group
        aggregate_targets.each do |aggregate_target|
          is_app_extension = !(aggregate_target.user_targets.map(&:symbol_type) &
                               [:app_extension, :watch_extension, :watch2_extension, :tv_extension]).empty?
          is_app_extension ||= aggregate_target.user_targets.any? { |ut| ut.common_resolved_build_setting('APPLICATION_EXTENSION_API_ONLY') == 'YES' }

          aggregate_target.pod_targets.each do |pod_target|
            configure_app_extension_api_only_for_target(aggregate_target) if is_app_extension

            unless pod_target.should_build?
              pod_target.resource_bundle_targets.each do |resource_bundle_target|
                aggregate_target.native_target.add_dependency(resource_bundle_target)
              end

              next
            end

            aggregate_target.native_target.add_dependency(pod_target.native_target)
            configure_app_extension_api_only_for_target(pod_target) if is_app_extension

            pod_target.dependent_targets.each do |pod_dependency_target|
              next unless pod_dependency_target.should_build?
              pod_target.native_target.add_dependency(pod_dependency_target.native_target)
              configure_app_extension_api_only_for_target(pod_dependency_target) if is_app_extension

              if pod_target.requires_frameworks?
                product_ref = frameworks_group.files.find { |f| f.path == pod_dependency_target.product_name } ||
                  frameworks_group.new_product_ref_for_target(pod_dependency_target.product_basename, pod_dependency_target.product_type)
                pod_target.native_target.frameworks_build_phase.add_file_reference(product_ref, true)
              end
            end
          end
        end
      end
    end
  end
end
