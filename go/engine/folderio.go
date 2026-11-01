package engine

import (
	"encoding/json"
	"fmt"
	"strings"
)

type FolderExport struct {
	Name         string   `json:"name"`
	Emoticon     string   `json:"emoticon,omitempty"`
	Chats        []string `json:"chats,omitempty"`
	Pinned       []string `json:"pinned,omitempty"`
	Exclude      []string `json:"exclude,omitempty"`
	Contacts     bool     `json:"contacts,omitempty"`
	NonContacts  bool     `json:"non_contacts,omitempty"`
	Groups       bool     `json:"groups,omitempty"`
	Channels     bool     `json:"channels,omitempty"`
	Bots         bool     `json:"bots,omitempty"`
	ExcludeMuted bool     `json:"exclude_muted,omitempty"`
	ExcludeRead  bool     `json:"exclude_read,omitempty"`
	ExcludeArch  bool     `json:"exclude_archived,omitempty"`
	IsChatList   bool     `json:"is_chat_list,omitempty"`
}

type foldersExportEnvelope struct {
	Version int            `json:"uniclient_folders"`
	Folders []FolderExport `json:"folders"`
}

const foldersExportVersion = 1

func foldersToExport(fs []FolderInfo) []FolderExport {
	out := make([]FolderExport, 0, len(fs))
	for _, f := range fs {
		out = append(out, FolderExport{
			Name:         f.Name,
			Emoticon:     f.Emoticon,
			Chats:        f.ChatIDs,
			Pinned:       f.PinnedChatIDs,
			Exclude:      f.ExcludeChatIDs,
			Contacts:     f.Contacts,
			NonContacts:  f.NonContacts,
			Groups:       f.Groups,
			Channels:     f.Channels,
			Bots:         f.Bots,
			ExcludeMuted: f.ExcludeMuted,
			ExcludeRead:  f.ExcludeRead,
			ExcludeArch:  f.ExcludeArchived,
			IsChatList:   f.IsChatList,
		})
	}
	return out
}

func EncodeFoldersExport(fs []FolderInfo) (string, error) {
	env := foldersExportEnvelope{Version: foldersExportVersion, Folders: foldersToExport(fs)}
	b, err := json.MarshalIndent(env, "", " ")
	if err != nil {
		return "", err
	}
	return string(b), nil
}

func ParseFoldersExport(data string) ([]FolderExport, error) {
	data = strings.TrimSpace(data)
	if data == "" {
		return nil, fmt.Errorf("empty import")
	}
	var env foldersExportEnvelope
	if err := json.Unmarshal([]byte(data), &env); err != nil {
		return nil, fmt.Errorf("invalid folder JSON: %w", err)
	}
	if env.Version != foldersExportVersion {
		return nil, fmt.Errorf("unknown export version %d (want %d)", env.Version, foldersExportVersion)
	}
	if len(env.Folders) == 0 {
		return nil, fmt.Errorf("no folders in export")
	}
	for i, f := range env.Folders {
		if strings.TrimSpace(f.Name) == "" {
			return nil, fmt.Errorf("folder %d has no name", i+1)
		}
	}
	return env.Folders, nil
}

func ExportToOpts(f FolderExport) *CreateFolderOpts {
	return &CreateFolderOpts{
		Contacts:        f.Contacts,
		NonContacts:     f.NonContacts,
		Groups:          f.Groups,
		Channels:        f.Channels,
		Bots:            f.Bots,
		ExcludeMuted:    f.ExcludeMuted,
		ExcludeRead:     f.ExcludeRead,
		ExcludeArchived: f.ExcludeArch,
		ExcludeChatIDs:  f.Exclude,
		PinnedChatIDs:   f.Pinned,
		IsChatList:      f.IsChatList,
		Emoticon:        f.Emoticon,
	}
}

func (e *Engine) ExportFoldersJSON(accountID string) (string, error) {
	folders, err := e.GetFolders(accountID)
	if err != nil {
		return "", err
	}
	if len(folders) == 0 {
		return "", fmt.Errorf("no folders to export")
	}
	return EncodeFoldersExport(folders)
}

func (e *Engine) ImportFoldersJSON(accountID, data string) (int, error) {
	entries, err := ParseFoldersExport(data)
	if err != nil {
		return 0, err
	}
	existing, _ := e.GetFolders(accountID)
	have := make(map[string]bool, len(existing))
	for _, f := range existing {
		have[strings.TrimSpace(f.Name)] = true
	}
	created := 0
	for _, entry := range entries {
		name := strings.TrimSpace(entry.Name)
		if have[name] {
			continue
		}
		if _, err := e.CreateFolder(accountID, name, entry.Chats, ExportToOpts(entry)); err != nil {
			return created, fmt.Errorf("folder %q: %w", name, err)
		}
		have[name] = true
		created++
	}
	return created, nil
}
