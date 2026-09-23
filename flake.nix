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
        # Go 1.27: go.mod requires >= 1.27 and buildGoModule hardcodes
        # GOTOOLCHAIN="local", so nixpkgs' default Go 1.26 toolchain
        # (buildGoModule = buildGo126Module) can never build this. The 1.27
        # builder is buildGoLatestModule (all-packages.nix:
        # buildGo127Module = callPackage ../build-support/go/module.nix
        # { go = buildPackages.go_1_27; }).
        uniclient = pkgs.buildGoLatestModule {
          pname = "uniclient";
          version = "0.10.2";
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
          vendorHash = "sha256-pWVnXRcYeX1uZUMeQlfPv01qwSk7gQq99AM9kBzd5gc=";
          buildInputs = with pkgs; [
            libX11 libXcursor libXfixes
            libxkbcommon
            wayland
            mesa
            # gioui.org/internal/vk/vulkan_{x11,wayland}.go #include
            # <vulkan/vulkan.h> on every Linux build — without these headers
            # the build dies in gioui.org/internal/vk.
            vulkan-headers
            # gio's pkg-config line is `egl wayland-egl wayland-client
            # wayland-cursor x11 xkbcommon xkbcommon-x11 x11-xcb xcursor
            # xfixes`: x11-xcb.pc Requires: xcb, and egl.pc ships in libglvnd.
            libxcb
            libglvnd
          ];
          nativeBuildInputs = with pkgs; [ pkg-config ];
          # Gio's Linux GPU/X11 access is cgo, so cgo is mandatory (§4).
          # This MUST live under `env`: mkGoDerivation always writes
          # env.CGO_ENABLED itself (nixpkgs pkgs/build-support/go/module.nix:
          # `CGO_ENABLED = args.env.CGO_ENABLED or go.CGO_ENABLED`), and a
          # top-level CGO_ENABLED collides with it — `nix build` died with
          # "The `env` attribute set cannot contain any attributes passed to
          # derivation" and the owner's `nix run` was broken.
          env.CGO_ENABLED = 1;
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
            pkg-config
            libX11.dev libXcursor.dev libXfixes.dev
            libxkbcommon.dev
            # gio's pkg-config line asks for egl wayland-* x11 xkbcommon
            # xkbcommon-x11 x11-xcb xcursor xfixes — x11-xcb needs xcb.pc
            # (xkbcommon-x11.pc itself ships in libxkbcommon.dev above).
            libxcb
            libxcb-util
            libxcb-image
            libxcb-keysyms
            libxcb-wm
            wayland.dev
            # nixpkgs' mesa exposes no .dev output anymore; the EGL/GL/Vulkan
            # headers pkg-config needs live in libglvnd.dev.
            libglvnd.dev
            mesa
            # gioui.org/internal/vk #includes <vulkan/vulkan.h> on every build.
            vulkan-headers
            vulkan-loader
            upx
          ];
          shellHook = ''
            echo "Uniclient dev shell — cd go && make build, or make run"
          '';
        };
      });
}
