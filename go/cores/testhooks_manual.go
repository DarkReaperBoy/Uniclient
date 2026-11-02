package cores

func (x tsPacketState) ForTestWithRecvInit(v bool) tsPacketState {
	x.recvInit = v
	return x
}

func (x tsPacketState) ForTestWithLastRecvPID(v uint16) tsPacketState {
	x.lastRecvPID = v
	return x
}

func (x tsPacketState) ForTestWithRecvGenID(v uint32) tsPacketState {
	x.recvGenID = v
	return x
}

func (x tsPacketState) ForTestWithNextRecvID(v uint16) tsPacketState {
	x.nextRecvID = v
	return x
}

func (x tsPacketState) ForTestRecvGenID() uint32 {
	return x.recvGenID
}
