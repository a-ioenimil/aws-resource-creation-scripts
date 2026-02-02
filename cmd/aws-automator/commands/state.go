package commands

import (
	"fmt"

	"github.com/a-ioenimil/aws-resource-creation-scripts/aws-automator/internal/config"
	"github.com/a-ioenimil/aws-resource-creation-scripts/aws-automator/internal/runner"
	"github.com/a-ioenimil/aws-resource-creation-scripts/aws-automator/internal/tracker"
	"github.com/a-ioenimil/aws-resource-creation-scripts/aws-automator/internal/ui"
	"github.com/spf13/cobra"
)

var stateCmd = &cobra.Command{
	Use:   "state",
	Short: "Manage remote state backend",
	Long:  `Commands for managing the S3 remote state backend for infrastructure tracking.`,
}

var stateInitCmd = &cobra.Command{
	Use:   "init",
	Short: "Initialize S3 state bucket",
	Run:   runStateInit,
}

var statePullCmd = &cobra.Command{
	Use:   "pull",
	Short: "Pull state from S3 to local",
	Run:   runStatePull,
}

var statePushCmd = &cobra.Command{
	Use:   "push",
	Short: "Push local state to S3",
	Run:   runStatePush,
}

var stateShowCmd = &cobra.Command{
	Use:   "show",
	Short: "Show remote state configuration",
	Run:   runStateShow,
}

func init() {
	stateCmd.AddCommand(stateInitCmd)
	stateCmd.AddCommand(statePullCmd)
	stateCmd.AddCommand(statePushCmd)
	stateCmd.AddCommand(stateShowCmd)

	stateInitCmd.Flags().StringP("bucket", "b", "", "S3 bucket name (required)")
	stateInitCmd.Flags().StringP("region", "r", "", "AWS region")
	stateInitCmd.MarkFlagRequired("bucket")
}

func runStateInit(cmd *cobra.Command, args []string) {
	bucket, _ := cmd.Flags().GetString("bucket")
	region, _ := cmd.Flags().GetString("region")

	ui.Cyan.Println("🪣 Initializing S3 state bucket...")

	scriptArgs := []string{"--bucket", bucket}
	if region != "" {
		scriptArgs = append(scriptArgs, "--region", region)
	}

	runner.ExecuteScript("init_state.sh", scriptArgs...)
}

func runStatePull(cmd *cobra.Command, args []string) {
	if !config.IsRemoteStateEnabled() {
		ui.Yellow.Println("⚠️  Remote state is not configured.")
		fmt.Println("\nTo enable remote state, set S3_STATE_BUCKET in your .env file:")
		fmt.Println("  S3_STATE_BUCKET=your-bucket-name")
		return
	}

	err := tracker.PullState()
	if err != nil {
		ui.Red.Printf("❌ %v\n", err)
		return
	}
}

func runStatePush(cmd *cobra.Command, args []string) {
	if !config.IsRemoteStateEnabled() {
		ui.Yellow.Println("⚠️  Remote state is not configured.")
		fmt.Println("\nTo enable remote state, set S3_STATE_BUCKET in your .env file:")
		fmt.Println("  S3_STATE_BUCKET=your-bucket-name")
		return
	}

	err := tracker.PushState()
	if err != nil {
		ui.Red.Printf("❌ %v\n", err)
		return
	}
}

func runStateShow(cmd *cobra.Command, args []string) {
	ui.Cyan.Println("🔧 Remote State Configuration\n")

	if config.IsRemoteStateEnabled() {
		ui.Green.Println("Status: ✅ Enabled")
		fmt.Printf("  Bucket:  %s\n", config.S3StateBucket)
		fmt.Printf("  Key:     %s\n", config.S3StateKey)
		fmt.Printf("  Region:  %s\n", config.S3StateRegion)
		fmt.Printf("  S3 URI:  s3://%s/%s\n", config.S3StateBucket, config.S3StateKey)
	} else {
		ui.Yellow.Println("Status: ⚠️  Disabled (local state only)")
		fmt.Println("\nTo enable remote state, add to your .env file:")
		fmt.Println("  S3_STATE_BUCKET=your-bucket-name")
		fmt.Println("  S3_STATE_KEY=state/created_resources.json")
		fmt.Println("  S3_STATE_REGION=us-east-1")
	}
}
