import gleam/io
import gleam/result

pub fn log_error(incoming: Result(a, b), error_message: String) -> Result(a, b) {
  result.try_recover(incoming, fn(_) {
    io.println_error(error_message)
    incoming
  })
}
