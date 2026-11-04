package tests

import (
	"testing"
	"time"

	. "uniclient/cores"
)

func FuzzTSCommand(f *testing.F) {
	f.Add([]byte(""))
	f.Add([]byte("error id=0 msg=ok"))
	f.Add([]byte("error id=2568 msg=insufficient\\sclient\\spermissions failed_permid=139"))
	f.Add([]byte("notifyclientmoved ctid=43 clid=7"))
	f.Add([]byte("channellist cid=1 channel_name=x|cid=2 channel_name=y"))
	f.Add([]byte{0x00, 0xFF, 0x0A, 0x0D})
	f.Add([]byte("key=" + string(make([]byte, 4096))))
	f.Fuzz(func(t *testing.T, data []byte) {
		_, _ = TsParseCommand(data)
	})
}

func FuzzTSPacket(f *testing.F) {
	f.Add([]byte{})
	f.Add([]byte{0, 1, 2, 3, 4, 5, 6, 7, 0, 1, 0, 2, 0x02})
	f.Add([]byte{0, 1, 2, 3, 4, 5, 6, 7, 0, 1, 0, 2, 0x62})
	f.Add(make([]byte, 13))
	f.Add(append(make([]byte, 13), 0xAA))
	f.Fuzz(func(t *testing.T, data []byte) {
		_, _, _, _, _ = TsParseS2CPacket(data)
	})
}

func FuzzTSEAXDecrypt(f *testing.F) {
	f.Add([]byte{}, []byte{}, []byte{})
	f.Add([]byte{1, 2, 3}, []byte{4, 5, 6, 7}, []byte{0, 0, 0, 0, 0, 0, 0, 0})
	f.Add(make([]byte, 16), make([]byte, 5), make([]byte, 8))
	f.Fuzz(func(t *testing.T, header, ciphertext, mac []byte) {
		if len(mac) != 8 {
			t.Skip()
		}
		var macIn [8]byte
		copy(macIn[:], mac)
		_, _ = TsEAXDecrypt(TsFakeKey[:], TsFakeNonce[:], header, ciphertext, macIn)
	})
}

func FuzzTSHandleServerCommand(f *testing.F) {
	f.Add([]byte(""))
	f.Add([]byte("notifyclientmoved ctid=43 clid=7"))
	f.Add([]byte("notifycliententerview ctid=44 clid=9 client_nickname=x"))
	f.Add([]byte("notifytextmessage targetmode=3 invokerid=5 msg=hi"))
	f.Add([]byte("notifyclientpoke invokerid=5 invokername=b msg=p"))
	f.Add([]byte("notifychannelcreated cid=77 channel_name=z"))
	f.Add([]byte("notifyclientupdated clid=7 client_talk_power=20"))
	f.Add([]byte("channellist cid=1 channel_name=a|cid=2 channel_name=b"))
	f.Add([]byte("initserver virtualserver_name=x aclid=7"))

	core := newWireFuzzCore(f)

	f.Fuzz(func(t *testing.T, data []byte) {
		name, params := TsParseCommand(data)
		core.TsHandleServerCommand(*ForTestNewTsIncomingCmd(name, params, string(data)))
	})
}

func FuzzMumbleURL(f *testing.F) {
	f.Add("")
	f.Add("mumble://user:pass@host:64738/Channel/Sub")
	f.Add("mumble://host/Channel?version=1.2.3")
	f.Add("mumble://")
	f.Add("mumble://[::1]:64738/")
	f.Add("mumble://" + string(make([]byte, 4096)))
	f.Fuzz(func(t *testing.T, raw string) {
		_, _, _, _, _, _ = ParseMumbleURL(raw)
	})
}

func newWireFuzzCore(tb testing.TB) *TeamSpeakCore {
	tb.Helper()
	old := TsExecVoidTimeout
	TsExecVoidTimeout = 2 * time.Second
	tb.Cleanup(func() { TsExecVoidTimeout = old })
	core, _ := newScriptedTSCore(tb, tsScriptedConfig{ClientID: 7})
	return core
}
