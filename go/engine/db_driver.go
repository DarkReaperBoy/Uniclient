//go:build !js

package engine

import _ "modernc.org/sqlite" // registers the "sqlite" driver for database/sql
