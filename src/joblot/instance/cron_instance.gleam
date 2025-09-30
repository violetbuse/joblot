import clockwork
import gleam/time/duration
import gleam/time/timestamp
import joblot/executor
import joblot/instance/attempts
import joblot/instance/builder
import joblot/instance/sql
import pog

pub fn get_next_execution_time(
  state: builder.State,
) -> Result(builder.NextExecutionResult, String) {
  let latest_planned_at = attempts.latest_planned_at(state.db, state.id)
  let assert Ok(attempts) =
    attempts.get_attempts_for_planned_at(state.db, state.id, latest_planned_at)
  let assert Ok(pog.Returned(_, [job_data_row])) =
    sql.get_cron_job(pog.named_connection(state.db), state.id)

  let should_retry =
    attempts.should_retry(attempts, job_data_row.maximum_attempts)

  case should_retry {
    attempts.CanRetry -> {
      let next_retry_time =
        attempts.next_retry_time(
          attempts,
          latest_planned_at,
          state.initial_delay_seconds,
          state.factor,
          state.maximum_delay_seconds,
        )
      Ok(builder.NextExecutionResult(latest_planned_at, next_retry_time))
    }
    _ -> {
      let assert Ok(cron) = clockwork.from_string(job_data_row.cron)
      let next_occurrence =
        clockwork.next_occurrence(
          cron,
          timestamp.from_unix_seconds(latest_planned_at),
          duration.milliseconds(0),
        )
      let #(unix_seconds, _) =
        timestamp.to_unix_seconds_and_nanoseconds(next_occurrence)
      Ok(builder.NextExecutionResult(unix_seconds, unix_seconds))
    }
  }
}

pub fn get_next_request_data(
  state: builder.State,
) -> Result(builder.NextRequestDataResult, String) {
  let assert Ok(pog.Returned(_, [job_data_row])) =
    sql.get_cron_job(pog.named_connection(state.db), state.id)
  let request =
    executor.ExecutorRequest(
      method: job_data_row.method,
      url: job_data_row.url,
      headers: job_data_row.headers,
      body: job_data_row.body,
      timeout_ms: job_data_row.timeout_ms,
      non_2xx_is_failure: job_data_row.non_2xx_is_failure,
    )
  Ok(
    builder.NextRequestDataResult(request, fn(planned_at, attempted_at) {
      attempts.AttemptSaveData(
        planned_at: planned_at,
        attempted_at: attempted_at,
        job_id: state.id,
        job_type: attempts.CronJob,
        user_id: job_data_row.user_id,
        tenant_id: job_data_row.tenant_id,
      )
    }),
  )
}
