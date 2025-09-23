import gleam/erlang/process
import gleam/io
import gleam/otp/actor
import gleam/otp/static_supervisor as supervisor
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
) -> Result(process.Pid, actor.StartError) {
  let result =
    supervisor.new(supervisor.OneForOne)
    |> supervisor.auto_shutdown(supervisor.AnySignificant)
    |> supervisor.add(lock.supervised(
      "instance_lock_" <> job_id.id,
      lock_manager,
      db,
    ))
    |> supervisor.start

  case result {
    Error(error) -> Error(error)
    Ok(actor.Started(pid, _supervisor)) -> Ok(pid)
  }
}
