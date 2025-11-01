import gleam/bool
import gleam/bytes_tree
import gleam/erlang/process
import gleam/http/request
import gleam/http/response
import gleam/json
import gleam/list
import gleam/result
import joblot/swim
import mist
import pog

pub type ApiConfig {
  ApiConfig(
    port: Int,
    bind_address: String,
    swim: process.Subject(swim.Message),
    db_name: process.Name(pog.Message),
    secret: String,
  )
}

type Context {
  Context(
    swim: process.Subject(swim.Message),
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
          #(
            "error",
            json.string("Did not receive a response from the swim process"),
          ),
        ])

      let byte_tree = json.to_string_tree(json) |> bytes_tree.from_string_tree

      response.new(500)
      |> response.set_body(mist.Bytes(byte_tree))
    }
  }
}

fn handle_swim_cluster_view(
  req: request.Request(mist.Connection),
  context: Context,
) -> response.Response(mist.ResponseData) {
  use _, context <- use_protected(req, context)

  let #(self, nodes) = process.call(context.swim, 1000, swim.GetClusterView)
  let json =
    json.object([
      #("self", swim.encode_node_info(self)),
      #(
        "nodes",
        json.array(nodes |> list.sort(swim.compare_node), swim.encode_node_info),
      ),
    ])

  let bytes =
    json.to_string_tree(json) |> bytes_tree.from_string_tree |> mist.Bytes

  response.new(200)
  |> response.set_header("content-type", "application/json")
  |> response.set_body(bytes)
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
    ["swim"] -> handle_swim(req, context)
    ["cluster"] -> handle_swim_cluster_view(req, context)
    ["health"] -> handle_health_check()
    _ -> not_found()
  }
}

pub fn supervised(config: ApiConfig) {
  let ctx =
    Context(swim: config.swim, db_name: config.db_name, secret: config.secret)

  mist.new(handle_request(_, ctx))
  |> mist.bind("0.0.0.0")
  |> mist.with_ipv6
  |> mist.port(config.port)
  |> mist.supervised
}
