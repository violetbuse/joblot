import gleam/bool
import gleam/bytes_tree
import gleam/erlang/process
import gleam/http/request
import gleam/http/response
import gleam/json
import gleam/list
import gleam/option
import gleam/result
import joblot/pubsub
import joblot/swim
import mist
import pog

pub type ApiConfig {
  ApiConfig(
    port: Int,
    bind_address: String,
    swim: process.Subject(swim.Message),
    pubsub: process.Subject(pubsub.Message),
    db_name: process.Name(pog.Message),
    secret: String,
  )
}

type Context {
  Context(
    swim: process.Subject(swim.Message),
    pubsub: process.Subject(pubsub.Message),
    db_name: process.Name(pog.Message),
    secret: String,
  )
}

fn not_found() {
  let data =
    json.object([#("error", json.string("Not Found"))])
    |> json.to_string_tree
    |> bytes_tree.from_string_tree
    |> mist.Bytes

  response.new(404)
  |> response.set_body(data)
}

fn not_authorized() {
  let data =
    json.object([#("error", json.string("Not Authorized."))])
    |> json.to_string_tree
    |> bytes_tree.from_string_tree
    |> mist.Bytes

  response.new(403)
  |> response.set_body(data)
}

fn use_protected(
  req: request.Request(mist.Connection),
  context: Context,
  callback: fn(request.Request(mist.Connection), Context) ->
    response.Response(mist.ResponseData),
) -> response.Response(mist.ResponseData) {
  let secret_header = request.get_header(req, "authorization")
  let secret_param =
    request.get_query(req)
    |> result.map(list.key_find(_, "secret_key"))
    |> result.flatten

  let secret = result.or(secret_header, secret_param) |> result.unwrap("")

  use <- bool.guard(when: secret != context.secret, return: not_authorized())

  callback(req, context)
}

fn handle_swim_cluster_view(
  req: request.Request(mist.Connection),
  context: Context,
) -> response.Response(mist.ResponseData) {
  use _, context <- use_protected(req, context)

  let #(self, nodes) = process.call(context.swim, 1000, swim.GetClusterView)
  let alive_nodes = list.filter(nodes, swim.is_alive)
  let suspect_nodes = list.filter(nodes, swim.is_suspect)
  let dead_nodes = list.filter(nodes, swim.is_dead)

  let alive_json =
    process.call(context.swim, 1000, swim.GetClosestNodes(
      list.map(alive_nodes, fn(node) { node.id }),
      _,
    ))
    |> list.map(fn(node) {
      process.call(context.swim, 1000, swim.GetNodeStats(node.id, _))
      |> swim.encode_node_info(node, _)
    })

  let rest_json =
    list.append(suspect_nodes, dead_nodes)
    |> list.map(swim.encode_node_info(_, option.None))

  let json =
    json.object([
      #("self", swim.encode_node_info(self, option.None)),
      #("nodes", json.preprocessed_array(list.append(alive_json, rest_json))),
    ])

  let bytes =
    json.to_string_tree(json) |> bytes_tree.from_string_tree |> mist.Bytes

  response.new(200)
  |> response.set_header("content-type", "application/json")
  |> response.set_body(bytes)
}

fn handle_swim(
  req: request.Request(mist.Connection),
  context: Context,
) -> response.Response(mist.ResponseData) {
  use req, context <- use_protected(req, context)

  let recv = process.new_subject()
  process.send(context.swim, swim.HandleRequest(req, recv))

  case process.receive(recv, 1000) {
    Ok(res) -> res
    Error(_) -> {
      let json =
        json.object([
          #("error", json.string("No swim process response")),
        ])
        |> json.to_string_tree
        |> bytes_tree.from_string_tree
        |> mist.Bytes

      response.new(500)
      |> response.set_body(json)
    }
  }
}

fn handle_pubsub(
  req: request.Request(mist.Connection),
  context: Context,
) -> response.Response(mist.ResponseData) {
  use req, context <- use_protected(req, context)

  let recv = process.new_subject()
  process.send(context.pubsub, pubsub.HandleRequest(req, recv))

  case process.receive(recv, 1000) {
    Ok(res) -> res
    Error(_) -> {
      let json =
        json.object([#("error", json.string("No pubsub process response"))])
        |> json.to_string_tree
        |> bytes_tree.from_string_tree
        |> mist.Bytes

      response.new(500)
      |> response.set_body(json)
    }
  }
}

fn handle_health_check() -> response.Response(mist.ResponseData) {
  let data =
    json.object([#("healthy", json.bool(True))])
    |> json.to_string_tree
    |> bytes_tree.from_string_tree
    |> mist.Bytes

  response.new(200) |> response.set_body(data)
}

fn handle_request(
  req: request.Request(mist.Connection),
  context: Context,
) -> response.Response(mist.ResponseData) {
  case request.path_segments(req) {
    ["cluster"] -> handle_swim_cluster_view(req, context)
    ["swim", ..] -> handle_swim(req, context)
    ["pubsub", ..] -> handle_pubsub(req, context)
    ["health"] -> handle_health_check()
    _ -> not_found()
  }
}

pub fn supervised(config: ApiConfig) {
  let ctx =
    Context(
      swim: config.swim,
      pubsub: config.pubsub,
      db_name: config.db_name,
      secret: config.secret,
    )

  mist.new(handle_request(_, ctx))
  |> mist.bind("0.0.0.0")
  |> mist.with_ipv6
  |> mist.port(config.port)
  |> mist.supervised
}
