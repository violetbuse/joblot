import gleam/erlang/process
import gleam/otp/actor
import gleam/otp/static_supervisor as supervisor
import joblot/cache/cron as cron_cache
import joblot/cache/one_off_jobs as one_off_cache
import joblot/instance/builder
import joblot/instance/cron_instance
import joblot/instance/one_off_instance
import joblot/lock
import pog

pub type JobId {
  Cron(id: String)
  OneTime(id: String)
}

pub fn start(
  job_id: JobId,
  db: process.Name(pog.Message),
  lock_manager: process.Name(lock.LockMgrMessage),
  cron_cache: process.Name(cron_cache.Message),
  one_off_cache: process.Name(one_off_cache.Message),
) -> Result(process.Pid, actor.StartError) {
  let lock_id = "instance_lock_" <> job_id.id

  let result =
    supervisor.new(supervisor.OneForOne)
    |> supervisor.add(lock.supervised(lock_id, lock_manager, db))
    |> try_add_cron_worker(
      job_id,
      db,
      lock_manager,
      cron_cache,
      one_off_cache,
      lock_id,
    )
    |> try_add_one_off_worker(
      job_id,
      db,
      lock_manager,
      cron_cache,
      one_off_cache,
      lock_id,
    )
    |> supervisor.start

  case result {
    Error(error) -> Error(error)
    Ok(actor.Started(pid, _supervisor)) -> Ok(pid)
  }
}

fn try_add_cron_worker(
  supervisor: supervisor.Builder,
  job_id: JobId,
  db: process.Name(pog.Message),
  lock_manager: process.Name(lock.LockMgrMessage),
  cron_cache: process.Name(cron_cache.Message),
  one_off_cache: process.Name(one_off_cache.Message),
  lock_id: String,
) -> supervisor.Builder {
  case job_id {
    Cron(id) -> {
      builder.new()
      |> builder.create_refresh_function(cron_instance.create_refresh_function)
      |> builder.next_execution_time(cron_instance.get_next_execution_time)
      |> builder.next_request_data(cron_instance.get_next_request_data)
      |> builder.heartbeat_interval_ms(5000)
      |> builder.supervised(
        id,
        lock_id,
        db,
        lock_manager,
        cron_cache,
        one_off_cache,
      )
      |> supervisor.add(supervisor, _)
    }
    OneTime(_id) -> supervisor
  }
}

fn try_add_one_off_worker(
  supervisor: supervisor.Builder,
  job_id: JobId,
  db: process.Name(pog.Message),
  lock_manager: process.Name(lock.LockMgrMessage),
  cron_cache: process.Name(cron_cache.Message),
  one_off_cache: process.Name(one_off_cache.Message),
  lock_id: String,
) -> supervisor.Builder {
  case job_id {
    Cron(_id) -> supervisor
    OneTime(id) -> {
      builder.new()
      |> builder.create_refresh_function(
        one_off_instance.create_refresh_function,
      )
      |> builder.next_execution_time(one_off_instance.get_next_execution_time)
      |> builder.next_request_data(one_off_instance.get_next_request_data)
      |> builder.post_execution_hook(one_off_instance.post_execution_hook)
      |> builder.heartbeat_interval_ms(5000)
      |> builder.supervised(
        id,
        lock_id,
        db,
        lock_manager,
        cron_cache,
        one_off_cache,
      )
      |> supervisor.add(supervisor, _)
    }
  }
}
