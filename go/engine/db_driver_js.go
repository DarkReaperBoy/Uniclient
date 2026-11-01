//go:build js

package engine

import (
	"database/sql"
	"database/sql/driver"
	"io"
)

func init() {
	sql.Register("sqlite", &nullDriver{})
}

type nullDriver struct{}

func (d *nullDriver) Open(_ string) (driver.Conn, error) { return &nullConn{}, nil }

type nullConn struct{}

func (c *nullConn) Prepare(_ string) (driver.Stmt, error) { return &nullStmt{}, nil }
func (c *nullConn) Close() error                          { return nil }
func (c *nullConn) Begin() (driver.Tx, error)             { return &nullTx{}, nil }

type nullStmt struct{}

func (s *nullStmt) Close() error                                 { return nil }
func (s *nullStmt) NumInput() int                                { return -1 }
func (s *nullStmt) Exec(_ []driver.Value) (driver.Result, error) { return nullResult{}, nil }
func (s *nullStmt) Query(_ []driver.Value) (driver.Rows, error)  { return &nullRows{}, nil }

type nullResult struct{}

func (r nullResult) LastInsertId() (int64, error) { return 0, nil }
func (r nullResult) RowsAffected() (int64, error) { return 0, nil }

type nullRows struct{}

func (r *nullRows) Columns() []string           { return nil }
func (r *nullRows) Close() error                { return nil }
func (r *nullRows) Next(_ []driver.Value) error { return io.EOF }

type nullTx struct{}

func (t *nullTx) Commit() error   { return nil }
func (t *nullTx) Rollback() error { return nil }
