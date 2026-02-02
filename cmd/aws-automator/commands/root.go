package commands

import (
	"fmt"
	"os"

	"github.com/a-ioenimil/aws-resource-creation-scripts/aws-automator/internal/config"
	"github.com/spf13/cobra"
)

var RootCmd = &cobra.Command{
	Use:   "aws-automator",
	Short: "Automate AWS resource creation with Bash scripts",
	Long:  `A CLI tool to orchestrate AWS resource creation scripts for EC2, S3, and Security Groups.`,
}

func Execute() {
	config.Init() // Initialize configuration
	if err := RootCmd.Execute(); err != nil {
		fmt.Println(err)
		os.Exit(1)
	}
}

func init() {
	RootCmd.AddCommand(createCmd)
	RootCmd.AddCommand(cleanupCmd)
	RootCmd.AddCommand(statusCmd)
	RootCmd.AddCommand(interactiveCmd)
	RootCmd.AddCommand(autoCmd)
	RootCmd.AddCommand(planCmd)
	RootCmd.AddCommand(stateCmd)

	createCmd.Flags().StringP("resource", "r", "all", "Resource to create: sg, ec2, s3, or all")
}
