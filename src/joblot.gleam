import gleam/otp/static_supervisor as supervisor
import dot_env as dot
import api
import gleam/erlang/process
import target
import registry
import reconciler

pub fn main() {
  dot.load_default()

  let target_name = process.new_name("target")
  let registry_name = process.new_name("registry")
  let reconciler_name = process.new_name("reconciler")

  let assert Ok(_) = supervisor.new(supervisor.OneForOne)
  |> supervisor.add(api.supervised())
  |> supervisor.add(target.supervised(target_name))
  |> supervisor.add(registry.supervised(registry_name))
  |> supervisor.add(reconciler.supervised(reconciler_name, target:target_name, registry:registry_name))
  |> supervisor.start

  process.sleep_forever()
}
