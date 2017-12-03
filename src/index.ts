import { Handler, Context, Callback } from 'aws-lambda';

interface HelloResponse {
  statusCode: number;
  body: string;
}

export const handler: Handler = (event: any, context: Context, callback: Callback) => {
  console.log("Event: ");
  console.log(event);

  const response: HelloResponse = {
    statusCode: 204,
    body: JSON.stringify({
      message: "Hello, world!"
    })
  };

  callback(undefined, response);
};

// export { handler }