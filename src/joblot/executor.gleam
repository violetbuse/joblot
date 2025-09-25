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
    method: String,
    url: String,
    headers: List(String),
    body: String,
    timeout_ms: Int,
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
  io.println("Executing request: " <> request.method <> " " <> request.url)
  Error(TimeoutError)
}
