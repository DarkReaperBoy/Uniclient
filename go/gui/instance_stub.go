//go:build !windows

package gui

func HandleLaunchURI(args []string, configDir string) bool { return false }

func (a *App) ServeInstanceCommands(configDir string) {}

func stopInstanceServer() {}
