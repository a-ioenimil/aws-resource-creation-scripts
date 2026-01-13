package config

import (
	"os"
	"path/filepath"
)

var (
	ProjectRoot string
	ScriptsDir  string
	TrackerFile string
)

func Init() {
	ex, err := os.Executable()
	if err != nil {
		panic(err)
	}

	// Determine project root based on execution context
	cwd, _ := os.Getwd()

	if filepath.Base(filepath.Dir(ex)) == "bin" {
		// Running detailed binary from ./bin/
		ProjectRoot = filepath.Dir(filepath.Dir(ex))
	} else {
		// Fallback for development (go run)
		ProjectRoot = cwd
	}

	ScriptsDir = filepath.Join(ProjectRoot, "scripts")
	TrackerFile = filepath.Join(ProjectRoot, "created_resources.json")
}
