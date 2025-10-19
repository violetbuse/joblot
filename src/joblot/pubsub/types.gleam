import gleam/erlang/process

pub type ManagerMessage {
  MgrHeartbeat
  GetChannel(
    channel_name: String,
    reply_with: process.Subject(process.Subject(ChannelMessage)),
  )
}

pub type ChannelMessage {
  Publish(data: String)
  Subscribe(recv: process.Subject(String))
}

pub type ServerMessage

pub type ClientMessage
