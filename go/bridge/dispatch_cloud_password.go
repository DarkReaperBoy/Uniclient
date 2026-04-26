package bridge

import (
	"encoding/json"

	"uniclient/cores"
)

func dispatchTelegramCloudPassword(c *cores.TelegramCore, method string, payload []byte) ([]byte, error, bool) {
	switch method {
	case "GetCloudPasswordState":
		r, err := c.GetCloudPasswordState()
		if err != nil {
			return nil, err, true
		}
		b, _ := json.Marshal(r)
		return b, nil, true

	case "CheckCloudPassword":
		var req struct {
			Password string `json:"password"`
		}
		if err := json.Unmarshal(payload, &req); err != nil {
			return nil, err, true
		}
		err := c.CheckCloudPassword(req.Password)
		if err != nil {
			return nil, err, true
		}
		return nil, nil, true

	case "SetCloudPassword":
		var req struct {
			CurrentPassword string `json:"currentPassword"`
			NewPassword     string `json:"newPassword"`
			Hint            string `json:"hint"`
			Email           string `json:"email"`
		}
		if err := json.Unmarshal(payload, &req); err != nil {
			return nil, err, true
		}
		err := c.SetCloudPassword(req.CurrentPassword, req.NewPassword, req.Hint, req.Email)
		if err != nil {
			return nil, err, true
		}
		return nil, nil, true

	case "RemoveCloudPassword":
		var req struct {
			CurrentPassword string `json:"currentPassword"`
		}
		if err := json.Unmarshal(payload, &req); err != nil {
			return nil, err, true
		}
		err := c.RemoveCloudPassword(req.CurrentPassword)
		if err != nil {
			return nil, err, true
		}
		return nil, nil, true

	default:
		return nil, nil, false
	}
}
