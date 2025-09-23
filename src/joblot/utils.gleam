import gleam/dict
import gleam/dynamic/decode
import gleam/json
import gleam/result
import gleam/time/timestamp
import joblot/api/error

pub fn get_unix_timestamp() -> Int {
  let #(current_time, _) =
    timestamp.system_time() |> timestamp.to_unix_seconds_and_nanoseconds
  current_time
}

pub fn json_string_to_metadata(
  json_string: String,
) -> Result(List(#(String, String)), error.ApiError) {
  json.parse(
    from: json_string,
    using: decode.dict(decode.string, decode.string) |> decode.map(dict.to_list),
  )
  |> result.map_error(fn(_) { error.InternalServerError })
}
