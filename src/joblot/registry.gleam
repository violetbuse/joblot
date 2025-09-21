import gleam/dict.{type Dict}
import gleam/erlang/process
import gleam/int
import gleam/list
import gleam/otp/actor
import gleam/otp/supervision
import gleam/result
import joblot/instance
import joblot/lock
import pog

const test_instances_interval = 10_000

pub fn start_registry(
  name: process.Name(Message),
  db: process.Name(pog.Message),
  lock_manager: process.Name(lock.LockMgrMessage),
) {
  actor.new_with_initialiser(5000, fn(subject) {
    process.send_after(subject, test_instances_interval, TestInstances)
    let state = State(subject, db, lock_manager, dict.new(), dict.new())

    let selector =
      process.new_selector()
      |> process.select(subject)
      |> process.select_monitors(fn(down) {
        let assert process.ProcessDown(_, pid, reason) = down
        InstanceExited(pid, reason)
      })

    actor.initialised(state)
    |> actor.selecting(selector)
    |> actor.returning(subject)
    |> Ok
  })
  |> actor.on_message(handle_message)
  |> actor.named(name)
  |> actor.start
}

pub fn supervised(
  name: process.Name(Message),
  db: process.Name(pog.Message),
  lock_manager: process.Name(lock.LockMgrMessage),
) {
  supervision.worker(fn() { start_registry(name, db, lock_manager) })
}

type InstanceInfo {
  InstanceInfo(job_id: instance.JobId, supervisor_pid: process.Pid)
}

type State {
  State(
    self: process.Subject(Message),
    db: process.Name(pog.Message),
    lock_manager: process.Name(lock.LockMgrMessage),
    instances: Dict(process.Pid, InstanceInfo),
    jobid_index: Dict(instance.JobId, process.Pid),
  )
}

pub opaque type Message {
  InstanceExited(process.Pid, reason: process.ExitReason)
  TestInstances
  AddInstance(instance.JobId)
  RemoveInstance(instance.JobId)
}

fn handle_message(state: State, message: Message) -> actor.Next(State, Message) {
  case message {
    InstanceExited(pid, reason) -> handle_instance_exited(state, pid, reason)
    TestInstances -> handle_test_instances(state)
    AddInstance(job_id) -> handle_add_instance(state, job_id)
    RemoveInstance(job_id) -> handle_remove_instance(state, job_id)
  }
}

fn replace_instance(
  state: State,
  job_id: instance.JobId,
  pid: process.Pid,
) -> Result(State, String) {
  use supervisor_pid <- result.try(
    instance.start(job_id, state.db, state.lock_manager)
    |> result.replace_error("Failed to start replacement instance"),
  )

  let new_info = InstanceInfo(job_id, supervisor_pid)

  let new_instances_dict =
    state.instances
    |> dict.delete(pid)
    |> dict.insert(supervisor_pid, new_info)

  let new_jobid_index =
    state.jobid_index
    |> dict.insert(job_id, supervisor_pid)

  Ok(
    State(..state, instances: new_instances_dict, jobid_index: new_jobid_index),
  )
}

fn handle_instance_exited(
  state: State,
  pid: process.Pid,
  _reason: process.ExitReason,
) -> actor.Next(State, Message) {
  case dict.get(state.instances, pid) {
    Ok(InstanceInfo(job_id, _)) -> {
      case replace_instance(state, job_id, pid) {
        Ok(new_state) -> actor.continue(new_state)
        Error(reason) -> {
          state.instances
          |> dict.each(fn(_, info) { process.send_exit(info.supervisor_pid) })

          actor.stop_abnormal(reason)
        }
      }
    }
    Error(_) -> {
      let new_jobid_index =
        state.jobid_index
        |> dict.filter(fn(_, value) { value != pid })

      actor.continue(State(..state, jobid_index: new_jobid_index))
    }
  }
}

fn handle_test_instances(state: State) -> actor.Next(State, Message) {
  process.send_after(state.self, test_instances_interval, TestInstances)

  let sample_size =
    dict.size(state.instances)
    |> int.divide(4)
    |> result.map(int.clamp(_, 3, 30))
    |> result.unwrap(3)

  let randomly_selected_instances =
    state.instances
    |> dict.to_list
    |> list.sample(sample_size)

  let new_state_result =
    list.fold(
      randomly_selected_instances,
      Ok(state),
      fn(state_result, instance) -> Result(State, String) {
        let #(pid, InstanceInfo(job_id, _)) = instance
        case process.is_alive(pid) {
          True -> state_result
          False ->
            case state_result {
              Ok(state) -> replace_instance(state, job_id, pid)
              Error(reason) -> Error(reason)
            }
        }
      },
    )

  case new_state_result {
    Ok(new_state) -> actor.continue(new_state)
    Error(reason) -> {
      actor.stop_abnormal(reason)
    }
  }
}

fn handle_add_instance(
  state: State,
  job_id: instance.JobId,
) -> actor.Next(State, Message) {
  let new_state_result = {
    let existing_instance_info =
      dict.get(state.jobid_index, job_id)
      |> result.map(dict.get(state.instances, _))

    case existing_instance_info {
      Ok(_existing_instance) -> Ok(state)
      Error(_) -> {
        use pid <- result.try(
          instance.start(job_id, state.db, state.lock_manager)
          |> result.replace_error("Failed to start new instance"),
        )

        let new_info = InstanceInfo(job_id, pid)
        let new_instances_dict = state.instances |> dict.insert(pid, new_info)

        let new_jobid_index = state.jobid_index |> dict.insert(job_id, pid)

        Ok(
          State(
            ..state,
            instances: new_instances_dict,
            jobid_index: new_jobid_index,
          ),
        )
      }
    }
  }

  case new_state_result {
    Ok(new_state) -> actor.continue(new_state)
    Error(reason) -> {
      actor.stop_abnormal(reason)
    }
  }
}

fn handle_remove_instance(
  state: State,
  job_id: instance.JobId,
) -> actor.Next(State, Message) {
  let pid = dict.get(state.jobid_index, job_id)

  let instance_subject =
    pid
    |> result.map(dict.get(state.instances, _))
    |> result.flatten
    |> result.map(fn(info) { info.supervisor_pid })

  let new_instances_dict =
    pid
    |> result.map(dict.delete(state.instances, _))
    |> result.unwrap(state.instances)
  let new_jobid_index = dict.delete(state.jobid_index, job_id)

  let _ = instance_subject |> result.map(process.send_exit)

  actor.continue(
    State(..state, instances: new_instances_dict, jobid_index: new_jobid_index),
  )
}
