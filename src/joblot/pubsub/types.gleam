import gleam/dict
import gleam/erlang/process
import gleam/erlang/reference
import gleam/set
import glisten

pub type ManagerMessage {
  MgrHeartbeat
  GetChannel(
    channel_name: String,
    reply_with: process.Subject(process.Subject(ChannelMessage)),
  )
  InitServer(ref: reference.Reference, subject: process.Subject(ServerMessage))
  CloseServer(ref: reference.Reference)
  ClientAddresses(reply_with: process.Subject(set.Set(String)))
  InitClient(address: String, subject: process.Subject(ClientMessage))
  CloseClient(address: String)
}

pub type ChannelMessage {
  ChHeartbeat(connections: set.Set(Connection))
  IncomingMessage(message: String)
  Publish(data: String)
  Subscribe(recv: process.Subject(String))
}

pub type ServerMessage {
  SrvHeartbeat(
    channels: dict.Dict(String, process.Subject(ChannelMessage)),
    connections: set.Set(Connection),
  )
  SrvRefresh
  SrvOutgoingMessage(channel_id: String, message: String, count_to_limit: Int)
}

pub type ClientMessage {
  CltHeartbeat(
    channels: dict.Dict(String, process.Subject(ChannelMessage)),
    connections: set.Set(Connection),
  )
  CltRefresh
  CltOutgoingMessage(channel_id: String, message: String, count_to_limit: Int)
}

pub type Connection {
  ServerConnection(process.Subject(ServerMessage))
  ClientConnection(process.Subject(ClientMessage))
}
