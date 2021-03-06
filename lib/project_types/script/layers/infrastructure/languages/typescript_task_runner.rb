# frozen_string_literal: true

module Script
  module Layers
    module Infrastructure
      module Languages
        class TypeScriptTaskRunner < TaskRunner
          NODE_MIN_VERSION = "14.15.0"
          NPM_MIN_VERSION = "5.2.0"

          BYTECODE_FILE = "build/index.wasm"
          METADATA_FILE = "build/metadata.json"
          SCRIPT_SDK_BUILD = "npm run build"
          GEN_METADATA = "npm run gen-metadata"
          NPM_SET_REGISTRY_COMMAND = "npm --userconfig ./.npmrc config set @shopify:registry https://registry.npmjs.com"
          NPM_SET_ENGINE_STRICT_COMMAND = "npm --userconfig ./.npmrc config set engine-strict true"
          NPM_INSTALL_COMMAND = "npm install --no-audit --no-optional --legacy-peer-deps --loglevel error"

          def build
            compile
          rescue Errors::SystemCallFailureError => e
            raise Errors::BuildError, e.out
          end

          def install_dependencies
            run_cmd_with_env_check(NPM_INSTALL_COMMAND)

          rescue Errors::SystemCallFailureError => e
            raise Errors::DependencyInstallError, e.out
          end

          def dependencies_installed?
            # Assuming if node_modules folder exist at root of script folder, all deps are installed
            ctx.dir_exist?("node_modules")
          end

          def metadata_file_location
            METADATA_FILE
          end

          def library_version(library_name)
            output = JSON.parse(run_cmd_with_env_check("npm -s list --json"))
            library_version_from_npm_list(output, library_name)
          rescue Errors::SystemCallFailureError => error
            library_version_from_npm_list_error_output(error, library_name)
          end

          def set_npm_config
            run_cmd_with_env_check(NPM_SET_REGISTRY_COMMAND)
            run_cmd_with_env_check(NPM_SET_ENGINE_STRICT_COMMAND)
          end

          private

          def ensure_environment
            return if defined?(@environment_checked)
            @environment_checked = true

            ToolVersionChecker.check_node(minimum_version: NODE_MIN_VERSION)
            ToolVersionChecker.check_npm(minimum_version: NPM_MIN_VERSION)
          end

          def run_cmd_with_env_check(cmd)
            ensure_environment
            CommandRunner.new(ctx: ctx).call(cmd)
          end

          def library_version_from_npm_list_error_output(error, library_name)
            # npm list can return a failure status code, even when returning the correct data.
            # This causes the CommandRunner to throw a SystemCallFailure error that contains the data.
            # In here, we check that the output contains `npm list`'s structure and extract the version.
            output = JSON.parse(error.out)
            raise error unless output.key?("dependencies")

            library_version_from_npm_list(output, library_name)
          rescue JSON::ParserError
            raise error
          end

          def library_version_from_npm_list(output, library_name)
            output.dig("dependencies", library_name, "version").tap do |version|
              raise Errors::APILibraryNotFoundError, library_name unless version
            end
          end

          def compile
            check_compilation_dependencies!
            run_cmd_with_env_check(SCRIPT_SDK_BUILD)
            run_cmd_with_env_check(GEN_METADATA)
          end

          def check_compilation_dependencies!
            pkg = JSON.parse(File.read("package.json"))
            build_script = pkg.dig("scripts", "build")

            raise Errors::BuildScriptNotFoundError,
              "Build script not found" if build_script.nil?
          end
        end
      end
    end
  end
end
