package commands

import (
	"fmt"
	"time"

	"github.com/a-ioenimil/aws-resource-creation-scripts/aws-automator/internal/aws"
	"github.com/a-ioenimil/aws-resource-creation-scripts/aws-automator/internal/runner"
	"github.com/a-ioenimil/aws-resource-creation-scripts/aws-automator/internal/ui"
	"github.com/spf13/cobra"
)

var autoCmd = &cobra.Command{
	Use:   "auto",
	Short: "Automatically create all resources in order",
	Run:   runAuto,
}

func runAuto(cmd *cobra.Command, args []string) {
	ui.Cyan.Println("\n🚀 Starting automated AWS resource creation...")

	if !aws.CheckCredentials() {
		ui.Red.Println("❌ AWS credentials not configured!")
		fmt.Println("\nRun: aws configure")
		return
	}

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
		ui.Cyan.Printf("\n[%d/%d] %s Creating %s...\n", i+1, len(steps), step.emoji, step.name)
		if !runner.ExecuteScript(step.script) {
			ui.Red.Printf("❌ Failed to create %s. Aborting...\n", step.name)
			return
		}
		time.Sleep(2 * time.Second)
	}

	ui.Green.Println("\n✅ All resources created successfully!")
	runStatus(cmd, args)
}
