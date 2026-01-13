package aws

import (
	"os/exec"
)

func CheckCredentials() bool {
	cmd := exec.Command("aws", "sts", "get-caller-identity")
	if err := cmd.Run(); err != nil {
		return false
	}
	return true
}
