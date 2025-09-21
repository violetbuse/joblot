import dot_env/env
import gleam/bytes_tree
import gleam/erlang/process
import gleam/http/request.{type Request}
import gleam/http/response.{type Response}
import mist.{type Connection, type ResponseData}
import pog

type Context {
  Context(db: process.Name(pog.Message))
}

fn handle_request(
  _request: Request(Connection),
  _context: Context,
) -> Response(ResponseData) {
  response.new(200)
  |> response.set_body(mist.Bytes(bytes_tree.from_string("Hello, World!")))
}

pub fn supervised(db: process.Name(pog.Message)) {
  let context = Context(db)

  mist.new(handle_request(_, context))
  |> mist.bind("0.0.0.0")
  |> mist.with_ipv6
  |> mist.port(env.get_int_or("PORT", 8080))
  |> mist.supervised
}
