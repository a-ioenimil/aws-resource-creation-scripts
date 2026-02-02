package commands

import (
	"fmt"
	"strings"

	"github.com/a-ioenimil/aws-resource-creation-scripts/aws-automator/internal/aws"
	"github.com/a-ioenimil/aws-resource-creation-scripts/aws-automator/internal/runner"
	"github.com/a-ioenimil/aws-resource-creation-scripts/aws-automator/internal/ui"
	"github.com/manifoldco/promptui"
	"github.com/spf13/cobra"
)

var interactiveCmd = &cobra.Command{
	Use:   "interactive",
	Short: "Interactive mode to select resources to create",
	Run:   runInteractive,
}

func runInteractive(cmd *cobra.Command, args []string) {
	ui.Cyan.Println("\n🎯 AWS Resource Creator - Interactive Mode")

	if !aws.CheckCredentials() {
		ui.Red.Println("❌ AWS credentials not configured!")
		fmt.Println("Please run 'aws configure' first.")
		return
	}

	resources := []string{
		"Security Group (SSH + HTTP)",
		"EC2 Instance (Amazon Linux 2)",
		"S3 Bucket (with versioning)",
		"All Resources (Automated)",
		"View Status",
		"Cleanup All",
		"Exit",
	}

	prompt := promptui.Select{
		Label: "Select an action",
		Items: resources,
		Size:  7,
	}

	for {
		_, result, err := prompt.Run()

		if err != nil {
			return
		}

		switch {
		case strings.Contains(result, "Security Group"):
			runner.ExecuteScript("create_security_group.sh")
		case strings.Contains(result, "EC2 Instance"):
			runner.ExecuteScript("create_ec2.sh")
		case strings.Contains(result, "S3 Bucket"):
			runner.ExecuteScript("create_s3_bucket.sh")
		case strings.Contains(result, "All Resources"):
			runAuto(cmd, args)
		case strings.Contains(result, "View Status"):
			runStatus(cmd, args)
		case strings.Contains(result, "Cleanup"):
			runCleanup(cmd, args)
		case strings.Contains(result, "Exit"):
			ui.Cyan.Println("\n👋 Goodbye!")
			return
		}

		fmt.Println()
	}
}
