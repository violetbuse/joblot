import gleam/dict
import gleam/dynamic/decode
import gleam/option.{type Option, None, Some}

pub fn decode_metadata() -> decode.Decoder(List(#(String, String))) {
  use metadata <- decode.optional_field(
    "metadata",
    [],
    decode.optional(
      decode.dict(decode.string, decode.string) |> decode.map(dict.to_list),
    )
      |> decode.map(option.unwrap(_, [])),
  )

  decode.success(metadata)
}
