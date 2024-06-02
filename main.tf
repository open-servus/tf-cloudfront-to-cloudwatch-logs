// Converting sw.template to Terraform!
// Existing Terraform src code found at /tmp/terraform_src.

data "aws_region" "current" {}

data "aws_caller_identity" "current" {}

variable "notification_bucket" {
  description = "Name of the S3 bucket where we are storing our CloudFront Logs. S3 Bucket should be in the same region that this template is deployed in. ex. my-logging-bucket"
  type        = string
}

variable "cf_log_prefix_parameter" {
  description = "Select the S3 prefix where CloudFront Logs are being written. ex. logs/"
  type        = string
}

variable "contributor_insight_rule_state" {
  description = "Select to enable or disable the Contributor Insight Rules on Creation."
  type        = string
  default     = "ENABLED"
}

variable "cf_distribution_id" {
  description = "Select the CF DistributioID - this will be used to pull metrics for a CF Dashboard, naming of the Log Group, and Namespace for our Metric Filters - ex. EDFDVBD6EXAMPLE"
  type        = string
}

resource "aws_cloudwatch_log_group" "cloud_watch_log_group" {
  name = "cloudfront/${var.cf_distribution_id}"
}

resource "aws_lambda_function" "c_fto_cw_log_function" {

  s3_bucket = "mng-blog-solutions"
  s3_key    = "cloudfront-to-cloudwatch-blog/lambda_function.zip"

  handler       = "lambda_function.lambda_handler"
  role          = aws_iam_role.lambda_iam_role_cw.arn
  runtime       = "python3.8"
  timeout       = 30
  function_name = "CF-to-CW-Log-Function-${var.cf_distribution_id}"
  environment {
    variables = {
      LOG_GROUP_NAME = aws_cloudwatch_log_group.cloud_watch_log_group.arn
    }
  }
  description = "Lambda Function which takes CF logs from S3, and writes them to a CW Log group defined in env variables"
}

resource "aws_lambda_permission" "lambda_invoke_permission" {
  function_name  = aws_lambda_function.c_fto_cw_log_function.arn
  action         = "lambda:InvokeFunction"
  principal      = "s3.amazonaws.com"
  source_account = data.aws_caller_identity.current.account_id
  source_arn     = "arn:aws:s3:::${var.notification_bucket}"
}

resource "aws_iam_role" "lambda_iam_role" {
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = [
            "lambda.amazonaws.com"
          ]
        }
        Action = [
          "sts:AssumeRole"
        ]
      }
    ]
  })
  path = "/"
  force_detach_policies = [
    {
      PolicyName = "root"
      PolicyDocument = {
        Version = "2012-10-17"
        Statement = [
          {
            Effect = "Allow"
            Action = [
              "s3:GetBucketNotification",
              "s3:PutBucketNotification"
            ]
            Resource = "arn:aws:s3:::${var.notification_bucket}"
          },
          {
            Effect = "Allow"
            Action = [
              "logs:CreateLogGroup",
              "logs:CreateLogStream",
              "logs:PutLogEvents"
            ]
            Resource = "arn:aws:logs:*:*:*"
          }
        ]
      }
    }
  ]
}

resource "aws_iam_role" "lambda_iam_role_cw" {
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = [
            "lambda.amazonaws.com"
          ]
        }
        Action = [
          "sts:AssumeRole"
        ]
      }
    ]
  })
  path = "/"
  force_detach_policies = [
    {
      PolicyName = "root"
      PolicyDocument = {
        Version = "2012-10-17"
        Statement = [
          {
            Effect = "Allow"
            Action = [
              "s3:GetObject"
            ]
            Resource = "arn:aws:s3:::${var.notification_bucket}/${var.cf_log_prefix_parameter}*"
          },
          {
            Effect = "Allow"
            Action = [
              "logs:CreateLogGroup",
              "logs:CreateLogStream",
              "logs:PutLogEvents"
            ]
            Resource = "arn:aws:logs:*:*:*"
          }
        ]
      }
    }
  ]
}

data "archive_file" "custom_resource_lambda_function" {
  type        = "zip"
  source_dir  = "${path.module}/lambda_code"
  output_path = "${path.module}/custom_resource_lambda_function.zip"
}

resource "aws_lambda_function" "custom_resource_lambda_function" {
  description      = "Lambda Function to modify the S3 event notification for an existing S3 bucket"
  handler          = "index.lambda_handler"
  role             = aws_iam_role.lambda_iam_role.arn
  filename         = data.archive_file.lambda_function_publish_admin_instance_metrics.output_path
  source_code_hash = data.archive_file.lambda_function_publish_admin_instance_metrics.output_base64sha256
  runtime          = "python3.9"
  timeout          = 50
}

resource "aws_codecommit_trigger" "lambda_trigger" {
  // CF Property(ServiceToken) = aws_lambda_function.custom_resource_lambda_function.arn
  // CF Property(LambdaArn) = aws_lambda_function.c_fto_cw_log_function.arn
  // CF Property(Bucket) = var.notification_bucket
  // CF Property(Prefix) = var.cf_log_prefix_parameter
}

resource "aws_cloudwatch_log_metric_filter" "http_metric_filter" {
  log_group_name = aws_cloudwatch_log_group.cloud_watch_log_group.arn
  pattern        = "[date, time, x_edge_location, sc_bytes, c_ip, cs_method, Host, cs_uri_stem, sc_status, cs_referer, cs_User_Agent, us_uri_query, Cookie, x_edge_result_type, x_edge_request_id, x_host_header, cs_protocol=http, cs_bytes, time_taken, x_forwarded_for, ssl_protocol, ssl_cipher, x_edge_response_result_type, cs_protocol_version, fle_status, fle_encrypted_fields, c_port, time_to_first_byte, x_edge_detailed_result_type, sc_content_type, sc_content_len, sc_range_start, sc_range_end ]"
  metric_transformation = [
    {
      MetricValue     = "$time_taken"
      MetricNamespace = aws_cloudwatch_log_group.cloud_watch_log_group.arn
      MetricName      = "HTTP-Requests"
    }
  ]
}

resource "aws_cloudwatch_log_metric_filter" "htt_ps_metric_filter" {
  log_group_name = aws_cloudwatch_log_group.cloud_watch_log_group.arn
  pattern        = "[date, time, x_edge_location, sc_bytes, c_ip, cs_method, Host, cs_uri_stem, sc_status, cs_referer, cs_User_Agent, us_uri_query, Cookie, x_edge_result_type, x_edge_request_id, x_host_header, cs_protocol=https, cs_bytes, time_taken, x_forwarded_for, ssl_protocol, ssl_cipher, x_edge_response_result_type, cs_protocol_version, fle_status, fle_encrypted_fields, c_port, time_to_first_byte, x_edge_detailed_result_type, sc_content_type, sc_content_len, sc_range_start, sc_range_end ]"
  metric_transformation = [
    {
      MetricValue     = "$time_taken"
      MetricNamespace = aws_cloudwatch_log_group.cloud_watch_log_group.arn
      MetricName      = "HTTPS-Requests"
    }
  ]
}

resource "aws_cloudwatch_log_metric_filter" "time_taken_metric_filter" {
  log_group_name = aws_cloudwatch_log_group.cloud_watch_log_group.arn
  pattern        = "[date, time, x_edge_location, sc_bytes, c_ip, cs_method, Host, cs_uri_stem, sc_status, cs_referer, cs_User_Agent, us_uri_query, Cookie, x_edge_result_type, x_edge_request_id, x_host_header, cs_protocol, cs_bytes, time_taken, x_forwarded_for, ssl_protocol, ssl_cipher, x_edge_response_result_type, cs_protocol_version, fle_status, fle_encrypted_fields, c_port, time_to_first_byte, x_edge_detailed_result_type, sc_content_type, sc_content_len, sc_range_start, sc_range_end ]"
  metric_transformation = [
    {
      MetricValue     = "$time_taken"
      MetricNamespace = aws_cloudwatch_log_group.cloud_watch_log_group.arn
      MetricName      = "Time-Taken"
    }
  ]
}

resource "aws_cloudwatch_log_metric_filter" "ttfb_metric_filter" {
  log_group_name = aws_cloudwatch_log_group.cloud_watch_log_group.arn
  pattern        = "[date, time, x_edge_location, sc_bytes, c_ip, cs_method, Host, cs_uri_stem, sc_status, cs_referer, cs_User_Agent, us_uri_query, Cookie, x_edge_result_type, x_edge_request_id, x_host_header, cs_protocol, cs_bytes, time_taken, x_forwarded_for, ssl_protocol, ssl_cipher, x_edge_response_result_type, cs_protocol_version, fle_status, fle_encrypted_fields, c_port, time_to_first_byte, x_edge_detailed_result_type, sc_content_type, sc_content_len, sc_range_start, sc_range_end ]"
  metric_transformation = [
    {
      MetricValue     = "$time_to_first_byte"
      MetricNamespace = aws_cloudwatch_log_group.cloud_watch_log_group.arn
      MetricName      = "Time-to-First-Byte"
    }
  ]
}

resource "aws_cloudwatch_log_metric_filter" "hit_request_metric_filter" {
  log_group_name = aws_cloudwatch_log_group.cloud_watch_log_group.arn
  pattern        = "[date, time, x_edge_location, sc_bytes, c_ip, cs_method, Host, cs_uri_stem, sc_status, cs_referer, cs_User_Agent, us_uri_query, Cookie, x_edge_result_type=Hit, x_edge_request_id, x_host_header, cs_protocol, cs_bytes, time_taken, x_forwarded_for, ssl_protocol, ssl_cipher, x_edge_response_result_type, cs_protocol_version, fle_status, fle_encrypted_fields, c_port, time_to_first_byte, x_edge_detailed_result_type, sc_content_type, sc_content_len, sc_range_start, sc_range_end ]"
  metric_transformation = [
    {
      MetricValue     = "$time_taken"
      MetricNamespace = aws_cloudwatch_log_group.cloud_watch_log_group.arn
      MetricName      = "Hit-Requests"
    }
  ]
}

resource "aws_cloudwatch_log_metric_filter" "refresh_hit_request_metric_filter" {
  log_group_name = aws_cloudwatch_log_group.cloud_watch_log_group.arn
  pattern        = "[date, time, x_edge_location, sc_bytes, c_ip, cs_method, Host, cs_uri_stem, sc_status, cs_referer, cs_User_Agent, us_uri_query, Cookie, x_edge_result_type=RefreshHit, x_edge_request_id, x_host_header, cs_protocol, cs_bytes, time_taken, x_forwarded_for, ssl_protocol, ssl_cipher, x_edge_response_result_type, cs_protocol_version, fle_status, fle_encrypted_fields, c_port, time_to_first_byte, x_edge_detailed_result_type, sc_content_type, sc_content_len, sc_range_start, sc_range_end ]"
  metric_transformation = [
    {
      MetricValue     = "$time_taken"
      MetricNamespace = aws_cloudwatch_log_group.cloud_watch_log_group.arn
      MetricName      = "RefreshHit-Requests"
    }
  ]
}

resource "aws_cloudwatch_log_metric_filter" "origin_shield_hit_request_metric_filter" {
  log_group_name = aws_cloudwatch_log_group.cloud_watch_log_group.arn
  pattern        = "[date, time, x_edge_location, sc_bytes, c_ip, cs_method, Host, cs_uri_stem, sc_status, cs_referer, cs_User_Agent, us_uri_query, Cookie, x_edge_result_type=OriginShieldHit, x_edge_request_id, x_host_header, cs_protocol, cs_bytes, time_taken, x_forwarded_for, ssl_protocol, ssl_cipher, x_edge_response_result_type, cs_protocol_version, fle_status, fle_encrypted_fields, c_port, time_to_first_byte, x_edge_detailed_result_type, sc_content_type, sc_content_len, sc_range_start, sc_range_end ]"
  metric_transformation = [
    {
      MetricValue     = "$time_taken"
      MetricNamespace = aws_cloudwatch_log_group.cloud_watch_log_group.arn
      MetricName      = "OriginShieldHit-Requests"
    }
  ]
}

resource "aws_cloudwatch_log_metric_filter" "redirect_request_metric_filter" {
  log_group_name = aws_cloudwatch_log_group.cloud_watch_log_group.arn
  pattern        = "[date, time, x_edge_location, sc_bytes, c_ip, cs_method, Host, cs_uri_stem, sc_status, cs_referer, cs_User_Agent, us_uri_query, Cookie, x_edge_result_type=Redirect, x_edge_request_id, x_host_header, cs_protocol, cs_bytes, time_taken, x_forwarded_for, ssl_protocol, ssl_cipher, x_edge_response_result_type, cs_protocol_version, fle_status, fle_encrypted_fields, c_port, time_to_first_byte, x_edge_detailed_result_type, sc_content_type, sc_content_len, sc_range_start, sc_range_end ]"
  metric_transformation = [
    {
      MetricValue     = "$time_taken"
      MetricNamespace = aws_cloudwatch_log_group.cloud_watch_log_group.arn
      MetricName      = "Redirect-Requests"
    }
  ]
}

resource "aws_cloudwatch_log_metric_filter" "miss_request_metric_filter" {
  log_group_name = aws_cloudwatch_log_group.cloud_watch_log_group.arn
  pattern        = "[date, time, x_edge_location, sc_bytes, c_ip, cs_method, Host, cs_uri_stem, sc_status, cs_referer, cs_User_Agent, us_uri_query, Cookie, x_edge_result_type=Miss, x_edge_request_id, x_host_header, cs_protocol, cs_bytes, time_taken, x_forwarded_for, ssl_protocol, ssl_cipher, x_edge_response_result_type, cs_protocol_version, fle_status, fle_encrypted_fields, c_port, time_to_first_byte, x_edge_detailed_result_type, sc_content_type, sc_content_len, sc_range_start, sc_range_end ]"
  metric_transformation = [
    {
      MetricValue     = "$time_taken"
      MetricNamespace = aws_cloudwatch_log_group.cloud_watch_log_group.arn
      MetricName      = "Miss-Requests"
    }
  ]
}

resource "aws_cloudwatch_log_metric_filter" "error_request_metric_filter" {
  log_group_name = aws_cloudwatch_log_group.cloud_watch_log_group.arn
  pattern        = "[date, time, x_edge_location, sc_bytes, c_ip, cs_method, Host, cs_uri_stem, sc_status, cs_referer, cs_User_Agent, us_uri_query, Cookie, x_edge_result_type=Error, x_edge_request_id, x_host_header, cs_protocol, cs_bytes, time_taken, x_forwarded_for, ssl_protocol, ssl_cipher, x_edge_response_result_type, cs_protocol_version, fle_status, fle_encrypted_fields, c_port, time_to_first_byte, x_edge_detailed_result_type, sc_content_type, sc_content_len, sc_range_start, sc_range_end ]"
  metric_transformation = [
    {
      MetricValue     = "$time_taken"
      MetricNamespace = aws_cloudwatch_log_group.cloud_watch_log_group.arn
      MetricName      = "Error-Requests"
    }
  ]
}

resource "aws_cloudwatch_log_metric_filter" "limit_exceeded_metric_filter" {
  log_group_name = aws_cloudwatch_log_group.cloud_watch_log_group.arn
  pattern        = "[date, time, x_edge_location, sc_bytes, c_ip, cs_method, Host, cs_uri_stem, sc_status, cs_referer, cs_User_Agent, us_uri_query, Cookie, x_edge_result_type=LimitExceeded, x_edge_request_id, x_host_header, cs_protocol, cs_bytes, time_taken, x_forwarded_for, ssl_protocol, ssl_cipher, x_edge_response_result_type, cs_protocol_version, fle_status, fle_encrypted_fields, c_port, time_to_first_byte, x_edge_detailed_result_type, sc_content_type, sc_content_len, sc_range_start, sc_range_end ]"
  metric_transformation = [
    {
      MetricValue     = "$time_taken"
      MetricNamespace = aws_cloudwatch_log_group.cloud_watch_log_group.arn
      MetricName      = "LimitExceeded-Requests"
    }
  ]
}

resource "aws_cloudwatch_log_metric_filter" "capacity_exceeded_metric_filter" {
  log_group_name = aws_cloudwatch_log_group.cloud_watch_log_group.arn
  pattern        = "[date, time, x_edge_location, sc_bytes, c_ip, cs_method, Host, cs_uri_stem, sc_status, cs_referer, cs_User_Agent, us_uri_query, Cookie, x_edge_result_type=CapacityExceeded, x_edge_request_id, x_host_header, cs_protocol, cs_bytes, time_taken, x_forwarded_for, ssl_protocol, ssl_cipher, x_edge_response_result_type, cs_protocol_version, fle_status, fle_encrypted_fields, c_port, time_to_first_byte, x_edge_detailed_result_type, sc_content_type, sc_content_len, sc_range_start, sc_range_end ]"
  metric_transformation = [
    {
      MetricValue     = "$time_taken"
      MetricNamespace = aws_cloudwatch_log_group.cloud_watch_log_group.arn
      MetricName      = "CapacityExceeded-Requests"
    }
  ]
}

resource "aws_cloudwatch_event_rule" "bytes_out_by_pop_contributor_insight_rule" {
  // CF Property(RuleBody) = "{
  //     "Schema": {
  //         "Name": "CloudWatchLogRule",
  //         "Version": 1
  //     },
  //     "AggregateOn": "Sum",
  //     "Contribution": {
  //         "Filters": [],
  //         "Keys": [
  //             "Edge Location"
  //         ],
  //         "ValueOf": "Bytes Out"
  //     },
  //     "LogFormat": "CLF",
  //     "LogGroupNames": [
  //         "${aws_cloudwatch_log_group.cloud_watch_log_group.arn}"
  //     ],
  //     "Fields": {
  //         "1": "Date",
  //         "2": "Time",
  //         "3": "Edge Location",
  //         "4": "Bytes Out",
  //         "5": "Viewer IP",
  //         "6": "HTTP Method",
  //         "7": "Host",
  //         "8": "URI Path",
  //         "9": "HTTP Status",
  //         "10": "Referer",
  //         "11": "User-Agent",
  //         "12": "Query String",
  //         "13": "Cookie",
  //         "14": "Edge Result Type",
  //         "15": "Edge Request ID",
  //         "16": "Host Header",
  //         "17": "Viewer Protocol",
  //         "18": "Bytes In",
  //         "19": "Time Taken",
  //         "20": "x-forwarded-for",
  //         "21": "SSL Protocol",
  //         "22": "SSL Cipher",
  //         "23": "Edge Response Result Type",
  //         "24": "Protocol Version",
  //         "25": "FLE  Status",
  //         "26": "FLW Encrypted Fields",
  //         "27": "Viewer Port",
  //         "28": "Time to First Byte",
  //         "29": "x-edge-detailed-result-type",
  //         "30": "Content Type",
  //         "31": "content Length",
  //         "32": "Start Range",
  //         "33": "End Range"
  //     }
  // }
  // "
  name  = "CF-Bytes-Out-By-POP-${var.cf_distribution_id}"
  state = var.contributor_insight_rule_state
}

resource "aws_cloudwatch_event_rule" "cache_miss_by_uri_contributor_insight_rule" {
  // CF Property(RuleBody) = "{
  //     "Schema": {
  //         "Name": "CloudWatchLogRule",
  //         "Version": 1
  //     },
  //     "AggregateOn": "Count",
  //     "Contribution": {
  //         "Filters": [
  //             {
  //                 "Match": "Edge Result Type",
  //                 "In": [
  //                     "Miss"
  //                 ]
  //             },
  //             {
  //                 "In": [
  //                     "GET",
  //                     "HEAD"
  //                 ],
  //                 "Match": "HTTP Method"
  //             }
  //         ],
  //         "Keys": [
  //             "URI Path"
  //         ],
  //         "ValueOf": "Bytes Out"
  //     },
  //     "LogFormat": "CLF",
  //     "LogGroupNames": [
  //         "${aws_cloudwatch_log_group.cloud_watch_log_group.arn}"
  //     ],
  //     "Fields": {
  //         "1": "Date",
  //         "2": "Time",
  //         "3": "Edge Location",
  //         "4": "Bytes Out",
  //         "5": "Viewer IP",
  //         "6": "HTTP Method",
  //         "7": "Host",
  //         "8": "URI Path",
  //         "9": "HTTP Status",
  //         "10": "Referer",
  //         "11": "User-Agent",
  //         "12": "Query String",
  //         "13": "Cookie",
  //         "14": "Edge Result Type",
  //         "15": "Edge Request ID",
  //         "16": "Host Header",
  //         "17": "Viewer Protocol",
  //         "18": "Bytes In",
  //         "19": "Time Taken",
  //         "20": "x-forwarded-for",
  //         "21": "SSL Protocol",
  //         "22": "SSL Cipher",
  //         "23": "Edge Response Result Type",
  //         "24": "Protocol Version",
  //         "25": "FLE  Status",
  //         "26": "FLW Encrypted Fields",
  //         "27": "Viewer Port",
  //         "28": "Time to First Byte",
  //         "29": "x-edge-detailed-result-type",
  //         "30": "Content Type",
  //         "31": "content Length",
  //         "32": "Start Range",
  //         "33": "End Range"
  //     }
  // }
  // "
  name  = "CF-Cache-Miss-by-URI-${var.cf_distribution_id}"
  state = var.contributor_insight_rule_state
}

resource "aws_cloudwatch_event_rule" "edge_status_by_pop_contributor_insight_rule" {
  // CF Property(RuleBody) = "{
  //     "Schema": {
  //         "Name": "CloudWatchLogRule",
  //         "Version": 1
  //     },
  //     "AggregateOn": "Count",
  //     "Contribution": {
  //         "Filters": [],
  //         "Keys": [
  //             "x-edge-detailed-result-type",
  //             "Edge Location"
  //         ],
  //         "ValueOf": "Bytes Out"
  //     },
  //     "LogFormat": "CLF",
  //     "LogGroupNames": [
  //         "${aws_cloudwatch_log_group.cloud_watch_log_group.arn}"
  //     ],
  //     "Fields": {
  //         "1": "Date",
  //         "2": "Time",
  //         "3": "Edge Location",
  //         "4": "Bytes Out",
  //         "5": "Viewer IP",
  //         "6": "HTTP Method",
  //         "7": "Host",
  //         "8": "URI Path",
  //         "9": "HTTP Status",
  //         "10": "Referer",
  //         "11": "User-Agent",
  //         "12": "Query String",
  //         "13": "Cookie",
  //         "14": "Edge Result Type",
  //         "15": "Edge Request ID",
  //         "16": "Host Header",
  //         "17": "Viewer Protocol",
  //         "18": "Bytes In",
  //         "19": "Time Taken",
  //         "20": "x-forwarded-for",
  //         "21": "SSL Protocol",
  //         "22": "SSL Cipher",
  //         "23": "Edge Response Result Type",
  //         "24": "Protocol Version",
  //         "25": "FLE  Status",
  //         "26": "FLW Encrypted Fields",
  //         "27": "Viewer Port",
  //         "28": "Time to First Byte",
  //         "29": "x-edge-detailed-result-type",
  //         "30": "Content Type",
  //         "31": "content Length",
  //         "32": "Start Range",
  //         "33": "End Range"
  //     }
  // }
  // "
  name  = "CF-Edge-Status-by-POP-${var.cf_distribution_id}"
  state = var.contributor_insight_rule_state
}

resource "aws_cloudwatch_event_rule" "errors_by_pop_and_path_contributor_insight_rule" {
  // CF Property(RuleBody) = "{
  //     "Schema": {
  //         "Name": "CloudWatchLogRule",
  //         "Version": 1
  //     },
  //     "AggregateOn": "Count",
  //     "Contribution": {
  //         "Filters": [
  //             {
  //                 "Match": "HTTP Status",
  //                 "StartsWith": [
  //                     "5",
  //                     "4"
  //                 ]
  //             },
  //             {
  //                 "Match": "Edge Result Type",
  //                 "StartsWith": [
  //                     "Error",
  //                     "LimitExceeded",
  //                     "CapacityExceeded"
  //                 ]
  //             }
  //         ],
  //         "Keys": [
  //             "Edge Location",
  //             "URI Path"
  //         ],
  //         "ValueOf": "Bytes Out"
  //     },
  //     "LogFormat": "CLF",
  //     "LogGroupNames": [
  //         "${aws_cloudwatch_log_group.cloud_watch_log_group.arn}"
  //     ],
  //     "Fields": {
  //         "1": "Date",
  //         "2": "Time",
  //         "3": "Edge Location",
  //         "4": "Bytes Out",
  //         "5": "Viewer IP",
  //         "6": "HTTP Method",
  //         "7": "Host",
  //         "8": "URI Path",
  //         "9": "HTTP Status",
  //         "10": "Referer",
  //         "11": "User-Agent",
  //         "12": "Query String",
  //         "13": "Cookie",
  //         "14": "Edge Result Type",
  //         "15": "Edge Request ID",
  //         "16": "Host Header",
  //         "17": "Viewer Protocol",
  //         "18": "Bytes In",
  //         "19": "Time Taken",
  //         "20": "x-forwarded-for",
  //         "21": "SSL Protocol",
  //         "22": "SSL Cipher",
  //         "23": "Edge Response Result Type",
  //         "24": "Protocol Version",
  //         "25": "FLE  Status",
  //         "26": "FLW Encrypted Fields",
  //         "27": "Viewer Port",
  //         "28": "Time to First Byte",
  //         "29": "x-edge-detailed-result-type",
  //         "30": "Content Type",
  //         "31": "content Length",
  //         "32": "Start Range",
  //         "33": "End Range"
  //     }
  // }
  // "
  name  = "CF-Errors-By-POP-and-Path-${var.cf_distribution_id}"
  state = var.contributor_insight_rule_state
}

resource "aws_cloudwatch_event_rule" "cf_requests_by_http_method_contributor_insight_rule" {
  // CF Property(RuleBody) = "{
  //     "Schema": {
  //         "Name": "CloudWatchLogRule",
  //         "Version": 1
  //     },
  //     "AggregateOn": "Count",
  //     "Contribution": {
  //         "Filters": [],
  //         "Keys": [
  //             "HTTP Method"
  //         ],
  //         "ValueOf": "Bytes Out"
  //     },
  //     "LogFormat": "CLF",
  //     "LogGroupNames": [
  //         "${aws_cloudwatch_log_group.cloud_watch_log_group.arn}"
  //     ],
  //     "Fields": {
  //         "1": "Date",
  //         "2": "Time",
  //         "3": "Edge Location",
  //         "4": "Bytes Out",
  //         "5": "Viewer IP",
  //         "6": "HTTP Method",
  //         "7": "Host",
  //         "8": "URI Path",
  //         "9": "HTTP Status",
  //         "10": "Referer",
  //         "11": "User-Agent",
  //         "12": "Query String",
  //         "13": "Cookie",
  //         "14": "Edge Result Type",
  //         "15": "Edge Request ID",
  //         "16": "Host Header",
  //         "17": "Viewer Protocol",
  //         "18": "Bytes In",
  //         "19": "Time Taken",
  //         "20": "x-forwarded-for",
  //         "21": "SSL Protocol",
  //         "22": "SSL Cipher",
  //         "23": "Edge Response Result Type",
  //         "24": "Protocol Version",
  //         "25": "FLE  Status",
  //         "26": "FLW Encrypted Fields",
  //         "27": "Viewer Port",
  //         "28": "Time to First Byte",
  //         "29": "x-edge-detailed-result-type",
  //         "30": "Content Type",
  //         "31": "content Length",
  //         "32": "Start Range",
  //         "33": "End Range"
  //     }
  // }
  // "
  name  = "CF-Requests-by-HTTP-Method"
  state = var.contributor_insight_rule_state
}

resource "aws_cloudwatch_event_rule" "cf_requests_by_uri_contributor_insight_rule" {
  // CF Property(RuleBody) = "{
  //     "Schema": {
  //         "Name": "CloudWatchLogRule",
  //         "Version": 1
  //     },
  //     "AggregateOn": "Count",
  //     "Contribution": {
  //         "Filters": [],
  //         "Keys": [
  //             "URI Path"
  //         ],
  //         "ValueOf": "Bytes Out"
  //     },
  //     "LogFormat": "CLF",
  //     "LogGroupNames": [
  //         "${aws_cloudwatch_log_group.cloud_watch_log_group.arn}"
  //     ],
  //     "Fields": {
  //         "1": "Date",
  //         "2": "Time",
  //         "3": "Edge Location",
  //         "4": "Bytes Out",
  //         "5": "Viewer IP",
  //         "6": "HTTP Method",
  //         "7": "Host",
  //         "8": "URI Path",
  //         "9": "HTTP Status",
  //         "10": "Referer",
  //         "11": "User-Agent",
  //         "12": "Query String",
  //         "13": "Cookie",
  //         "14": "Edge Result Type",
  //         "15": "Edge Request ID",
  //         "16": "Host Header",
  //         "17": "Viewer Protocol",
  //         "18": "Bytes In",
  //         "19": "Time Taken",
  //         "20": "x-forwarded-for",
  //         "21": "SSL Protocol",
  //         "22": "SSL Cipher",
  //         "23": "Edge Response Result Type",
  //         "24": "Protocol Version",
  //         "25": "FLE  Status",
  //         "26": "FLW Encrypted Fields",
  //         "27": "Viewer Port",
  //         "28": "Time to First Byte",
  //         "29": "x-edge-detailed-result-type",
  //         "30": "Content Type",
  //         "31": "content Length",
  //         "32": "Start Range",
  //         "33": "End Range"
  //     }
  // }
  // "
  name  = "CF-Requests-by-URI-${var.cf_distribution_id}"
  state = var.contributor_insight_rule_state
}

resource "aws_cloudwatch_event_rule" "cf_requests_by_uri_and_user_agent_contributor_insight_rule" {
  // CF Property(RuleBody) = "{
  //     "Schema": {
  //         "Name": "CloudWatchLogRule",
  //         "Version": 1
  //     },
  //     "AggregateOn": "Count",
  //     "Contribution": {
  //         "Filters": [],
  //         "Keys": [
  //             "URI Path",
  //             "User-Agent"
  //         ],
  //         "ValueOf": "Bytes Out"
  //     },
  //     "LogFormat": "CLF",
  //     "LogGroupNames": [
  //         "${aws_cloudwatch_log_group.cloud_watch_log_group.arn}"
  //     ],
  //     "Fields": {
  //         "1": "Date",
  //         "2": "Time",
  //         "3": "Edge Location",
  //         "4": "Bytes Out",
  //         "5": "Viewer IP",
  //         "6": "HTTP Method",
  //         "7": "Host",
  //         "8": "URI Path",
  //         "9": "HTTP Status",
  //         "10": "Referer",
  //         "11": "User-Agent",
  //         "12": "Query String",
  //         "13": "Cookie",
  //         "14": "Edge Result Type",
  //         "15": "Edge Request ID",
  //         "16": "Host Header",
  //         "17": "Viewer Protocol",
  //         "18": "Bytes In",
  //         "19": "Time Taken",
  //         "20": "x-forwarded-for",
  //         "21": "SSL Protocol",
  //         "22": "SSL Cipher",
  //         "23": "Edge Response Result Type",
  //         "24": "Protocol Version",
  //         "25": "FLE  Status",
  //         "26": "FLW Encrypted Fields",
  //         "27": "Viewer Port",
  //         "28": "Time to First Byte",
  //         "29": "x-edge-detailed-result-type",
  //         "30": "Content Type",
  //         "31": "content Length",
  //         "32": "Start Range",
  //         "33": "End Range"
  //     }
  // }
  // "
  name  = "CF-Requests-by-URI-and-UserAgent-${var.cf_distribution_id}"
  state = var.contributor_insight_rule_state
}

resource "aws_cloudwatch_event_rule" "cf_status_by_pop_contributor_insight_rule" {
  // CF Property(RuleBody) = "{
  //     "Schema": {
  //         "Name": "CloudWatchLogRule",
  //         "Version": 1
  //     },
  //     "AggregateOn": "Count",
  //     "Contribution": {
  //         "Filters": [],
  //         "Keys": [
  //             "HTTP Status",
  //             "Edge Location"
  //         ],
  //         "ValueOf": "Bytes Out"
  //     },
  //     "LogFormat": "CLF",
  //     "LogGroupNames": [
  //         "${aws_cloudwatch_log_group.cloud_watch_log_group.arn}"
  //     ],
  //     "Fields": {
  //         "1": "Date",
  //         "2": "Time",
  //         "3": "Edge Location",
  //         "4": "Bytes Out",
  //         "5": "Viewer IP",
  //         "6": "HTTP Method",
  //         "7": "Host",
  //         "8": "URI Path",
  //         "9": "HTTP Status",
  //         "10": "Referer",
  //         "11": "User-Agent",
  //         "12": "Query String",
  //         "13": "Cookie",
  //         "14": "Edge Result Type",
  //         "15": "Edge Request ID",
  //         "16": "Host Header",
  //         "17": "Viewer Protocol",
  //         "18": "Bytes In",
  //         "19": "Time Taken",
  //         "20": "x-forwarded-for",
  //         "21": "SSL Protocol",
  //         "22": "SSL Cipher",
  //         "23": "Edge Response Result Type",
  //         "24": "Protocol Version",
  //         "25": "FLE  Status",
  //         "26": "FLW Encrypted Fields",
  //         "27": "Viewer Port",
  //         "28": "Time to First Byte",
  //         "29": "x-edge-detailed-result-type",
  //         "30": "Content Type",
  //         "31": "content Length",
  //         "32": "Start Range",
  //         "33": "End Range"
  //     }
  // }
  // "
  name  = "CF-Status-by-POP-${var.cf_distribution_id}"
  state = var.contributor_insight_rule_state
}

output "output_dashboard_uri" {
  description = "Link to the CloudWatch Dashboard"
  value       = "https://console.aws.amazon.com/cloudwatch/home?region=${data.aws_region.current.name}#dashboards:name=${aws_cloudwatch_dashboard.cw_dashboard_for_cf_logs.dashboard_arn}"
}