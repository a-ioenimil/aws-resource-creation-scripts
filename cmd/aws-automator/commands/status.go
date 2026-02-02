package commands

import (
	"fmt"

	"github.com/a-ioenimil/aws-resource-creation-scripts/aws-automator/internal/tracker"
	"github.com/a-ioenimil/aws-resource-creation-scripts/aws-automator/internal/ui"
	"github.com/spf13/cobra"
)

var statusCmd = &cobra.Command{
	Use:   "status",
	Short: "Show status of created resources",
	Run:   runStatus,
}

func runStatus(cmd *cobra.Command, args []string) {
	ui.Cyan.Println("\n📊 Resource Status")
	t := tracker.Load()

	fmt.Println("┌─────────────────────┬───────┬────────────────────────────┐")
	fmt.Println("│ Resource Type       │ Count │ IDs                        │")
	fmt.Println("├─────────────────────┼───────┼────────────────────────────┤")
	ui.PrintResourceRow("EC2 Instances", t.Instances)
	ui.PrintResourceRow("Security Groups", t.SecurityGroups)
	ui.PrintResourceRow("Key Pairs", t.KeyPairs)
	ui.PrintResourceRow("S3 Buckets", t.S3Buckets)
	fmt.Println("└─────────────────────┴───────┴────────────────────────────┘")
}
