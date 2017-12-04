variable "region" {
  type = "string"
  default = "us-west-2"
}
variable "fitbit_verify_code" {}
data "aws_caller_identity" "current" {}

# Sync state to s3 bucket
terraform {
  backend "s3" {
    bucket = "fitbit-terraform-state"
    key    = "terraform.tfstate"
    region = "us-west-2"
    profile = "personal"
  }
}

provider "aws" {
  shared_credentials_file = "/home/torben/.aws/creds"
  profile                 = "personal"
  region                  = "${var.region}"
}

# Zip file containing compiled lambda code
data "archive_file" "lambda" {
  type = "zip"
  source_file = "dist/bundle.js"
  output_path = "lambda.zip"
}

# Define the lambda function
resource "aws_lambda_function" "fitbit_sync" {
  filename = "${data.archive_file.lambda.output_path}"
  function_name = "fitbit_sync"
  role = "${aws_iam_role.fitbit_sync_api_role.arn}"
  handler = "bundle.handler"
  runtime = "nodejs6.10"
  source_code_hash = "${base64sha256(file("${data.archive_file.lambda.output_path}"))}"
  publish = true
  environment {
    variables = {
      fitbit_verify_code = "${var.fitbit_verify_code}"
    }
  }
}

# Role for this lambda function
resource "aws_iam_role" "fitbit_sync_api_role" {
  name = "fitbit_sync_api_role"
  assume_role_policy = "${file("policies/lambda-role.json")}"
}


# API Root
resource "aws_api_gateway_rest_api" "fitbit_sync_api" {
  name = "FitBitSyncAPI"
  description = "API Gateway for receiving FitBit subscriptions"
}

# Endpoint
resource "aws_api_gateway_resource" "sync" {
  rest_api_id = "${aws_api_gateway_rest_api.fitbit_sync_api.id}"
  parent_id = "${aws_api_gateway_rest_api.fitbit_sync_api.root_resource_id}"
  path_part = "sync"
}

// Unit
resource "aws_api_gateway_resource" "user" {
  rest_api_id = "${aws_api_gateway_rest_api.fitbit_sync_api.id}"
  parent_id = "${aws_api_gateway_resource.sync.id}"
  path_part = "{userId}"
}

resource "aws_api_gateway_method" "fitbit_sync_api_method" {
  rest_api_id = "${aws_api_gateway_rest_api.fitbit_sync_api.id}"
  resource_id = "${aws_api_gateway_resource.user.id}"
  http_method = "POST"
  authorization = "NONE"
  request_parameters {
    "method.request.path.userId" = true,
    "method.request.header.X-Fitbit-Signature" = true
  }
}

resource "aws_api_gateway_integration" "fitbit_sync_api_method-integration" {
  rest_api_id = "${aws_api_gateway_rest_api.fitbit_sync_api.id}"
  resource_id = "${aws_api_gateway_resource.user.id}"
  http_method = "${aws_api_gateway_method.fitbit_sync_api_method.http_method}"
  type = "AWS_PROXY"
  uri = "arn:aws:apigateway:${var.region}:lambda:path/2015-03-31/functions/arn:aws:lambda:${var.region}:${data.aws_caller_identity.current.account_id}:function:${aws_lambda_function.fitbit_sync.function_name}/invocations"
  integration_http_method = "POST"
}

#Fitbit Subscription Verification
resource "aws_api_gateway_method" "fitbit_sync_verify_api_method" {
  rest_api_id = "${aws_api_gateway_rest_api.fitbit_sync_api.id}"
  resource_id = "${aws_api_gateway_resource.sync.id}"
  http_method = "GET"
  authorization = "NONE"
  request_parameters {
    "method.request.querystring.verify" = true
  }
}

resource "aws_api_gateway_integration" "fitbit_sync_verify_api_method-integration" {
  rest_api_id = "${aws_api_gateway_rest_api.fitbit_sync_api.id}"
  resource_id = "${aws_api_gateway_resource.sync.id}"
  http_method = "${aws_api_gateway_method.fitbit_sync_verify_api_method.http_method}"
  type = "AWS_PROXY"
  uri = "arn:aws:apigateway:${var.region}:lambda:path/2015-03-31/functions/arn:aws:lambda:${var.region}:${data.aws_caller_identity.current.account_id}:function:${aws_lambda_function.fitbit_sync.function_name}/invocations"
  integration_http_method = "POST"
}

#Cloudwatch permissions
resource "aws_iam_role_policy" "cloudwatch-policy" {
    name   = "cloudwatch-policy"
    role   = "${aws_iam_role.fitbit_sync_api_role.id}"
    policy = "${file("policies/lambda-cloudwatch-policy.json")}"
}


# Connect API and Lambda
resource "aws_api_gateway_deployment" "fitbit_sync_deployment_prod" {
  depends_on = [
    "aws_api_gateway_method.fitbit_sync_api_method",
    "aws_api_gateway_integration.fitbit_sync_api_method-integration",
    "aws_api_gateway_integration.fitbit_sync_verify_api_method-integration"
  ]
  rest_api_id = "${aws_api_gateway_rest_api.fitbit_sync_api.id}"
  stage_name = "api"
}

resource "aws_lambda_permission" "apigw_lambda_sync" {
  statement_id  = "AllowExecutionFromAPIGatewaySync"
  action        = "lambda:InvokeFunction"
  function_name = "${aws_lambda_function.fitbit_sync.arn}"
  principal     = "apigateway.amazonaws.com"

  source_arn = "arn:aws:execute-api:${var.region}:${data.aws_caller_identity.current.account_id}:${aws_api_gateway_rest_api.fitbit_sync_api.id}/*/${aws_api_gateway_method.fitbit_sync_api_method.http_method}/*"
}

resource "aws_lambda_permission" "apigw_lambda_verify" {
  statement_id  = "AllowExecutionFromAPIGatewayVerify"
  action        = "lambda:InvokeFunction"
  function_name = "${aws_lambda_function.fitbit_sync.arn}"
  principal     = "apigateway.amazonaws.com"

  source_arn = "arn:aws:execute-api:${var.region}:${data.aws_caller_identity.current.account_id}:${aws_api_gateway_rest_api.fitbit_sync_api.id}/*/${aws_api_gateway_method.fitbit_sync_verify_api_method.http_method}/*"
}

# Connect API and Lambda

output "prod_url" {
  value = "https://${aws_api_gateway_deployment.fitbit_sync_deployment_prod.rest_api_id}.execute-api.${var.region}.amazonaws.com/${aws_api_gateway_deployment.fitbit_sync_deployment_prod.stage_name}"
}