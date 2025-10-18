import clockwork
import gleam/bool
import gleam/float
import gleam/list
import gleam/result
import gleam/time/duration
import gleam/time/timestamp
import joblot/cache
import joblot/cache/cron as cron_cache
import joblot/executor
import joblot/instance/attempts
import joblot/instance/builder

pub fn create_refresh_function(state: builder.State) -> builder.RefreshFunction {
  fn() { cache.refresh_cache(state.cron_job_cache, state.id) }
}

pub fn get_next_execution_time(
  state: builder.State,
) -> Result(builder.NextExecutionResult, String) {
  use cron_job <- result.try(cache.query_cache(
    state.cron_job_cache,
    state.id,
    10_000,
  ))
  let should_retry = {
    let any_successful = list.any(cron_job.attempts, cron_cache.is_successful)
    use <- bool.guard(when: any_successful, return: False)
    use <- bool.guard(
      when: list.length(cron_job.attempts) >= cron_job.maximum_attempts,
      return: False,
    )
    True
  }

  let last_planned_at =
    list.first(cron_job.attempts)
    |> result.map(fn(a) { a.planned_at })
    |> result.unwrap(cron_job.created_at)

  case should_retry {
    True -> {
      attempts.next_retry_time(
        attempts: list.map(cron_job.attempts, fn(a) { a.attempted_at }),
        planned: last_planned_at,
        initial: cron_job.initial_delay_secs,
        factor: cron_job.retry_factor,
        maximum: cron_job.maximum_delay_secs,
      )
      |> builder.NextExecutionResult(last_planned_at, _)
      |> Ok
    }
    False -> {
      let next_planned =
        clockwork.next_occurrence(
          cron_job.cron,
          timestamp.from_unix_seconds(last_planned_at),
          with_offset: duration.seconds(0),
        )
        |> timestamp.to_unix_seconds
        |> float.round
      Ok(builder.NextExecutionResult(next_planned, next_planned))
    }
  }
}

pub fn get_next_request_data(
  state: builder.State,
) -> Result(builder.NextRequestDataResult, String) {
  use cron_job <- result.try(cache.query_cache(
    state.cron_job_cache,
    state.id,
    10_000,
  ))
  let request =
    executor.ExecutorRequest(
      method: cron_job.method,
      url: cron_job.url,
      headers: cron_job.headers,
      body: cron_job.body,
      timeout_ms: cron_job.timeout_ms,
      non_2xx_is_failure: cron_job.non_2xx_is_failure,
    )
  Ok(
    builder.NextRequestDataResult(request, fn(planned_at, attempted_at) {
      attempts.AttemptSaveData(
        planned_at: planned_at,
        attempted_at: attempted_at,
        job_id: state.id,
        job_type: attempts.CronJob,
        user_id: cron_job.user_id,
        tenant_id: cron_job.tenant_id,
      )
    }),
  )
}
