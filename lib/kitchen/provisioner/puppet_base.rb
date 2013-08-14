# -*- encoding: utf-8 -*-
#
# Author:: Fletcher Nichol (<fnichol@nichol.ca>)
#
# Copyright (C) 2013, Fletcher Nichol
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#    http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

require 'fileutils'
require 'json'
require 'puppet'
require 'kitchen/provisioner/chef_base'

module Kitchen

  module Provisioner

    class PuppetBase < ChefBase

      def install_command
        config[:require_chef_omnibus] = true
        super +
        <<-INSTALL.gsub(/^ {10}/, '')
          bash -c '
            https://www.opscode.com/chef/install.sh
            if [ -e "/etc/debian_version" ]; then
              wget -O/tmp/puppet.deb http://apt.puppetlabs.com/puppetlabs-release-$(lsb_release -c -s).deb && \
                sudo dpkg -i /tmp/puppet.deb && \
                sudo apt-get update && \
                sudo apt-get -y install puppet
            fi'
        INSTALL
      end

      def init_command
        "#{sudo('rm')} -rf #{home_path}"
      end

      def cleanup_sandbox
        return if tmpdir.nil?

        debug("Cleaning up local sandbox in #{tmpdir}")
        FileUtils.rmtree(tmpdir)
      end

      protected

      def create_puppet_sandbox
        @tmpdir = Dir.mktmpdir("#{instance.name}-sandbox-")
        debug("Creating local sandbox in #{tmpdir}")

        yield if block_given?
        prepare_hiera
        prepare_manifest
        prepare_modules
        tmpdir
      end

      def prepare_modules
        if File.exists?(puppetfile)
          resolve_with_librarian
        elsif File.directory?(module_dir)
          cp_modules
        elsif File.exists?(modulefile)
          cp_this_module
        else
          FileUtils.rmtree(tmpdir)
          fatal("Puppetfile, modules/ directory, Modulefile" +
            " must exist in #{kitchen_root}")
          raise UserError, "Module(s) could not be found"
        end
      end

      def prepare_hiera
        FileUtils.mkdir_p(File.join(tmpdir, 'hieradata'))

        File.open(File.join(tmpdir, 'hieradata', 'base.yaml'), 'w') do |fh|
          fh.puts instance.hiera.to_yaml
        end

        File.open(File.join(tmpdir, 'hiera.yaml'), 'w') do |fh|
          fh.puts <<-EOF.gsub(/^ {10}/, '')
          ---
          :backends:
            - yaml

          :hierarchy:
            - common

          :yaml:
            :datadir: hieradata
          EOF
        end
      end

      def prepare_manifest
        File.open(File.join(tmpdir, 'base.pp'), 'w') do |fh|
          fh.puts instance.classes.map { |i| "include #{i}" }.join('; ')
        end
      end

      def puppetfile
        File.join(kitchen_root, "Puppetfile")
      end

      def module_dir
        File.join(kitchen_root, "modules")
      end

      def modulefile
        File.join(kitchen_root, "Modulefile")
      end

      def tmpmodule_dir
        File.join(tmpdir, "modules")
      end

      def cp_modules
        info("Preparing modules from project directory")
        debug("Using modules from #{module_dir}")

        FileUtils.mkdir_p(tmpmodule_dir)
        FileUtils.cp_r(File.join(module_dir, "."), tmpmodule_dir)
        cp_this_module if File.exists?(metadata_rb)
      end

      def cp_this_module
        info("Preparing current project directory as a module")
        debug("Using Modulefile from #{modulefile}")

        metadata = Puppet::ModuleTool::Metadata.new
        Puppet::ModuleTool::ModulefileReader.evaluate(metadata, modulefile)
        module_name = metadata.name or raise(UserError,
          "The Modulefile does not define the 'name' key." +
            " Please add: `name '<author>-<module_name>'` to Modulefile and retry")

        module_path = File.join(tmpmodule_dir, module_name)
        glob = Dir.glob("#{kitchen_root}/{Modulefile,README.*," +
          "lib,manifests,files,templates}")

        FileUtils.mkdir_p(module_path)
        FileUtils.cp_r(glob, module_path)
      end

      def resolve_with_librarian
        info("Resolving cookbook dependencies with Librarian-Chef")
        debug("Using Cheffile from #{cheffile}")

        begin
          require 'librarian/chef/environment'
          require 'librarian/action/resolve'
          require 'librarian/action/install'
        rescue LoadError
          fatal("The `librarian-chef' gem is missing and must be installed." +
            " Run `gem install librarian-chef` or add the following " +
            "to your Gemfile if you are using Bundler: `gem 'librarian-chef'`.")
          raise UserError, "Could not load Librarian-Chef"
        end

        Kitchen.mutex.synchronize do
          env = Librarian::Chef::Environment.new
          env.config_db.local["path"] = tmpbooks_dir
          Librarian::Action::Resolve.new(env).run
          Librarian::Action::Install.new(env).run
        end
      end
    end
  end
end
