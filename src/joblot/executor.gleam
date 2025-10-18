import gleam/http
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
    headers: List(#(String, String)),
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
    <> request.method |> http.method_to_string
    <> " "
    <> request.url |> uri.to_string,
  )
  Error(TimeoutError)
}
