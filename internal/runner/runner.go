package runner

import (
	"os"
	"os/exec"
	"path/filepath"

	"github.com/a-ioenimil/aws-resource-creation-scripts/aws-automator/internal/config"
	"github.com/a-ioenimil/aws-resource-creation-scripts/aws-automator/internal/ui"
)

func ExecuteScript(scriptName string) bool {
	scriptPath := filepath.Join(config.ScriptsDir, scriptName)
	if _, err := os.Stat(scriptPath); os.IsNotExist(err) {
		ui.Red.Printf("❌ Script not found: %s\n", scriptPath)
		return false
	}

	command := exec.Command("bash", scriptPath)
	command.Dir = config.ProjectRoot
	command.Stdout = os.Stdout
	command.Stderr = os.Stderr
	command.Env = os.Environ() // Pass current environment

	if err := command.Run(); err != nil {
		ui.Red.Printf("❌ Script execution failed: %s\n", scriptName)
		return false
	}
	return true
}

func Cleanup(force bool) {
	scriptPath := filepath.Join(config.ScriptsDir, "cleanup_resources.sh")

	args := []string{scriptPath}
	if force {
		args = append(args, "--force")
	}

	command := exec.Command("bash", args...)
	command.Dir = config.ProjectRoot
	command.Stdout = os.Stdout
	command.Stderr = os.Stderr

	if err := command.Run(); err != nil {
		ui.Red.Println("❌ Cleanup failed")
	} else {
		ui.Green.Println("✅ Cleanup completed successfully!")
	}
}
