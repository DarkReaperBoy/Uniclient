// gen_bridge — Parses Go AST of all core files and generates:
//   - Per-core .proto files with request/response messages for every exported method
//   - Go dispatch code (method name → function call)
//   - Dart typed wrapper classes
//
// Usage: go run ./scripts/gen_bridge [--dump] [--proto] [--dispatch] [--dart]
//   --dump: print extracted method signatures to stdout (default if no flags)
//   --proto: generate proto/cores/*.proto
//   --dispatch: generate go/bridge/dispatch_gen.go
//   --dart: generate dart/lib/bridge/cores/*_gen.dart
package main

import (
	"fmt"
	"go/ast"
	"go/parser"
	"go/token"
	"os"
	"path/filepath"
	"sort"
	"strings"
)

// CoreMethod represents a single exported method on a core struct.
type CoreMethod struct {
	ReceiverType string    // e.g. "TelegramCore"
	Name         string    // e.g. "SendMessage"
	Params       []Param   // input parameters (excluding receiver)
	Results      []Param   // return values
}

// Param represents a single function parameter or return value.
type Param struct {
	Name string // empty for unnamed returns
	Type string // Go type as string
}

// StructDef represents an exported struct type used in method signatures.
type StructDef struct {
	Name   string  // e.g. "RubikaFolderInfo"
	Fields []Param // struct fields (Name + Type)
}

// CoreInfo groups methods by core.
type CoreInfo struct {
	Name       string       // e.g. "telegram"
	StructName string       // e.g. "TelegramCore"
	Methods    []CoreMethod
	Structs    []StructDef  // exported structs (excluding the core struct itself)
}

// repoRoot finds the project root by looking for go/cores relative to CWD or script location.
var repoRoot string

func init() {
	// Try CWD first (if run from project root)
	if _, err := os.Stat("go/cores"); err == nil {
		repoRoot = "."
		return
	}
	// Try two levels up (if run from scripts/gen_bridge/)
	if _, err := os.Stat(filepath.Join("..", "..", "go", "cores")); err == nil {
		repoRoot = filepath.Join("..", "..")
		return
	}
	repoRoot = "."
}

func main() {
	mode := "dump"
	if len(os.Args) > 1 {
		mode = os.Args[1]
	}

	coresDir := filepath.Join(repoRoot, "go", "cores")

	cores, err := parseCores(coresDir)
	if err != nil {
		fmt.Fprintf(os.Stderr, "error parsing cores: %v\n", err)
		os.Exit(1)
	}

	switch mode {
	case "dump", "--dump":
		dumpMethods(cores)
	case "--proto":
		if err := generateProtos(cores); err != nil {
			fmt.Fprintf(os.Stderr, "error generating protos: %v\n", err)
			os.Exit(1)
		}
	case "--dispatch":
		if err := generateDispatch(cores); err != nil {
			fmt.Fprintf(os.Stderr, "error generating dispatch: %v\n", err)
			os.Exit(1)
		}
	default:
		dumpMethods(cores)
	}
}

// coreFiles maps file name → (core name, struct name)
var coreFiles = map[string][2]string{
	"telegram.go":  {"telegram", "TelegramCore"},
	"bale.go":      {"bale", "BaleCore"},
	"rubika.go":    {"rubika", "RubikaCore"},
	"matrix.go":    {"matrix", "MatrixCore"},
	"deltachat.go": {"deltachat", "DeltaChatCore"},
	"teamspeak.go": {"teamspeak", "TeamSpeakCore"},
	"mumble.go":    {"mumble", "MumbleCore"},
	"xmpp.go":      {"xmpp", "XMPPCore"},
	"irc.go":       {"irc", "IRCCore"},
	"github.go":    {"github", "GitHubCore"},
}

func parseCores(dir string) ([]CoreInfo, error) {
	fset := token.NewFileSet()
	var cores []CoreInfo

	for filename, info := range coreFiles {
		path := filepath.Join(dir, filename)
		if _, err := os.Stat(path); err != nil {
			continue
		}

		f, err := parser.ParseFile(fset, path, nil, 0)
		if err != nil {
			return nil, fmt.Errorf("parse %s: %w", filename, err)
		}

		coreName, structName := info[0], info[1]
		ci := CoreInfo{Name: coreName, StructName: structName}

		for _, decl := range f.Decls {
			fd, ok := decl.(*ast.FuncDecl)
			if !ok || fd.Recv == nil || len(fd.Recv.List) == 0 {
				continue
			}

			// Check receiver is our core struct (pointer receiver)
			recvType := exprString(fd.Recv.List[0].Type)
			if recvType != "*"+structName {
				continue
			}

			// Only exported methods
			if !fd.Name.IsExported() {
				continue
			}

			m := CoreMethod{
				ReceiverType: structName,
				Name:         fd.Name.Name,
			}

			// Parse parameters
			if fd.Type.Params != nil {
				for _, field := range fd.Type.Params.List {
					typeStr := exprString(field.Type)
					if len(field.Names) == 0 {
						m.Params = append(m.Params, Param{Type: typeStr})
					} else {
						for _, name := range field.Names {
							m.Params = append(m.Params, Param{Name: name.Name, Type: typeStr})
						}
					}
				}
			}

			// Parse results
			if fd.Type.Results != nil {
				for _, field := range fd.Type.Results.List {
					typeStr := exprString(field.Type)
					if len(field.Names) == 0 {
						m.Results = append(m.Results, Param{Type: typeStr})
					} else {
						for _, name := range field.Names {
							m.Results = append(m.Results, Param{Name: name.Name, Type: typeStr})
						}
					}
				}
			}

			ci.Methods = append(ci.Methods, m)
		}

		// Parse exported struct types (excluding the core struct itself)
		for _, decl := range f.Decls {
			gd, ok := decl.(*ast.GenDecl)
			if !ok || gd.Tok != token.TYPE {
				continue
			}
			for _, spec := range gd.Specs {
				ts, ok := spec.(*ast.TypeSpec)
				if !ok || !ts.Name.IsExported() {
					continue
				}
				if ts.Name.Name == structName {
					continue // skip the core struct itself
				}
				st, ok := ts.Type.(*ast.StructType)
				if !ok {
					continue
				}
				sd := StructDef{Name: ts.Name.Name}
				for _, field := range st.Fields.List {
					typeStr := exprString(field.Type)
					if len(field.Names) == 0 {
						// embedded field — skip for proto purposes
						continue
					}
					for _, name := range field.Names {
						if !name.IsExported() {
							continue
						}
						sd.Fields = append(sd.Fields, Param{Name: name.Name, Type: typeStr})
					}
				}
				if len(sd.Fields) > 0 {
					ci.Structs = append(ci.Structs, sd)
				}
			}
		}

		sort.Slice(ci.Methods, func(i, j int) bool {
			return ci.Methods[i].Name < ci.Methods[j].Name
		})
		sort.Slice(ci.Structs, func(i, j int) bool {
			return ci.Structs[i].Name < ci.Structs[j].Name
		})

		cores = append(cores, ci)
	}

	sort.Slice(cores, func(i, j int) bool {
		return cores[i].Name < cores[j].Name
	})

	return cores, nil
}

// exprString converts an AST expression to its string representation.
func exprString(expr ast.Expr) string {
	switch e := expr.(type) {
	case *ast.Ident:
		return e.Name
	case *ast.StarExpr:
		return "*" + exprString(e.X)
	case *ast.SelectorExpr:
		return exprString(e.X) + "." + e.Sel.Name
	case *ast.ArrayType:
		if e.Len == nil {
			return "[]" + exprString(e.Elt)
		}
		return "[" + exprString(e.Len) + "]" + exprString(e.Elt)
	case *ast.MapType:
		return "map[" + exprString(e.Key) + "]" + exprString(e.Value)
	case *ast.InterfaceType:
		return "interface{}"
	case *ast.Ellipsis:
		return "..." + exprString(e.Elt)
	case *ast.FuncType:
		return "func(" + fieldListString(e.Params) + ")"
	case *ast.ChanType:
		switch e.Dir {
		case ast.SEND:
			return "chan<- " + exprString(e.Value)
		case ast.RECV:
			return "<-chan " + exprString(e.Value)
		default:
			return "chan " + exprString(e.Value)
		}
	case *ast.BasicLit:
		return e.Value
	case *ast.StructType:
		return "struct{}"
	case *ast.ParenExpr:
		return "(" + exprString(e.X) + ")"
	default:
		return fmt.Sprintf("<%T>", expr)
	}
}

func fieldListString(fl *ast.FieldList) string {
	if fl == nil {
		return ""
	}
	var parts []string
	for _, f := range fl.List {
		typeStr := exprString(f.Type)
		if len(f.Names) == 0 {
			parts = append(parts, typeStr)
		} else {
			for range f.Names {
				parts = append(parts, typeStr)
			}
		}
	}
	return strings.Join(parts, ", ")
}

func dumpMethods(cores []CoreInfo) {
	total := 0
	for _, c := range cores {
		fmt.Printf("=== %s (%s) — %d methods ===\n", c.Name, c.StructName, len(c.Methods))
		for _, m := range c.Methods {
			fmt.Printf("  %s(%s)", m.Name, formatParams(m.Params))
			if len(m.Results) > 0 {
				fmt.Printf(" → (%s)", formatParams(m.Results))
			}
			fmt.Println()
		}
		total += len(c.Methods)
		fmt.Println()
	}
	fmt.Printf("Total: %d exported methods across %d cores\n", total, len(cores))
}

func formatParams(params []Param) string {
	var parts []string
	for _, p := range params {
		if p.Name != "" {
			parts = append(parts, p.Name+" "+p.Type)
		} else {
			parts = append(parts, p.Type)
		}
	}
	return strings.Join(parts, ", ")
}

// ═══════════════════════════════════════════════════════════════════════
// Proto generation (Step 13.3)
// ═══════════════════════════════════════════════════════════════════════

func generateProtos(cores []CoreInfo) error {
	outDir := filepath.Join(repoRoot, "proto", "cores")
	if err := os.MkdirAll(outDir, 0o755); err != nil {
		return err
	}

	for _, c := range cores {
		if err := generateCoreProto(c, outDir); err != nil {
			return fmt.Errorf("%s: %w", c.Name, err)
		}
	}
	fmt.Printf("Generated %d proto files in %s\n", len(cores), outDir)
	return nil
}

func generateCoreProto(c CoreInfo, outDir string) error {
	var b strings.Builder

	b.WriteString(fmt.Sprintf(`syntax = "proto3";

package uniclient.%s;

option go_package = "uniclient/proto/cores";

import "proto/models.proto";

`, c.Name))

	// Emit core-specific struct definitions first
	if len(c.Structs) > 0 {
		b.WriteString("// ═══════════════════════════════════════════════════════════════════\n")
		b.WriteString("// Core-specific types\n")
		b.WriteString("// ═══════════════════════════════════════════════════════════════════\n\n")
		for _, sd := range c.Structs {
			writeStructProto(&b, sd)
		}
		b.WriteString("// ═══════════════════════════════════════════════════════════════════\n")
		b.WriteString("// RPC request/response messages\n")
		b.WriteString("// ═══════════════════════════════════════════════════════════════════\n\n")
	}

	for _, m := range c.Methods {
		writeMethodProto(&b, c, m)
	}

	path := filepath.Join(outDir, c.Name+".proto")
	return os.WriteFile(path, []byte(b.String()), 0o644)
}

// goTypeToProto maps a Go type string to a proto type + whether it needs import.
func goTypeToProto(goType string) (protoType string, isMessage bool) {
	// Strip pointer
	goType = strings.TrimPrefix(goType, "*")

	switch goType {
	case "string":
		return "string", false
	case "bool":
		return "bool", false
	case "int", "int64":
		return "int64", false
	case "int32":
		return "int32", false
	case "uint32":
		return "uint32", false
	case "uint64":
		return "uint64", false
	case "float32":
		return "float", false
	case "float64":
		return "double", false
	case "byte":
		return "int32", false // single byte as int
	case "*bool":
		return "bool", false // nullable bool as regular bool in proto
	case "error":
		return "", false // errors as returns handled by BridgeResponse; as params → skipped for now
	case "[]byte":
		return "bytes", false
	case "[]string":
		return "repeated string", false
	case "[]int":
		return "repeated int64", false
	case "[]int64":
		return "repeated int64", false
	case "[]uint32":
		return "repeated uint32", false
	case "[]float32":
		return "repeated float", false
	case "[3]float32":
		return "repeated float", false // length 3
	case "[]int16":
		return "bytes", false // PCM audio data
	case "[]uint16":
		return "bytes", false
	case "[][]byte":
		return "repeated bytes", false
	case "time.Time":
		return "int64", false // unix millis
	case "time.Duration":
		return "int64", false // nanoseconds

	// base.go shared types → use models.proto
	case "Message":
		return "uniclient.Message", true
	case "OutgoingMessage":
		return "uniclient.OutgoingMessage", true
	case "Dialog":
		return "uniclient.Dialog", true
	case "User":
		return "uniclient.User", true
	case "Folder":
		return "uniclient.Folder", true
	case "Session":
		return "uniclient.Session", true
	case "CallSession":
		return "uniclient.CallSession", true
	case "ReadState":
		return "uniclient.ReadState", true
	case "FileRef":
		return "uniclient.FileRef", true
	case "FileUpload":
		return "uniclient.FileUploadRequest", true
	case "AuthConfig":
		return "uniclient.AuthConfig", true
	case "PaginationOpts":
		return "uniclient.PaginationOpts", true
	case "Update":
		return "uniclient.Update", true
	case "VerificationInfo":
		return "uniclient.VerificationInfo", true
	case "ChatType":
		return "uniclient.ChatType", true
	case "CallState":
		return "uniclient.CallState", true

	// Slices of shared types (both value and pointer slices)
	case "[]Message", "[]*Message":
		return "repeated uniclient.Message", true
	case "[]Dialog":
		return "repeated uniclient.Dialog", true
	case "[]User":
		return "repeated uniclient.User", true
	case "[]Folder":
		return "repeated uniclient.Folder", true
	case "[]Session":
		return "repeated uniclient.Session", true
	case "[]FileRef":
		return "repeated uniclient.FileRef", true
	case "[]Reaction":
		return "repeated uniclient.Reaction", true

	// Generic map types
	case "map[string]string":
		return "map<string, string>", false
	case "map[string]bool":
		return "map<string, bool>", false
	case "map[string]interface{}", "map[string]any":
		return "bytes", false // JSON blob
	case "map[string]map[string]interface{}":
		return "bytes", false // nested JSON blob
	case "map[int]string", "map[string][]string", "map[string]map[string]string",
		"map[int]map[string]string", "map[string]int",
		"map[string]map[string]map[string]interface{}":
		return "bytes", false // complex map → JSON blob
	case "json.RawMessage":
		return "bytes", false
	case "[]json.RawMessage":
		return "bytes", false
	case "[]interface{}", "[]any":
		return "bytes", false
	case "[][]map[string]string":
		return "bytes", false // nested complex type
	case "map[string]json.RawMessage":
		return "bytes", false
	case "[]map[string]int64":
		return "bytes", false

	// Callbacks and channels → not in proto (handled by event port)
	default:
		if strings.HasPrefix(goType, "func(") {
			return "", false // skip
		}
		if strings.HasPrefix(goType, "<-chan") || strings.HasPrefix(goType, "chan ") {
			return "", false // skip
		}
		if strings.HasPrefix(goType, "[]map[string]") {
			return "bytes", false // JSON array blob
		}
		if strings.HasPrefix(goType, "[]") {
			inner := strings.TrimPrefix(goType, "[]")
			innerProto, _ := goTypeToProto(inner)
			if innerProto == "bytes" && inner != "[]byte" {
				// Slice of external types → single JSON blob, not repeated bytes
				// But [][]byte is legitimately repeated bytes
				return "bytes", false
			}
			if innerProto != "" {
				return "repeated " + innerProto, true
			}
			return "bytes", false
		}
		if strings.HasPrefix(goType, "map[") {
			return "bytes", false // arbitrary maps → JSON blob
		}
		// Variadic
		if strings.HasPrefix(goType, "...") {
			inner := strings.TrimPrefix(goType, "...")
			innerProto, _ := goTypeToProto(inner)
			if innerProto != "" {
				return "repeated " + innerProto, false
			}
			return "bytes", false
		}
		// External types (tg.*, id.*, etc.)
		if strings.Contains(goType, ".") {
			// Most mautrix id types are string typedefs
			if strings.HasPrefix(goType, "id.") {
				return "string", false
			}
			return "bytes", false
		}
		// Core-specific exported types → inline message (will be defined in the same proto)
		if len(goType) > 0 && goType[0] >= 'A' && goType[0] <= 'Z' {
			return goType, true
		}
		return "bytes", false
	}
}

func writeStructProto(b *strings.Builder, sd StructDef) {
	b.WriteString(fmt.Sprintf("message %s {\n", sd.Name))
	for i, f := range sd.Fields {
		protoType, _ := goTypeToProto(f.Type)
		if protoType == "" {
			protoType = "bytes" // fallback for unrecognized types
		}
		name := toSnakeCase(f.Name)
		b.WriteString(fmt.Sprintf("  %s %s = %d;\n", protoType, name, i+1))
	}
	b.WriteString("}\n\n")
}

func writeMethodProto(b *strings.Builder, c CoreInfo, m CoreMethod) {
	// Skip callback registration methods (OnUpdate, OnVoice, Handle*, etc.)
	if isCallbackMethod(m) {
		return
	}

	prefix := capitalize(c.Name)
	reqName := prefix + m.Name + "Request"
	respName := prefix + m.Name + "Response"

	// Request message
	b.WriteString(fmt.Sprintf("message %s {\n", reqName))
	fieldNum := 1
	for _, p := range m.Params {
		protoType, _ := goTypeToProto(p.Type)
		if protoType == "" {
			continue // skip callbacks, channels
		}
		name := toSnakeCase(p.Name)
		if name == "" || name == "_" {
			name = fmt.Sprintf("param_%d", fieldNum)
		}
		// Handle "repeated" prefix
		if strings.HasPrefix(protoType, "repeated ") {
			b.WriteString(fmt.Sprintf("  %s %s = %d;\n", protoType, name, fieldNum))
		} else {
			b.WriteString(fmt.Sprintf("  %s %s = %d;\n", protoType, name, fieldNum))
		}
		fieldNum++
	}
	b.WriteString("}\n\n")

	// Response message
	b.WriteString(fmt.Sprintf("message %s {\n", respName))
	fieldNum = 1
	for _, r := range m.Results {
		if r.Type == "error" {
			continue // errors go in BridgeResponse.error
		}
		protoType, _ := goTypeToProto(r.Type)
		if protoType == "" {
			continue
		}
		name := toSnakeCase(r.Name)
		if name == "" {
			name = fmt.Sprintf("result_%d", fieldNum)
		}
		b.WriteString(fmt.Sprintf("  %s %s = %d;\n", protoType, name, fieldNum))
		fieldNum++
	}
	b.WriteString("}\n\n")
}

func isCallbackMethod(m CoreMethod) bool {
	// Methods that register callbacks (take func(...) params and return nothing useful)
	for _, p := range m.Params {
		if strings.HasPrefix(p.Type, "func(") {
			return true
		}
	}
	return false
}

func capitalize(s string) string {
	if s == "" {
		return ""
	}
	return strings.ToUpper(s[:1]) + s[1:]
}

func toSnakeCase(s string) string {
	if s == "" {
		return ""
	}
	var result strings.Builder
	for i, r := range s {
		if r >= 'A' && r <= 'Z' {
			if i > 0 {
				result.WriteByte('_')
			}
			result.WriteRune(r + 32) // lowercase
		} else {
			result.WriteRune(r)
		}
	}
	// Fix common abbreviation patterns (longest first to avoid partial matches)
	out := result.String()
	out = strings.ReplaceAll(out, "g_u_i_d", "guid")
	out = strings.ReplaceAll(out, "u_r_l", "url")
	out = strings.ReplaceAll(out, "u_r_i", "uri")
	out = strings.ReplaceAll(out, "t_t_l", "ttl")
	out = strings.ReplaceAll(out, "s_d_p", "sdp")
	out = strings.ReplaceAll(out, "r_t_p", "rtp")
	out = strings.ReplaceAll(out, "i_d", "id")
	out = strings.ReplaceAll(out, "i_p", "ip")
	out = strings.ReplaceAll(out, "d_c_", "dc_")
	return out
}

// ═══════════════════════════════════════════════════════════════════════
// Go dispatch generation (Step 13.5)
// ═══════════════════════════════════════════════════════════════════════

func generateDispatch(allCores []CoreInfo) error {
	outDir := filepath.Join(repoRoot, "go", "bridge")
	if err := os.MkdirAll(outDir, 0o755); err != nil {
		return err
	}

	// ── dispatch_gen.go ─────────────────────────────────────────────
	// (convert.go is hand-written — see go/bridge/convert.go)
	if err := generateDispatchFile(allCores, outDir); err != nil {
		return fmt.Errorf("dispatch: %w", err)
	}

	return nil
}

// NOTE: Converter generation (Step 13.4) is hand-written in go/bridge/convert.go
// because Go↔Proto field mappings involve time.Time, string-enums, *bool, etc.

// goFieldToProtoField maps a Go struct field name to the corresponding protoc-gen-go field name.
// protoc-gen-go converts snake_case proto fields to PascalCase Go fields.
func goFieldToProtoField(goName string) string {
	// The proto field name is toSnakeCase(goName), and protoc-gen-go converts
	// that back to PascalCase. For most fields they round-trip to the same name.
	// But abbreviations like ID, URL, etc. may differ.
	// For now, use the Go name directly since the proto was generated from Go.
	return goName
}


func _writeSharedConverters_removed(b *strings.Builder) {
	b.WriteString("// ═══════════════════════════════════════════════════════════════════\n")
	b.WriteString("// Shared type converters (cores ↔ proto)\n")
	b.WriteString("// ═══════════════════════════════════════════════════════════════════\n\n")

	// User
	b.WriteString(`func UserToProto(u *cores.User) *pb.User {
	if u == nil { return nil }
	return &pb.User{
		Id: u.ID, Username: u.Username, DisplayName: u.DisplayName,
		Phone: u.Phone, AvatarUrl: u.AvatarURL, AvatarB64: u.AvatarB64,
		IsBot: u.IsBot, IsOnline: u.IsOnline, LastSeenMs: u.LastSeenMS,
		Platform: u.Platform,
	}
}

func ProtoToUser(u *pb.User) *cores.User {
	if u == nil { return nil }
	return &cores.User{
		ID: u.Id, Username: u.Username, DisplayName: u.DisplayName,
		Phone: u.Phone, AvatarURL: u.AvatarUrl, AvatarB64: u.AvatarB64,
		IsBot: u.IsBot, IsOnline: u.IsOnline, LastSeenMS: u.LastSeenMs,
		Platform: u.Platform,
	}
}

`)

	// FileRef
	b.WriteString(`func FileRefToProto(f *cores.FileRef) *pb.FileRef {
	if f == nil { return nil }
	return &pb.FileRef{
		Id: f.ID, Name: f.Name, MimeType: f.MimeType,
		Size: f.Size, Url: f.URL, ThumbB64: f.ThumbB64, Extra: f.Extra,
	}
}

func ProtoToFileRef(f *pb.FileRef) *cores.FileRef {
	if f == nil { return nil }
	return &cores.FileRef{
		ID: f.Id, Name: f.Name, MimeType: f.MimeType,
		Size: f.Size, URL: f.Url, ThumbB64: f.ThumbB64, Extra: f.Extra,
	}
}

func FileRefsToProto(fs []cores.FileRef) []*pb.FileRef {
	out := make([]*pb.FileRef, len(fs))
	for i := range fs { out[i] = FileRefToProto(&fs[i]) }
	return out
}

func ProtoToFileRefs(fs []*pb.FileRef) []cores.FileRef {
	out := make([]cores.FileRef, len(fs))
	for i := range fs {
		if fs[i] != nil { out[i] = *ProtoToFileRef(fs[i]) }
	}
	return out
}

`)

	// Reaction
	b.WriteString(`func ReactionToProto(r *cores.Reaction) *pb.Reaction {
	if r == nil { return nil }
	return &pb.Reaction{Emoji: r.Emoji, Count: int32(r.Count), ByMe: r.ByMe, PeerId: r.PeerID, PeerName: r.PeerName}
}

func ReactionsToProto(rs []cores.Reaction) []*pb.Reaction {
	out := make([]*pb.Reaction, len(rs))
	for i := range rs { out[i] = ReactionToProto(&rs[i]) }
	return out
}

`)

	// Message
	b.WriteString(`func MessageToProto(m *cores.Message) *pb.Message {
	if m == nil { return nil }
	extra, _ := json.Marshal(m.ExtraJSON)
	return &pb.Message{
		Id: m.ID, ChatId: m.ChatID, SenderId: m.SenderID,
		SenderName: m.SenderName, Text: m.Text,
		TimestampMs: m.TimestampMS, EditedAtMs: m.EditedAtMS,
		Status: pb.MessageStatus(m.Status),
		ReplyToId: m.ReplyToID, ReplyPreview: m.ReplyPreview,
		ForwardFrom: m.ForwardFrom, IsEncrypted: m.IsEncrypted,
		DecryptFailed: m.DecryptFailed,
		Attachments: FileRefsToProto(m.Attachments),
		Reactions: ReactionsToProto(m.Reactions),
		IsPinned: m.IsPinned, Platform: m.Platform,
		ExtraJson: extra,
	}
}

func ProtoToMessage(m *pb.Message) *cores.Message {
	if m == nil { return nil }
	msg := &cores.Message{
		ID: m.Id, ChatID: m.ChatId, SenderID: m.SenderId,
		SenderName: m.SenderName, Text: m.Text,
		TimestampMS: m.TimestampMs, EditedAtMS: m.EditedAtMs,
		Status: cores.MessageStatus(m.Status),
		ReplyToID: m.ReplyToId, ReplyPreview: m.ReplyPreview,
		ForwardFrom: m.ForwardFrom, IsEncrypted: m.IsEncrypted,
		DecryptFailed: m.DecryptFailed,
		Attachments: ProtoToFileRefs(m.Attachments),
		IsPinned: m.IsPinned, Platform: m.Platform,
	}
	if len(m.ExtraJson) > 0 {
		_ = json.Unmarshal(m.ExtraJson, &msg.ExtraJSON)
	}
	return msg
}

func MessagesToProto(ms []cores.Message) []*pb.Message {
	out := make([]*pb.Message, len(ms))
	for i := range ms { out[i] = MessageToProto(&ms[i]) }
	return out
}

`)

	// OutgoingMessage
	b.WriteString(`func ProtoToOutgoingMessage(m *pb.OutgoingMessage) *cores.OutgoingMessage {
	if m == nil { return nil }
	om := &cores.OutgoingMessage{
		Text: m.Text, ReplyToID: m.ReplyToId,
		Attachments: ProtoToFileRefs(m.Attachments),
	}
	if len(m.ExtraJson) > 0 {
		_ = json.Unmarshal(m.ExtraJson, &om.ExtraJSON)
	}
	return om
}

`)

	// Dialog
	b.WriteString(`func DialogToProto(d *cores.Dialog) *pb.Dialog {
	if d == nil { return nil }
	return &pb.Dialog{
		Id: d.ID, Type: pb.ChatType(d.Type), Title: d.Title,
		AvatarUrl: d.AvatarURL, AvatarB64: d.AvatarB64,
		LastMessage: MessageToProto(d.LastMessage),
		UnreadCount: int32(d.UnreadCount), IsMuted: d.IsMuted,
		IsPinned: d.IsPinned, IsArchived: d.IsArchived,
		MemberCount: int32(d.MemberCount), ParentId: d.ParentID,
		Platform: d.Platform,
	}
}

func DialogsToProto(ds []cores.Dialog) []*pb.Dialog {
	out := make([]*pb.Dialog, len(ds))
	for i := range ds { out[i] = DialogToProto(&ds[i]) }
	return out
}

`)

	// Folder
	b.WriteString(`func FolderToProto(f *cores.Folder) *pb.Folder {
	if f == nil { return nil }
	return &pb.Folder{Id: f.ID, Name: f.Name, ChatIds: f.ChatIDs}
}

func FoldersToProto(fs []cores.Folder) []*pb.Folder {
	out := make([]*pb.Folder, len(fs))
	for i := range fs { out[i] = FolderToProto(&fs[i]) }
	return out
}

func ProtoToFolder(f *pb.Folder) *cores.Folder {
	if f == nil { return nil }
	return &cores.Folder{ID: f.Id, Name: f.Name, ChatIDs: f.ChatIds}
}

`)

	// Session
	b.WriteString(`func SessionToProto(s *cores.Session) *pb.Session {
	if s == nil { return nil }
	return &pb.Session{
		Id: s.ID, Device: s.Device, Platform: s.Platform,
		AppName: s.AppName, AppVersion: s.AppVersion,
		Ip: s.IP, Location: s.Location,
		LastActiveMs: s.LastActiveMS, IsCurrent: s.IsCurrent,
	}
}

func SessionsToProto(ss []cores.Session) []*pb.Session {
	out := make([]*pb.Session, len(ss))
	for i := range ss { out[i] = SessionToProto(&ss[i]) }
	return out
}

`)

	// CallSession
	b.WriteString(`func CallSessionToProto(c *cores.CallSession) *pb.CallSession {
	if c == nil { return nil }
	parts := make([]*pb.CallParticipant, len(c.Participants))
	for i, p := range c.Participants {
		parts[i] = &pb.CallParticipant{
			UserId: p.UserID, DisplayName: p.DisplayName,
			IsMuted: p.IsMuted, IsSpeaking: p.IsSpeaking, HasVideo: p.HasVideo,
		}
	}
	return &pb.CallSession{
		Id: c.ID, ChatId: c.ChatID, IsVideo: c.IsVideo, IsGroup: c.IsGroup,
		Participants: parts, State: pb.CallState(c.State), Meta: c.Meta,
	}
}

`)

	// ReadState
	b.WriteString(`func ReadStateToProto(r *cores.ReadState) *pb.ReadState {
	if r == nil { return nil }
	return &pb.ReadState{MyLastRead: r.MyLastRead, PeerLastRead: r.PeerLastRead}
}

`)

	// AuthConfig
	b.WriteString(`func ProtoToAuthConfig(a *pb.AuthConfig) cores.AuthConfig {
	if a == nil { return cores.AuthConfig{} }
	return cores.AuthConfig{
		Mode: cores.AuthMode(a.Mode), BotToken: a.BotToken,
		Phone: a.Phone, OTP: a.Otp, Password2F: a.Password_2F,
		Extra: a.Extra,
	}
}

`)

	// PaginationOpts
	b.WriteString(`func ProtoToPaginationOpts(p *pb.PaginationOpts) cores.PaginationOpts {
	if p == nil { return cores.PaginationOpts{} }
	return cores.PaginationOpts{Limit: int(p.Limit), Offset: p.Offset}
}

`)

	// VerificationInfo
	b.WriteString(`func VerificationInfoToProto(v *cores.VerificationInfo) *pb.VerificationInfo {
	if v == nil { return nil }
	decimals := make([]int32, len(v.Decimals))
	for i, d := range v.Decimals { decimals[i] = int32(d) }
	return &pb.VerificationInfo{
		TransactionId: v.TransactionID, State: v.State,
		FromUser: v.FromUser, FromDevice: v.FromDevice,
		Emojis: v.Emojis, EmojiSymbols: v.EmojiSymbols,
		Decimals: decimals,
		CancelCode: v.CancelCode, CancelReason: v.CancelReason,
	}
}

`)

	// Update
	b.WriteString(`func UpdateToProto(u *cores.Update) *pb.Update {
	if u == nil { return nil }
	return &pb.Update{
		Type: pb.UpdateType(u.Type), ChatId: u.ChatID,
		Message: MessageToProto(u.Message), MessageId: u.MessageID,
		UserId: u.UserID, ReadState: ReadStateToProto(u.ReadState),
		Call: CallSessionToProto(u.Call),
		IsOnline: u.IsOnline, HasIsOnline: u.HasIsOnline,
		Verification: VerificationInfoToProto(u.Verification),
		ConnState: u.ConnState, Platform: u.Platform,
	}
}

`)

	// mapToBytes / bytesToMap helpers for untyped methods
	b.WriteString(`func mapToBytes(m map[string]interface{}) []byte {
	if m == nil { return nil }
	b, _ := json.Marshal(m)
	return b
}

func bytesToMap(data []byte) map[string]interface{} {
	if len(data) == 0 { return nil }
	var m map[string]interface{}
	_ = json.Unmarshal(data, &m)
	return m
}

func mapStringToBytes(m map[string]string) []byte {
	if m == nil { return nil }
	b, _ := json.Marshal(m)
	return b
}

func bytesToMapString(data []byte) map[string]string {
	if len(data) == 0 { return nil }
	var m map[string]string
	_ = json.Unmarshal(data, &m)
	return m
}

func sliceMapToBytes(ms []map[string]interface{}) []byte {
	if ms == nil { return nil }
	b, _ := json.Marshal(ms)
	return b
}

func anyToBytes(v interface{}) []byte {
	if v == nil { return nil }
	b, _ := json.Marshal(v)
	return b
}

`)
}

// writeCoreStructConverters generates To/From proto converters for a core-specific struct.
func writeCoreStructConverters(b *strings.Builder, c CoreInfo, sd StructDef) {
	goType := fmt.Sprintf("cores.%s", sd.Name)
	protoType := fmt.Sprintf("pbcores.%s", sd.Name)

	// ToProto
	b.WriteString(fmt.Sprintf("func %sToProto(v *%s) *%s {\n", sd.Name, goType, protoType))
	b.WriteString("\tif v == nil { return nil }\n")
	b.WriteString(fmt.Sprintf("\treturn &%s{\n", protoType))
	for _, f := range sd.Fields {
		protoField := goFieldToProtoField(f.Name)
		goField := f.Name
		b.WriteString(fmt.Sprintf("\t\t%s: v.%s,\n", protoField, goField))
	}
	b.WriteString("\t}\n}\n\n")

	// FromProto
	b.WriteString(fmt.Sprintf("func ProtoTo%s(v *%s) *%s {\n", sd.Name, protoType, goType))
	b.WriteString("\tif v == nil { return nil }\n")
	b.WriteString(fmt.Sprintf("\treturn &%s{\n", goType))
	for _, f := range sd.Fields {
		protoField := goFieldToProtoField(f.Name)
		goField := f.Name
		b.WriteString(fmt.Sprintf("\t\t%s: v.%s,\n", goField, protoField))
	}
	b.WriteString("\t}\n}\n\n")
}

// ═══════════════════════════════════════════════════════════════════════
// Dispatch generation (Step 13.5)
// ═══════════════════════════════════════════════════════════════════════

func generateDispatchFile(allCores []CoreInfo, outDir string) error {
	var b strings.Builder
	b.WriteString("// Code generated by gen_bridge. DO NOT EDIT.\n")
	b.WriteString("package bridge\n\n")
	b.WriteString("import (\n")
	b.WriteString("\t\"bytes\"\n")
	b.WriteString("\t\"encoding/json\"\n")
	b.WriteString("\t\"fmt\"\n")
	b.WriteString("\t\"time\"\n\n")
	b.WriteString("\t\"google.golang.org/protobuf/proto\"\n\n")
	b.WriteString("\tpbcores \"uniclient/proto/cores\"\n")
	b.WriteString("\t\"uniclient/cores\"\n\n")
	b.WriteString("\t\"maunium.net/go/mautrix/id\"\n")
	b.WriteString(")\n\n")
	b.WriteString("var _ = bytes.NewReader // ensure import\n")
	b.WriteString("var _ time.Duration // ensure import\n\n")

	// Core type enum
	b.WriteString("// Dispatch routes a method call to the appropriate core method.\n")
	b.WriteString("// coreType is the core name (e.g. \"telegram\"), method is the Go method name.\n")
	b.WriteString("// payload is the serialized request proto, returns serialized response proto.\n")
	b.WriteString("func Dispatch(core interface{}, coreType string, method string, payload []byte) ([]byte, error) {\n")
	b.WriteString("\tswitch coreType {\n")
	for _, c := range allCores {
		b.WriteString(fmt.Sprintf("\tcase %q:\n", c.Name))
		b.WriteString(fmt.Sprintf("\t\tc, ok := core.(*cores.%s)\n", c.StructName))
		b.WriteString(fmt.Sprintf("\t\tif !ok { return nil, fmt.Errorf(\"invalid core type for %s\") }\n", c.Name))
		b.WriteString(fmt.Sprintf("\t\treturn dispatch%s(c, method, payload)\n", capitalize(c.Name)))
	}
	b.WriteString("\tdefault:\n")
	b.WriteString("\t\treturn nil, fmt.Errorf(\"unknown core type: %s\", coreType)\n")
	b.WriteString("\t}\n}\n\n")

	// Generate core-specific struct converters (JSON round-trip via goToProtoJSON)
	coreTypes := collectCoreSpecificReturnTypes(allCores)
	if len(coreTypes) > 0 {
		b.WriteString("// ═══════════════════════════════════════════════════════════════════\n")
		b.WriteString("// Core-specific type converters (JSON round-trip)\n")
		b.WriteString("// ═══════════════════════════════════════════════════════════════════\n\n")
		for _, ct := range coreTypes {
			// Single value converter
			b.WriteString(fmt.Sprintf("func coreToProto_%s(v cores.%s) *pbcores.%s {\n", ct, ct, ct))
			b.WriteString(fmt.Sprintf("\tout := &pbcores.%s{}\n", ct))
			b.WriteString("\t_ = goToProtoJSON(v, out)\n")
			b.WriteString("\treturn out\n")
			b.WriteString("}\n\n")

			// Pointer converter
			b.WriteString(fmt.Sprintf("func coreToProto_%s_ptr(v *cores.%s) *pbcores.%s {\n", ct, ct, ct))
			b.WriteString("\tif v == nil { return nil }\n")
			b.WriteString(fmt.Sprintf("\treturn coreToProto_%s(*v)\n", ct))
			b.WriteString("}\n\n")

			// Slice converter (value slice)
			b.WriteString(fmt.Sprintf("func coreSliceToProto_%s(vs []cores.%s) []*pbcores.%s {\n", ct, ct, ct))
			b.WriteString(fmt.Sprintf("\tout := make([]*pbcores.%s, len(vs))\n", ct))
			b.WriteString(fmt.Sprintf("\tfor i := range vs { out[i] = coreToProto_%s(vs[i]) }\n", ct))
			b.WriteString("\treturn out\n")
			b.WriteString("}\n\n")

			// Slice converter (pointer slice)
			b.WriteString(fmt.Sprintf("func corePtrSliceToProto_%s(vs []*cores.%s) []*pbcores.%s {\n", ct, ct, ct))
			b.WriteString(fmt.Sprintf("\tout := make([]*pbcores.%s, len(vs))\n", ct))
			b.WriteString(fmt.Sprintf("\tfor i := range vs { out[i] = coreToProto_%s_ptr(vs[i]) }\n", ct))
			b.WriteString("\treturn out\n")
			b.WriteString("}\n\n")

			// Proto → Core value converter
			b.WriteString(fmt.Sprintf("func protoToCore_%s(v *pbcores.%s) cores.%s {\n", ct, ct, ct))
			b.WriteString(fmt.Sprintf("\tout := cores.%s{}\n", ct))
			b.WriteString("\t_ = protoToGoJSON(v, &out)\n")
			b.WriteString("\treturn out\n")
			b.WriteString("}\n\n")

			// Proto → Core pointer converter
			b.WriteString(fmt.Sprintf("func protoToCorePtr_%s(v *pbcores.%s) *cores.%s {\n", ct, ct, ct))
			b.WriteString("\tif v == nil { return nil }\n")
			b.WriteString(fmt.Sprintf("\tout := protoToCore_%s(v)\n", ct))
			b.WriteString("\treturn &out\n")
			b.WriteString("}\n\n")

			// Proto slice → Core slice converter
			b.WriteString(fmt.Sprintf("func protoSliceToCore_%s(vs []*pbcores.%s) []cores.%s {\n", ct, ct, ct))
			b.WriteString(fmt.Sprintf("\tout := make([]cores.%s, len(vs))\n", ct))
			b.WriteString(fmt.Sprintf("\tfor i := range vs { out[i] = protoToCore_%s(vs[i]) }\n", ct))
			b.WriteString("\treturn out\n")
			b.WriteString("}\n\n")
		}
	}

	// Per-core dispatch functions
	for _, c := range allCores {
		writeCoreDipatch(&b, c)
	}

	path := filepath.Join(outDir, "dispatch_gen.go")
	return os.WriteFile(path, []byte(b.String()), 0o644)
}

// collectCoreSpecificReturnTypes finds all core-specific struct types used in method params and returns.
func collectCoreSpecificReturnTypes(allCores []CoreInfo) []string {
	seen := make(map[string]bool)
	var result []string

	// Base types that have hand-written converters
	baseTypes := map[string]bool{
		"Message": true, "Dialog": true, "User": true, "Folder": true,
		"Session": true, "CallSession": true, "ReadState": true,
		"VerificationInfo": true, "FileRef": true, "Reaction": true,
		"Update": true, "OutgoingMessage": true, "AuthConfig": true,
		"PaginationOpts": true, "CallParticipant": true,
		"FileUpload": true, "ChatType": true, "CallState": true,
	}

	addType := func(goType string) {
		goType = strings.TrimPrefix(goType, "*")
		goType = strings.TrimPrefix(goType, "[]")
		goType = strings.TrimPrefix(goType, "*")
		if len(goType) == 0 || goType[0] < 'A' || goType[0] > 'Z' {
			return
		}
		if strings.Contains(goType, ".") || baseTypes[goType] || seen[goType] {
			return
		}
		seen[goType] = true
		result = append(result, goType)
	}

	for _, c := range allCores {
		for _, m := range c.Methods {
			for _, r := range m.Results {
				if r.Type != "error" {
					addType(r.Type)
				}
			}
			for _, p := range m.Params {
				addType(p.Type)
			}
		}
	}
	sort.Strings(result)
	return result
}

func writeCoreDipatch(b *strings.Builder, c CoreInfo) {
	prefix := capitalize(c.Name)
	b.WriteString(fmt.Sprintf("func dispatch%s(c *cores.%s, method string, payload []byte) ([]byte, error) {\n",
		prefix, c.StructName))
	b.WriteString("\tswitch method {\n")

	for _, m := range c.Methods {
		if isCallbackMethod(m) {
			continue
		}
		writeMethodDispatchCase(b, c, m)
	}

	b.WriteString("\tdefault:\n")
	b.WriteString(fmt.Sprintf("\t\treturn nil, fmt.Errorf(\"unknown method %%s for %s\", method)\n", c.Name))
	b.WriteString("\t}\n}\n\n")
}

func hasUnresolvableTypes(m CoreMethod) bool {
	for _, p := range m.Params {
		// error as param type is unusual and hard to serialize
		if p.Type == "error" {
			return true
		}
		t := strings.TrimPrefix(p.Type, "*")
		// map with external key/value types
		if strings.HasPrefix(t, "map[") && strings.Contains(t, ".") {
			return true
		}
		// External complex types that we can't convert via simple type casting
		inner := strings.TrimPrefix(t, "[]")
		inner = strings.TrimPrefix(inner, "*")
		if strings.Contains(inner, ".") && !strings.HasPrefix(inner, "id.") &&
			!strings.HasPrefix(inner, "time.") && !strings.HasPrefix(inner, "io.") &&
			!strings.HasPrefix(inner, "json.") {
			// External struct types in params can't be converted from bytes
			return true
		}
	}
	return false
}

func writeMethodDispatchCase(b *strings.Builder, c CoreInfo, m CoreMethod) {
	prefix := capitalize(c.Name)
	reqType := prefix + m.Name + "Request"
	respType := prefix + m.Name + "Response"

	// Skip methods with unresolvable external types
	if hasUnresolvableTypes(m) {
		b.WriteString(fmt.Sprintf("\t// Skipped: %s (complex external types)\n", m.Name))
		return
	}

	b.WriteString(fmt.Sprintf("\tcase %q:\n", m.Name))

	// Unmarshal request
	hasParams := false
	for _, p := range m.Params {
		pt, _ := goTypeToProto(p.Type)
		if pt != "" {
			hasParams = true
			break
		}
	}

	if hasParams {
		b.WriteString(fmt.Sprintf("\t\tvar req pbcores.%s\n", reqType))
		b.WriteString("\t\tif err := proto.Unmarshal(payload, &req); err != nil { return nil, err }\n")
	}

	// Build the method call
	var args []string
	fieldNum := 1
	for _, p := range m.Params {
		pt, _ := goTypeToProto(p.Type)
		if pt == "" {
			continue // skip callbacks
		}
		name := p.Name
		if name == "" || name == "_" {
			name = fmt.Sprintf("param_%d", fieldNum)
		}
		protoField := goFieldToProtoField(capitalize(toProtoFieldName(name)))
		arg := fmt.Sprintf("req.%s", protoField)

		// Convert proto types to Go types where needed
		arg = convertProtoArgToGo(p.Type, arg)
		// Spread variadic params
		if strings.HasPrefix(p.Type, "...") {
			arg += "..."
		}
		args = append(args, arg)
		fieldNum++
	}

	// Build return capture
	var retNames []string
	hasError := false
	retIdx := 1
	for _, r := range m.Results {
		if r.Type == "error" {
			hasError = true
			continue
		}
		pt, _ := goTypeToProto(r.Type)
		if pt == "" {
			continue
		}
		retNames = append(retNames, fmt.Sprintf("r%d", retIdx))
		retIdx++
	}

	var callLHS string
	if hasError && len(retNames) > 0 {
		callLHS = strings.Join(retNames, ", ") + ", err"
	} else if hasError {
		callLHS = "err"
	} else if len(retNames) > 0 {
		callLHS = strings.Join(retNames, ", ")
	}

	if callLHS != "" {
		b.WriteString(fmt.Sprintf("\t\t%s := c.%s(%s)\n", callLHS, m.Name, strings.Join(args, ", ")))
	} else {
		b.WriteString(fmt.Sprintf("\t\tc.%s(%s)\n", m.Name, strings.Join(args, ", ")))
	}

	if hasError {
		b.WriteString("\t\tif err != nil { return nil, err }\n")
	}

	// Build response
	if len(retNames) > 0 {
		b.WriteString(fmt.Sprintf("\t\tresp := &pbcores.%s{\n", respType))
		retIdx = 0
		for _, r := range m.Results {
			if r.Type == "error" {
				continue
			}
			pt, _ := goTypeToProto(r.Type)
			if pt == "" {
				continue
			}
			retIdx++
			var protoField string
			if r.Name != "" {
				protoField = capitalize(toProtoFieldName(r.Name))
			} else {
				protoField = fmt.Sprintf("Result_%d", retIdx)
			}
			val := fmt.Sprintf("r%d", retIdx)
			val = convertGoRetToProto(r.Type, val)
			b.WriteString(fmt.Sprintf("\t\t\t%s: %s,\n", protoField, val))
		}
		b.WriteString("\t\t}\n")
		b.WriteString("\t\treturn proto.Marshal(resp)\n")
	} else {
		b.WriteString("\t\treturn nil, nil\n")
	}
}

// toProtoFieldName converts a Go param name to what protoc-gen-go uses as the Go field name.
// Proto field names are snake_case, protoc-gen-go converts them to CamelCase.
func toProtoFieldName(goParamName string) string {
	// Replicate protoc-gen-go's CamelCase conversion.
	// Proto field name is toSnakeCase(goParamName).
	// protoc-gen-go then converts to CamelCase with these rules:
	// - Capitalize after '_' or at start
	// - Keep '_' before numeric parts (param_1 → Param_1)
	// - Capitalize letter after digit run (p256dh → P256Dh)
	snake := toSnakeCase(goParamName)
	parts := strings.Split(snake, "_")
	var result strings.Builder
	for i, p := range parts {
		if p == "" {
			continue
		}
		// protoc-gen-go keeps underscore before pure-numeric parts
		if i > 0 && len(p) > 0 && p[0] >= '0' && p[0] <= '9' {
			result.WriteByte('_')
			result.WriteString(p)
			continue
		}
		// Apply protoc-gen-go's CamelCase: capitalize after digit→letter transitions
		capNext := true
		for j, ch := range p {
			if capNext && ch >= 'a' && ch <= 'z' {
				result.WriteRune(ch - 32)
				capNext = false
			} else {
				result.WriteRune(ch)
				// After a digit, the next letter should be capitalized
				if ch >= '0' && ch <= '9' && j < len(p)-1 {
					next := p[j+1]
					if next >= 'a' && next <= 'z' {
						capNext = true
					}
				} else {
					capNext = false
				}
			}
		}
	}
	return result.String()
}

// convertProtoArgToGo converts a proto request field to the Go type the method expects.
func convertProtoArgToGo(goType string, expr string) string {
	// Handle pointer-to-primitive before stripping *
	if goType == "*bool" {
		return "boolPtr(" + expr + ")"
	}
	if goType == "*int" {
		return "intPtr(int(" + expr + "))"
	}
	if goType == "*string" {
		return "stringPtr(" + expr + ")"
	}
	isPtr := strings.HasPrefix(goType, "*")
	goType = strings.TrimPrefix(goType, "*")
	_ = isPtr // used for distinguishing pointer vs value types
	switch goType {
	case "AuthConfig":
		return "ProtoToAuthConfig(" + expr + ")"
	case "PaginationOpts":
		return "ProtoToPaginationOpts(" + expr + ")"
	case "OutgoingMessage":
		if isPtr {
			return "ProtoToOutgoingMessage(" + expr + ")"
		}
		return "*ProtoToOutgoingMessage(" + expr + ")"
	case "FileRef":
		if isPtr {
			return "ProtoToFileRef(" + expr + ")"
		}
		return "*ProtoToFileRef(" + expr + ")"
	case "map[string]interface{}", "map[string]any":
		return "bytesToMap(" + expr + ")"
	case "map[string]string":
		return expr // proto map<string,string> is already map[string]string in Go
	case "map[string]bool":
		return expr // proto map<string,bool> is already map[string]bool in Go
	case "int":
		return "int(" + expr + ")"
	case "int32":
		return "int32(" + expr + ")"
	case "byte":
		return "byte(" + expr + ")"
	case "[]byte":
		return expr
	case "[]int":
		return "int64sToInts(" + expr + ")"
	case "[]interface{}", "[]any":
		return "bytesToSliceInterface(" + expr + ")"
	case "interface{}":
		return "anyFromBytes(" + expr + ")"
	case "io.Reader":
		return "bytes.NewReader(" + expr + ")"
	case "time.Duration":
		return "time.Duration(" + expr + ")"
	case "time.Time":
		return "msToTime(" + expr + ")"
	case "map[int]string":
		return "bytesToMapIntString(" + expr + ")"
	case "map[string]map[string]string":
		return "bytesToMapStringMapStringString(" + expr + ")"
	case "map[string]map[string]map[string]interface{}":
		return "bytesToMapStringMapStringMapStringInterface(" + expr + ")"
	case "[][]map[string]string":
		return "bytesToNestedSliceMapString(" + expr + ")"
	case "json.RawMessage":
		return "json.RawMessage(" + expr + ")"
	case "[]int16":
		return "bytesToInt16Slice(" + expr + ")"
	case "[]uint16":
		return "bytesToUint16Slice(" + expr + ")"
	case "[3]float32":
		return "float32SliceTo3(" + expr + ")"
	default:
		// External string-typedef types (id.RoomID etc.)
		if strings.HasPrefix(goType, "id.") {
			return goType + "(" + expr + ")"
		}
		// Core-specific struct types as params — need JSON round-trip
		if len(goType) > 0 && goType[0] >= 'A' && goType[0] <= 'Z' && !strings.Contains(goType, ".") {
			if isPtr {
				return "protoToCorePtr_" + goType + "(" + expr + ")"
			}
			return "protoToCore_" + goType + "(" + expr + ")"
		}
		if strings.HasPrefix(goType, "[]map[string]interface{}") {
			return "bytesToSliceMap(" + expr + ")"
		}
		if strings.HasPrefix(goType, "[][]map[string]string") {
			return "bytesToNestedSliceMapString(" + expr + ")"
		}
		if strings.HasPrefix(goType, "[]map[string]string") {
			return "bytesToSliceMapString(" + expr + ")"
		}
		if strings.HasPrefix(goType, "[]map[string]") {
			return expr // bytes in proto
		}
		// Slice of core-specific structs: proto []*pbcores.X → []cores.X
		if strings.HasPrefix(goType, "[]") {
			inner := strings.TrimPrefix(goType, "[]")
			inner = strings.TrimPrefix(inner, "*")
			if len(inner) > 0 && inner[0] >= 'A' && inner[0] <= 'Z' && !strings.Contains(inner, ".") {
				return "protoSliceToCore_" + inner + "(" + expr + ")"
			}
		}
		return expr
	}
}

// convertGoRetToProto converts a Go return value to the proto response field value.
func convertGoRetToProto(goType string, expr string) string {
	isPtr := strings.HasPrefix(goType, "*")
	goType = strings.TrimPrefix(goType, "*")
	switch goType {
	case "Message":
		return "MessageToProto(" + expr + ")"
	case "OutgoingMessage":
		return "OutgoingMessageToProto(" + expr + ")"
	case "Dialog":
		return "DialogToProto(" + expr + ")"
	case "User":
		return "UserToProto(" + expr + ")"
	case "Folder":
		return "FolderToProto(" + expr + ")"
	case "Session":
		return "SessionToProto(" + expr + ")"
	case "CallSession":
		return "CallSessionToProto(" + expr + ")"
	case "ReadState":
		return "ReadStateToProto(" + expr + ")"
	case "VerificationInfo":
		return "VerificationInfoToProto(" + expr + ")"
	case "[]Message":
		return "MessagesToProto(" + expr + ")"
	case "[]*Message":
		return "PtrMessagesToProto(" + expr + ")"
	case "time.Time":
		return "timeToMS(" + expr + ")"
	case "time.Duration":
		return "int64(" + expr + ")"
	case "[]Dialog":
		return "DialogsToProto(" + expr + ")"
	case "[]User":
		return "UsersToProto(" + expr + ")"
	case "[]Folder":
		return "FoldersToProto(" + expr + ")"
	case "[]Session":
		return "SessionsToProto(" + expr + ")"
	case "[]FileRef":
		return "FileRefsToProto(" + expr + ")"
	case "[]Reaction":
		return "ReactionsToProto(" + expr + ")"
	case "map[string]interface{}":
		return "mapToBytes(" + expr + ")"
	case "map[string]string":
		return expr // proto map<string,string> is same Go type
	case "map[string]bool":
		return expr // proto map<string,bool> is same Go type
	case "[]map[string]interface{}":
		return "sliceMapToBytes(" + expr + ")"
	case "[]map[string]string":
		return "anyToBytes(" + expr + ")"
	case "map[string][]string":
		return "anyToBytes(" + expr + ")"
	case "map[string]map[string]interface{}":
		return "anyToBytes(" + expr + ")"
	case "map[string]json.RawMessage":
		return "anyToBytes(" + expr + ")"
	case "json.RawMessage":
		return "[]byte(" + expr + ")"
	case "[]json.RawMessage":
		return "anyToBytes(" + expr + ")"
	case "[]interface{}", "[]any":
		return "anyToBytes(" + expr + ")"
	case "map[int]string", "map[int]map[string]string", "map[string]int",
		"[]map[string]int64":
		return "anyToBytes(" + expr + ")"
	case "[]string":
		return expr
	case "[]int":
		return "intsToInt64s(" + expr + ")"
	case "[]int16":
		return "int16SliceToBytes(" + expr + ")"
	case "[]uint16":
		return "uint16SliceToBytes(" + expr + ")"
	case "[][]byte":
		return expr
	case "int":
		return "int64(" + expr + ")"
	case "int32":
		return expr
	default:
		// External types that become bytes in proto
		if strings.Contains(goType, ".") {
			return "anyToBytes(" + expr + ")"
		}
		// Core-specific types: use JSON round-trip converter
		stripped := goType
		isSlice := strings.HasPrefix(stripped, "[]")
		stripped = strings.TrimPrefix(stripped, "[]")
		isPtrInner := strings.HasPrefix(stripped, "*")
		stripped = strings.TrimPrefix(stripped, "*")
		if len(stripped) > 0 && stripped[0] >= 'A' && stripped[0] <= 'Z' && !strings.Contains(stripped, ".") {
			if isSlice {
				if isPtrInner {
					return "corePtrSliceToProto_" + stripped + "(" + expr + ")"
				}
				return "coreSliceToProto_" + stripped + "(" + expr + ")"
			}
			if isPtr {
				return "coreToProto_" + stripped + "_ptr(" + expr + ")"
			}
			return "coreToProto_" + stripped + "(" + expr + ")"
		}
		// Slices of unexported types → anyToBytes (they map to bytes in proto)
		if isSlice && len(stripped) > 0 && stripped[0] >= 'a' && stripped[0] <= 'z' &&
			!strings.Contains(stripped, ".") && stripped != "string" && stripped != "byte" &&
			stripped != "int" && stripped != "int64" && stripped != "int32" &&
			stripped != "float32" && stripped != "float64" && stripped != "bool" {
			return "anyToBytes(" + expr + ")"
		}
		return expr
	}
}

