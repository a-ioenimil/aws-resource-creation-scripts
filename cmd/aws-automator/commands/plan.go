package commands

import (
	"github.com/a-ioenimil/aws-resource-creation-scripts/aws-automator/internal/aws"
	"github.com/a-ioenimil/aws-resource-creation-scripts/aws-automator/internal/runner"
	"github.com/a-ioenimil/aws-resource-creation-scripts/aws-automator/internal/ui"
	"github.com/spf13/cobra"
)

var planCmd = &cobra.Command{
	Use:   "plan",
	Short: "Preview AWS resource creation (Dry Run)",
	Run:   runPlan,
}

func init() {
	// Register flags for the plan command if needed
	// For now it shares structure with create
	planCmd.Flags().StringP("resource", "r", "all", "Resource to plan (sg, ec2, s3, all)")
}

func runPlan(cmd *cobra.Command, args []string) {
	ui.Cyan.Println("🔍 Generating execution plan...\n")

	if !aws.CheckCredentials() {
		ui.Red.Println("❌ AWS credentials not configured!")
		return
	}

	resource, _ := cmd.Flags().GetString("resource")
	dryRunFlag := "--dry-run"

	switch resource {
	case "sg":
		runner.ExecuteScript("create_security_group.sh", dryRunFlag)
	case "ec2":
		runner.ExecuteScript("create_ec2.sh", dryRunFlag)
	case "s3":
		runner.ExecuteScript("create_s3_bucket.sh", dryRunFlag)
	case "all":
		// For 'all', we run the auto sequence but with dry-run
		runAutoPlan()
	default:
		ui.Red.Printf("❌ Unknown resource type: %s\n", resource)
	}
}

func runAutoPlan() {
	steps := []struct {
		name   string
		script string
		emoji  string
	}{
		{"Firewall Rules (Security Group)", "create_security_group.sh", "🛡️ "},
		{"SSH Key & EC2 Instance", "create_ec2.sh", "🖥️ "},
		{"S3 Bucket", "create_s3_bucket.sh", "🪣 "},
	}

	for i, step := range steps {
		ui.Cyan.Printf("\n[%d/%d] %s Planning %s...\n", i+1, len(steps), step.emoji, step.name)
		if !runner.ExecuteScript(step.script, "--dry-run") {
			ui.Red.Printf("❌ Failed to generate plan for %s.\n", step.name)
			return
		}
	}
	ui.Green.Println("\n✅ Plan generation complete.")
}
