import dot_env as dot
import dot_env/env
import gleam/erlang/application
import gleam/erlang/process
import gleam/io
import gleam/otp/static_supervisor as supervisor
import joblot/api
import joblot/cache/cron as cron_cache
import joblot/cache/one_off_jobs as one_off_cache
import joblot/lock
import joblot/reconciler
import joblot/registry
import joblot/scanner
import joblot/target
import pog

pub fn main() {
  dot.load_default()

  let assert Ok(priv) = application.priv_directory("joblot")
  io.println("Priv directory: " <> priv)

  let pool_name = process.new_name("pool")
  let target_name = process.new_name("target")
  let registry_name = process.new_name("registry")
  let lock_manager_name = process.new_name("lock_manager")

  let one_off_jobs_cache_name = process.new_name("one_off_jobs_cache")
  let cron_jobs_cache_name = process.new_name("cron_jobs_cache")

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
    |> supervisor.add(api.supervised(pool_name))
    |> supervisor.add(target.supervised(target_name))
    |> supervisor.add(cron_cache.supervised(cron_jobs_cache_name, pool_name))
    |> supervisor.add(one_off_cache.supervised(
      one_off_jobs_cache_name,
      pool_name,
    ))
    |> supervisor.add(registry.supervised(
      registry_name,
      pool_name,
      lock_manager_name,
      cron_jobs_cache_name,
      one_off_jobs_cache_name,
    ))
    |> supervisor.add(lock.lock_manager_supervised(lock_manager_name, pool_name))
    |> supervisor.add(reconciler.supervised(
      target: target_name,
      registry: registry_name,
    ))
    |> supervisor.add(scanner.supervised(pool_name, target_name))
    |> supervisor.start

  process.sleep_forever()
}
