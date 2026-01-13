package ui

import (
	"fmt"
	"strings"

	"github.com/fatih/color"
)

var (
	Green  = color.New(color.FgGreen, color.Bold)
	Red    = color.New(color.FgRed, color.Bold)
	Yellow = color.New(color.FgYellow, color.Bold)
	Cyan   = color.New(color.FgCyan, color.Bold)
)

func PrintResourceRow(resourceType string, resources []string) {
	count := len(resources)
	ids := "None"
	if count > 0 {
		ids = strings.Join(resources, ", ")
		if len(ids) > 26 {
			ids = ids[:23] + "..."
		}
	}

	col := Green
	if count == 0 {
		col = Yellow
	}

	fmt.Printf("│ %-19s │ ", resourceType)
	col.Printf("%-5d", count)
	fmt.Printf(" │ %-26s │\n", ids)
}
