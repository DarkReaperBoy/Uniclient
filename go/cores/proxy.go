package cores

type ProxyConfig struct {
	Enabled  bool
	Type     string
	Host     string
	Port     int
	Username string
	Password string
	Secret   string
	IPv6     bool
}

func (p ProxyConfig) active() bool {
	return p.Enabled && p.Host != "" && p.Port > 0 &&
		(p.Type == "socks5" || p.Type == "http" || p.Type == "mtproto")
}
