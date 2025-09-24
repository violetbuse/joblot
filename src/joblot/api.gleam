import dot_env/env
import gleam/bytes_tree
import gleam/erlang/process
import gleam/http/request
import gleam/http/response
import joblot/api/cron_jobs/handlers as cron_jobs
import joblot/api/error
import joblot/api/one_off_jobs/handlers as one_off_jobs
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
    _, ["api", "one_off_jobs", ..path_segments] ->
      one_off_jobs.one_off_job_router(path_segments, request, context.db)
    _, ["api", "cron_jobs", ..path_segments] ->
      cron_jobs.cron_job_router(path_segments, request, context.db)
    _, _ -> error.to_response(error.NotFoundError)
  }
}
