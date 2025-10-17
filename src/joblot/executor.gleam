import gleam/io

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
  io.println("Executing request: " <> request.method <> " " <> request.url)
  Error(TimeoutError)
}
