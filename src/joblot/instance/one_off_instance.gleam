import gleam/bool
import gleam/list
import gleam/result
import joblot/cache
import joblot/cache/one_off_jobs
import joblot/executor
import joblot/instance/attempts
import joblot/instance/builder
import joblot/instance/sql
import pog

pub fn create_refresh_function(state: builder.State) -> builder.RefreshFunction {
  fn() { cache.refresh_cache(state.one_off_cache, state.id) }
}

pub fn pre_execute_hook(
  state: builder.State,
  refresh: fn() -> Nil,
) -> Result(Nil, String) {
  use job <- result.try(cache.query_cache(state.one_off_cache, state.id, 10_000))

  case should_retry(job) {
    True -> Ok(Nil)
    False -> {
      let assert Ok(_) =
        sql.set_one_off_job_complete(pog.named_connection(state.db), state.id)
      refresh()
      Ok(Nil)
    }
  }
}

pub fn get_next_execution_time(
  state: builder.State,
) -> Result(builder.NextExecutionResult, String) {
  use job <- result.try(cache.query_cache(state.one_off_cache, state.id, 10_000))

  use <- bool.guard(
    when: !should_retry(job),
    return: Error("Instance should not be retrying. Id: " <> state.id),
  )

  attempts.next_retry_time(
    attempts: list.map(job.attempts, fn(a) { a.attempted_at }),
    planned: job.execute_at,
    initial: job.initial_delay_secs,
    factor: job.retry_factor,
    maximum: job.maximum_delay_secs,
  )
  |> builder.NextExecutionResult(job.execute_at, _)
  |> Ok
}

pub fn get_next_request_data(
  state: builder.State,
) -> Result(builder.NextRequestDataResult, String) {
  use job <- result.try(cache.query_cache(state.one_off_cache, state.id, 10_000))
  let request =
    executor.ExecutorRequest(
      method: job.method,
      url: job.url,
      headers: job.headers,
      body: job.body,
      timeout_ms: job.timeout_ms,
      non_2xx_is_failure: job.non_2xx_is_failure,
    )
  Ok(
    builder.NextRequestDataResult(request, fn(planned_at, attempted_at) {
      attempts.AttemptSaveData(
        attempted_at: attempted_at,
        planned_at: planned_at,
        job_id: state.id,
        job_type: attempts.OneOffJob,
        user_id: job.user_id,
        tenant_id: job.tenant_id,
      )
    }),
  )
}

pub fn post_execution_hook(
  state: builder.State,
  _request: executor.ExecutorRequest,
  _execution_result: Result(executor.ExecutorResponse, executor.ExecutorError),
  refresh: fn() -> Nil,
) -> Result(Nil, String) {
  use job <- result.try(cache.query_cache(state.one_off_cache, state.id, 10_000))
  case should_retry(job) {
    True -> {
      Ok(Nil)
    }
    False -> {
      let assert Ok(_) =
        sql.set_one_off_job_complete(pog.named_connection(state.db), state.id)
      refresh()
      Ok(Nil)
    }
  }
}

fn should_retry(job: one_off_jobs.Job) -> Bool {
  let any_successful = list.any(job.attempts, one_off_jobs.is_successful)
  use <- bool.guard(when: any_successful, return: False)
  use <- bool.guard(
    when: list.length(job.attempts) >= job.maximum_attempts,
    return: False,
  )
  True
}
