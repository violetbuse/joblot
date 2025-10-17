import clockwork
import glanoid
import gleam/dict
import gleam/erlang/process
import gleam/function
import gleam/http
import gleam/json
import gleam/list
import gleam/option.{type Option, Some}
import gleam/result
import gleam/uri
import joblot/api/attempts
import joblot/api/cron_jobs/sql
import joblot/api/error
import joblot/hash
import joblot/utils
import pog
import wisp.{type Request as WispRequest}

pub type CronJob {
  CronJob(
    id: String,
    created_at: Int,
    request: RequestData,
    user_id: Option(String),
    tenant_id: Option(String),
    metadata: List(#(String, String)),
    cron: String,
    maximum_attempts: Int,
    attempts: List(attempts.AttemptData),
  )
}

pub type RequestData {
  RequestData(
    method: http.Method,
    url: uri.Uri,
    headers: List(String),
    body: String,
    timeout_ms: Int,
    non_2xx_is_failure: Bool,
  )
}

pub fn cron_job_json(job: CronJob) -> json.Json {
  json.object([
    #("id", json.string(job.id)),
    #("created_at", json.int(job.created_at)),
    #("request", request_data_json(job.request)),
    #("user_id", json.nullable(job.user_id, json.string)),
    #("tenant_id", json.nullable(job.tenant_id, json.string)),
    #(
      "metadata",
      json.dict(job.metadata |> dict.from_list, function.identity, json.string),
    ),
    #("cron", json.string(job.cron)),
    #("maximum_attempts", json.int(job.maximum_attempts)),
    #("attempts", json.array(job.attempts, attempts.attempt_data_json)),
  ])
}

fn request_data_json(request: RequestData) -> json.Json {
  json.object([
    #("method", json.string(http.method_to_string(request.method))),
    #("url", json.string(uri.to_string(request.url))),
    #("headers", json.array(request.headers, json.string)),
    #("body", json.string(request.body)),
    #("timeout_ms", json.int(request.timeout_ms)),
    #("non_2xx_is_failure", json.bool(request.non_2xx_is_failure)),
  ])
}

pub type CreateCronJob {
  CreateCronJob(
    cron: clockwork.Cron,
    method: http.Method,
    url: uri.Uri,
    headers: List(String),
    body: String,
    metadata: List(#(String, String)),
    user_id: Option(String),
    tenant_id: Option(String),
    timeout_ms: Option(Int),
    maximum_attempts: Option(Int),
    non_2xx_is_failure: Option(Bool),
  )
}

pub fn create_cron_job(
  db: process.Name(pog.Message),
  job: CreateCronJob,
) -> Result(CronJob, error.ApiError) {
  let connection = pog.named_connection(db)

  let assert Ok(nanoid) = glanoid.make_generator(glanoid.default_alphabet)
  let id = "cron_job_" <> nanoid(21)
  let hash = hash.create_shard_key_hash(id)

  let user_id = job.user_id |> option.unwrap("")
  let tenant_id = job.tenant_id |> option.unwrap("")
  let metadata =
    job.metadata
    |> dict.from_list
    |> json.dict(function.identity, json.string)

  let method = http.method_to_string(job.method)
  let url = uri.to_string(job.url)
  let headers = job.headers
  let body = job.body

  let cron = clockwork.to_string(job.cron)
  let maximum_attempts = job.maximum_attempts |> option.unwrap(1)
  let non_2xx_is_failure = job.non_2xx_is_failure |> option.unwrap(True)
  let timeout_ms = job.timeout_ms |> option.unwrap(10_000)

  let insert_result =
    sql.create_cron_job(
      connection,
      id,
      hash,
      user_id,
      tenant_id,
      metadata,
      cron,
      method,
      url,
      headers,
      body,
      maximum_attempts,
      non_2xx_is_failure,
      timeout_ms,
    )

  use returned <- result.try(
    insert_result |> result.map_error(error.from_pog_query_error),
  )

  case returned {
    pog.Returned(_, [single_row]) ->
      Ok(
        CronJob(
          id: single_row.id,
          created_at: single_row.created_at,
          request: RequestData(
            method: job.method,
            url: job.url,
            headers: single_row.headers,
            body: single_row.body,
            timeout_ms: single_row.timeout_ms,
            non_2xx_is_failure: single_row.non_2xx_is_failure,
          ),
          user_id: single_row.user_id |> option.Some,
          tenant_id: single_row.tenant_id |> option.Some,
          metadata: job.metadata,
          cron: single_row.cron,
          maximum_attempts: single_row.maximum_attempts,
          attempts: [],
        ),
      )
    _ -> panic as "Attempted to create cron job but got multiple rows"
  }
}

pub type Filter {
  Filter(user_id: Option(String), tenant_id: Option(String))
}

pub fn filter_from_request(request: WispRequest) -> Option(Filter) {
  let query = wisp.get_query(request)
  let user_id = query |> list.key_find("user_id") |> option.from_result
  let tenant_id = query |> list.key_find("tenant_id") |> option.from_result
  Some(Filter(user_id, tenant_id))
}

fn filter_user_id_like(filter: Option(Filter)) -> String {
  filter
  |> option.map(fn(filter) { filter.user_id })
  |> option.flatten
  |> option.unwrap("%")
}

fn filter_tenant_id_like(filter: Option(Filter)) -> String {
  filter
  |> option.map(fn(filter) { filter.tenant_id })
  |> option.flatten
  |> option.unwrap("%")
}

pub fn delete_cron_job(
  db: process.Name(pog.Message),
  id: String,
  filter: Option(Filter),
) -> Result(Option(CronJob), error.ApiError) {
  let connection = pog.named_connection(db)
  let user_id = filter_user_id_like(filter)
  let tenant_id = filter_tenant_id_like(filter)

  let got_row = get_cron_job(db, id, filter) |> option.from_result
  let delete_result =
    sql.delete_cron_job(connection, id, user_id, tenant_id)
    |> result.map_error(error.from_pog_query_error)

  delete_result
  |> result.replace(got_row)
}

pub fn get_cron_job(
  db: process.Name(pog.Message),
  id: String,
  filter: Option(Filter),
) -> Result(CronJob, error.ApiError) {
  let connection = pog.named_connection(db)
  let user_id = filter_user_id_like(filter)
  let tenant_id = filter_tenant_id_like(filter)

  use pog.Returned(_, rows) <- result.try(
    sql.get_cron_job(connection, id, user_id, tenant_id)
    |> result.map_error(error.from_pog_query_error),
  )

  let ids = rows |> list.map(fn(row) { row.id })

  use attempts <- result.try(attempts.get_attempts_for_jobs(db, ids))

  case rows {
    [item] -> {
      let attempts = attempts |> dict.get(item.id) |> result.unwrap([])
      use method <- result.try(
        http.parse_method(item.method)
        |> result.replace_error(error.InternalServerError),
      )
      use url <- result.try(
        uri.parse(item.url) |> result.replace_error(error.InternalServerError),
      )
      use metadata <- result.try(utils.json_string_to_metadata(item.metadata))
      Ok(CronJob(
        id: item.id,
        created_at: item.created_at,
        request: RequestData(
          method: method,
          url: url,
          headers: item.headers,
          body: item.body,
          timeout_ms: item.timeout_ms,
          non_2xx_is_failure: item.non_2xx_is_failure,
        ),
        user_id: item.user_id |> option.Some,
        tenant_id: item.tenant_id |> option.Some,
        metadata: metadata,
        cron: item.cron,
        maximum_attempts: item.maximum_attempts,
        attempts: attempts,
      ))
    }
    [] -> Error(error.NotFoundError)
    _ -> panic as "Attempted to get cron job but got multiple rows"
  }
}

pub fn list_cron_jobs(
  db: process.Name(pog.Message),
  cursor: String,
  filter: Option(Filter),
) -> Result(List(CronJob), error.ApiError) {
  let connection = pog.named_connection(db)
  let user_id = filter_user_id_like(filter)
  let tenant_id = filter_tenant_id_like(filter)

  use pog.Returned(_, rows) <- result.try(
    sql.list_cron_jobs(connection, user_id, tenant_id, cursor, 10)
    |> result.map_error(error.from_pog_query_error),
  )

  let ids = rows |> list.map(fn(row) { row.id })

  use attempts <- result.try(attempts.get_attempts_for_jobs(db, ids))

  rows
  |> list.map(fn(row) {
    use method <- result.try(
      http.parse_method(row.method)
      |> result.replace_error(error.InternalServerError),
    )
    use url <- result.try(
      uri.parse(row.url) |> result.replace_error(error.InternalServerError),
    )
    use metadata <- result.try(utils.json_string_to_metadata(row.metadata))
    Ok(CronJob(
      id: row.id,
      created_at: row.created_at,
      request: RequestData(
        method: method,
        url: url,
        headers: row.headers,
        body: row.body,
        timeout_ms: row.timeout_ms,
        non_2xx_is_failure: row.non_2xx_is_failure,
      ),
      user_id: row.user_id |> option.Some,
      tenant_id: row.tenant_id |> option.Some,
      metadata: metadata,
      cron: row.cron,
      maximum_attempts: row.maximum_attempts,
      attempts: attempts |> dict.get(row.id) |> result.unwrap([]),
    ))
  })
  |> result.all
}
