#if DEBUG
import Testing
@testable import dev_manager

@Suite("Provisioning shell inspection")
@MainActor
struct ProvisioningShellInspectionTests {
    @Test("recognizes a standalone fnm initializer")
    func recognizesDirectInitializer() {
        #expect(ProvisioningShellConfiguration.classifyExternalInitialization(
            "eval \"$(fnm env --use-on-cd --shell zsh)\"\n"
        ) == .recognized)
        #expect(ProvisioningShellConfiguration.classifyExternalInitialization(
            "eval \"$(/opt/homebrew/bin/fnm env --shell zsh)\"\n"
        ) == .recognized)
        #expect(ProvisioningShellConfiguration.classifyExternalInitialization(
            #"eval "$('/Users/test/bin/fnm' env --use-on-cd --shell zsh)"#
        ) == .recognized)
    }

    @Test("comments and an absent initializer are not setup")
    func commentsAndMissingAreNotSetup() {
        #expect(ProvisioningShellConfiguration.classifyExternalInitialization("# fnm env --shell zsh\n") == .none)
        #expect(ProvisioningShellConfiguration.classifyExternalInitialization("export PATH=\"$PATH:/usr/local/bin\"\n") == .none)
        #expect(ProvisioningShellConfiguration.classifyExternalInitialization("") == .none)
    }

    @Test("a top-level initializer is not hidden by an unrelated fnm path wrapper")
    func topLevelInitializerIgnoresManagedPathReference() {
        let text = """
        eval "$(fnm env --use-on-cd --shell zsh)"
        pi() {
          export PATH="/Users/test/.local/share/fnm/node-versions/v24.21.0/installation/bin:$PATH"
        }
        """
        #expect(ProvisioningShellConfiguration.classifyExternalInitialization(text) == .recognized)
    }

    @Test("an FNM_DIR local path is not an fnm command")
    func fnmDirectoryAssignmentIsDataOnly() {
        let text = """
        eval "$(fnm env --use-on-cd --shell zsh)"
        export FNM_DIR="$HOME/.local/share/fnm"
        runtime_helper() {
          local root="${FNM_DIR:-$HOME/.local/share/fnm}/aliases/runtime-node"
          export PATH="$root/bin:$PATH"
        }
        """
        #expect(ProvisioningShellConfiguration.classifyExternalInitialization(text) == .recognized)
    }

    @Test("a profile-shaped initializer remains recognized around unrelated setup")
    func profileShapedInitializerRemainsRecognized() {
        let text = #"""
        # An anonymized interactive zsh profile fixture.
        eval "$(fnm env --use-on-cd --shell zsh)"
        eval "$(zoxide init zsh)"
        eval "$(starship init zsh)"
        autoload -Uz compinit
        compinit
        if [[ -r "/opt/dev-tools/zsh/highlighting.zsh" ]]; then
          source "/opt/dev-tools/zsh/highlighting.zsh"
        fi
        runtime_helper() {
          local root="${FNM_DIR:-$HOME/.local/share/fnm}/aliases/runtime-node"
          if [[ -x "$root/bin/node" ]]; then
            "$root/bin/node" \
              "$@"
          fi
        }
        """#
        #expect(ProvisioningShellConfiguration.classifyExternalInitialization(text) == .recognized)
    }

    @Test("function wrappers before and after a top-level initializer are scoped")
    func functionWrappersDoNotLatchClassification() {
        let before = """
        pi ()    {
          export PATH="/Users/test/.local/share/fnm/node-versions/v24.21.0/installation/bin:$PATH"
        }
        eval "$(/Users/test/.local/share/fnm/fnm env --shell zsh)"
        """
        let after = """
        eval "$(fnm env --shell zsh)"
        setup()
        {
          if true; then
            export PATH="/Users/test/.local/share/fnm/node-versions/v24.21.0/installation/bin:$PATH"
          fi
        }
        """
        #expect(ProvisioningShellConfiguration.classifyExternalInitialization(before) == .recognized)
        #expect(ProvisioningShellConfiguration.classifyExternalInitialization(after) == .recognized)
    }

    @Test("wrapped initializers and false conditionals remain unknown")
    func wrappedInitializersRemainUnknown() {
        for text in [
            "setup() {\n  eval \"$(fnm env --shell zsh)\"\n}\n",
            "if false; then\n  eval \"$(fnm env --shell zsh)\"\nfi\n",
            "if false; then eval \"$(fnm env --shell zsh)\"; fi\n"
        ] {
            #expect(ProvisioningShellConfiguration.classifyExternalInitialization(text) == .unknown)
        }
    }

    @Test("commented fnm paths are not ambiguous setup")
    func commentedPathIsNotSetup() {
        let text = """
        # export PATH="/Users/test/.local/share/fnm/node-versions/v24.21.0/installation/bin:$PATH"
        pi() {
          # fnm env --shell zsh
          export PATH="/Users/test/.local/share/fnm/node-versions/v24.21.0/installation/bin:$PATH"
        }
        """
        #expect(ProvisioningShellConfiguration.classifyExternalInitialization(text) == .none)
    }

    @Test("legacy and root-aware app blocks retain their canonical shape")
    func appOwnedBlockShapesRemainCanonical() {
        let legacy = ProvisioningShellConfiguration.makeManagedBlock(
            fnmPath: "/opt/homebrew/bin/fnm",
            nodeVersion: "24.21.0",
            fnmDirectoryURL: nil
        )
        let rootAware = ProvisioningShellConfiguration.makeManagedBlock(
            fnmPath: "/opt/homebrew/bin/fnm",
            nodeVersion: "24.21.0",
            fnmDirectoryURL: URL(fileURLWithPath: "/Users/test/.local/share/fnm", isDirectory: true)
        )
        #expect(ProvisioningShellConfiguration.isCanonicalManagedBlock(legacy))
        #expect(ProvisioningShellConfiguration.isCanonicalManagedBlock(rootAware))
    }

    @Test("indirection and shell wrappers remain unverified")
    func ambiguousSetupIsNotGreen() {
        for text in [
            "eval \"$($FNM_BIN env --shell zsh)\"\n",
            "source \"$FNM_BIN\"\n",
            "\"$FNM_BIN\" env --shell zsh\n",
            "source ~/.fnm.zsh\n",
            "if command -v fnm >/dev/null; then fnm env --shell zsh; fi\n",
            "if command -v fnm; then\neval \"$(fnm env --shell zsh)\"\nfi\n",
            "fnm_init() { eval \"$(fnm env --shell zsh)\"; }\n",
            "setup ()    {\n  eval \"$(fnm env --shell zsh)\"\n}\n",
            "setup()\n{\n  eval \"$(fnm env --shell zsh)\"\n}\n"
        ] {
            #expect(ProvisioningShellConfiguration.classifyExternalInitialization(text) == .unknown)
        }
    }
}
#endif
