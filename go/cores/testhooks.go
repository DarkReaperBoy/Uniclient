package cores

func (x *groupPeer) ForTestKey() string {
	return x.key
}

func (x *TeamSpeakCore) ForTestMyClientID() int {
	return x.myClientID
}

func (x *tsP256Identity) ForTestTsOmega() string {
	return x.tsOmega()
}

func (x *tsP256Identity) ForTestTsSign(data []byte) ([]byte, error) {
	return x.tsSign(data)
}

func (x *TsConnection) ForTestTsTrackRecvPID(pktType byte, pID uint16) uint32 {
	return x.tsTrackRecvPID(pktType, pID)
}

func (x *tsP256Identity) ForTestTsUID() string {
	return x.tsUID()
}

func ForTestNewTsIncomingCmd(name string, params map[string]string, raw string) *TsIncomingCmd {
	return &TsIncomingCmd{name: name, params: params, raw: raw}
}
