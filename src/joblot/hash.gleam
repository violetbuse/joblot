import gleam/bit_array
import gleam/crypto
import gleam/int
import gleam/result

pub fn create_shard_key_hash(id: String) -> Int {
  let result = {
    let bits_result =
      bit_array.from_string(id)
      |> crypto.hash(crypto.Sha256, _)
      |> bit_array.slice(0, 32)

    use bits <- result.try(bits_result)
    bits |> bit_array.base16_encode |> int.base_parse(16)
  }

  case result {
    Error(error) -> {
      echo "could not create shard key hash"
      echo error
      echo "id: "
      panic as "could not create shard key hash from id"
    }
    Ok(int) -> int
  }
}
