{
  description = "dumbpipe - pipe data over the network with NAT hole punching";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
    rust-overlay = {
      url = "github:oxalica/rust-overlay";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    crane.url = "github:ipetkov/crane";
  };

  outputs =
    {
      self,
      nixpkgs,
      flake-utils,
      rust-overlay,
      crane,
    }:
    flake-utils.lib.eachDefaultSystem (
      system:
      let
        pkgs = import nixpkgs {
          inherit system;
          overlays = [ (import rust-overlay) ];
        };

        # Toolchain pinned to the rust-version declared in Cargo.toml.
        rustToolchain = pkgs.rust-bin.stable."1.91.0".default;

        craneLib = (crane.mkLib pkgs).overrideToolchain rustToolchain;

        # Use mold as the linker for both the nix build and the devshell so the
        # two environments link identically.  `-fuse-ld=mold` makes cc invoke
        # `mold` (which we put on PATH) instead of the default bfd/gold linker.
        moldFlags = "-C link-arg=-fuse-ld=mold";

        commonArgs = {
          src = craneLib.cleanCargoSource ./.;
          strictDeps = true;

          nativeBuildInputs = [ pkgs.mold ];

          # Threaded from here into both cargoArtifacts and the crate build.
          CARGO_BUILD_RUSTFLAGS = moldFlags;
        };

        cargoArtifacts = craneLib.buildDepsOnly commonArgs;

        dumbpipe = craneLib.buildPackage (
          commonArgs
          // {
            inherit cargoArtifacts;
            doCheck = false;
          }
        );
      in
      {
        packages = {
          inherit dumbpipe;
          default = dumbpipe;
        };

        checks = {
          inherit dumbpipe;

          clippy = craneLib.cargoClippy (
            commonArgs
            // {
              inherit cargoArtifacts;
              cargoClippyExtraArgs = "--all-targets -- --deny warnings";
            }
          );

          fmt = craneLib.cargoFmt { src = commonArgs.src; };
        };

        apps.default = flake-utils.lib.mkApp { drv = dumbpipe; };

        devShells.default = craneLib.devShell {
          inputsFrom = [ dumbpipe ];

          packages = [
            pkgs.mold
            pkgs.rust-analyzer
          ];

          # Ensure `cargo build`/`cargo test` in the shell also link with mold.
          CARGO_BUILD_RUSTFLAGS = moldFlags;
        };
      }
    );
}
