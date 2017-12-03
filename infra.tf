variable "region" {
  type = "string"
  default = "us-west-2"
}

variable "account_id" {}
/*
# Direct input approach
variable "access_key" {}
variable "secret_key" {}

provider "aws" {
  version = "~> 1.0"

  access_key = "${var.access_key}"
  secret_key = "${var.secret_key}"
  region     = "${var.region}"
}
*/
provider "aws" {
  shared_credentials_file = "/home/torben/.aws/creds"
  profile                 = "personal"
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

# Connect API and Lambda
resource "aws_api_gateway_integration" "fitbit_sync_api_method-integration" {
  rest_api_id = "${aws_api_gateway_rest_api.fitbit_sync_api.id}"
  resource_id = "${aws_api_gateway_resource.user.id}"
  http_method = "${aws_api_gateway_method.fitbit_sync_api_method.http_method}"
  type = "AWS_PROXY"
  uri = "arn:aws:apigateway:${var.region}:lambda:path/2015-03-31/functions/arn:aws:lambda:${var.region}:${var.account_id}:function:${aws_lambda_function.fitbit_sync.function_name}/invocations"
  integration_http_method = "POST"
}

resource "aws_api_gateway_deployment" "fitbit_sync_deployment_prod" {
  depends_on = [
    "aws_api_gateway_method.fitbit_sync_api_method",
    "aws_api_gateway_integration.fitbit_sync_api_method-integration"
  ]
  rest_api_id = "${aws_api_gateway_rest_api.fitbit_sync_api.id}"
  stage_name = "api"
}

output "prod_url" {
  value = "https://${aws_api_gateway_deployment.fitbit_sync_deployment_prod.rest_api_id}.execute-api.${var.region}.amazonaws.com/${aws_api_gateway_deployment.fitbit_sync_deployment_prod.stage_name}"
}