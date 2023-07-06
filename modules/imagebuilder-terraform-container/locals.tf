locals {
  imagebuilder_components = toset([
    "common_packages",
    "tfenv",
    "kubectl"
  ])

  resource_tags = merge(
    {
      "TfModule" : "mtonxbjss/terraform-aws-autoscaling-github-runners//modules/imagebuilder-terraform-container",
    },
    var.resource_tags
  )
}
