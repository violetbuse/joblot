import dot_env/env
import gleam/bytes_tree
import gleam/erlang/process
import gleam/http
import gleam/http/request
import gleam/http/response
import joblot/api/one_off_jobs
import mist.{type Connection, type ResponseData}
import pog
import wisp.{type Request, type Response}
import wisp/wisp_mist

type Context {
  Context(db: process.Name(pog.Message))
}

pub fn supervised(db: process.Name(pog.Message)) {
  let context = Context(db)
  let secret = env.get_string_or("SECRET", "shhhh! super secret value!!!!!")

  let wisp_handler = wisp_mist.handler(handle_request(_, context), secret)

  mist.new(mist_handler(_, context, wisp_handler))
  |> mist.bind("0.0.0.0")
  |> mist.with_ipv6
  |> mist.port(env.get_int_or("PORT", 8080))
  |> mist.supervised
}

fn mist_handler(
  req: request.Request(Connection),
  _context: Context,
  wisp_handler: fn(request.Request(Connection)) ->
    response.Response(ResponseData),
) -> response.Response(ResponseData) {
  case request.path_segments(req) {
    ["mist"] ->
      response.new(200)
      |> response.set_body(
        mist.Bytes(bytes_tree.from_string("Hello from mist!")),
      )
    _ -> wisp_handler(req)
  }
}

fn handle_request(request: Request, context: Context) -> Response {
  use <- wisp.log_request(request)

  case request.method, request.path_segments(request) {
    http.Post, ["api", "one_off_jobs"] ->
      one_off_jobs.handle_create_one_off_job(request, context.db)
    http.Put, ["api", "one_off_jobs", id] ->
      one_off_jobs.handle_update_one_off_job(id, request, context.db)
    http.Delete, ["api", "one_off_jobs", id] ->
      one_off_jobs.handle_delete_one_off_job(id, request, context.db)
    http.Get, ["api", "one_off_jobs", id] ->
      one_off_jobs.handle_get_one_off_job(id, request, context.db)
    http.Get, ["api", "one_off_jobs"] ->
      one_off_jobs.handle_list_one_off_jobs(request, context.db)
    _, _ -> wisp.not_found()
  }
}
