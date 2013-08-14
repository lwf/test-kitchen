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

require 'kitchen/provisioner/puppet_base'

module Kitchen

  module Provisioner

    # Chef Zero provisioner.
    #
    # @author Fletcher Nichol <fnichol@nichol.ca>
    class PuppetApply < PuppetBase

      def create_sandbox
        create_puppet_sandbox
      end

      def prepare_command
        ""
      end

      def run_command
        [
          sudo("puppet"),
          "apply",
          File.join(home_path, 'base.pp'),
          "--modulepath=#{File.join(home_path, 'modules')}",
          "--hiera_config=#{File.join(home_path, 'hiera.yaml')}"
        ].join(" ")
      end

      def home_path
        "/tmp/kitchen-puppet-apply".freeze
      end
    end
  end
end
