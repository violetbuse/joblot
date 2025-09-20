import dot_env as dot
import dot_env/env
import gleam/erlang/application
import gleam/erlang/process
import gleam/io
import gleam/otp/static_supervisor as supervisor
import joblot/api
import joblot/reconciler
import joblot/registry
import joblot/target
import pog

pub fn main() {
  dot.load_default()

  let assert Ok(priv) = application.priv_directory("joblot")
  io.println("Priv directory: " <> priv)

  let pool_name = process.new_name("pool")
  let target_name = process.new_name("target")
  let registry_name = process.new_name("registry")
  let reconciler_name = process.new_name("reconciler")

  let db_url =
    env.get_string_or(
      "DATABASE_URL",
      "postgres://postgres:postgres@localhost:5432/postgres",
    )
  let assert Ok(pool_config) = pog.url_config(pool_name, db_url)

  let pool_child =
    pool_config
    |> pog.pool_size(env.get_int_or("POOL_SIZE", 10))
    |> pog.supervised

  let assert Ok(_) =
    supervisor.new(supervisor.OneForOne)
    |> supervisor.add(pool_child)
    |> supervisor.add(api.supervised())
    |> supervisor.add(target.supervised(target_name))
    |> supervisor.add(registry.supervised(registry_name, pool_name))
    |> supervisor.add(reconciler.supervised(
      reconciler_name,
      target: target_name,
      registry: registry_name,
    ))
    |> supervisor.start

  process.sleep_forever()
}
