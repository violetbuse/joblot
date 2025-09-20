import gleam/bytes_tree
import gleam/http/request.{type Request}
import gleam/http/response.{type Response}
import mist.{type Connection, type ResponseData}
import dot_env/env

fn handle_request(_request: Request(Connection)) -> Response(ResponseData) {
    response.new(200)
    |> response.set_body(mist.Bytes(bytes_tree.from_string("Hello, World!")))
}

pub fn supervised() {
    handle_request
    |> mist.new
    |> mist.bind("0.0.0.0")
    |> mist.with_ipv6
    |> mist.port(env.get_int_or("PORT", 8080))
    |> mist.supervised
}
