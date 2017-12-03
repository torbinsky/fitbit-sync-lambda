const path = require('path');

module.exports = {
  entry: './src/index.ts',
  target: 'node',
  externals: [
    /aws-sdk/, // Available on AWS Lambda 
  ],
  module: {
    rules: [
      {
        test: /\.ts?$/,
        use: 'ts-loader',
        exclude: /node_modules/
      }
    ]
  },
  resolve: {
    extensions: [ '.ts', '.js' ]
  },
  output: {
    filename: 'bundle.js',
    library: 'bundle',
    libraryTarget: 'commonjs2',
    path: path.resolve(__dirname, 'dist')
  }
};