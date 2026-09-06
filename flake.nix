{
  description = "Uniclient Go core — multi-platform messaging cores (Go only)";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
  };

  outputs = { self, nixpkgs }:
    nixpkgs.lib.eachDefaultSystem (system:
      let
        pkgs = import nixpkgs { inherit system; };

        goLibDir = "./go/build";

        shellHook = ''
          export CGO_ENABLED=0
          export GOLIB_DIR="${goLibDir}"
          export LD_LIBRARY_PATH="${goLibDir}:$LD_LIBRARY_PATH"

          # goolm = pure-Go Matrix E2EE (libolm C bindings are never used)
          export GOFLAGS=-tags=goolm

          # Convenience aliases
          alias build-go="bash scripts/build_go.sh"
          alias test-go="cd go && go test -tags goolm ./... && cd .."

          echo "uniclient Go core dev shell ready"
          echo "  go: $(go version | cut -d' ' -f3)"
          echo ""
          echo "Build shared lib: scripts/build_go.sh linux   -> go/build/libcores.so"
          echo "Run tests:        cd go && go test -tags goolm ./..."
        '';
      in {
        devShells.default = pkgs.mkShell {
          buildInputs = with pkgs; [
            go

            # C toolchain — needed only to LINK the c-shared libcores.so build
            # (external linking); all core code itself stays pure Go.
            gcc

            # Protobuf codegen (scripts/gen_proto.sh)
            protobuf          # protoc compiler
            protoc-gen-go     # Go codegen plugin

            # Dev tools
            jq
            ripgrep
          ];
          inherit shellHook;
        };
      }
    );
}
