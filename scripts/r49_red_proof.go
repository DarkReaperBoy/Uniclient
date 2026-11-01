package main

import "fmt"

type row struct{ id string }

func main() {
	full := make([]row, 3, 5)
	full[0], full[1], full[2] = row{"30"}, row{"20"}, row{"10"}

	head := full

	grouped := []row{{"25"}}
	merged := append(head, grouped...)

	fmt.Println("pre-fix merge reuses the frame-shared array:", &merged[0] == &head[0])
}
