{
  description = "Uniclient — one pure-Go native messenger for every network";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = { self, nixpkgs, flake-utils }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = import nixpkgs { inherit system; };
        # Pure Go: no cgo, no system libraries — the tree is engine + cores
        # only (the GUI is parked for a from-scratch rebuild, AGENTS.md).
        # Go 1.27: go.mod requires >= 1.27 and buildGoModule hardcodes
        # GOTOOLCHAIN="local", so nixpkgs' default Go 1.26 toolchain
        # (buildGoModule = buildGo126Module) can never build this. The 1.27
        # builder is buildGoLatestModule (all-packages.nix:
        # buildGo127Module = callPackage ../build-support/go/module.nix
        # { go = buildPackages.go_1_27; }).
        uniclient = pkgs.buildGoLatestModule {
          pname = "uniclient";
          version = "0.10.3";
          # The Go module root is the go/ directory — but a store directory
          # unpacks under its own basename, and buildGoModule exports
          # GOPATH="$TMPDIR/go", so src=./go unpacked to /build/go == GOPATH.
          # Go then refused module mode ("ignoring go.mod in $GOPATH") and
          # every `nix build` died before compiling anything. Renaming the
          # store path keeps the module root intact and dodges the clash.
          src = builtins.path { path = ./go; name = "uniclient-src"; };
          subPackages = [ "cmd/uniclient" ];
          tags = [ "goolm" ];
          doCheck = false; # run `make test` in the dev shell
          # Reported by the first real build (the placeholder hash fails
          # the go-modules fixed-output derivation with the correct one).
          vendorHash = "sha256-F0u1N0VnU96e6GQjMlwtecdc3UAAjZImtdA5rsz1SLw=";
          # -trimpath belongs to `go build`, NOT to the linker: `go tool link`
          # dies with "flag provided but not defined: -trimpath". nixpkgs
          # already injects -trimpath through GOFLAGS (module.nix adds it when
          # allowGoReference is false), and it appends -buildid= itself.
          # This mirrors the Makefile's `STRIP := -trimpath -ldflags "-s -w"`.
          ldflags = [ "-s" "-w" ];
          meta = with pkgs.lib; {
            description = "One pure-Go native messenger for every network";
            homepage = "https://github.com/DarkReaperBoy/Uniclient";
            license = licenses.mit;
            mainProgram = "uniclient";
          };
        };
      in {
        packages.default = uniclient;
        packages.uniclient = uniclient;

        apps.default = {
          type = "app";
          program = "${uniclient}/bin/uniclient";
        };

        devShells.default = pkgs.mkShell {
          packages = with pkgs; [
            # 1.27 to match go.mod (see buildGoLatestModule above).
            go_1_27
            upx
          ];
          shellHook = ''
            echo "Uniclient dev shell — cd go && make build, or make run"
          '';
        };
      });
}
