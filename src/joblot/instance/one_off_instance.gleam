import gleam/bool
import joblot/executor
import joblot/instance/attempts
import joblot/instance/builder
import joblot/instance/sql
import pog

pub fn pre_execute_hook(state: builder.State) -> Result(Nil, String) {
  let #(job_data, attempts) = get_info(state)

  case attempts.should_retry(attempts, job_data.maximum_attempts) {
    attempts.CanRetry -> Ok(Nil)
    _ -> {
      let assert Ok(_) =
        sql.set_one_off_job_complete(pog.named_connection(state.db), state.id)
      Ok(Nil)
    }
  }
}

pub fn get_next_execution_time(
  state: builder.State,
) -> Result(builder.NextExecutionResult, String) {
  let #(job_data, attempts) = get_info(state)
  let should_retry = attempts.should_retry(attempts, job_data.maximum_attempts)

  use <- bool.guard(
    when: should_retry != attempts.CanRetry,
    return: Error("Instance should not be retrying"),
  )

  let next_retry_time =
    attempts.next_retry_time(
      attempts,
      job_data.execute_at,
      state.initial_delay_seconds,
      state.factor,
      state.maximum_delay_seconds,
    )

  Ok(builder.NextExecutionResult(job_data.execute_at, next_retry_time))
}

pub fn get_next_request_data(
  state: builder.State,
) -> Result(builder.NextRequestDataResult, String) {
  let assert Ok(pog.Returned(_, [job_data_row])) =
    sql.get_one_off_job(pog.named_connection(state.db), state.id)
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
        attempted_at: attempted_at,
        planned_at: planned_at,
        job_id: state.id,
        job_type: attempts.OneOffJob,
        user_id: job_data_row.user_id,
        tenant_id: job_data_row.tenant_id,
      )
    }),
  )
}

pub fn post_execution_hook(
  state: builder.State,
  _request: executor.ExecutorRequest,
  _execution_result: Result(executor.ExecutorResponse, executor.ExecutorError),
) -> Result(Nil, String) {
  let #(job_data, attempts) = get_info(state)
  case attempts.should_retry(attempts, job_data.maximum_attempts) {
    attempts.CanRetry -> {
      Ok(Nil)
    }
    _ -> {
      let assert Ok(_) =
        sql.set_one_off_job_complete(pog.named_connection(state.db), state.id)
      Ok(Nil)
    }
  }
}

fn get_info(
  state: builder.State,
) -> #(sql.GetOneOffJobRow, List(attempts.Attempt)) {
  let connection = pog.named_connection(state.db)
  let assert Ok(pog.Returned(_, [job_data_row])) =
    sql.get_one_off_job(connection, state.id)
  let assert Ok(attempts) =
    attempts.get_attempts_for_planned_at(
      state.db,
      state.id,
      job_data_row.execute_at,
    )
  #(job_data_row, attempts)
}
