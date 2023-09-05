# #@filename_check_ignore - file contains multiple policies of equal importance so plural filename is ok

locals {
  scale_out_concurrency = (var.ec2_maximum_concurrent_github_jobs * -1)
  scale_out_threshold   = (var.ec2_maximum_concurrent_github_jobs * -1)
  scale_in_concurrency  = var.ec2_maximum_concurrent_github_jobs
  scale_in_threshold    = var.ec2_maximum_concurrent_github_jobs * 3
}

resource "aws_autoscaling_policy" "dynamic_scale_out" {
  count                     = var.ec2_dynamic_scaling_enabled ? 1 : 0
  name                      = "${var.unique_prefix}-dynamic-scale-out"
  autoscaling_group_name    = aws_autoscaling_group.github_runner.name
  adjustment_type           = "ChangeInCapacity"
  policy_type               = "StepScaling"
  metric_aggregation_type   = "Average"
  estimated_instance_warmup = 180

  step_adjustment {
    scaling_adjustment          = 2                                                             # scale out 2 instances if underprovisioned by
    metric_interval_upper_bound = ""                                                            # up to
    metric_interval_lower_bound = (2 * local.scale_out_concurrency) + local.scale_out_threshold # 2x concurrency
  }
  step_adjustment {
    scaling_adjustment          = 4                                                             # scale out 4 instances if underprovisioned by
    metric_interval_upper_bound = (2 * local.scale_out_concurrency) + local.scale_out_threshold # between 2x concurrency
    metric_interval_lower_bound = (6 * local.scale_out_concurrency) + local.scale_out_threshold # and 6x concurrency
  }
  step_adjustment {
    scaling_adjustment          = 6                                                             # scale out 6 instances if underprovisioned by
    metric_interval_upper_bound = (6 * local.scale_out_concurrency) + local.scale_out_threshold # between 6x concurrency
    metric_interval_lower_bound = (8 * local.scale_out_concurrency) + local.scale_out_threshold # and 8x concurrency
  }
  step_adjustment {
    scaling_adjustment          = 8                                                             # scale out 8 instances if underprovisioned by
    metric_interval_upper_bound = (8 * local.scale_out_concurrency) + local.scale_out_threshold # 8x concurrency
    metric_interval_lower_bound = ""                                                            # or more
  }
}

resource "aws_autoscaling_policy" "dynamic_scale_in" {
  count                   = var.ec2_dynamic_scaling_enabled ? 1 : 0
  name                    = "${var.unique_prefix}-dynamic-scale-in"
  autoscaling_group_name  = aws_autoscaling_group.github_runner.name
  adjustment_type         = "ChangeInCapacity"
  policy_type             = "StepScaling"
  metric_aggregation_type = "Average"

  step_adjustment {
    scaling_adjustment          = -1                                                          # scale in 1 instances if overprovisioned by
    metric_interval_lower_bound = ""                                                          # up to
    metric_interval_upper_bound = (5 * local.scale_in_concurrency) - local.scale_in_threshold # 5x concurrency
  }
  step_adjustment {
    scaling_adjustment          = -2                                                          # scale in 2 instances if overprovisioned by
    metric_interval_lower_bound = (5 * local.scale_in_concurrency) - local.scale_in_threshold # between 5x concurrency
    metric_interval_upper_bound = (8 * local.scale_in_concurrency) - local.scale_in_threshold # and 8x concurrency
  }
  step_adjustment {
    scaling_adjustment          = -3                                                          # scale in 3 instances if overprovisioned by
    metric_interval_lower_bound = (8 * local.scale_in_concurrency) - local.scale_in_threshold # 8x concurrency
    metric_interval_upper_bound = ""                                                          # or higher
  }
}

resource "aws_cloudwatch_metric_alarm" "dynamic_scale_out_free_capacity" {
  count               = var.ec2_dynamic_scaling_enabled ? 1 : 0
  alarm_name          = "${var.unique_prefix}-${var.ec2_github_runner_name}-dynamic-scale-out-fc"
  alarm_description   = "AUTOSCALING: Drives the dynamic scaling out (adding instances) of the github runners based on the amount of free capacity"
  evaluation_periods  = "5"                                    // within the 5 most recent periods
  comparison_operator = "LessThanThreshold"                    // scale out if the "free capacity" metric is less than
  threshold           = var.ec2_maximum_concurrent_github_jobs // the concurrency of a single runner
  datapoints_to_alarm = "2"                                    // in 2 of those 5 evaluated periods
  treat_missing_data  = "notBreaching"                         // (treat missing data as free capacity = 0)

  actions_enabled = "true"
  ok_actions      = []
  alarm_actions = [
    aws_autoscaling_policy.dynamic_scale_out.0.arn
  ]

  metric_query {
    id          = "fc"
    expression  = "(ar*${var.ec2_maximum_concurrent_github_jobs})-(rj+qj)"
    label       = "Free GitHub Capacity"
    return_data = "true"
  }

  metric_query {
    id    = "ar"
    label = "Active Runners"
    metric {
      stat        = "Average"                 // the average of
      namespace   = "AWS/AutoScaling"         // the AWS/AutoScaling
      metric_name = "GroupInServiceInstances" // GroupInServiceInstances metric
      period      = "60"                      // over 60 seconds (1 min)
      dimensions = {
        AutoScalingGroupName = aws_autoscaling_group.github_runner.name
      }
    }
  }

  metric_query {
    id    = "rj"
    label = "Running Jobs"
    metric {
      stat        = "Maximum"                                      // the average of
      namespace   = local.cloudwatch_logs_metric_filters_namespace // the custom
      metric_name = "githubRunning"                                // githubRunning metric
      period      = "60"                                           // over 60 seconds (1 min)
      dimensions = {
        Tag = var.ec2_github_runner_tag_list
      }
    }
  }

  metric_query {
    id    = "qj"
    label = "Queued Jobs"
    metric {
      stat        = "Maximum"                                      // the average of
      namespace   = local.cloudwatch_logs_metric_filters_namespace // the custom
      metric_name = "githubQueued"                                 // githubPending metric
      period      = "60"                                           // over 60 seconds (1 min)
      dimensions = {
        Tag = var.ec2_github_runner_tag_list
      }
    }
  }
}

resource "aws_cloudwatch_metric_alarm" "dynamic_scale_in_free_capacity" {
  count               = var.ec2_dynamic_scaling_enabled ? 1 : 0
  alarm_name          = "${var.unique_prefix}-${var.ec2_github_runner_name}-dynamic-scale-in-fc"
  alarm_description   = "AUTOSCALING: Drives the dynamic scaling in (removing instances) of the github runners based on the amount of free capacity"
  evaluation_periods  = "10"                                                                           // within the 10 most recent periods
  comparison_operator = "GreaterThanOrEqualToThreshold"                                                // scale in if the "free capacity" metric is greater than or equal to
  threshold           = var.ec2_maximum_concurrent_github_jobs * var.ec2_autoscaling_minimum_instances // (minimum instances)x the concurrency of a single runner
  datapoints_to_alarm = "10"                                                                           // in all 10 of those 10 evaluated periods
  treat_missing_data  = "notBreaching"                                                                 // (treat missing data as free capacity = 0)

  actions_enabled = "true"
  ok_actions      = []
  alarm_actions = [
    aws_autoscaling_policy.dynamic_scale_in.0.arn
  ]

  metric_query {
    id          = "fc"
    expression  = "(ar*${var.ec2_maximum_concurrent_github_jobs})-(rj+qj)"
    label       = "Free GitHub Capacity"
    return_data = "true"
  }

  metric_query {
    id    = "ar"
    label = "Active Runners"
    metric {
      stat        = "Average"                 // the average of
      namespace   = "AWS/AutoScaling"         // the AWS/AutoScaling
      metric_name = "GroupInServiceInstances" // GroupInServiceInstances metric
      period      = "60"                      // over 60 seconds (1 mins)
      dimensions = {
        AutoScalingGroupName = aws_autoscaling_group.github_runner.name
      }
    }
  }

  metric_query {
    id    = "rj"
    label = "Running Jobs"
    metric {
      stat        = "Maximum"                                      // the average of
      namespace   = local.cloudwatch_logs_metric_filters_namespace // the custom
      metric_name = "githubRunning"                                // githubRunning metric
      period      = "60"                                           // over 60 seconds (1 mins)
      dimensions = {
        Tag = var.ec2_github_runner_tag_list
      }
    }
  }

  metric_query {
    id    = "qj"
    label = "Queued Jobs"
    metric {
      stat        = "Sum"                                          // the average of
      namespace   = local.cloudwatch_logs_metric_filters_namespace // the custom
      metric_name = "githubQueued"                                 // githubPending metric
      period      = "60"                                           // over 60 seconds (1 mins)
      dimensions = {
        Tag = var.ec2_github_runner_tag_list
      }
    }
  }
}
