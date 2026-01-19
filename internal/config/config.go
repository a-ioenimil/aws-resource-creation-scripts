package config

import (
	"os"
	"path/filepath"
)

var (
	ProjectRoot   string
	ScriptsDir    string
	TrackerFile   string
	S3StateBucket string
	S3StateKey    string
	S3StateRegion string
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

	// Load S3 state backend config from environment
	S3StateBucket = os.Getenv("S3_STATE_BUCKET")
	S3StateKey = os.Getenv("S3_STATE_KEY")
	if S3StateKey == "" {
		S3StateKey = "state/created_resources.json"
	}
	S3StateRegion = os.Getenv("S3_STATE_REGION")
	if S3StateRegion == "" {
		S3StateRegion = os.Getenv("AWS_REGION")
	}
	if S3StateRegion == "" {
		S3StateRegion = "us-east-1"
	}
}

func IsRemoteStateEnabled() bool {
	return S3StateBucket != ""
}
