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
        # cgo is required by Gio on Linux (X11/Wayland/EGL); everything links
        # against Nix libraries, so the binary is fully native on NixOS.
        uniclient = pkgs.buildGoModule {
          pname = "uniclient";
          version = "0.4.0";
          # The Go module root is the go/ directory.
          src = ./go;
          subPackages = [ "cmd/uniclient" ];
          tags = [ "goolm" ];
          doCheck = false; # run `make test` in the dev shell
          vendorHash = "sha256-AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA="; # placeholder — set after first build failure
          buildInputs = with pkgs; [
            libX11 libXcursor libXfixes
            libxkbcommon
            wayland
            mesa
          ];
          nativeBuildInputs = with pkgs; [ pkg-config ];
          CGO_ENABLED = 1;
          ldflags = [ "-s" "-w" "-trimpath" ];
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
            go
            pkg-config
            libX11.dev libXcursor.dev libXfixes.dev
            libxkbcommon.dev
            wayland.dev
            mesa.dev
            upx
          ];
          shellHook = ''
            echo "Uniclient dev shell — cd go && make build, or make run"
          '';
        };
      });
}
