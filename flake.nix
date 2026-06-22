{
  description = "Uniclient — unified multi-platform messaging client (Flutter + Go)";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
    android-nixpkgs = {
      url = "github:tadfisher/android-nixpkgs";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = { self, nixpkgs, flake-utils, android-nixpkgs }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = import nixpkgs {
          inherit system;
          config.allowUnfree = true;
          config.android_sdk.accept_license = true;
        };

        androidSdk = android-nixpkgs.sdk.${system} (sdkPkgs: with sdkPkgs; [
          cmdline-tools-latest
          platform-tools
          build-tools-34-0-0
          platforms-android-34
          ndk-26-1-10909125
          emulator
        ]);

        # Go shared lib output directory
        goLibDir = "./go/build";

        # Linux desktop build dependencies — shared by every dev shell.
        # These are everything Flutter's Linux desktop CMake build and the
        # native plugins (media_kit/libmpv, appindicator tray) link against.
        desktopDeps = with pkgs; [
          # Go (CGO is required: libcores.so is a c-shared lib) + C toolchain
          go
          gcc
          clang

          # Flutter & Dart
          flutter

          # Native build toolchain
          pkg-config
          cmake
          ninja

          # Linux desktop / GTK stack
          gtk3
          glib
          libepoxy
          libx11
          libxcb
          libxdmcp
          libGL
          pcre2
          util-linux
          libselinux
          libsepol
          libthai
          libdatrie
          libxkbcommon
          libayatana-appindicator
          dbus

          # media_kit (video/audio) needs libmpv
          mpv-unwrapped

          # Protobuf
          protobuf          # protoc compiler
          protoc-gen-go     # Go codegen plugin

          # Dev tools
          jq
          ripgrep
          libnotify  # notify-send for ralph.sh notifications
        ];

        # Shell hook shared by both shells; takes a flag for whether to wire
        # up the Android SDK env (only the full shell needs it).
        mkShellHook = { withAndroid }: ''
          # Default off (project invariant); scripts/build_go.sh sets =1 itself
          # for the c-shared libcores.so build, which is the one cgo exception.
          export CGO_ENABLED=0
          export GOLIB_DIR="${goLibDir}"
          export LD_LIBRARY_PATH="${goLibDir}:$LD_LIBRARY_PATH"
        '' + (if withAndroid then ''
          export ANDROID_HOME="${androidSdk}/share/android-sdk"
          export ANDROID_SDK_ROOT="$ANDROID_HOME"
        '' else "") + ''
          # Chrome for Flutter web dev
          if command -v chromium &> /dev/null; then
            export CHROME_EXECUTABLE="$(command -v chromium)"
          elif command -v google-chrome-stable &> /dev/null; then
            export CHROME_EXECUTABLE="$(command -v google-chrome-stable)"
          fi

          # Convenience aliases
          alias build-go="bash scripts/build_go.sh"
          alias test-go="cd go && go test ./... && cd .."
          alias test-dart="cd dart && flutter test && cd .."
          alias test-all="test-go && test-dart"

          echo "uniclient dev shell ready (${if withAndroid then "full / with Android" else "lean / Linux desktop only"})"
          echo "  go:      $(go version | cut -d' ' -f3)"
          echo "  flutter: $(flutter --version 2>/dev/null | head -1)"
          ${if withAndroid then ''echo "  android: $ANDROID_HOME"'' else ""}
          echo ""
          echo "Build: scripts/build_go.sh linux && scripts/build_flutter.sh linux release"
          echo "Commands: build-go | test-go | test-dart | test-all"
        '';

      in {
        devShells = {
          # Full shell: Linux desktop + Android (mobile) tooling.
          # First entry downloads the Android SDK/NDK/emulator (multi-GB).
          default = pkgs.mkShell {
            buildInputs = desktopDeps ++ [ androidSdk ];
            shellHook = mkShellHook { withAndroid = true; };
          };

          # Lean shell: Linux desktop build only — NO Android download.
          # Use this if you only care about the desktop app:  nix develop .#linux
          linux = pkgs.mkShell {
            buildInputs = desktopDeps;
            shellHook = mkShellHook { withAndroid = false; };
          };
        };
      }
    );
}
