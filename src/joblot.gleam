import dot_env as dot
import gleam/erlang/process
import joblot/shards

pub fn main() {
  dot.load_default()

  let assert Ok(_) =
    shards.create_config(3)
    |> shards.start_program

  process.sleep_forever()
}
