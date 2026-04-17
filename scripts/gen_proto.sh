#!/usr/bin/env bash
set -euo pipefail

# Regenerate the protobuf bridge: proto files, Go types, dispatch code.
# Usage: ./scripts/gen_proto.sh
#
# Requires: protoc, protoc-gen-go (go install google.golang.org/protobuf/cmd/protoc-gen-go@latest)

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
GEN_DIR="$SCRIPT_DIR/gen_bridge"

# Ensure protoc-gen-go is available
export PATH="$PATH:$(go env GOPATH)/bin"

echo "=== Step 1: Build codegen tool ==="
cd "$GEN_DIR"
go build -o gen_bridge .

echo "=== Step 2: Generate .proto files ==="
./gen_bridge --proto

echo "=== Step 3: Run protoc (Go types) ==="
cd "$PROJECT_DIR"
protoc --proto_path=. \
  --go_out=go --go_opt=paths=source_relative \
  proto/cores/*.proto proto/models.proto proto/engine.proto

echo "=== Step 4: Generate dispatch code ==="
cd "$GEN_DIR"
./gen_bridge --dispatch

echo "=== Step 5: Verify build ==="
cd "$PROJECT_DIR/go"
go build -tags goolm ./bridge/...
go build -tags goolm ./cmd/bridge/

echo ""
echo "Done! Bridge generated successfully."
echo "  Proto files:  proto/cores/*.proto"
echo "  Go types:     go/proto/cores/*.pb.go"
echo "  Dispatch:     go/bridge/dispatch_gen.go"
echo "  FFI entry:    go/cmd/bridge/main.go"
