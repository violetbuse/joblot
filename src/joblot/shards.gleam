import dot_env/env
import glanoid
import gleam/bool
import gleam/erlang/process
import gleam/io
import gleam/list
import gleam/option
import gleam/otp/static_supervisor
import gleam/result
import gleam/string
import gleam/uri
import joblot/api
import joblot/swim
import pog

pub type Config {
  Config(
    listen_address: uri.Uri,
    bind_address: String,
    server_id: String,
    bootstrap_addresses: List(uri.Uri),
    port: Int,
    region: String,
    valid_regions: List(String),
    secret: String,
    db_name: process.Name(pog.Message),
    db_url: String,
    db_pool_size: Int,
    swim_name: process.Name(swim.Message),
    shards: List(Shard),
  )
}

pub type Shard {
  Shard(
    shard_id: Int,
    secret: String,
    region: String,
    db_name: process.Name(pog.Message),
  )
}

pub fn create_config(shard_count: Int) -> Config {
  let assert Ok(nanoid) = glanoid.make_generator(glanoid.default_alphabet)

  let assert Ok(hostname) = env.get_string("HOSTNAME")
  let bind_address = env.get_string_or("BIND_ADDRESS", "0.0.0.0")
  let assert Ok(port) = env.get_int("PORT")
  let secret = env.get_string_or("SECRET", "")
  let region = env.get_string_or("REGION", "auto")

  let valid_regions =
    env.get_string_or("VALID_REGIONS", region)
    |> string.split(",")
    |> list.filter(fn(str) { string.is_empty(str) |> bool.negate })
    |> list.map(string.lowercase)

  let listen_address =
    uri.Uri(
      ..uri.empty,
      scheme: option.Some("http"),
      host: option.Some(hostname),
      port: option.Some(port),
      path: "/",
    )
  let bootstrap_addresses =
    env.get_string_or("BOOTSTRAP_NODES", "")
    |> string.split(",")
    |> list.filter(fn(str) { string.is_empty(str) |> bool.negate })
    |> list.map(uri.parse)
    |> result.values

  list.map(bootstrap_addresses, uri.to_string) |> list.each(io.println)

  let server_id = env.get_string_or("SERVER_ID", nanoid(21))
  let assert Ok(db_url) = env.get_string("DATABASE_URL")
  let db_pool_size = env.get_int_or("POOL_SIZE", 10)
  let db_name = process.new_name("db_pool")

  let swim_name = process.new_name("swim")

  Config(
    listen_address:,
    bind_address:,
    server_id:,
    bootstrap_addresses:,
    port:,
    secret:,
    region:,
    valid_regions:,
    db_name:,
    db_url:,
    db_pool_size:,
    swim_name:,
    shards: list.range(from: 1, to: shard_count)
      |> list.map(fn(shard_id) { Shard(shard_id:, secret:, region:, db_name:) }),
  )
}

fn create_shard_supervisor(_config: Shard) {
  static_supervisor.new(static_supervisor.OneForOne)
  |> static_supervisor.supervised
}

fn multiple_shards(builder: static_supervisor.Builder, config: List(Shard)) {
  case config {
    [] -> builder
    [first, ..rest] ->
      static_supervisor.add(builder, create_shard_supervisor(first))
      |> multiple_shards(rest)
  }
}

fn swim_config(config: Config) -> swim.SwimConfig {
  swim.SwimConfig(
    api_address: config.listen_address,
    server_id: config.server_id,
    name: config.swim_name,
    secret: config.secret,
    bootstrap_addresses: config.bootstrap_addresses,
    region: config.region,
    shard_count: config.shards |> list.length,
  )
}

fn api_config(config: Config) -> api.ApiConfig {
  api.ApiConfig(
    port: config.port,
    swim: config.swim_name |> process.named_subject,
    db_name: config.db_name,
    secret: config.secret,
    bind_address: config.bind_address,
  )
}

pub fn start_program(config: Config) {
  let assert Ok(pool_config) = pog.url_config(config.db_name, config.db_url)
  let db_pool_supervised =
    pool_config |> pog.pool_size(config.db_pool_size) |> pog.supervised

  let assert Ok(_) =
    static_supervisor.new(static_supervisor.OneForOne)
    |> static_supervisor.add(db_pool_supervised)
    |> static_supervisor.add(swim_config(config) |> swim.supervised)
    |> static_supervisor.add(api_config(config) |> api.supervised)
    |> multiple_shards(config.shards)
    |> static_supervisor.start
}
