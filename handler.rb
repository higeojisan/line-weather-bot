require 'json'

def input(event:, context:)
  { statusCode: 200, body: JSON.generate('Go Serverless v1.0! Your function executed successfully!') }
end
