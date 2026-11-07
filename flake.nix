# ==================================================================================================
# clean-gone Development Flake
# ==================================================================================================

{
  description = "clean-gone packages and development environment";

  nixConfig = {
    extra-substituters = [ "https://hakula.cachix.org" ];
    extra-trusted-public-keys = [
      "hakula.cachix.org-1:7zwB3fhMfReHdOjh6DmnaLXgqbPDBcojvN9F+osZw0k="
    ];
  };

  # ------------------------------------------------------------------------------------------------
  # Inputs
  # ------------------------------------------------------------------------------------------------
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-26.05";

    devkit = {
      url = "github:hakula139/devkit/v1.0.0-rc.3";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  # ------------------------------------------------------------------------------------------------
  # Outputs
  # ------------------------------------------------------------------------------------------------
  outputs =
    {
      nixpkgs,
      devkit,
      ...
    }:
    let
      inherit (nixpkgs) lib;

      mkCleanGone =
        pkgs:
        (devkit.lib.mkLib pkgs).mkNuApplication {
          pname = "clean-gone";
          version = "0.1.0";
          src = ./src;
          runtimeInputs = with pkgs; [
            coreutils
            git
            lsof
            openssh
          ];
          meta = {
            description = "Remove finished local Git branches and stale linked worktrees";
            homepage = "https://github.com/hakula139/clean-gone";
            license = lib.licenses.mit;
            platforms = lib.platforms.unix;
          };
        };
    in
    {
      overlays.default = final: _: { clean-gone = mkCleanGone final; };
    }
    // devkit.lib.eachSystem devkit.lib.systems (
      system:
      let
        pkgs = nixpkgs.legacyPackages.${system};
        dk = devkit.lib.mkLib pkgs;
        cleanGone = mkCleanGone pkgs;

        preCommit = dk.preCommit {
          src = ./.;
          hooks.nu-check.enable = true;
        };
      in
      {
        # ------------------------------------------------------------------------------------------
        # Dev Shell
        # ------------------------------------------------------------------------------------------
        devShells.default = pkgs.mkShell {
          name = "clean-gone-dev";
          packages = [
            dk.nushell
            dk.nu-test
            pkgs.git
            pkgs.git-cliff
          ];
          inputsFrom = [ preCommit.shell ];
        };

        # ------------------------------------------------------------------------------------------
        # Packages
        # ------------------------------------------------------------------------------------------
        packages = {
          default = cleanGone;
          clean-gone = cleanGone;
        };

        # ------------------------------------------------------------------------------------------
        # Checks
        # ------------------------------------------------------------------------------------------
        checks = {
          pre-commit = preCommit.check;
          package = cleanGone;
          tests = dk.nuTests {
            src = ./src;
            runtimeInputs = [ pkgs.git ];
          };
        };

        # ------------------------------------------------------------------------------------------
        # Formatter
        # ------------------------------------------------------------------------------------------
        formatter = pkgs.nixfmt-tree;
      }
    );
}
