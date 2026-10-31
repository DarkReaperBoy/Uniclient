package main

// R49 RED proof (Law 22): the PRE-FIX merge shape — append(a.callsBoxRows,
// grouped...) with spare capacity left by the delete shift — reuses the
// backing array that a frame snapshot still holds. Run with:
//   go run scripts/r49_red_proof.go
// Prints "true" = the pre-fix shape reuses the shared array, which is exactly
// what TestCallsBoxPageMergeBuildsFreshSlice forbids post-fix.

import "fmt"

type row struct{ id string }

func main() {
	// len 3, cap 5 — the post-delete shape (the shift keeps the array and
	// shrinks only the length).
	full := make([]row, 3, 5)
	full[0], full[1], full[2] = row{"30"}, row{"20"}, row{"10"}

	// What App holds, and what a frame snapshot built this frame would hold:
	// the same backing array.
	head := full

	grouped := []row{{"25"}}
	merged := append(head, grouped...) // the PRE-FIX shape

	fmt.Println("pre-fix merge reuses the frame-shared array:", &merged[0] == &head[0])
}
