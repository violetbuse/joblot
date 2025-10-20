import dot_env/env
import gleam/erlang/process
import gleam/list
import gleam/otp/static_supervisor as supervisor
import joblot/api
import joblot/cache/cron as cron_cache
import joblot/cache/one_off_jobs as one_off_cache
import joblot/lock
import joblot/pubsub
import joblot/reconciler
import joblot/registry
import joblot/scanner
import joblot/servers
import joblot/target
import pog

pub type ProgramConfig {
  ProgramConfig(
    address: String,
    servers_name: process.Name(servers.Message),
    db_name: process.Name(pog.Message),
    db_url: String,
    db_pool_size: Int,
    pubsub_name: process.Name(pubsub.Message),
    pubsub_port: Int,
    api_port: Int,
    shards: List(ShardConfig),
  )
}

pub type ShardConfig {
  ShardConfig(
    shard_id: Int,
    db_name: process.Name(pog.Message),
    pubsub_name: process.Name(pubsub.Message),
    cron_cache: process.Name(cron_cache.Message),
    one_off_cache: process.Name(one_off_cache.Message),
    target: process.Name(target.Message),
    registry: process.Name(registry.Message),
    locks: process.Name(lock.LockMgrMessage),
  )
}

pub fn create_config(shard_count: Int) -> ProgramConfig {
  let address = env.get_string_or("HOSTNAME", "127.0.0.1:9090")

  let servers_name = process.new_name("servers_watcher")

  let db_url =
    env.get_string_or(
      "DATABASE_URL",
      "postgres://postgres:postgres@localhost:5432/postgres",
    )

  let db_pool_size = env.get_int_or("POOL_SIZE", 10)

  let db_name = process.new_name("db_pool")

  let pubsub_name = process.new_name("pubsub")

  let pubsub_port = env.get_int_or("PUBSUB_PORT", 9090)

  let api_port = env.get_int_or("API_PORT", 8080)

  ProgramConfig(
    address:,
    servers_name:,
    db_name:,
    db_pool_size:,
    db_url:,
    pubsub_name:,
    pubsub_port:,
    api_port:,
    shards: list.range(from: 1, to: shard_count)
      |> list.map(fn(local_shard_id) {
        ShardConfig(
          shard_id: local_shard_id,
          db_name:,
          pubsub_name:,
          cron_cache: process.new_name("cron_cache"),
          one_off_cache: process.new_name("one_off_cache"),
          target: process.new_name("target"),
          registry: process.new_name("registry"),
          locks: process.new_name("locks_manager"),
        )
      }),
  )
}

fn create_shard_supervisor(config: ShardConfig) {
  supervisor.new(supervisor.OneForOne)
  |> supervisor.add(cron_cache.supervised(
    config.cron_cache,
    config.db_name,
    config.pubsub_name,
  ))
  |> supervisor.add(one_off_cache.supervised(
    config.one_off_cache,
    config.db_name,
    config.pubsub_name,
  ))
  |> supervisor.add(target.supervised(config.target, config.shard_id))
  |> supervisor.add(lock.lock_manager_supervised(config.locks, config.db_name))
  |> supervisor.add(registry.supervised(
    config.registry,
    config.db_name,
    config.locks,
    config.cron_cache,
    config.one_off_cache,
  ))
  |> supervisor.add(reconciler.supervised(
    target: config.target,
    registry: config.registry,
  ))
  |> supervisor.add(scanner.supervised(config.db_name, config.target))
}

pub fn start_shard(config: ShardConfig) {
  let assert Ok(_) = create_shard_supervisor(config) |> supervisor.start
}

fn shard_supervised(config: ShardConfig) {
  create_shard_supervisor(config) |> supervisor.supervised
}

fn multiple_shards(
  builder: supervisor.Builder,
  config: List(ShardConfig),
) -> supervisor.Builder {
  case config {
    [] -> builder
    [first, ..rest] ->
      supervisor.add(builder, shard_supervised(first)) |> multiple_shards(rest)
  }
}

pub fn start_program(config: ProgramConfig) {
  let assert Ok(pool_config) = pog.url_config(config.db_name, config.db_url)
  let db_pool_supervised =
    pool_config |> pog.pool_size(config.db_pool_size) |> pog.supervised

  let cron_caches = list.map(config.shards, fn(shard) { shard.cron_cache })
  let one_off_caches =
    list.map(config.shards, fn(shard) { shard.one_off_cache })

  let assert Ok(_) =
    supervisor.new(supervisor.OneForOne)
    |> supervisor.add(db_pool_supervised)
    |> supervisor.add(servers.supervised(
      config.servers_name,
      config.db_name,
      config.address,
    ))
    |> supervisor.add(pubsub.supervised(config.pubsub_name, config.pubsub_port))
    |> supervisor.add(api.supervised(
      config.db_name,
      config.pubsub_name,
      cron_caches,
      one_off_caches,
      config.api_port,
    ))
    |> multiple_shards(config.shards)
    |> supervisor.start
}
