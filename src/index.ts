import { Context, ProxyCallback, ProxyHandler, APIGatewayEvent } from 'aws-lambda';
import * as process from 'process';

const fitbitVerificationCode = process.env["fitbit_verify_code"];

export const handler: ProxyHandler = (event: APIGatewayEvent, context: Context, callback?: ProxyCallback) => {
  let response = {
    statusCode: 204, // default successful
    body: ""
  }

  // If it's a GET request, then Fitbit is asking us to verify the subscription
  if(event.httpMethod == "GET"){
    console.log("Verification requested...")
    // Verify
    response.statusCode = 404;
    if(event.queryStringParameters && fitbitVerificationCode == event.queryStringParameters['verify']){
      response.statusCode = 204;
      console.log("Verification successful!")
    }else{
      console.log("Verification failed. Query params were:")
      console.log(event.queryStringParameters)
    }
  }else{
    // Sync
    console.log("Body:")
    console.log(event.body);
  }

  if(callback){
    callback(null,response)
  }
};
