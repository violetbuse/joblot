import gleam/bool
import gleam/bytes_tree
import gleam/dict
import gleam/dynamic/decode
import gleam/erlang/process
import gleam/http
import gleam/http/request
import gleam/http/response
import gleam/int
import gleam/io
import gleam/json
import gleam/list
import gleam/option
import gleam/order
import gleam/otp/actor
import gleam/otp/supervision
import gleam/result
import gleam/uri
import httpp/send
import joblot/util
import mist

const heartbeat_interval = 5000

pub type SwimConfig {
  SwimConfig(
    api_address: uri.Uri,
    bootstrap_addresses: List(uri.Uri),
    server_id: String,
    name: process.Name(Message),
    secret: String,
    region: String,
  )
}

pub type Message {
  HandleRequest(
    req: request.Request(mist.Connection),
    response: ResponseChannel,
  )
  Heartbeat
  SelfInfo(NodeInfo)
  YouInfo(NodeInfo)
  Info(NodeInfo)
  FailedSync(node_id: String)
  MarkDead(node_id: String)
  MarkAlive(node_id: String)
  GetClusterView(recv: process.Subject(#(NodeInfo, List(NodeInfo))))
}

pub type ResponseChannel =
  process.Subject(response.Response(mist.ResponseData))

type State {
  State(
    subject: process.Subject(Message),
    self: NodeInfo,
    nodes: dict.Dict(String, NodeInfo),
    cluster_secret: String,
    bootstrap_addresses: List(uri.Uri),
  )
}

pub type NodeInfo {
  NodeInfo(
    version: Int,
    state: NodeState,
    id: String,
    address: uri.Uri,
    region: String,
  )
}

pub type NodeState {
  Alive
  Suspect
  Dead
}

pub fn compare_state(a: NodeInfo, b: NodeInfo) -> order.Order {
  case a.state, b.state {
    Alive, Alive -> order.Eq
    Alive, Suspect -> order.Lt
    Alive, Dead -> order.Lt
    Suspect, Alive -> order.Gt
    Suspect, Suspect -> order.Eq
    Suspect, Dead -> order.Lt
    Dead, Alive -> order.Gt
    Dead, Suspect -> order.Gt
    Dead, Dead -> order.Eq
  }
}

fn degrade_state(node: NodeInfo) -> NodeInfo {
  let new_state = case node.state {
    Alive -> Suspect
    existing -> existing
  }

  NodeInfo(..node, state: new_state)
}

pub fn is_alive(node: NodeInfo) -> Bool {
  node.state == Alive
}

pub fn is_suspect(node: NodeInfo) -> Bool {
  node.state == Suspect
}

pub fn is_dead(node: NodeInfo) -> Bool {
  node.state == Dead
}

const empty_node_info = NodeInfo(
  version: 0,
  state: Dead,
  id: "",
  address: uri.empty,
  region: "auto",
)

pub fn encode_node_info(node_info: NodeInfo) -> json.Json {
  let status_string = case node_info.state {
    Alive -> "alive"
    Suspect -> "suspect"
    Dead -> "dead"
  }

  json.object([
    #("id", json.string(node_info.id)),
    #("status", json.string(status_string)),
    #("version", json.int(node_info.version)),
    #("address", json.string(node_info.address |> uri.to_string)),
    #("region", json.string(node_info.region)),
  ])
}

pub fn decode_node_info() -> decode.Decoder(NodeInfo) {
  {
    let node_state_decoder = {
      use status <- decode.then(decode.string)

      case status {
        "alive" -> decode.success(Alive)
        "suspect" -> decode.success(Suspect)
        "dead" -> decode.success(Dead)
        _ -> decode.failure(Alive, "NodeState")
      }
    }

    use id <- decode.field("id", decode.string)
    use state <- decode.field("status", node_state_decoder)
    use version <- decode.field("version", decode.int)
    use addr_string <- decode.field("address", decode.string)
    use region <- decode.field("region", decode.string)

    case uri.parse(addr_string) {
      Error(_) -> decode.failure(empty_node_info, "uri.Uri")
      Ok(address) ->
        decode.success(NodeInfo(id:, state:, version:, address:, region:))
    }
    // decode.success(NodeInfo(id:, version:, address:))
  }
}

fn initialize(
  self: process.Subject(Message),
  config: SwimConfig,
) -> Result(actor.Initialised(State, Message, Nil), String) {
  process.send(self, Heartbeat)

  actor.initialised(State(
    subject: self,
    self: NodeInfo(
      version: 1,
      state: Alive,
      id: config.server_id,
      address: config.api_address,
      region: config.region,
    ),
    nodes: dict.new(),
    cluster_secret: config.secret,
    bootstrap_addresses: config.bootstrap_addresses,
  ))
  |> Ok
}

fn on_message(state: State, message: Message) -> actor.Next(State, Message) {
  case message {
    HandleRequest(req, recv) -> handle_request(state, req, recv)
    Heartbeat -> handle_heartbeat(state)
    Info(info) -> handle_info(state, info)
    SelfInfo(info) -> handle_self_info(state, info)
    YouInfo(info) -> handle_you_info(state, info)
    FailedSync(node_id) -> handle_failed_sync(state, node_id)
    MarkDead(node_id) -> handle_mark_dead(state, node_id)
    MarkAlive(node_id) -> handle_mark_alive(state, node_id)
    GetClusterView(recv) -> get_cluster_view(state, recv)
  }
}

fn handle_heartbeat(state: State) -> actor.Next(State, Message) {
  process.send_after(state.subject, heartbeat_interval, Heartbeat)

  heartbeat_sync(state)
  try_bootstrap(state)

  actor.continue(state)
}

fn heartbeat_sync(state: State) {
  process.spawn(fn() {
    let nodelist = dict.values(state.nodes)

    let alive_nodes = list.filter(nodelist, is_alive) |> list.sample(10)
    let sus_nodes =
      list.filter(nodelist, is_suspect) |> list.sample(int.random(1))
    let dead_nodes =
      list.filter(nodelist, is_dead) |> list.sample(int.random(1))

    let candidates =
      alive_nodes |> list.append(sus_nodes) |> list.append(dead_nodes)

    list.each(candidates, fn(candidate) {
      process.spawn(fn() {
        let result =
          send_sync_request(
            candidate.address,
            state.cluster_secret,
            state.self,
            state.nodes |> dict.values |> list.sample(10),
          )

        case result {
          Error(_) -> process.send(state.subject, FailedSync(candidate.id))
          Ok(sync_response) -> {
            process.send(state.subject, MarkAlive(sync_response.self.id))
            process.send(state.subject, SelfInfo(sync_response.self))
            process.send(state.subject, YouInfo(sync_response.you))
            list.each(sync_response.subset, fn(node) {
              process.send(state.subject, Info(node))
            })
          }
        }
      })
    })
  })
}

fn try_bootstrap(state: State) {
  process.spawn(fn() {
    let stringify_addr = fn(uri: uri.Uri) -> String {
      let assert option.Some(hostname) = uri.host
      let assert option.Some(port) = uri.port

      hostname <> ":" <> int.to_string(port)
    }

    let already_connected_nodes =
      [state.self, ..dict.values(state.nodes)]
      |> list.map(fn(node) { stringify_addr(node.address) })

    let not_connected_bootstrap_nodes =
      list.filter(state.bootstrap_addresses, fn(addr) {
        let key = stringify_addr(addr)

        list.contains(already_connected_nodes, key) |> bool.negate
      })

    list.sample(not_connected_bootstrap_nodes, 5)
    |> list.each(fn(address) {
      let result =
        send_sync_request(
          address,
          state.cluster_secret,
          state.self,
          state.nodes |> dict.values |> list.sample(10),
        )

      case result {
        Error(_) -> Nil
        Ok(sync_response) -> {
          process.send(state.subject, SelfInfo(sync_response.self))
          process.send(state.subject, YouInfo(sync_response.you))
          list.each(sync_response.subset, fn(node) {
            process.send(state.subject, Info(node))
          })
        }
      }
    })
  })
}

fn handle_info(state: State, info: NodeInfo) -> actor.Next(State, Message) {
  use <- bool.guard(
    when: info.id == state.self.id,
    return: actor.continue(state),
  )

  actor.continue(
    State(
      ..state,
      nodes: dict.upsert(state.nodes, info.id, fn(existing) {
        case existing {
          option.None -> info
          option.Some(existing_node) if existing_node.version < info.version ->
            info
          option.Some(existing_node) -> existing_node
        }
      }),
    ),
  )
}

fn handle_self_info(state: State, info: NodeInfo) -> actor.Next(State, Message) {
  use <- bool.guard(
    when: info.id == state.self.id,
    return: actor.continue(state),
  )

  actor.continue(
    State(
      ..state,
      nodes: dict.upsert(state.nodes, info.id, fn(existing) {
        case existing {
          option.None -> info
          option.Some(existing_node)
            if existing_node != info && existing_node.version <= info.version
          -> info
          option.Some(existing_node) -> existing_node
        }
      }),
    ),
  )
}

fn handle_you_info(state: State, info: NodeInfo) -> actor.Next(State, Message) {
  let next_version = {
    use <- bool.guard(when: state.self == info, return: info.version)
    use <- bool.guard(
      when: state.self.version > info.version,
      return: state.self.version,
    )
    use <- bool.guard(
      when: state.self.version <= info.version,
      return: info.version + 1,
    )
    state.self.version
  }

  case info != state.self {
    False -> Nil
    True -> io.println("you & self mismatch")
  }

  case next_version > state.self.version {
    False -> Nil
    True -> io.println("incrementing self version because of version mismatch")
  }

  actor.continue(
    State(..state, self: NodeInfo(..state.self, version: next_version)),
  )
}

fn handle_failed_sync(
  state: State,
  node_id: String,
) -> actor.Next(State, Message) {
  io.println_error("sync with " <> node_id <> " failed, handling.")

  let new_nodes = case dict.get(state.nodes, node_id) {
    Error(_) -> state.nodes
    Ok(node) -> dict.insert(state.nodes, node_id, degrade_state(node))
  }

  process.spawn(fn() {
    let random_alive_node =
      dict.values(state.nodes)
      |> list.filter(is_alive)
      |> list.sample(1)
      |> list.first
    case dict.get(state.nodes, node_id), random_alive_node {
      Error(_), _ -> Nil
      Ok(_), Error(_) -> {
        process.send(state.subject, MarkDead(node_id:))
      }
      Ok(node), Ok(other_alive_node) -> {
        let successful = case
          send_request_ping(
            other_alive_node.address,
            state.cluster_secret,
            node,
          )
        {
          Error(_) -> False
          Ok(RequestPingResponse(success)) -> success
        }

        case successful {
          True -> process.send(state.subject, MarkAlive(node_id:))
          False -> process.send(state.subject, MarkDead(node_id:))
        }
      }
    }
  })

  actor.continue(State(..state, nodes: new_nodes))
}

fn handle_mark_dead(state: State, node_id: String) -> actor.Next(State, Message) {
  let new_nodes = case dict.get(state.nodes, node_id) {
    Error(_) -> state.nodes
    Ok(node) if node.state == Dead -> state.nodes
    Ok(node) ->
      dict.insert(
        state.nodes,
        node_id,
        NodeInfo(..node, state: Dead, version: node.version + 1),
      )
  }

  actor.continue(State(..state, nodes: new_nodes))
}

fn handle_mark_alive(
  state: State,
  node_id: String,
) -> actor.Next(State, Message) {
  let new_nodes = case dict.get(state.nodes, node_id) {
    Error(_) -> state.nodes
    Ok(node) if node.state == Alive -> state.nodes
    Ok(node) ->
      dict.insert(
        state.nodes,
        node_id,
        NodeInfo(..node, state: Alive, version: node.version + 1),
      )
  }

  actor.continue(State(..state, nodes: new_nodes))
}

fn get_cluster_view(
  state: State,
  recv: process.Subject(#(NodeInfo, List(NodeInfo))),
) -> actor.Next(State, Message) {
  process.send(recv, #(state.self, dict.values(state.nodes)))
  actor.continue(state)
}

type Request {
  Sync(self: NodeInfo, subset: List(NodeInfo))
  Ping
  RequestPing(node: NodeInfo)
}

fn encode_request(request: Request) -> json.Json {
  case request {
    Sync(self, subset) ->
      json.object([
        #("type", json.string("sync")),
        #("self", encode_node_info(self)),
        #("subset", json.array(subset, encode_node_info)),
      ])
    Ping -> json.object([#("type", json.string("ping"))])
    RequestPing(node_info) ->
      json.object([
        #("type", json.string("requesting_ping")),
        #("node", encode_node_info(node_info)),
      ])
  }
}

fn decode_request() -> decode.Decoder(Request) {
  let heartbeat_decoder = {
    use self <- decode.field("self", decode_node_info())
    use subset <- decode.field("subset", decode.list(decode_node_info()))

    decode.success(Sync(self:, subset:))
  }

  let ping_request_decoder = {
    use node <- decode.field("node", decode_node_info())

    decode.success(RequestPing(node))
  }

  {
    use tag <- decode.field("type", decode.string)

    case tag {
      "sync" -> heartbeat_decoder
      "ping" -> decode.success(Ping)
      "requesting_ping" -> ping_request_decoder
      _ -> decode.failure(Ping, "ValidSwimRequestType")
    }
  }
}

const one_gb = 1_099_511_627_776

fn handle_request(
  state: State,
  req: request.Request(mist.Connection),
  recv: ResponseChannel,
) -> actor.Next(State, Message) {
  let assert Ok(req) = mist.read_body(req, one_gb)
  case json.parse_bits(req.body, decode_request()) {
    Error(_) -> {
      io.println_error("Invalid incoming swim request.")
      let error =
        json.object([#("error", json.string("Invalid swim request."))])
      let error_bytes =
        json.to_string_tree(error) |> bytes_tree.from_string_tree

      let response =
        response.new(400) |> response.set_body(mist.Bytes(error_bytes))

      process.send(recv, response)

      actor.continue(state)
    }
    Ok(request) ->
      case request {
        Sync(self:, subset:) -> handle_sync_request(state, recv, self, subset)
        Ping -> handle_ping(recv, state)
        RequestPing(node:) -> handle_request_ping(state, recv, node)
      }
  }
}

type SyncResponse {
  SyncResponse(self: NodeInfo, you: NodeInfo, subset: List(NodeInfo))
}

fn encode_sync_response(res: SyncResponse) -> json.Json {
  json.object([
    #("self", encode_node_info(res.self)),
    #("you", encode_node_info(res.you)),
    #("subset", json.array(res.subset, encode_node_info)),
  ])
}

fn decode_sync_response() -> decode.Decoder(SyncResponse) {
  {
    use self <- decode.field("self", decode_node_info())
    use you <- decode.field("you", decode_node_info())
    use subset <- decode.field("subset", decode.list(decode_node_info()))

    decode.success(SyncResponse(self:, you:, subset:))
  }
}

fn handle_sync_request(
  state: State,
  recv: ResponseChannel,
  self: NodeInfo,
  subset: List(NodeInfo),
) -> actor.Next(State, Message) {
  // io.println("Incoming sync from " <> self.id)
  process.send(state.subject, SelfInfo(self))
  list.each(subset, fn(node) { process.send(state.subject, Info(node)) })

  let you = dict.get(state.nodes, self.id) |> result.unwrap(self)

  let response_bytes =
    SyncResponse(
      self: state.self,
      you:,
      subset: dict.values(state.nodes) |> list.sample(10),
    )
    |> encode_sync_response
    |> json.to_string
    |> bytes_tree.from_string

  let response =
    response.new(200) |> response.set_body(mist.Bytes(response_bytes))

  process.send(recv, response)

  actor.continue(state)
}

fn send_sync_request(
  api_address: uri.Uri,
  secret: String,
  self: NodeInfo,
  subset: List(NodeInfo),
) -> Result(SyncResponse, Nil) {
  let assert Ok(base_req) =
    uri.Uri(..api_address, path: "/swim") |> request.from_uri

  let data = Sync(self:, subset:) |> encode_request |> json.to_string

  let request =
    base_req
    |> request.set_method(http.Post)
    |> request.set_header("authorization", secret)
    |> request.set_query([#("secret_key", secret)])
    |> request.set_body(data)

  use response <- result.try(
    send.send(request)
    |> util.log_error(
      "Error getting result from " <> request.host <> " for sync request",
    )
    |> result.replace_error(Nil),
  )
  use heartbeat_response <- result.try(
    json.parse(response.body, decode_sync_response())
    |> util.log_error(
      "Error parsing sync response from "
      <> request.host
      <> ": "
      <> response.body,
    )
    |> result.replace_error(Nil),
  )

  Ok(heartbeat_response)
}

type PingResponse {
  PingResponse
}

fn encode_ping_response(_res: PingResponse) -> json.Json {
  json.object([#("type", json.string("ping_response"))])
}

fn decode_ping_response() -> decode.Decoder(PingResponse) {
  {
    use msg_type <- decode.field("type", decode.string)

    case msg_type {
      "ping_response" -> PingResponse |> decode.success
      _ -> decode.failure(PingResponse, "PingResponse")
    }
  }
}

fn handle_ping(
  recv: ResponseChannel,
  state: State,
) -> actor.Next(State, Message) {
  // io.println("Incoming ping!")
  let response = PingResponse |> encode_ping_response
  let response_bytes =
    response
    |> json.to_string_tree
    |> bytes_tree.from_string_tree

  let response =
    response.new(200) |> response.set_body(mist.Bytes(response_bytes))

  process.send(recv, response)

  actor.continue(state)
}

fn send_ping(api_address: uri.Uri, secret: String) -> Result(PingResponse, Nil) {
  let assert Ok(base_req) =
    uri.Uri(..api_address, path: "/swim") |> request.from_uri

  let data = Ping |> encode_request |> json.to_string

  let request =
    base_req
    |> request.set_method(http.Post)
    |> request.set_header("authorization", secret)
    |> request.set_query([#("secret_key", secret)])
    |> request.set_body(data)

  use response <- result.try(
    send.send(request)
    |> util.log_error(
      "Error fetching http from " <> request.host <> " for ping",
    )
    |> result.replace_error(Nil),
  )
  use ping_response <- result.try(
    json.parse(response.body, decode_ping_response())
    |> util.log_error(
      "Error parsing ping response from "
      <> request.host
      <> ": "
      <> response.body,
    )
    |> result.replace_error(Nil),
  )

  Ok(ping_response)
}

type RequestPingResponse {
  RequestPingResponse(successful: Bool)
}

fn encode_request_ping_response(res: RequestPingResponse) -> json.Json {
  json.object([#("successful", json.bool(res.successful))])
}

fn decode_request_ping_response() -> decode.Decoder(RequestPingResponse) {
  {
    use successful <- decode.field("successful", decode.bool)

    RequestPingResponse(successful) |> decode.success
  }
}

fn handle_request_ping(
  state: State,
  recv: ResponseChannel,
  to_ping: NodeInfo,
) -> actor.Next(State, Message) {
  // io.println("Incoming request ping for " <> to_ping.id)
  process.spawn(fn() {
    let successful = case send_ping(to_ping.address, state.cluster_secret) {
      Error(_) -> False
      Ok(_) -> True
    }

    let response_bytes =
      RequestPingResponse(successful:)
      |> encode_request_ping_response
      |> json.to_string_tree
      |> bytes_tree.from_string_tree

    let response =
      response.new(200) |> response.set_body(mist.Bytes(response_bytes))

    process.send(recv, response)
  })

  actor.continue(state)
}

fn send_request_ping(
  api_address: uri.Uri,
  secret: String,
  to_ping: NodeInfo,
) -> Result(RequestPingResponse, Nil) {
  let assert Ok(base_req) =
    uri.Uri(..api_address, path: "/swim") |> request.from_uri

  let data = RequestPing(to_ping) |> encode_request |> json.to_string

  let request =
    base_req
    |> request.set_method(http.Post)
    |> request.set_header("authorization", secret)
    |> request.set_query([#("secret_key", secret)])
    |> request.set_body(data)

  use response <- result.try(
    send.send(request)
    |> util.log_error(
      "Error http fetch from " <> request.host <> " for request ping",
    )
    |> result.replace_error(Nil),
  )
  use request_ping_response <- result.try(
    json.parse(response.body, decode_request_ping_response())
    |> util.log_error(
      "Error parsing response from " <> request.host <> ": " <> response.body,
    )
    |> result.replace_error(Nil),
  )

  echo request_ping_response

  Ok(request_ping_response)
}

pub fn supervised(config: SwimConfig) {
  supervision.worker(fn() {
    actor.new_with_initialiser(1000, initialize(_, config))
    |> actor.on_message(on_message)
    |> actor.named(config.name)
    |> actor.start
  })
}
