import gleam/http
import gleam/http/request
import gleam/http/response
import gleam/io
import gleam/uri

pub type ExecutorError {
  TimeoutError
  PrivateIpError
  InvalidUtf8Response
  FailedToConnect
}

pub type ExecutorRequest {
  ExecutorRequest(
    method: http.Method,
    url: uri.Uri,
    headers: List(String),
    body: String,
    timeout_ms: Int,
    non_2xx_is_failure: Bool,
  )
}

pub type ExecutorResponse {
  ExecutorResponse(
    status_code: Int,
    headers: List(String),
    body: String,
    response_time_ms: Int,
  )
}

pub fn execute_request(
  request: ExecutorRequest,
) -> Result(ExecutorResponse, ExecutorError) {
  io.println(
    "Executing request: "
    <> http.method_to_string(request.method)
    <> " "
    <> uri.to_string(request.url),
  )
  Error(TimeoutError)
}
