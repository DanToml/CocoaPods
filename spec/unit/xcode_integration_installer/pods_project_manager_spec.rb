require File.expand_path('../../../spec_helper', __FILE__)
module Pod
  describe XcodeIntegrationInstaller::PodsProjectManager do
    describe "Generating Pods Project" do
      describe "Preparing" do
        before do
          @manager = XcodeIntegrationInstaller::PodsProjectManager.new([], nil, nil, nil, nil)
        end

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
          build_settings = @installer.pods_project.build_configurations.map(&:build_settings)
          build_settings.each do |build_setting|
            build_setting['MACOSX_DEPLOYMENT_TARGET'].should == '10.8'
            build_setting['IPHONEOS_DEPLOYMENT_TARGET'].should == '6.0'
          end
        end
      end
    end
  end
end
