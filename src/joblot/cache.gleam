import gleam/erlang/process
import gleam/option
import joblot/cache/registry

pub fn query_cache(
  name: process.Name(registry.Message(datatype)),
  id: String,
  timeout: Int,
) {
  let recv = process.new_subject()
  process.send(name |> process.named_subject, registry.GetData(id, recv))

  process.receive(recv, timeout)
  |> option.from_result
  |> option.flatten
  |> option.to_result("Could not fetch data from cache for id: " <> id)
}

pub fn refresh_cache(name: process.Name(registry.Message(datatype)), id: String) {
  process.send(name |> process.named_subject, registry.Refresh(id))
}
