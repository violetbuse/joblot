import file_streams/file_open_mode
import file_streams/file_stream
import file_streams/file_stream_error
import filepath
import gleam/bit_array
import gleam/bool
import gleam/dict
import gleam/dynamic/decode
import gleam/erlang/process
import gleam/int
import gleam/json
import gleam/list
import gleam/option
import gleam/otp/actor
import gleam/result
import gleam/string
import simplifile

pub type ChannelDatastoreConfig {
  ChannelDatastoreConfig(data_dir: String)
}

pub opaque type ChannelDatastore {
  ChannelDatastore(subject: process.Subject(Message))
}

pub opaque type Message {
  GetBuckets(recv: process.Subject(List(String)))
  GetLatestEvent(node_id: String, recv: process.Subject(option.Option(Event)))
  GetEventsPast(
    node_id: String,
    past_sequence: Int,
    recv: process.Subject(List(Event)),
  )
  WriteEvents(
    node_id: String,
    events: List(Event),
    recv: process.Subject(List(Event)),
  )
}

pub type Event {
  Event(time: Int, data: String)
}

fn parse_line(line: String, last_time: Int) -> Result(Event, String) {
  use #(timestamp, data) <- result.try(
    string.split_once(line, ":")
    |> result.replace_error("line did not contain a ':'"),
  )

  use timestamp <- result.try(
    int.parse(timestamp)
    |> result.replace_error("text preceding the ':' was not a valid int"),
  )

  use <- bool.guard(
    when: timestamp <= 0,
    return: Error("timestamp is less than or equal to zero"),
  )

  use <- bool.guard(
    when: timestamp < last_time,
    return: Error("timestamp may not be less than that of the preceding event"),
  )

  use data <- result.try(
    json.parse(data, decode.string)
    |> result.replace_error("data was not a json formatted string"),
  )

  Ok(Event(time: timestamp, data:))
}

fn encode_line(event: Event) -> String {
  let linedata = json.to_string(json.string(event.data))
  int.to_string(event.time) <> ":" <> linedata <> "\n"
}

type VerificationResult {
  Verified
  FileStreamError
  ParseLineError(error: String, line: String)
}

fn verify_data_dir(
  data_dir: String,
) -> dict.Dict(String, file_stream.FileStream) {
  let assert Ok(files) = simplifile.read_directory(data_dir)
  let filepaths = list.map(files, filepath.join(data_dir, _))

  filepaths
  |> list.map(fn(file) {
    let stream = open_file(file)
    let verified = verify_stream(stream)

    #(file, stream, verified)
  })
  |> list.filter(fn(verification) {
    let #(filename, stream, result) = verification

    case result {
      Verified -> True
      _ -> {
        let assert Ok(_) = file_stream.close(stream)
        let assert Ok(_) = simplifile.delete(filename)
        False
      }
    }
  })
  |> list.map(fn(tuple) {
    let #(file, stream, _) = tuple
    let filename = filepath.base_name(file)
    #(filename, stream)
  })
  |> dict.from_list
}

fn verify_stream(stream: file_stream.FileStream) -> VerificationResult {
  let new_position =
    file_stream.position(stream, file_stream.BeginningOfFile(0))
  use <- bool.guard(
    when: result.is_error(new_position),
    return: FileStreamError,
  )

  verify_lines(stream)
}

fn verify_lines(stream: file_stream.FileStream) -> VerificationResult {
  case file_stream.read_line(stream) {
    Error(err) ->
      case err {
        file_stream_error.Eof -> Verified
        _ -> FileStreamError
      }
    Ok(line) ->
      case parse_line(line, 0) {
        Error(err) -> ParseLineError(err, line)
        Ok(_) -> verify_lines(stream)
      }
  }
}

fn get_last_event(stream: file_stream.FileStream) -> Result(Event, Nil) {
  let assert Ok(_) =
    file_stream.position(stream, file_stream.BeginningOfFile(0))

  internal_get_last_event(stream)
}

fn internal_get_last_event(stream: file_stream.FileStream) -> Result(Event, Nil) {
  case file_stream.read_line(stream) {
    Ok(line) ->
      case internal_get_last_event(stream) {
        Ok(event) -> Ok(event)
        Error(_) ->
          case parse_line(line, 0) {
            Ok(event) -> Ok(event)
            Error(_) -> panic as "invalid event"
          }
      }
    Error(file_stream_error.Eof) -> Error(Nil)
    Error(_) -> panic as "could not get last event due to a read error."
  }
}

fn write_events_to_disk(
  stream: file_stream.FileStream,
  events: List(Event),
) -> List(Event) {
  let last_event_time =
    get_last_event(stream)
    |> result.map(fn(event) { event.time })
    |> result.unwrap(0)

  let events_to_be_written =
    list.reverse(events)
    |> list.take_while(fn(event) { event.time > last_event_time })
    |> list.reverse

  let text_to_write =
    events_to_be_written |> list.map(encode_line) |> string.concat
  let assert Ok(_) = file_stream.write_chars(stream, text_to_write)

  events_to_be_written
}

fn get_events_past_sequence(
  stream: file_stream.FileStream,
  past: Int,
) -> List(Event) {
  let assert Ok(_) =
    file_stream.position(stream, file_stream.BeginningOfFile(0))
  read_events_past(stream, past)
}

fn read_events_past(stream: file_stream.FileStream, past: Int) -> List(Event) {
  let read_result = file_stream.read_line(stream)

  case read_result {
    Ok(line) ->
      case parse_line(line, 0) {
        Error(_) -> panic as "Line could not be parsed"
        Ok(event) if event.time < past -> read_events_past(stream, past)
        Ok(event) -> [event, ..read_events_past(stream, past)]
      }
    Error(file_stream_error.Eof) -> []
    Error(_) -> panic as "Unexpected error reading events"
  }
}

type State {
  State(streams: dict.Dict(String, file_stream.FileStream), directory: String)
}

fn open_file(path: String) -> file_stream.FileStream {
  let assert Ok(stream) =
    file_stream.open(path, [
      file_open_mode.Append,
      file_open_mode.Exclusive,
      file_open_mode.Read,
      file_open_mode.Write,
      file_open_mode.Raw,
    ])

  stream
}

fn get_stream(state: State, node_id: String) -> #(State, file_stream.FileStream) {
  case dict.get(state.streams, node_id) {
    Ok(stream) -> #(state, stream)
    Error(_) -> {
      let path = filepath.join(state.directory, node_id)
      let stream = open_file(path)
      #(
        State(..state, streams: dict.insert(state.streams, node_id, stream)),
        stream,
      )
    }
  }
}

fn initialize(
  self: process.Subject(Message),
  config: ChannelDatastoreConfig,
) -> Result(actor.Initialised(State, Message, ChannelDatastore), String) {
  let datastore = ChannelDatastore(self)
  let streams = verify_data_dir(config.data_dir)
  let state = State(streams:, directory: config.data_dir)

  actor.initialised(state) |> actor.returning(datastore) |> Ok
}

fn on_message(state: State, message: Message) -> actor.Next(State, Message) {
  case message {
    GetBuckets(recv:) -> handle_get_buckets(state, recv)
    GetLatestEvent(node_id:, recv:) ->
      handle_get_latest_event(state, node_id, recv)
    GetEventsPast(node_id:, past_sequence:, recv:) ->
      handle_get_events_past(state, node_id, past_sequence, recv)
    WriteEvents(node_id:, events:, recv:) ->
      handle_write_events(state, node_id, events, recv)
  }
}

fn handle_get_buckets(
  state: State,
  recv: process.Subject(List(String)),
) -> actor.Next(State, Message) {
  process.send(recv, dict.keys(state.streams))

  actor.continue(state)
}

fn handle_get_latest_event(
  state: State,
  node_id: String,
  recv: process.Subject(option.Option(Event)),
) -> actor.Next(State, Message) {
  let #(state, stream) = get_stream(state, node_id)
  let event = get_last_event(stream) |> option.from_result

  process.send(recv, event)

  actor.continue(state)
}

fn handle_get_events_past(
  state: State,
  node_id: String,
  past: Int,
  recv: process.Subject(List(Event)),
) -> actor.Next(State, Message) {
  let #(state, stream) = get_stream(state, node_id)
  let events = get_events_past_sequence(stream, past)

  process.send(recv, events)

  actor.continue(state)
}

fn handle_write_events(
  state: State,
  node_id: String,
  events: List(Event),
  recv: process.Subject(List(Event)),
) -> actor.Next(State, Message) {
  let #(state, stream) = get_stream(state, node_id)
  let inserted = write_events_to_disk(stream, events)

  process.send(recv, inserted)

  actor.continue(state)
}

pub fn start(config: ChannelDatastoreConfig) -> Result(ChannelDatastore, Nil) {
  let data =
    actor.new_with_initialiser(5000, initialize(_, config))
    |> actor.on_message(on_message)
    |> actor.start

  case data {
    Error(_) -> Error(Nil)
    Ok(data) -> {
      process.link(data.pid)
      Ok(data.data)
    }
  }
}

pub fn get_buckets(datastore: ChannelDatastore) {
  process.call(datastore.subject, 2000, GetBuckets)
}

pub fn get_latest_event(datastore: ChannelDatastore, node_id: String) {
  process.call(datastore.subject, 2000, GetLatestEvent(node_id, _))
}

pub fn get_events_past(datastore: ChannelDatastore, node_id: String, past: Int) {
  process.call(datastore.subject, 2000, GetEventsPast(node_id, past, _))
}

pub fn write_events(
  datastore: ChannelDatastore,
  node_id: String,
  events: List(Event),
) {
  process.call(datastore.subject, 2000, WriteEvents(node_id, events, _))
}
