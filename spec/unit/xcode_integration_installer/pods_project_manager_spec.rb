require File.expand_path('../../../spec_helper', __FILE__)

# @return [Lockfile]
#
def generate_lockfile(lockfile_version: Pod::VERSION)
  hash = {}
  hash['PODS'] = []
  hash['DEPENDENCIES'] = []
  hash['SPEC CHECKSUMS'] = {}
  hash['COCOAPODS'] = lockfile_version
  Pod::Lockfile.new(hash)
end

# @return [Podfile]
#
def generate_podfile(pods = ['JSONKit'])
  Pod::Podfile.new do
    platform :ios
    project SpecHelper.fixture('SampleProject/SampleProject'), 'Test' => :debug, 'App Store' => :release
    target 'SampleProject' do
      pods.each { |name| pod name }
      target 'SampleProjectTests' do
        inherit! :search_paths
      end
    end
  end
end

module Pod
  describe XcodeIntegrationInstaller::PodsProjectManager do
    describe "Generating Pods Project" do
      before do
        podfile = generate_podfile
        lockfile = generate_lockfile
        @installer = XcodeIntegrationInstaller.new(config.sandbox, podfile, lockfile)
        @installer.send(:analyze)
        @manager = @installer.send(:create_project_manager)
      end

      describe "Preparing" do
        it "creates build configurations for all of the user's targets" do
          @manager.send(:prepare)
          @manager.pods_project.build_configurations.map(&:name).sort.should == ['App Store', 'Debug', 'Release', 'Test']
        end

        it 'sets STRIP_INSTALLED_PRODUCT to NO for all configurations for the whole project' do
          @manager.send(:prepare)
          @manager.pods_project.build_settings('Debug')['STRIP_INSTALLED_PRODUCT'].should == 'NO'
          @manager.pods_project.build_settings('Test')['STRIP_INSTALLED_PRODUCT'].should == 'NO'
          @manager.pods_project.build_settings('Release')['STRIP_INSTALLED_PRODUCT'].should == 'NO'
          @manager.pods_project.build_settings('App Store')['STRIP_INSTALLED_PRODUCT'].should == 'NO'
        end

        #        before do
        #          @installer.stubs(:analysis_result).returns(stub(:all_user_build_configurations => {}, :target_inspections => nil))
        #        end

        it 'creates the Pods project' do
          @manager.send(:prepare)
          @manager.pods_project.class.should == Pod::Project
        end

        #        it 'preserves Pod paths specified as absolute or rooted to home' do
        #          local_podfile = generate_local_podfile
        #          local_installer = XcodeIntegrationInstaller.new(config.sandbox, local_podfile)
        #          local_installer.send(:analyze)
        #          local_installer.send(:prepare_pods_project)
        #          group = local_installer.pods_project.group_for_spec('Reachability')
        #          Pathname.new(group.path).should.be.absolute
        #        end

        it 'adds the Podfile to the Pods project' do
          config.stubs(:podfile_path).returns(Pathname.new('/Podfile'))
          @manager.send(:prepare)
          @manager.pods_project['Podfile'].should.be.not.nil
        end

        it 'sets the deployment target for the whole project' do
          target_definition_osx = fixture_target_definition('OSX Target', Platform.new(:osx, '10.8'))
          target_definition_ios = fixture_target_definition('iOS Target', Platform.new(:ios, '6.0'))
          aggregate_target_osx = AggregateTarget.new(target_definition_osx, config.sandbox)
          aggregate_target_ios = AggregateTarget.new(target_definition_ios, config.sandbox)
          @manager.stubs(:aggregate_targets).returns([aggregate_target_osx, aggregate_target_ios])
          @manager.stubs(:pod_targets).returns([])
          @manager.send(:prepare)
          build_settings = @manager.pods_project.build_configurations.map(&:build_settings)
          build_settings.each do |build_setting|
            build_setting['MACOSX_DEPLOYMENT_TARGET'].should == '10.8'
            build_setting['IPHONEOS_DEPLOYMENT_TARGET'].should == '6.0'
          end
        end
      end

      #-------------------------------------#

      describe '#install_file_references' do
        it 'installs the file references' do
          @manager.stubs(:pod_targets).returns([])
          XcodeIntegrationInstaller::FileReferencesInstaller.any_instance.expects(:install!)
          @manager.send(:install_file_references)
        end
      end

      #-------------------------------------#
 
      describe '#install_libraries' do
        it 'install the targets of the Pod project' do
          spec = fixture_spec('banana-lib/BananaLib.podspec')
          target_definition = Podfile::TargetDefinition.new(:default, nil)
          target_definition.abstract = false
          target_definition.store_pod('BananaLib')
          pod_target = PodTarget.new([spec], [target_definition], config.sandbox)
          @manager.stubs(:aggregate_targets).returns([])
          @manager.stubs(:pod_targets).returns([pod_target])
          XcodeIntegrationInstaller::PodTargetInstaller.any_instance.expects(:install!)
          @manager.send(:install_libraries)
        end

        it 'does not skip empty pod targets' do
          spec = fixture_spec('banana-lib/BananaLib.podspec')
          target_definition = Podfile::TargetDefinition.new(:default, nil)
          target_definition.abstract = false
          pod_target = PodTarget.new([spec], [target_definition], config.sandbox)
          @manager.stubs(:aggregate_targets).returns([])
          @manager.stubs(:pod_targets).returns([pod_target])
          XcodeIntegrationInstaller::PodTargetInstaller.any_instance.expects(:install!).once
          @manager.send(:install_libraries)
        end

        it 'adds the frameworks required by to the pod to the project for informative purposes' do
          Specification::Consumer.any_instance.stubs(:frameworks).returns(['QuartzCore'])
          @manager.generate!
          names = @manager.sandbox.project['Frameworks']['iOS'].children.map(&:name)
          names.sort.should == ['Foundation.framework', 'QuartzCore.framework']
        end
      end

      #-------------------------------------#
      
      describe '#set_target_dependencies' do
        def test_extension_target(symbol_type)
          mock_user_target = mock('usertarget', :symbol_type => symbol_type)
          @target.stubs(:user_targets).returns([mock_user_target])

          build_settings = {}
          mock_configuration = mock('buildconfiguration', :build_settings => build_settings)
          @mock_target.stubs(:build_configurations).returns([mock_configuration])

          @manager.send(:set_target_dependencies)

          build_settings.should == { 'application_extension_api_only' => 'yes' }
        end

        before do
          spec = fixture_spec('banana-lib/BananaLib.podspec')

          target_definition = Podfile::TargetDefinition.new(:default, @installer.podfile.root_target_definitions.first)
          @pod_target = PodTarget.new([spec], [target_definition], config.sandbox)
          @target = AggregateTarget.new(target_definition, config.sandbox)

          @mock_target = mock('PodNativeTarget')

          mock_project = mock('PodsProject', :frameworks_group => mock('FrameworksGroup'))
          @manager.stubs(:pods_project).returns(mock_project)

          @target.stubs(:native_target).returns(@mock_target)
          @target.stubs(:pod_targets).returns([@pod_target])
          @installer.stubs(:aggregate_targets).returns([@target])
        end

        it 'sets resource bundles for not build pods as target dependencies of the user target' do
          @pod_target.stubs(:resource_bundle_targets).returns(['dummy'])
          @pod_target.stubs(:should_build? => false)
          @mock_target.expects(:add_dependency).with('dummy')

          @manager.send(:set_target_dependencies)
        end

        it 'configures APPLICATION_EXTENSION_API_ONLY for app extension targets' do
          test_extension_target(:app_extension)
        end

        it 'configures APPLICATION_EXTENSION_API_ONLY for watch extension targets' do
          test_extension_target(:watch_extension)
        end

        it 'configures APPLICATION_EXTENSION_API_ONLY for watchOS 2 extension targets' do
          test_extension_target(:watch2_extension)
        end

        it 'configures APPLICATION_EXTENSION_API_ONLY for tvOS extension targets' do
          test_extension_target(:tv_extension)
        end

        it 'configures APPLICATION_EXTENSION_API_ONLY for targets where the user target has it set' do
          mock_user_target = mock('UserTarget', :symbol_type => :application)
          mock_user_target.expects(:common_resolved_build_setting).with('APPLICATION_EXTENSION_API_ONLY').returns('YES')
          @target.stubs(:user_targets).returns([mock_user_target])

          build_settings = {}
          mock_configuration = mock('BuildConfiguration', :build_settings => build_settings)
          @mock_target.stubs(:build_configurations).returns([mock_configuration])

          @manager.send(:set_target_dependencies)

          build_settings.should == { 'APPLICATION_EXTENSION_API_ONLY' => 'YES' }
        end

        it 'does not try to set APPLICATION_EXTENSION_API_ONLY if there are no pod targets' do
          lambda do
            mock_user_target = mock('UserTarget', :symbol_type => :app_extension)
            @target.stubs(:user_targets).returns([mock_user_target])

            @target.stubs(:native_target).returns(nil)
            @target.stubs(:pod_targets).returns([])

            @manager.send(:set_target_dependencies)
          end.should.not.raise NoMethodError
        end
      end

      #--------------------------------------#

      describe '#write' do
        before do
          @manager.stubs(:aggregate_targets).returns([])
          @manager.stubs(:analysis_result).returns(stub(:all_user_build_configurations => {}, :target_inspections => nil))
          @manager.send(:prepare)
        end

        it 'recursively sorts the project' do
          Xcodeproj::Project.any_instance.stubs(:recreate_user_schemes)
          @manager.pods_project.main_group.expects(:sort)
          @manager.send(:write)
        end

        it 'saves the project to the given path' do
          Xcodeproj::Project.any_instance.stubs(:recreate_user_schemes)
          temporary_directory + 'Pods/Pods.xcodeproj'
          @manager.pods_project.expects(:save)
          @manager.send(:write)
        end

        it 'shares schemes of development pods' do
          spec = fixture_spec('banana-lib/BananaLib.podspec')
          pod_target = fixture_pod_target(spec)

          @manager.stubs(:pod_targets).returns([pod_target])
          @manager.sandbox.stubs(:development_pods).returns('BananaLib' => nil)

          Xcodeproj::XCScheme.expects(:share_scheme).with(
            @manager.pods_project.path,
            'BananaLib')

          @manager.send(:share_development_pod_schemes)
        end

        it "uses the user project's object version for the pods project" do
          tmp_directory = Pathname(Dir.tmpdir) + 'CocoaPods'
          FileUtils.mkdir_p(tmp_directory)
          proj = Xcodeproj::Project.new(tmp_directory + 'Yolo.xcodeproj', false, 1)
          proj.save

          aggregate_target = AggregateTarget.new(fixture_target_definition, config.sandbox)
          aggregate_target.user_project = proj
          @manager.stubs(:aggregate_targets).returns([aggregate_target])

          @manager.send(:prepare)
          @manager.pods_project.object_version.should == '1'

          FileUtils.rm_rf(tmp_directory)
        end
      end
    end
  end
end
