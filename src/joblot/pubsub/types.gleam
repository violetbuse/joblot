import gleam/dict
import gleam/erlang/process
import gleam/erlang/reference
import gleam/set

pub type ManagerMessage {
  MgrHeartbeat
  GetChannel(
    channel_name: String,
    reply_with: process.Subject(process.Subject(ChannelMessage)),
  )
  RegisterServer(
    ref: reference.Reference,
    subject: process.Subject(ServerMessage),
  )
  CloseServer(ref: reference.Reference)
  ClientAddresses(reply_with: process.Subject(set.Set(String)))
  RegisterClient(address: String, subject: process.Subject(ClientMessage))
  CloseClient(address: String)
  RegisterChannel(channel_id: String, subject: process.Subject(ChannelMessage))
}

pub type ChannelMessage {
  ChHeartbeat(servers: set.Set(process.Subject(ServerMessage)))
  Publish(data: String)
  Subscribe(recv: process.Subject(String))
}

pub type ServerMessage {
  SrvHeartbeat(channels: dict.Dict(String, process.Subject(ChannelMessage)))
  SrvRefresh
}

pub type ClientMessage {
  Close
  CltHeartbeat(channels: dict.Dict(String, process.Subject(ChannelMessage)))
  CltRefresh
}
