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

      in {
        devShells.default = pkgs.mkShell {
          buildInputs = with pkgs; [
            # Go
            go
            gcc

            # Flutter & Dart
            flutter

            # Android SDK (no Android Studio)
            androidSdk

            # Linux desktop build deps (Flutter)
            gtk3
            pkg-config
            cmake
            ninja
            clang
            libepoxy
            libx11
            libGL
            pcre2
            util-linux
            libselinux
            libsepol
            libthai
            libdatrie
            libxkbcommon
            dbus

            # Protobuf
            protobuf          # protoc compiler
            protoc-gen-go     # Go codegen plugin

            # Dev tools
            jq
            ripgrep
          ];

          shellHook = ''
            export ANDROID_HOME="${androidSdk}/share/android-sdk"
            export ANDROID_SDK_ROOT="$ANDROID_HOME"
            export CGO_ENABLED=0
            export GOLIB_DIR="${goLibDir}"
            export LD_LIBRARY_PATH="${goLibDir}:$LD_LIBRARY_PATH"

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

            echo "uniclient dev shell ready"
            echo "  go:      $(go version | cut -d' ' -f3)"
            echo "  flutter: $(flutter --version 2>/dev/null | head -1)"
            echo "  android: $ANDROID_HOME"
            echo ""
            echo "Commands: build-go | test-go | test-dart | test-all"
          '';
        };
      }
    );
}
