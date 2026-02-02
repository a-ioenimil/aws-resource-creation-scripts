package commands

import (
	"fmt"

	"github.com/a-ioenimil/aws-resource-creation-scripts/aws-automator/internal/aws"
	"github.com/a-ioenimil/aws-resource-creation-scripts/aws-automator/internal/runner"
	"github.com/a-ioenimil/aws-resource-creation-scripts/aws-automator/internal/ui"
	"github.com/spf13/cobra"
)

var createCmd = &cobra.Command{
	Use:   "create",
	Short: "Create AWS resources",
	Run:   runCreate,
}

func runCreate(cmd *cobra.Command, args []string) {
	if !aws.CheckCredentials() {
		ui.Red.Println("❌ AWS credentials not configured!")
		fmt.Println("Please run 'aws configure' first.")
		return
	}

	resource, _ := cmd.Flags().GetString("resource")
	switch resource {
	case "sg":
		runner.ExecuteScript("create_security_group.sh")
	case "ec2":
		runner.ExecuteScript("create_ec2.sh")
	case "s3":
		runner.ExecuteScript("create_s3_bucket.sh")
	case "all":
		runAuto(cmd, args)
	default:
		ui.Red.Printf("❌ Unknown resource type: %s\n", resource)
	}
}
