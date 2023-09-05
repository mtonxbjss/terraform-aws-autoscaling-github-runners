resource "aws_cloudwatch_dashboard" "account" {
  dashboard_name = "${var.unique_prefix}-${var.ec2_github_runner_name}"

  # These variables must be the superset of all variables required by the cohort explorer dashboards
  dashboard_body = templatefile(
    "${path.module}/templates/github_dashboard_template.tmpl.json",
    {
      RUNNER_NAME               = var.ec2_github_runner_name
      UPPER_RUNNER_NAME         = upper(var.ec2_github_runner_name)
      AUTOSCALING_GROUP_NAME    = aws_autoscaling_group.github_runner.name
      METRICS_NAMESPACE         = local.cloudwatch_logs_metric_filters_namespace
      INSTANCE_TYPE             = var.ec2_instance_type
      TAG_LIST                  = var.ec2_github_runner_tag_list
      CONCURRENT_JOBS           = var.ec2_maximum_concurrent_github_jobs
      SCALE_IN_AT_FREE_CAPACITY = var.ec2_maximum_concurrent_github_jobs * var.ec2_autoscaling_minimum_instances
      Y_AXIS_MIN                = var.ec2_maximum_concurrent_github_jobs * (var.ec2_autoscaling_maximum_instances * -1)
      Y_AXIS_MAX                = var.ec2_maximum_concurrent_github_jobs * var.ec2_autoscaling_maximum_instances
    }
  )
}
