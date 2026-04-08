swagger: "2.0"
info:
  title: "Cloud Run Hono API Gateway"
  version: "1.0.0"
  description: "API Gateway for Hono backend with IAM authentication"
schemes:
  - "https"
produces:
  - "application/json"
securityDefinitions:
  google_id_token:
    authorizationUrl: ""
    flow: "implicit"
    type: "oauth2"
    x-google-issuer: "https://accounts.google.com"
    x-google-jwks_uri: "https://www.googleapis.com/oauth2/v3/certs"
    x-google-audiences: "${api_managed_service}"
security:
  - google_id_token: []
paths:
  /health:
    get:
      summary: "Health check endpoint"
      operationId: "healthCheck"
      security: []
      x-google-backend:
        address: "${cloud_run_url}/health"
        jwt_audience: "${cloud_run_url}"
      responses:
        200:
          description: "Healthy"
  /api/hello:
    get:
      summary: "Get hello message"
      operationId: "getHello"
      x-google-backend:
        address: "${cloud_run_url}/api/hello"
        jwt_audience: "${cloud_run_url}"
      responses:
        200:
          description: "Success"
    post:
      summary: "Post hello message"
      operationId: "postHello"
      x-google-backend:
        address: "${cloud_run_url}/api/hello"
        jwt_audience: "${cloud_run_url}"
      parameters:
        - name: body
          in: body
          required: true
          schema:
            type: object
            properties:
              name:
                type: string
      responses:
        200:
          description: "Success"
  /webhook/example:
    post:
      summary: "Webhook endpoint (API key auth at app level)"
      operationId: "postWebhookExample"
      security: []
      x-google-backend:
        address: "${cloud_run_url}/webhook/example"
        jwt_audience: "${cloud_run_url}"
      parameters:
        - name: body
          in: body
          required: true
          schema:
            type: object
      responses:
        200:
          description: "Success"
        401:
          description: "Unauthorized"
  /api/users:
    get:
      summary: "Get users list"
      operationId: "getUsers"
      x-google-backend:
        address: "${cloud_run_url}/api/users"
        jwt_audience: "${cloud_run_url}"
      responses:
        200:
          description: "Success"
