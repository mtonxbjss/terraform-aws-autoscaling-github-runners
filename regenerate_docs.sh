#!/usr/bin/env bash

set -euo pipefail

terraform fmt --recursive .
terraform-docs markdown table --output-file README.md .
terraform-docs markdown table --output-file README.md modules/imagebuilder-github-runner-ami
terraform-docs markdown table --output-file README.md modules/imagebuilder-terraform-container

