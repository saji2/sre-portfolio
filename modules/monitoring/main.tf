#------------------------------------------------------------------------------
# Monitoring Module
# CloudWatch alarms, SNS notifications, and log groups
#------------------------------------------------------------------------------

#------------------------------------------------------------------------------
# SNS Topic for Alerts
#------------------------------------------------------------------------------
resource "aws_sns_topic" "alerts" {
  name = "${var.project_name}-alerts"

  tags = var.tags
}

resource "aws_sns_topic_policy" "alerts" {
  arn = aws_sns_topic.alerts.arn

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AllowCloudWatchAlarms"
        Effect = "Allow"
        Principal = {
          Service = "cloudwatch.amazonaws.com"
        }
        Action   = "sns:Publish"
        Resource = aws_sns_topic.alerts.arn
      }
    ]
  })
}

resource "aws_sns_topic_subscription" "email" {
  count     = var.alert_email != "" ? 1 : 0
  topic_arn = aws_sns_topic.alerts.arn
  protocol  = "email"
  endpoint  = var.alert_email
}

#------------------------------------------------------------------------------
# CloudWatch Log Groups for EKS
#------------------------------------------------------------------------------
resource "aws_cloudwatch_log_group" "eks_cluster" {
  name              = "/aws/eks/${var.cluster_name}/cluster"
  retention_in_days = var.log_retention_days

  tags = var.tags
}

resource "aws_cloudwatch_log_group" "application" {
  name              = "/aws/eks/${var.cluster_name}/application/api-service"
  retention_in_days = var.log_retention_days

  tags = var.tags
}

resource "aws_cloudwatch_log_group" "frontend" {
  name              = "/aws/eks/${var.cluster_name}/application/frontend-service"
  retention_in_days = var.log_retention_days

  tags = var.tags
}

resource "aws_cloudwatch_log_group" "kube_system" {
  name              = "/aws/eks/${var.cluster_name}/system/kube-system"
  retention_in_days = var.log_retention_days

  tags = var.tags
}

#------------------------------------------------------------------------------
# CloudWatch Dashboard
#------------------------------------------------------------------------------
resource "aws_cloudwatch_dashboard" "main" {
  dashboard_name = "${var.project_name}-dashboard"

  dashboard_body = jsonencode({
    widgets = [
      {
        type   = "text"
        x      = 0
        y      = 0
        width  = 24
        height = 1
        properties = {
          markdown = "# ${var.project_name} Infrastructure Dashboard"
        }
      },
      {
        type   = "metric"
        x      = 0
        y      = 1
        width  = 8
        height = 6
        properties = {
          title  = "EKS Cluster - Node CPU Utilization"
          region = var.aws_region
          metrics = [
            ["AWS/EC2", "CPUUtilization", { stat = "Average", period = 300 }]
          ]
          view = "timeSeries"
        }
      },
      {
        type   = "metric"
        x      = 8
        y      = 1
        width  = 8
        height = 6
        properties = {
          title  = "RDS - CPU Utilization"
          region = var.aws_region
          metrics = var.rds_instance_identifier != "" ? [
            ["AWS/RDS", "CPUUtilization", "DBInstanceIdentifier", var.rds_instance_identifier, { stat = "Average", period = 300 }]
          ] : []
          view = "timeSeries"
        }
      },
      {
        type   = "metric"
        x      = 16
        y      = 1
        width  = 8
        height = 6
        properties = {
          title  = "RDS - Database Connections"
          region = var.aws_region
          metrics = var.rds_instance_identifier != "" ? [
            ["AWS/RDS", "DatabaseConnections", "DBInstanceIdentifier", var.rds_instance_identifier, { stat = "Average", period = 300 }]
          ] : []
          view = "timeSeries"
        }
      },
      {
        type   = "metric"
        x      = 0
        y      = 7
        width  = 8
        height = 6
        properties = {
          title  = "RDS - Free Storage Space"
          region = var.aws_region
          metrics = var.rds_instance_identifier != "" ? [
            ["AWS/RDS", "FreeStorageSpace", "DBInstanceIdentifier", var.rds_instance_identifier, { stat = "Average", period = 300 }]
          ] : []
          view = "timeSeries"
        }
      },
      {
        type   = "metric"
        x      = 8
        y      = 7
        width  = 8
        height = 6
        properties = {
          title  = "ElastiCache - CPU Utilization"
          region = var.aws_region
          metrics = var.elasticache_cluster_id != "" ? [
            ["AWS/ElastiCache", "CPUUtilization", "CacheClusterId", var.elasticache_cluster_id, { stat = "Average", period = 300 }]
          ] : []
          view = "timeSeries"
        }
      },
      {
        type   = "metric"
        x      = 16
        y      = 7
        width  = 8
        height = 6
        properties = {
          title  = "ElastiCache - Cache Hit Rate"
          region = var.aws_region
          metrics = var.elasticache_cluster_id != "" ? [
            ["AWS/ElastiCache", "CacheHitRate", "CacheClusterId", var.elasticache_cluster_id, { stat = "Average", period = 300 }]
          ] : []
          view = "timeSeries"
        }
      },
      {
        type   = "metric"
        x      = 0
        y      = 13
        width  = 12
        height = 6
        properties = {
          title  = "ALB - Request Count"
          region = var.aws_region
          metrics = var.alb_arn_suffix != "" ? [
            ["AWS/ApplicationELB", "RequestCount", "LoadBalancer", var.alb_arn_suffix, { stat = "Sum", period = 60 }]
          ] : []
          view = "timeSeries"
        }
      },
      {
        type   = "metric"
        x      = 12
        y      = 13
        width  = 12
        height = 6
        properties = {
          title  = "ALB - Target Response Time"
          region = var.aws_region
          metrics = var.alb_arn_suffix != "" ? [
            ["AWS/ApplicationELB", "TargetResponseTime", "LoadBalancer", var.alb_arn_suffix, { stat = "p95", period = 60 }]
          ] : []
          view = "timeSeries"
        }
      }
    ]
  })
}

#------------------------------------------------------------------------------
# CloudWatch Alarms - EKS
#------------------------------------------------------------------------------
resource "aws_cloudwatch_metric_alarm" "eks_cluster_failed_node_count" {
  count               = var.create_eks_alarms ? 1 : 0
  alarm_name          = "${var.project_name}-eks-failed-node-count"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "cluster_failed_node_count"
  namespace           = "ContainerInsights"
  period              = 300
  statistic           = "Average"
  threshold           = 0
  alarm_description   = "EKS cluster has failed nodes"
  alarm_actions       = [aws_sns_topic.alerts.arn]
  ok_actions          = [aws_sns_topic.alerts.arn]

  dimensions = {
    ClusterName = var.cluster_name
  }

  tags = var.tags
}

#------------------------------------------------------------------------------
# CloudWatch Alarms - ALB
#------------------------------------------------------------------------------
resource "aws_cloudwatch_metric_alarm" "alb_5xx_errors" {
  count               = var.create_alb_alarms && var.alb_arn_suffix != "" ? 1 : 0
  alarm_name          = "${var.project_name}-alb-5xx-errors"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 3
  metric_name         = "HTTPCode_Target_5XX_Count"
  namespace           = "AWS/ApplicationELB"
  period              = 60
  statistic           = "Sum"
  threshold           = var.alb_5xx_threshold
  alarm_description   = "ALB is returning 5xx errors"
  alarm_actions       = [aws_sns_topic.alerts.arn]
  ok_actions          = [aws_sns_topic.alerts.arn]
  treat_missing_data  = "notBreaching"

  dimensions = {
    LoadBalancer = var.alb_arn_suffix
  }

  tags = var.tags
}

resource "aws_cloudwatch_metric_alarm" "alb_target_response_time" {
  count               = var.create_alb_alarms && var.alb_arn_suffix != "" ? 1 : 0
  alarm_name          = "${var.project_name}-alb-response-time"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 3
  metric_name         = "TargetResponseTime"
  namespace           = "AWS/ApplicationELB"
  period              = 60
  extended_statistic  = "p95"
  threshold           = var.alb_response_time_threshold
  alarm_description   = "ALB target response time is high (P95)"
  alarm_actions       = [aws_sns_topic.alerts.arn]
  ok_actions          = [aws_sns_topic.alerts.arn]

  dimensions = {
    LoadBalancer = var.alb_arn_suffix
  }

  tags = var.tags
}

resource "aws_cloudwatch_metric_alarm" "alb_unhealthy_hosts" {
  count               = var.create_alb_alarms && var.alb_target_group_arn_suffix != "" ? 1 : 0
  alarm_name          = "${var.project_name}-alb-unhealthy-hosts"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "UnHealthyHostCount"
  namespace           = "AWS/ApplicationELB"
  period              = 60
  statistic           = "Average"
  threshold           = 0
  alarm_description   = "ALB has unhealthy target hosts"
  alarm_actions       = [aws_sns_topic.alerts.arn]
  ok_actions          = [aws_sns_topic.alerts.arn]

  dimensions = {
    LoadBalancer = var.alb_arn_suffix
    TargetGroup  = var.alb_target_group_arn_suffix
  }

  tags = var.tags
}

#------------------------------------------------------------------------------
# IAM Role for Fluent Bit (IRSA)
#------------------------------------------------------------------------------
resource "aws_iam_role" "fluent_bit" {
  count = var.create_fluent_bit_role ? 1 : 0
  name  = "${var.project_name}-fluent-bit-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRoleWithWebIdentity"
      Effect = "Allow"
      Principal = {
        Federated = var.oidc_provider_arn
      }
      Condition = {
        StringEquals = {
          "${replace(var.oidc_provider_url, "https://", "")}:sub" = "system:serviceaccount:${var.fluent_bit_namespace}:${var.fluent_bit_service_account}"
          "${replace(var.oidc_provider_url, "https://", "")}:aud" = "sts.amazonaws.com"
        }
      }
    }]
  })

  tags = var.tags
}

resource "aws_iam_role_policy" "fluent_bit" {
  count = var.create_fluent_bit_role ? 1 : 0
  name  = "${var.project_name}-fluent-bit-policy"
  role  = aws_iam_role.fluent_bit[0].id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogStream",
          "logs:CreateLogGroup",
          "logs:PutLogEvents",
          "logs:DescribeLogStreams",
          "logs:DescribeLogGroups"
        ]
        Resource = "*"
      }
    ]
  })
}
