package cores

// StubCore implements the full Core interface with ErrNotSupported
// responses. Real backends embed it and override the methods they support,
// so the interface can grow without breaking every core.
type StubCore struct{}

var _ Core = (*StubCore)(nil)

func (StubCore) Name() string                                  { return "stub" }
func (StubCore) Capabilities() []string                        { return nil }
func (StubCore) Authenticate(AuthConfig) error                 { return ErrNotSupported }
func (StubCore) Logout() error                                 { return ErrNotSupported }
func (StubCore) GetDialogs(PaginationOpts) ([]Dialog, error)   { return nil, ErrNotSupported }
func (StubCore) CreateGroup(string, []string) (*Dialog, error) { return nil, ErrNotSupported }
func (StubCore) CreateChannel(string, string) (*Dialog, error) { return nil, ErrNotSupported }
func (StubCore) CreateTopic(string, string) (*Dialog, error)   { return nil, ErrNotSupported }
func (StubCore) GetFolders() ([]Folder, error)                 { return nil, ErrNotSupported }
func (StubCore) CreateFolder(string, []string) (*Folder, error) {
	return nil, ErrNotSupported
}
func (StubCore) SendMessage(string, OutgoingMessage) (*Message, error) {
	return nil, ErrNotSupported
}
func (StubCore) GetMessages(string, PaginationOpts) ([]Message, error) {
	return nil, ErrNotSupported
}
func (StubCore) EditMessage(string, string, string) (*Message, error) {
	return nil, ErrNotSupported
}
func (StubCore) DeleteMessage(string, string) error { return ErrNotSupported }
func (StubCore) ReplyToMessage(string, string, OutgoingMessage) (*Message, error) {
	return nil, ErrNotSupported
}
func (StubCore) ForwardMessage(string, string, string) (*Message, error) {
	return nil, ErrNotSupported
}
func (StubCore) ReactToMessage(string, string, string) error { return ErrNotSupported }
func (StubCore) PinMessage(string, string) error             { return ErrNotSupported }
func (StubCore) UnpinMessage(string, string) error           { return ErrNotSupported }
func (StubCore) MarkAsRead(string, string) error             { return ErrNotSupported }
func (StubCore) GetReadState(string) (*ReadState, error)     { return nil, ErrNotSupported }
func (StubCore) UploadFile(string, FileUpload, func(int64, int64)) (*Message, error) {
	return nil, ErrNotSupported
}
func (StubCore) DownloadFile(FileRef, string, func(int64, int64)) error {
	return ErrNotSupported
}
func (StubCore) SendImageBase64(string, string, string) (*Message, error) {
	return nil, ErrNotSupported
}
func (StubCore) StartCall(string, bool) (*CallSession, error) {
	return nil, ErrNotSupported
}
func (StubCore) JoinGroupCall(string) (*CallSession, error) {
	return nil, ErrNotSupported
}
func (StubCore) EndCall(string) error                     { return ErrNotSupported }
func (StubCore) SetCallMuted(string, bool) error          { return ErrNotSupported }
func (StubCore) ToggleCamera(string, bool) error          { return ErrNotSupported }
func (StubCore) GetProfile(string) (*User, error)         { return nil, ErrNotSupported }
func (StubCore) OnUpdate(func(Update))                    {}
func (StubCore) Close() error                             { return nil }
func (StubCore) GetChatInfo(string) (*Dialog, error)      { return nil, ErrNotSupported }
func (StubCore) EditChatTitle(string, string) error       { return ErrNotSupported }
func (StubCore) EditChatDescription(string, string) error { return ErrNotSupported }
func (StubCore) LeaveChat(string) error                   { return ErrNotSupported }
func (StubCore) GetInviteLink(string) (string, error)     { return "", ErrNotSupported }
func (StubCore) AddMembers(string, []string) error        { return ErrNotSupported }
func (StubCore) RemoveMember(string, string) error        { return ErrNotSupported }
func (StubCore) BanMember(string, string) error           { return ErrNotSupported }
func (StubCore) UnbanMember(string, string) error         { return ErrNotSupported }
func (StubCore) GetMembers(string, PaginationOpts) ([]User, error) {
	return nil, ErrNotSupported
}
func (StubCore) SetAdmin(string, string, bool) error { return ErrNotSupported }
func (StubCore) GetContacts() ([]User, error)        { return nil, ErrNotSupported }
func (StubCore) AddContact(string, string, string) error {
	return ErrNotSupported
}
func (StubCore) DeleteContact(string) error       { return ErrNotSupported }
func (StubCore) BlockUser(string) error           { return ErrNotSupported }
func (StubCore) UnblockUser(string) error         { return ErrNotSupported }
func (StubCore) GetBlockedUsers() ([]User, error) { return nil, ErrNotSupported }
func (StubCore) SearchMessages(string, string, PaginationOpts) ([]Message, error) {
	return nil, ErrNotSupported
}
func (StubCore) SearchGlobal(string, PaginationOpts) ([]Dialog, error) {
	return nil, ErrNotSupported
}
func (StubCore) SendTyping(string) error { return ErrNotSupported }
func (StubCore) CreatePoll(string, string, []string) (*Message, error) {
	return nil, ErrNotSupported
}
func (StubCore) VotePoll(string, string, int) error { return ErrNotSupported }
func (StubCore) SendSticker(string, string) (*Message, error) {
	return nil, ErrNotSupported
}
func (StubCore) GetSessions() ([]Session, error) { return nil, ErrNotSupported }
func (StubCore) TerminateSession(string) error   { return ErrNotSupported }
func (StubCore) MuteChat(string, bool) error     { return ErrNotSupported }
func (StubCore) ArchiveChat(string, bool) error  { return ErrNotSupported }
func (StubCore) MarkUnread(string, bool) error   { return ErrNotSupported }
func (StubCore) UnpinAllMessages(string) error   { return ErrNotSupported }
func (StubCore) AcceptCall(string) (*CallSession, error) {
	return nil, ErrNotSupported
}
func (StubCore) DeclineCall(string) error { return ErrNotSupported }
func (StubCore) SendLocation(string, float64, float64) (*Message, error) {
	return nil, ErrNotSupported
}
