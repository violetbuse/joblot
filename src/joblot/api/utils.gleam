import gleam/dict
import gleam/dynamic/decode
import gleam/http
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/string
import gleam/uri

pub fn decode_metadata(
  next: fn(List(#(String, String))) -> decode.Decoder(final),
) -> decode.Decoder(final) {
  use metadata <- decode.optional_field(
    "metadata",
    [],
    decode.optional(
      decode.dict(decode.string, decode.string) |> decode.map(dict.to_list),
    )
      |> decode.map(option.unwrap(_, [])),
  )

  next(metadata)
}

pub fn decode_optional_string_field(
  name: String,
  next: fn(Option(String)) -> decode.Decoder(final),
) -> decode.Decoder(final) {
  use value <- decode.optional_field(
    name,
    None,
    decode.string |> decode.map(option.Some),
  )
  next(value)
}

pub fn decode_optional_int_field(
  name: String,
  next: fn(Option(Int)) -> decode.Decoder(final),
) -> decode.Decoder(final) {
  use value <- decode.optional_field(
    name,
    None,
    decode.int |> decode.map(option.Some),
  )
  next(value)
}

pub fn decode_http_method() -> decode.Decoder(http.Method) {
  use value <- decode.then(decode.string)
  case string.uppercase(value) {
    "GET" -> decode.success(http.Get)
    "POST" -> decode.success(http.Post)
    "PUT" -> decode.success(http.Put)
    "DELETE" -> decode.success(http.Delete)
    "PATCH" -> decode.success(http.Patch)
    "HEAD" -> decode.success(http.Head)
    "OPTIONS" -> decode.success(http.Options)
    "TRACE" -> decode.success(http.Trace)
    "CONNECT" -> decode.success(http.Connect)
    _ -> decode.failure(http.Get, "http.Method")
  }
}

pub fn decode_url() -> decode.Decoder(uri.Uri) {
  use value <- decode.then(decode.string)
  case uri.parse(value) {
    Ok(uri) -> decode.success(uri)
    Error(_) -> decode.failure(uri.empty, "uri.Uri")
  }
}

pub fn decode_headers(
  next: fn(List(String)) -> decode.Decoder(final),
) -> decode.Decoder(final) {
  use headers <- decode.optional_field(
    "headers",
    [],
    decode.dict(decode.string, decode.string)
      |> decode.map(dict.to_list),
  )

  list.map(headers, fn(tuple) { tuple.0 <> ":" <> tuple.1 })
  |> next
}
