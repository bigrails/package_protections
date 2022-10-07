# typed: strict

# For String#camelize
require 'active_support/core_ext/string/inflections'

module RuboCop
  module Cop
    module PackageProtections
      class NamespacedUnderPackageName < Packs::NamespacedUnderPackageName
        extend T::Sig
        include ::PackageProtections::RubocopProtectionInterface

        # We override `cop_configs` for this protection.
        # The default behavior disables cops when a package has turned off a protection.
        # However: namespace violations can occur even when one package has TURNED OFF their namespace protection
        # but another package has it turned on. Therefore, all packages must always be opted in no matter what.
        #
        sig do
          params(packages: T::Array[::PackageProtections::ProtectedPackage])
          .returns(T::Array[::PackageProtections::RubocopProtectionInterface::CopConfig])
        end
        def cop_configs(packages)
          include_packs = T.let([], T::Array[String])
          packages.each do |p|
            enabled_for_pack = !p.violation_behavior_for(NamespacedUnderPackageName::IDENTIFIER).fail_never?
            if enabled_for_pack
              include_packs << p.name
            end
          end

          [
            ::PackageProtections::RubocopProtectionInterface::CopConfig.new(
              name: cop_name,
              enabled: include_packs.any?,
              metadata: {
                'IncludePacks' => include_packs,
                'GloballyPermittedNamespaces' => ::PackageProtections.config.globally_permitted_namespaces
              }
            )
          ]
        end

        sig { override.returns(T::Array[String]) }
        def included_globs_for_pack
          [
            'app/**/*',
            'lib/**/*'
          ]
        end

        IDENTIFIER = T.let('prevent_this_package_from_creating_other_namespaces'.freeze, String)

        sig { override.returns(String) }
        def identifier
          IDENTIFIER
        end

        sig { override.params(behavior: ::PackageProtections::ViolationBehavior, package: ParsePackwerk::Package).returns(T.nilable(String)) }
        def unmet_preconditions_for_behavior(behavior, package)
          if !behavior.enabled? && !package.metadata['global_namespaces'].nil?
            "Invalid configuration for package `#{package.name}`. `#{identifier}` must be turned on to use `global_namespaces` configuration."
          else
            # We don't need to validate if the behavior is currentely fail_never
            return if behavior.fail_never?

            # The reason for this is precondition is the `MultipleNamespacesProtection` assumes this to work properly.
            # To remove this precondition, we need to modify `MultipleNamespacesProtection` to be more generalized!
            is_root_package = package.name == ParsePackwerk::ROOT_PACKAGE_NAME
            in_allowed_directory = ::PackageProtections::EXPECTED_PACK_DIRECTORIES.any? do |expected_package_directory|
              package.directory.to_s.start_with?(expected_package_directory)
            end
            if in_allowed_directory || is_root_package
              nil
            else
              "Package #{package.name} must be located in one of #{::PackageProtections::EXPECTED_PACK_DIRECTORIES.join(', ')} (or be the root) to use this protection"
            end
          end
        end

        sig do
          override.params(file: String).returns(String)
        end
        def message_for_fail_on_any(file)
          "`#{file}` should be namespaced under the package namespace"
        end

        sig { override.returns(String) }
        def cop_name
          'PackageProtections/NamespacedUnderPackageName'
        end

        sig { override.returns(String) }
        def humanized_protection_name
          'Multiple Namespaces Violations'
        end

        sig { override.returns(String) }
        def humanized_protection_description
          <<~MESSAGE
            These files cannot have ANY modules/classes that are not submodules of the package's allowed namespaces.
            This is failing because these files are in `.rubocop_todo.yml` under `#{cop_name}`.
            If you want to be able to ignore these files, you'll need to open the file's package's `package.yml` file and
            change `#{IDENTIFIER}` to `#{::PackageProtections::ViolationBehavior::FailOnNew.serialize}`

            See https://go/packwerk_cheatsheet_namespaces for more info.
          MESSAGE
        end
      end
    end
  end
end
