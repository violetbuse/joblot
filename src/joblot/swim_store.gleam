import gleam/bool
import gleam/dynamic/decode
import gleam/erlang/process
import gleam/float
import gleam/list
import gleam/otp/actor
import gleam/result
import gleam/time/timestamp
import gleam/uri
import joblot/util
import sqlight

pub type NodeInfo {
  NodeInfo(
    id: String,
    version: Int,
    state: NodeState,
    address: uri.Uri,
    region: String,
    shard_count: Int,
  )
}

const default_node_info = NodeInfo("", 0, Dead, uri.empty, "", 0)

pub type NodeState {
  Alive
  Suspect
  Dead
}

fn state_to_string(state: NodeState) -> String {
  case state {
    Alive -> "alive"
    Suspect -> "suspect"
    Dead -> "dead"
  }
}

pub type SwimStore {
  SwimStore(subject: process.Subject(Message))
}

pub opaque type Message {
  GetNode(node_id: String, recv: process.Subject(Result(NodeInfo, Nil)))
  GetNodes(recv: process.Subject(List(NodeInfo)))
  SetLastOnline(node_id: String)
  SetState(node_id: String, state: NodeState)
  SetAliveWithoutVersionIncrement(node_id: String)
  Update(node_info: NodeInfo)
  IncreaseVersionTo(node_id: String, new_version: Int)
}

type State {
  State(db: sqlight.Connection)
}

const migrations = [
  "CREATE TABLE IF NOT EXISTS nodes (
    id TEXT NOT NULL PRIMARY KEY,
    version INTEGER NOT NULL CHECK (version >= 0),
    state TEXT NOT NULL CHECK (state IN ('alive', 'suspect', 'dead')),
    address TEXT NOT NULL,
    region TEXT NOT NULL,
    shard_count INTEGER NOT NULL CHECK(shard_count >= 0),
    last_online INTEGER NOT NULL DEFAULT 0
    ) STRICT;",
]

fn initialize(
  self: process.Subject(Message),
  datafile: String,
) -> Result(actor.Initialised(State, Message, SwimStore), String) {
  use db <- util.with_connection(datafile, migrations)

  actor.initialised(State(db:))
  |> actor.returning(SwimStore(self))
  |> Ok
}

fn node_decoder() -> decode.Decoder(NodeInfo) {
  {
    use id <- decode.field(0, decode.string)
    use version <- decode.field(1, decode.int)
    use state <- decode.field(2, decode.string)
    use address <- decode.field(3, decode.string)
    use region <- decode.field(4, decode.string)
    use shard_count <- decode.field(5, decode.int)

    let parsed_uri = uri.parse(address)
    use <- bool.guard(
      when: result.is_error(parsed_uri),
      return: decode.failure(default_node_info, "InvalidUri"),
    )

    let assert Ok(uri) = parsed_uri

    let node = case state {
      "alive" -> NodeInfo(id, version, Alive, uri, region, shard_count)
      "suspect" -> NodeInfo(id, version, Suspect, uri, region, shard_count)
      "dead" -> NodeInfo(id, version, Dead, uri, region, shard_count)
      _ -> panic as "invalid node state"
    }

    decode.success(node)
  }
}

fn internal_get_node(
  db: sqlight.Connection,
  node_id: String,
) -> Result(NodeInfo, Nil) {
  let sql =
    "
  SELECT id, version, state, address, region, shard_count
  FROM nodes
  WHERE id = ?1;
  "

  use rows <- result.try(
    sqlight.query(sql, db, [sqlight.text(node_id)], node_decoder())
    |> util.log_error("error fetching node from sqlite")
    |> result.replace_error(Nil),
  )

  list.first(rows)
}

fn internal_get_nodes(
  db: sqlight.Connection,
) -> Result(List(NodeInfo), sqlight.Error) {
  let sql =
    "
  SELECT id, version, state, address, region, shard_count
  FROM nodes;
  "

  sqlight.query(sql, db, [], node_decoder())
  |> util.log_error("error fetching node from sqlite")
}

fn handle_message(state: State, message: Message) -> actor.Next(State, Message) {
  case message {
    GetNode(node_id:, recv:) -> handle_get_node(state, node_id, recv)
    GetNodes(recv:) -> handle_get_nodes(state, recv)
    SetState(node_id:, state: new_state) ->
      handle_set_state(state, node_id, new_state)
    SetAliveWithoutVersionIncrement(node_id:) ->
      handle_set_alive_without_version_increment(state, node_id)
    SetLastOnline(node_id:) -> handle_set_last_online(state, node_id)
    Update(node_info:) -> handle_update(state, node_info)
    IncreaseVersionTo(node_id:, new_version:) ->
      handle_increase_version_to(state, node_id, new_version)
  }
}

fn handle_get_node(
  state: State,
  node_id: String,
  recv: process.Subject(Result(NodeInfo, Nil)),
) -> actor.Next(State, Message) {
  let node = internal_get_node(state.db, node_id)

  process.send(recv, node)

  actor.continue(state)
}

fn handle_get_nodes(
  state: State,
  recv: process.Subject(List(NodeInfo)),
) -> actor.Next(State, Message) {
  let assert Ok(nodes) = internal_get_nodes(state.db)
    as "failed to get nodes from sqlite"

  process.send(recv, nodes)

  actor.continue(state)
}

fn handle_set_last_online(
  state: State,
  node_id: String,
) -> actor.Next(State, Message) {
  let now = timestamp.system_time() |> timestamp.to_unix_seconds |> float.round
  let sql =
    "
  UPDATE nodes
  SET last_online = ?2, state = 'alive'
  WHERE id = ?1;
  "

  let assert Ok(_) =
    sqlight.query(
      sql,
      state.db,
      [sqlight.text(node_id), sqlight.int(now)],
      decode.dynamic,
    )
    as "could not update last online time for node"

  actor.continue(state)
}

fn handle_set_state(
  state: State,
  node_id: String,
  new_state: NodeState,
) -> actor.Next(State, Message) {
  let sql =
    "
  UPDATE nodes
  SET state = ?2, version = version + 1
  WHERE id = ?1;
  "

  let node_state = case new_state {
    Alive -> "alive"
    Dead -> "dead"
    Suspect -> "suspect"
  }

  let assert Ok(_) =
    sqlight.query(
      sql,
      state.db,
      [sqlight.text(node_id), sqlight.text(node_state)],
      decode.dynamic,
    )
    as "could not update state for node"

  actor.continue(state)
}

fn handle_set_alive_without_version_increment(
  state: State,
  node_id: String,
) -> actor.Next(State, Message) {
  let sql =
    "
  UPDATE nodes
  SET state = 'alive'
  WHERE id = ?1;
  "

  let assert Ok(_) =
    sqlight.query(sql, state.db, [sqlight.text(node_id)], decode.dynamic)
    as "could not update state for node"

  actor.continue(state)
}

fn handle_update(
  state: State,
  node_info: NodeInfo,
) -> actor.Next(State, Message) {
  let sql =
    "INSERT INTO nodes
        (id, version, state, address, region, shard_count)
      VALUES
        (?1, ?2, ?3, ?4, ?5, ?6) ON CONFLICT (id) DO UPDATE
      SET
        version = ?2, state = ?3, address = ?4, region = ?5, shard_count = ?6
      WHERE version < ?2"

  let assert Ok(_) =
    sqlight.query(
      sql,
      state.db,
      [
        sqlight.text(node_info.id),
        sqlight.int(node_info.version),
        sqlight.text(node_info.state |> state_to_string),
        sqlight.text(node_info.address |> uri.to_string),
        sqlight.text(node_info.region),
        sqlight.int(node_info.shard_count),
      ],
      decode.dynamic,
    )
    as "coultn't update node"

  actor.continue(state)
}

fn handle_increase_version_to(
  state: State,
  node_id: String,
  new_version: Int,
) -> actor.Next(State, Message) {
  let sql =
    "
  UPDATE nodes
  SET version = MAX(version, ?2)
  WHERE id = ?1
  "

  let assert Ok(_) =
    sqlight.query(
      sql,
      state.db,
      [sqlight.text(node_id), sqlight.int(new_version)],
      decode.dynamic,
    )
    as "could not set new version for node"

  actor.continue(state)
}

pub fn start(datafile: String) -> Result(SwimStore, Nil) {
  let start_result =
    actor.new_with_initialiser(1000, initialize(_, datafile))
    |> actor.on_message(handle_message)
    |> actor.start

  case start_result {
    Error(error) -> {
      echo error
      Error(Nil)
    }
    Ok(start_result) -> {
      process.link(start_result.pid)
      Ok(start_result.data)
    }
  }
}

pub fn get_node(store: SwimStore, node_id: String) {
  process.call(store.subject, 1000, GetNode(node_id, _))
}

pub fn get_nodes(store: SwimStore) {
  process.call(store.subject, 1000, GetNodes)
}

pub fn set_last_online(store: SwimStore, node_id: String) {
  process.send(store.subject, SetLastOnline(node_id))
}

pub fn set_state(store: SwimStore, node_id: String, new_state: NodeState) {
  process.send(store.subject, SetState(node_id, new_state))
}

pub fn set_alive_without_version_increment(store: SwimStore, node_id: String) {
  process.send(store.subject, SetAliveWithoutVersionIncrement(node_id))
}

pub fn update(store: SwimStore, node: NodeInfo) {
  process.send(store.subject, Update(node))
}

pub fn set_version_to(store: SwimStore, node_id: String, new_version: Int) {
  process.send(store.subject, IncreaseVersionTo(node_id:, new_version:))
}
