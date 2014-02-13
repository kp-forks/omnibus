#
# Copyright:: Copyright (c) 2014 Chef Software, Inc.
# License:: Apache License, Version 2.0
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#

require 'stringio'
require 'omnibus/packagers/mac_pkg'
require 'spec_helper'

describe Omnibus::Packagers::MacPkg do


  # TODO: need project to support a mac_pkg_identifier attribute.
  # IOW, this isn't consistent with Project's interface
  let(:mac_pkg_identifier) { "com.mycorp.myproject" }

  let(:omnibus_root) { "/omnibus/project/root" }

  let(:scripts_path) { "#{omnibus_root}/scripts" }

  # TODO: need project to provide a package_dir method
  # IOW, this isn't consistent with Project's interface
  let(:package_dir) { "/home/someuser/omnibus-myproject/pkg" }

  # TODO: need project to provide a files_dir method
  # IOW, this isn't consistent with Project's interface
  let(:files_path) { "#{omnibus_root}/files" }

  let(:expected_distribution_content) do
    <<-EOH
<?xml version="1.0" standalone="no"?>
<installer-gui-script minSpecVersion="1">
    <title>Myproject</title>
    <background file="background.png" alignment="bottomleft" mime-type="image/png"/>
    <welcome file="welcome.html" mime-type="text/html"/>
    <license file="license.html" mime-type="text/html"/>

    <!-- Generated by productbuild - - synthesize -->
    <pkg-ref id="com.mycorp.myproject"/>
    <options customize="never" require-scripts="false"/>
    <choices-outline>
        <line choice="default">
            <line choice="com.mycorp.myproject"/>
        </line>
    </choices-outline>
    <choice id="default"/>
    <choice id="com.mycorp.myproject" visible="false">
        <pkg-ref id="com.mycorp.myproject"/>
    </choice>
    <pkg-ref id="com.mycorp.myproject" version="23.4.2" onConclusion="none">myproject-core.pkg</pkg-ref>
</installer-gui-script>
EOH
  end

  let(:productbuild_argv) do
    %w[
      productbuild
      --distribution /tmp/omnibus-mac-pkg-tmp/Distribution
      --resources /omnibus/project/root/files/mac_pkg/Resources
      /home/someuser/omnibus-myproject/pkg/myproject.pkg
    ]
  end

  let(:pkgbuild_argv) do
    %w[
      pkgbuild
      --identifier com.mycorp.myproject
      --version 23.4.2
      --scripts /omnibus/project/root/scripts
      --root /opt/myproject
      --install-location /opt/myproject
      myproject-core.pkg
    ]
  end

  let(:shellout_opts) do
     {
        :timeout => 3600,
        :cwd => "/tmp/omnibus-mac-pkg-tmp"
      }
  end

  let(:project) do
    double(Omnibus::Project,
           :name => "myproject",
           :build_version => "23.4.2",
           :install_path => "/opt/myproject",
           :package_scripts_path => scripts_path,
           :files_path => files_path,
           :package_dir => package_dir,
           :mac_pkg_identifier => mac_pkg_identifier)

  end


  let(:packager) do
    Omnibus::Packagers::MacPkg.new(project)
  end

  it "uses the project's version" do
    expect(packager.version).to eq(project.build_version)
  end

  it "uses the project's name" do
    expect(packager.name).to eq(project.name)
  end

  it "uses the project's mac_pkg_identifier" do
    expect(packager.identifier).to eq(mac_pkg_identifier)
  end

  it "uses the project's install_path as the package root" do
    expect(packager.pkg_root).to eq(project.install_path)
  end

  it "uses the project's install_path as the package install location" do
    expect(packager.install_location).to eq(project.install_path)
  end

  it "names the component package PROJECT_NAME-core.pkg" do
    expect(packager.component_pkg_name).to eq("myproject-core.pkg")
  end

  it "use's the project's package_scripts_path" do
    expect(packager.scripts).to eq(project.package_scripts_path)
  end

  it "makes a list of required files to generate the 'product' pkg file" do
    project_file_path = "/omnibus/project/root/files/mac_pkg/Resources"
    required_files = %w[background.png welcome.html license.html].map do |basename|
      File.join(project_file_path, basename)
    end

    expect(packager.required_files).to match_array(required_files)
  end

  it "validates that all required files are present" do
    expected_error_text=<<-E
      Your omnibus repo is missing the following files required to build Mac
      packages:
      * /omnibus/project/root/files/mac_pkg/Resources/background.png
      * /omnibus/project/root/files/mac_pkg/Resources/license.html
      * /omnibus/project/root/files/mac_pkg/Resources/welcome.html
E
    # RSpec 2.14.1 doesn't do nice diffs of expected error strings, so do this
    # the hard way for now.
    e = nil
    begin
      packager.validate_omnibus_project!
    rescue => e
    end
    expect(e).to be_a(Omnibus::MissingMacPkgResource)
    expect(e.to_s).to eq(expected_error_text)
  end

  it "clears and recreates the staging dir" do
    FileUtils.should_receive(:rm_rf).with("/tmp/omnibus-mac-pkg-tmp")
    FileUtils.should_receive(:mkdir).with("/tmp/omnibus-mac-pkg-tmp")
    packager.setup_staging_dir!
  end

  it "generates a pkgbuild command" do
    expect(packager.pkgbuild_command).to eq(pkgbuild_argv)
  end

  it "runs pkgbuild" do
    expected_args = pkgbuild_argv + [shellout_opts]
    packager.should_receive(:shellout!).with(*expected_args)
    packager.build_component_pkg
  end

  it "has a temporary staging location for the distribution file" do
    expect(packager.staging_dir).to eq("/tmp/omnibus-mac-pkg-tmp")
  end

  it "generates a Distribution file describing the product package content" do
    expect(packager.distribution).to eq(expected_distribution_content)
  end


  it "generates a productbuild command" do
    expect(packager.productbuild_command).to eq(productbuild_argv)
  end

  describe "building the product package" do

    let(:distribution_file) { StringIO.new }

    before do
      File.should_receive(:open).
        with("/tmp/omnibus-mac-pkg-tmp/Distribution", File::RDWR|File::CREAT|File::EXCL, 0600).
        and_yield(distribution_file)
    end

    it "writes the distribution file to the staging directory" do
      packager.generate_distribution
      distribution_file.string.should eq(expected_distribution_content)
    end

    it "generates the distribution and runs productbuild" do
      expected_shellout_args = productbuild_argv + [shellout_opts]

      packager.should_receive(:shellout!).with(*expected_shellout_args)
      packager.build_product_pkg
      distribution_file.string.should eq(expected_distribution_content)
    end

  end
  context "when the mac_pkg_identifier isn't specified by the project" do

    let(:mac_pkg_identifier) { nil }

    it "uses com.example.PROJECT_NAME as the identifier" do
      pending
      expect(packager.identifier).to eq("com.example.myproject")
    end

  end

  context "when the project has the required Resource files" do

    before do
      project_file_path = "/omnibus/project/root/files/mac_pkg/Resources"
      %w[background.png welcome.html license.html].each do |basename|
        path = File.join(project_file_path, basename)
        File.stub(:exist?).with(path).and_return(true)
      end
    end

    it "validates the presence of the required files" do
      expect(packager.validate_omnibus_project!).to be_true
    end


  end

end


