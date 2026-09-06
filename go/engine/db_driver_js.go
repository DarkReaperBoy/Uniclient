//go:build js

// On WASM/web, we register a no-op SQL driver. The engine's existing code all
// compiles and runs — queries return empty results, writes silently succeed.
// Persistent caching on web is handled by the host layer using browser storage
// (IndexedDB). The Go WASM module only handles protocol/networking.

package engine

import (
	"database/sql"
	"database/sql/driver"
	"io"
)

func init() {
	sql.Register("sqlite", &nullDriver{})
}

// nullDriver implements driver.Driver.
type nullDriver struct{}

func (d *nullDriver) Open(_ string) (driver.Conn, error) { return &nullConn{}, nil }

// nullConn implements driver.Conn.
type nullConn struct{}

func (c *nullConn) Prepare(_ string) (driver.Stmt, error) { return &nullStmt{}, nil }
func (c *nullConn) Close() error                          { return nil }
func (c *nullConn) Begin() (driver.Tx, error)             { return &nullTx{}, nil }

// nullStmt implements driver.Stmt.
type nullStmt struct{}

func (s *nullStmt) Close() error                                 { return nil }
func (s *nullStmt) NumInput() int                                { return -1 } // -1 = any number of args
func (s *nullStmt) Exec(_ []driver.Value) (driver.Result, error) { return nullResult{}, nil }
func (s *nullStmt) Query(_ []driver.Value) (driver.Rows, error)  { return &nullRows{}, nil }

// nullResult implements driver.Result.
type nullResult struct{}

func (r nullResult) LastInsertId() (int64, error) { return 0, nil }
func (r nullResult) RowsAffected() (int64, error) { return 0, nil }

// nullRows implements driver.Rows — always empty.
type nullRows struct{}

func (r *nullRows) Columns() []string           { return nil }
func (r *nullRows) Close() error                { return nil }
func (r *nullRows) Next(_ []driver.Value) error { return io.EOF }

// nullTx implements driver.Tx.
type nullTx struct{}

func (t *nullTx) Commit() error   { return nil }
func (t *nullTx) Rollback() error { return nil }
