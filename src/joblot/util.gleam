import gleam/bytes_tree
import gleam/http
import gleam/http/request
import gleam/http/response
import gleam/io
import gleam/json
import gleam/result
import gleam/uri
import httpp/send
import mist

pub fn log_error(incoming: Result(a, b), error_message: String) -> Result(a, b) {
  result.try_recover(incoming, fn(err) {
    io.println_error(error_message)
    echo err
    incoming
  })
}

pub fn send_internal_request(
  api_address: uri.Uri,
  secret: String,
  path: String,
  body: String,
) {
  let assert Ok(base_req) = uri.Uri(..api_address, path:) |> request.from_uri

  let request =
    base_req
    |> request.set_method(http.Post)
    |> request.set_header("authorization", secret)
    |> request.set_query([#("secret_key", secret)])
    |> request.set_body(body)

  send.send(request)
}

pub fn not_found() {
  let data =
    json.object([#("error", json.string("Not Found"))])
    |> json.to_string_tree
    |> bytes_tree.from_string_tree
    |> mist.Bytes

  response.new(404)
  |> response.set_body(data)
}

pub fn not_authorized() {
  let data =
    json.object([#("error", json.string("Not Authorized."))])
    |> json.to_string_tree
    |> bytes_tree.from_string_tree
    |> mist.Bytes

  response.new(403)
  |> response.set_body(data)
}
