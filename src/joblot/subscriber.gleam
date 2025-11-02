import gleam/bool
import gleam/erlang/process
import gleam/float
import gleam/int
import gleam/list
import gleam/option
import gleam/order
import gleam/set
import gleam/time/timestamp
import joblot/channel
import joblot/pubsub

pub opaque type Subscriber {
  Subscriber(subject: process.Subject(Message))
}

pub opaque type Message {
  Unsubscribe
  IncomingEvent(channel.PubsubEvent)
  Vacuum
  Heartbeat
  Publish(data: String, recv: process.Subject(Event))
}

pub type Event {
  Event(time: Int, data: String)
}

type State {
  State(
    pubsub: process.Subject(pubsub.Message),
    channel_name: String,
    latest_event: option.Option(Int),
    self: process.Subject(Message),
    receiver: process.Subject(channel.PubsubEvent),
    selector: process.Selector(Message),
    sender: process.Subject(Event),
    owning_process: process.Pid,
    already_received: set.Set(channel.PubsubEvent),
  )
}

pub fn new(
  pubsub: process.Subject(pubsub.Message),
  channel_name: String,
  start_from: option.Option(Int),
  receive on: process.Subject(Event),
) -> Result(Subscriber, Nil) {
  let get_subscriber = process.new_subject()
  let owning_process = process.self()

  process.spawn(fn() {
    let self = process.new_subject()
    let receiver = process.new_subject()

    let selector =
      process.new_selector()
      |> process.select(self)
      |> process.select_map(receiver, IncomingEvent)

    let state =
      State(
        pubsub:,
        channel_name:,
        latest_event: start_from,
        self:,
        receiver:,
        sender: on,
        selector:,
        already_received: set.new(),
        owning_process:,
      )

    process.call(pubsub, 1000, pubsub.GetChannel(channel_name, _))
    |> process.send(channel.Subscribe(receiver:, replay_from: start_from))

    process.send(self, Vacuum)
    process.send(self, Heartbeat)
    process.send(get_subscriber, Subscriber(self))

    loop(state)
  })

  process.receive(get_subscriber, 1000)
}

fn loop(state: State) -> State {
  let message = process.selector_receive_forever(state.selector)

  let new_state = case message {
    Unsubscribe -> handle_unsubscribe(state)
    Heartbeat -> handle_heartbeat(state)
    IncomingEvent(event) -> handle_event(state, event)
    Vacuum -> handle_vacuum(state)
    Publish(data:, recv:) -> handle_publish(state, data, recv)
  }

  loop(new_state)
}

fn handle_unsubscribe(state: State) -> State {
  process.call(state.pubsub, 1000, pubsub.GetChannel(state.channel_name, _))
  |> process.send(channel.Unsubscribe(state.receiver))

  process.unlink(state.owning_process)

  let assert Ok(pid) = process.subject_owner(state.self)
  process.kill(pid)

  state
}

const heartbeat_interval = 30_000

fn handle_heartbeat(state: State) -> State {
  process.send_after(state.self, heartbeat_interval, Heartbeat)

  process.call(state.pubsub, 1000, pubsub.GetChannel(state.channel_name, _))
  |> process.send(channel.Subscribe(state.receiver, state.latest_event))

  state
}

const vacuum_interval = 120_000

fn handle_vacuum(state: State) -> State {
  process.send_after(state.self, vacuum_interval, Vacuum)

  let now = timestamp.system_time() |> timestamp.to_unix_seconds |> float.round

  let already_received = {
    let filtered =
      set.filter(state.already_received, fn(event) {
        now - event.sequence_id > 3600
      })

    case set.size(filtered) > 5000 {
      False -> filtered
      True ->
        set.to_list(filtered)
        |> list.sort(fn(e1, e2) {
          int.compare(e1.sequence_id, e2.sequence_id) |> order.negate
        })
        |> list.take(1000)
        |> set.from_list
    }
  }

  State(..state, already_received:)
}

fn handle_event(state: State, event: channel.PubsubEvent) -> State {
  use <- bool.guard(
    when: set.contains(state.already_received, event),
    return: state,
  )

  let already_received = set.insert(state.already_received, event)

  process.send(state.sender, Event(event.sequence_id, event.data))

  State(..state, already_received:)
}

fn handle_publish(
  state: State,
  data: String,
  recv: process.Subject(Event),
) -> State {
  let new_event =
    process.call(state.pubsub, 1000, pubsub.GetChannel(state.channel_name, _))
    |> process.call(1000, channel.PublishEvent(data, _))

  let already_received = set.insert(state.already_received, new_event)

  process.send(recv, Event(new_event.sequence_id, new_event.data))

  State(..state, already_received:)
}

pub fn unsubscribe(subscriber: Subscriber) {
  process.send(subscriber.subject, Unsubscribe)
}

pub fn publish(subscriber: Subscriber, data: String) {
  process.call(subscriber.subject, 1000, Publish(data, _))
}
