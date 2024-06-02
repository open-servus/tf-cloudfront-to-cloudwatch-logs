# tf-cloudfront-to-cloudwatch-logs
Sending CloudFront standard logs to CloudWatch Logs for analysis

This is the Terraform Code alternative of below Cloudformation template showed at below article:

Amazon CloudFront is a fast content delivery network (CDN) service that securely delivers data, videos, applications, and APIs to customers globally with low latency, high transfer speeds, all within a developer-friendly environment.

CloudFront standard logs (also known as access logs) give you visibility into requests that are made to a CloudFront distribution. The logs can be analyzed for a variety of use cases, such as determining which objects are the most requested or which edge locations receive the most traffic. You can also use logging to troubleshoot errors or gain performance insights.

You can gain these insights using these Amazon CloudWatch Logs features:

CloudWatch Logs Insights, which enables you to interactively search and analyze your log data.
Metric filters, which allow you to extract metric data from log events.
Amazon CloudWatch Contributor Insights, which show you metrics about the top-N contributors, the total number of unique contributors, along with their usage.
In this blog post, I’ll show how you can send CloudFront access logs to Amazon CloudWatch Logs. I’ll also discuss tools that you can use with CloudWatch Logs to generate meaningful insights and create dashboards from your CloudFront logs.

Ref: https://aws.amazon.com/blogs/mt/sending-cloudfront-standard-logs-to-cloudwatch-logs-for-analysis/