//// This module contains the code to run the sql queries defined in
//// `./src/joblot/sql`.
//// > 🐿️ This module was generated automatically using v4.4.1 of
//// > the [squirrel package](https://github.com/giacomocavalieri/squirrel).
////

import gleam/dynamic/decode
import gleam/option.{type Option}
import pog

/// Runs the `clear_locks` query
/// defined in `./src/joblot/sql/clear_locks.sql`.
///
/// > 🐿️ This function was generated automatically using v4.4.1 of
/// > the [squirrel package](https://github.com/giacomocavalieri/squirrel).
///
pub fn clear_locks(
  db: pog.Connection,
  arg_1: Int,
) -> Result(pog.Returned(Nil), pog.QueryError) {
  let decoder = decode.map(decode.dynamic, fn(_) { Nil })

  "delete from locks where expires_at < $1;"
  |> pog.query
  |> pog.parameter(pog.int(arg_1))
  |> pog.returning(decoder)
  |> pog.execute(db)
}

/// A row you get from running the `find_crons` query
/// defined in `./src/joblot/sql/find_crons.sql`.
///
/// > 🐿️ This type definition was generated automatically using v4.4.1 of the
/// > [squirrel package](https://github.com/giacomocavalieri/squirrel).
///
pub type FindCronsRow {
  FindCronsRow(
    id: String,
    hash: Int,
    metadata: String,
    user_id: Option(String),
    tenant_id: Option(String),
    cron: String,
    created_at: Int,
    method: String,
    url: String,
    headers: Option(List(String)),
    body: Option(String),
    timeout_ms: Int,
  )
}

/// Runs the `find_crons` query
/// defined in `./src/joblot/sql/find_crons.sql`.
///
/// > 🐿️ This function was generated automatically using v4.4.1 of
/// > the [squirrel package](https://github.com/giacomocavalieri/squirrel).
///
pub fn find_crons(
  db: pog.Connection,
  arg_1: Int,
  arg_2: Int,
) -> Result(pog.Returned(FindCronsRow), pog.QueryError) {
  let decoder = {
    use id <- decode.field(0, decode.string)
    use hash <- decode.field(1, decode.int)
    use metadata <- decode.field(2, decode.string)
    use user_id <- decode.field(3, decode.optional(decode.string))
    use tenant_id <- decode.field(4, decode.optional(decode.string))
    use cron <- decode.field(5, decode.string)
    use created_at <- decode.field(6, decode.int)
    use method <- decode.field(7, decode.string)
    use url <- decode.field(8, decode.string)
    use headers <- decode.field(9, decode.optional(decode.list(decode.string)))
    use body <- decode.field(10, decode.optional(decode.string))
    use timeout_ms <- decode.field(11, decode.int)
    decode.success(FindCronsRow(
      id:,
      hash:,
      metadata:,
      user_id:,
      tenant_id:,
      cron:,
      created_at:,
      method:,
      url:,
      headers:,
      body:,
      timeout_ms:,
    ))
  }

  "select * from cron_jobs where hash % $1 = $2;"
  |> pog.query
  |> pog.parameter(pog.int(arg_1))
  |> pog.parameter(pog.int(arg_2))
  |> pog.returning(decoder)
  |> pog.execute(db)
}

/// A row you get from running the `insert_lock` query
/// defined in `./src/joblot/sql/insert_lock.sql`.
///
/// > 🐿️ This type definition was generated automatically using v4.4.1 of the
/// > [squirrel package](https://github.com/giacomocavalieri/squirrel).
///
pub type InsertLockRow {
  InsertLockRow(id: String, nonce: String, expires_at: Int)
}

/// Runs the `insert_lock` query
/// defined in `./src/joblot/sql/insert_lock.sql`.
///
/// > 🐿️ This function was generated automatically using v4.4.1 of
/// > the [squirrel package](https://github.com/giacomocavalieri/squirrel).
///
pub fn insert_lock(
  db: pog.Connection,
  arg_1: String,
  arg_2: String,
  arg_3: Int,
) -> Result(pog.Returned(InsertLockRow), pog.QueryError) {
  let decoder = {
    use id <- decode.field(0, decode.string)
    use nonce <- decode.field(1, decode.string)
    use expires_at <- decode.field(2, decode.int)
    decode.success(InsertLockRow(id:, nonce:, expires_at:))
  }

  "insert into locks (id, nonce, expires_at) 
values ($1, $2, $3) 
on conflict (id, nonce)
do update set expires_at = $3
returning *;"
  |> pog.query
  |> pog.parameter(pog.text(arg_1))
  |> pog.parameter(pog.text(arg_2))
  |> pog.parameter(pog.int(arg_3))
  |> pog.returning(decoder)
  |> pog.execute(db)
}

/// A row you get from running the `query_lock` query
/// defined in `./src/joblot/sql/query_lock.sql`.
///
/// > 🐿️ This type definition was generated automatically using v4.4.1 of the
/// > [squirrel package](https://github.com/giacomocavalieri/squirrel).
///
pub type QueryLockRow {
  QueryLockRow(id: String, nonce: String, expires_at: Int)
}

/// Runs the `query_lock` query
/// defined in `./src/joblot/sql/query_lock.sql`.
///
/// > 🐿️ This function was generated automatically using v4.4.1 of
/// > the [squirrel package](https://github.com/giacomocavalieri/squirrel).
///
pub fn query_lock(
  db: pog.Connection,
  arg_1: String,
) -> Result(pog.Returned(QueryLockRow), pog.QueryError) {
  let decoder = {
    use id <- decode.field(0, decode.string)
    use nonce <- decode.field(1, decode.string)
    use expires_at <- decode.field(2, decode.int)
    decode.success(QueryLockRow(id:, nonce:, expires_at:))
  }

  "select * from locks where id = $1;"
  |> pog.query
  |> pog.parameter(pog.text(arg_1))
  |> pog.returning(decoder)
  |> pog.execute(db)
}

/// Runs the `release_lock` query
/// defined in `./src/joblot/sql/release_lock.sql`.
///
/// > 🐿️ This function was generated automatically using v4.4.1 of
/// > the [squirrel package](https://github.com/giacomocavalieri/squirrel).
///
pub fn release_lock(
  db: pog.Connection,
  arg_1: String,
  arg_2: String,
) -> Result(pog.Returned(Nil), pog.QueryError) {
  let decoder = decode.map(decode.dynamic, fn(_) { Nil })

  "delete from locks where id = $1 and nonce = $2;"
  |> pog.query
  |> pog.parameter(pog.text(arg_1))
  |> pog.parameter(pog.text(arg_2))
  |> pog.returning(decoder)
  |> pog.execute(db)
}

/// A row you get from running the `update_lock` query
/// defined in `./src/joblot/sql/update_lock.sql`.
///
/// > 🐿️ This type definition was generated automatically using v4.4.1 of the
/// > [squirrel package](https://github.com/giacomocavalieri/squirrel).
///
pub type UpdateLockRow {
  UpdateLockRow(id: String, nonce: String, expires_at: Int)
}

/// Runs the `update_lock` query
/// defined in `./src/joblot/sql/update_lock.sql`.
///
/// > 🐿️ This function was generated automatically using v4.4.1 of
/// > the [squirrel package](https://github.com/giacomocavalieri/squirrel).
///
pub fn update_lock(
  db: pog.Connection,
  arg_1: String,
  arg_2: String,
  arg_3: Int,
) -> Result(pog.Returned(UpdateLockRow), pog.QueryError) {
  let decoder = {
    use id <- decode.field(0, decode.string)
    use nonce <- decode.field(1, decode.string)
    use expires_at <- decode.field(2, decode.int)
    decode.success(UpdateLockRow(id:, nonce:, expires_at:))
  }

  "update locks set expires_at = $3 where id = $1 and nonce = $2 returning *;"
  |> pog.query
  |> pog.parameter(pog.text(arg_1))
  |> pog.parameter(pog.text(arg_2))
  |> pog.parameter(pog.int(arg_3))
  |> pog.returning(decoder)
  |> pog.execute(db)
}
