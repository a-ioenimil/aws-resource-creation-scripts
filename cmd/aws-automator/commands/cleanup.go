package commands

import (
	"strings"

	"github.com/a-ioenimil/aws-resource-creation-scripts/aws-automator/internal/runner"
	"github.com/a-ioenimil/aws-resource-creation-scripts/aws-automator/internal/ui"
	"github.com/manifoldco/promptui"
	"github.com/spf13/cobra"
)

var cleanupCmd = &cobra.Command{
	Use:   "cleanup",
	Short: "Cleanup all created AWS resources",
	Run:   runCleanup,
}

func runCleanup(cmd *cobra.Command, args []string) {
	ui.Yellow.Println("\n⚠️  WARNING: This will delete all created resources!")

	prompt := promptui.Prompt{
		Label:     "Are you sure you want to proceed",
		IsConfirm: true,
	}

	result, err := prompt.Run()

	if err != nil || strings.ToLower(result) != "y" {
		ui.Cyan.Println("Cleanup cancelled.")
		return
	}

	ui.Cyan.Println("\n🧹 Cleaning up resources...")
	runner.Cleanup(true)
}
