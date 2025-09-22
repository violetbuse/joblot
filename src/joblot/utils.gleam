import gleam/time/timestamp

pub fn get_unix_timestamp() -> Int {
  let #(current_time, _) =
    timestamp.system_time() |> timestamp.to_unix_seconds_and_nanoseconds
  current_time
}
