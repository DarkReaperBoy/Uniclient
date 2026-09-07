# anet (patched fork)

Fork of github.com/wlynxg/anet v0.0.5 with one fix:

Upstream `interface_android.go` used `//go:linkname` against
`net.zoneCache` and `x/net/internal/socket.zoneCache`, which the Go 1.23+
linker rejects ("invalid reference") for android targets — breaking every
APK build of any project that (transitively) uses pion/webrtc, whose
`transport/stdnet` imports anet.

This fork drops the linknames and keeps private zone caches instead
(behaviorally equivalent: a 60s interface cache).

Consumed via a `replace` directive in ../go.mod. Track upstream for a
fixed release and drop this fork when available.
