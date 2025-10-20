//// This module contains the code to run the sql queries defined in
//// `./src/joblot/servers/sql`.
//// > 🐿️ This module was generated automatically using v4.4.1 of
//// > the [squirrel package](https://github.com/giacomocavalieri/squirrel).
////

import gleam/dynamic/decode
import pog

/// Runs the `delete_older_than` query
/// defined in `./src/joblot/servers/sql/delete_older_than.sql`.
///
/// > 🐿️ This function was generated automatically using v4.4.1 of
/// > the [squirrel package](https://github.com/giacomocavalieri/squirrel).
///
pub fn delete_older_than(
  db: pog.Connection,
  arg_1: Int,
) -> Result(pog.Returned(Nil), pog.QueryError) {
  let decoder = decode.map(decode.dynamic, fn(_) { Nil })

  "DELETE FROM servers where last_online < $1;
"
  |> pog.query
  |> pog.parameter(pog.int(arg_1))
  |> pog.returning(decoder)
  |> pog.execute(db)
}

/// A row you get from running the `list_servers` query
/// defined in `./src/joblot/servers/sql/list_servers.sql`.
///
/// > 🐿️ This type definition was generated automatically using v4.4.1 of the
/// > [squirrel package](https://github.com/giacomocavalieri/squirrel).
///
pub type ListServersRow {
  ListServersRow(address: String, last_online: Int)
}

/// Runs the `list_servers` query
/// defined in `./src/joblot/servers/sql/list_servers.sql`.
///
/// > 🐿️ This function was generated automatically using v4.4.1 of
/// > the [squirrel package](https://github.com/giacomocavalieri/squirrel).
///
pub fn list_servers(
  db: pog.Connection,
) -> Result(pog.Returned(ListServersRow), pog.QueryError) {
  let decoder = {
    use address <- decode.field(0, decode.string)
    use last_online <- decode.field(1, decode.int)
    decode.success(ListServersRow(address:, last_online:))
  }

  "SELECT * FROM servers;
"
  |> pog.query
  |> pog.returning(decoder)
  |> pog.execute(db)
}

/// Runs the `update_server_time` query
/// defined in `./src/joblot/servers/sql/update_server_time.sql`.
///
/// > 🐿️ This function was generated automatically using v4.4.1 of
/// > the [squirrel package](https://github.com/giacomocavalieri/squirrel).
///
pub fn update_server_time(
  db: pog.Connection,
  arg_1: String,
  arg_2: Int,
) -> Result(pog.Returned(Nil), pog.QueryError) {
  let decoder = decode.map(decode.dynamic, fn(_) { Nil })

  "INSERT INTO servers (address, last_online)
VALUES ($1, $2)
ON CONFLICT (address)
DO UPDATE SET last_online = $2;
"
  |> pog.query
  |> pog.parameter(pog.text(arg_1))
  |> pog.parameter(pog.int(arg_2))
  |> pog.returning(decoder)
  |> pog.execute(db)
}
