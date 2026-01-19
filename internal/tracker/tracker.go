package tracker

import (
	"encoding/json"
	"fmt"
	"io"
	"os"
	"os/exec"
	"syscall"

	"github.com/a-ioenimil/aws-resource-creation-scripts/aws-automator/internal/config"
)

type ResourceTracker struct {
	Instances      []string `json:"instances"`
	SecurityGroups []string `json:"security_groups"`
	KeyPairs       []string `json:"key_pairs"`
	S3Buckets      []string `json:"s3_buckets"`
}

// PullState downloads state from S3 to local file
func PullState() error {
	if !config.IsRemoteStateEnabled() {
		return nil
	}

	s3Path := fmt.Sprintf("s3://%s/%s", config.S3StateBucket, config.S3StateKey)
	fmt.Printf("📥 Pulling state from %s...\n", s3Path)

	cmd := exec.Command("aws", "s3", "cp", s3Path, config.TrackerFile,
		"--region", config.S3StateRegion)

	output, err := cmd.CombinedOutput()
	if err != nil {
		// Not an error if file doesn't exist yet
		if exitErr, ok := err.(*exec.ExitError); ok && exitErr.ExitCode() == 1 {
			fmt.Println("📝 No remote state found (first run)")
			return nil
		}
		return fmt.Errorf("failed to pull state: %s", string(output))
	}

	fmt.Println("✅ State pulled successfully")
	return nil
}

// PushState uploads local state to S3
func PushState() error {
	if !config.IsRemoteStateEnabled() {
		return nil
	}

	if _, err := os.Stat(config.TrackerFile); os.IsNotExist(err) {
		return fmt.Errorf("no local state file to push")
	}

	s3Path := fmt.Sprintf("s3://%s/%s", config.S3StateBucket, config.S3StateKey)
	fmt.Printf("📤 Pushing state to %s...\n", s3Path)

	cmd := exec.Command("aws", "s3", "cp", config.TrackerFile, s3Path,
		"--region", config.S3StateRegion)

	output, err := cmd.CombinedOutput()
	if err != nil {
		return fmt.Errorf("failed to push state: %s", string(output))
	}

	fmt.Println("✅ State pushed successfully")
	return nil
}

func Load() ResourceTracker {
	var tracker ResourceTracker

	// Auto-pull from S3 if enabled
	if config.IsRemoteStateEnabled() {
		_ = PullState() // Ignore errors, fall back to local
	}

	// Lock on the separate lock file to match Bash implementation
	lockPath := config.TrackerFile + ".lock"
	lockFile, err := os.OpenFile(lockPath, os.O_CREATE|os.O_RDWR, 0666)
	if err == nil {
		defer lockFile.Close()
		syscall.Flock(int(lockFile.Fd()), syscall.LOCK_SH)
		defer syscall.Flock(int(lockFile.Fd()), syscall.LOCK_UN)
	}

	// Open the actual data file
	file, err := os.Open(config.TrackerFile)
	if err != nil {
		// If file doesn't exist, return empty tracker (don't create empty file)
		return tracker
	}
	defer file.Close()

	data, err := io.ReadAll(file)
	if err != nil {
		return tracker
	}

	json.Unmarshal(data, &tracker)
	return tracker
}
