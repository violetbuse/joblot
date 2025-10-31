import dot_env as dot
import dot_env/env
import gleam/erlang/process
import joblot/shards

pub fn main() {
  dot.load_default()

  let assert Ok(_) =
    env.get_int_or("SHARD_COUNT", 3)
    |> shards.create_config()
    |> shards.start_program()

  process.sleep_forever()
}
