package tracker

import (
	"encoding/json"
	"io"
	"os"
	"syscall"

	"github.com/a-ioenimil/aws-resource-creation-scripts/aws-automator/internal/config"
	"github.com/a-ioenimil/aws-resource-creation-scripts/aws-automator/internal/ui"
)

type ResourceTracker struct {
	Instances      []string `json:"instances"`
	SecurityGroups []string `json:"security_groups"`
	KeyPairs       []string `json:"key_pairs"`
	S3Buckets      []string `json:"s3_buckets"`
}

func Load() ResourceTracker {
	var tracker ResourceTracker

	file, err := os.OpenFile(config.TrackerFile, os.O_RDONLY|os.O_CREATE, 0644)
	if err != nil {
		return tracker
	}
	defer file.Close()

	// Acquire shared lock for reading
	if err := syscall.Flock(int(file.Fd()), syscall.LOCK_SH); err != nil {
		ui.Red.Printf("⚠️  Warning: Could not lock file: %v\n", err)
	} else {
		defer syscall.Flock(int(file.Fd()), syscall.LOCK_UN)
	}

	data, err := io.ReadAll(file)
	if err != nil {
		return tracker
	}

	json.Unmarshal(data, &tracker)
	return tracker
}
