import gleam/dynamic
import gleam/dynamic/decode
import gleam/json
import gleam/list
import gleam/string
import pog
import wisp.{type Response}

pub type ApiError {
  JsonDecodeError(errors: List(String))
  BadRequestError(message: String)
  InternalServerError
  NotFoundError
}

pub fn to_response(error: ApiError) -> Response {
  let #(status_code, body) = case error {
    InternalServerError -> #(
      500,
      json.object([#("error", json.string("InternalServerError"))]),
    )
    BadRequestError(message) -> #(
      400,
      json.object([
        #("error", json.string("BadRequestError")),
        #("message", json.string(message)),
      ]),
    )
    JsonDecodeError(errors) -> #(
      400,
      json.object([
        #("error", json.string("JsonDecodeError")),
        #("errors", json.array(errors, json.string)),
      ]),
    )
    NotFoundError -> #(
      404,
      json.object([#("error", json.string("NotFoundError"))]),
    )
  }

  wisp.response(status_code)
  |> wisp.json_body(json.to_string(body))
}

fn json_decode_error(error: List(decode.DecodeError)) -> ApiError {
  list.map(error, fn(error) {
    "Expected "
    <> error.expected
    <> " but got "
    <> error.found
    <> " at "
    <> string.join(error.path, ".")
  })
  |> JsonDecodeError
}

pub fn require_decoded(
  json: dynamic.Dynamic,
  decoder: decode.Decoder(decoded),
  next: fn(decoded) -> Result(result_type, ApiError),
) -> Result(result_type, ApiError) {
  case decode.run(json, decoder) {
    Ok(decoded) -> next(decoded)
    Error(error) -> Error(json_decode_error(error))
  }
}

pub fn from_pog_query_error(_error: pog.QueryError) -> ApiError {
  InternalServerError
}
