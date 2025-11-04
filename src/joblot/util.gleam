import gleam/bool
import gleam/bytes_tree
import gleam/dynamic/decode
import gleam/http
import gleam/http/request
import gleam/http/response
import gleam/io
import gleam/json
import gleam/list
import gleam/result
import gleam/uri
import httpp/send
import mist
import sqlight

pub fn log_error(incoming: Result(a, b), error_message: String) -> Result(a, b) {
  result.try_recover(incoming, fn(err) {
    io.println_error(error_message)
    echo err
    incoming
  })
}

pub fn send_internal_request(
  api_address: uri.Uri,
  secret: String,
  path: String,
  body: String,
) {
  let assert Ok(base_req) = uri.Uri(..api_address, path:) |> request.from_uri

  let request =
    base_req
    |> request.set_method(http.Post)
    |> request.set_header("authorization", secret)
    |> request.set_query([#("secret_key", secret)])
    |> request.set_body(body)

  send.send(request)
}

pub fn not_found() {
  let data =
    json.object([#("error", json.string("Not Found"))])
    |> json.to_string_tree
    |> bytes_tree.from_string_tree
    |> mist.Bytes

  response.new(404)
  |> response.set_body(data)
}

pub fn not_authorized() {
  let data =
    json.object([#("error", json.string("Not Authorized."))])
    |> json.to_string_tree
    |> bytes_tree.from_string_tree
    |> mist.Bytes

  response.new(403)
  |> response.set_body(data)
}

pub fn with_transaction(
  db: sqlight.Connection,
  cb: fn(sqlight.Connection) -> Result(a, sqlight.Error),
) -> Result(a, sqlight.Error) {
  use _ <- result.try(sqlight.exec("BEGIN IMMEDIATE TRANSACTION;", db))

  case cb(db) {
    Ok(result) -> {
      use _ <- result.try(sqlight.exec("COMMIT TRANSACTION;", db))
      Ok(result)
    }
    Error(error) -> {
      let assert Ok(_) = sqlight.exec("ROLLBACK TRANSACTION;", db)
      Error(error)
    }
  }
}

pub fn with_pragma(
  value: String,
  connection: sqlight.Connection,
  cb: fn() -> Result(a, String),
) -> Result(a, String) {
  use _ <- result.try(
    sqlight.exec("PRAGMA " <> value <> ";", connection)
    |> result.replace_error("Could not set pragma: " <> value),
  )

  cb()
}

pub fn with_connection(
  datafile: String,
  migrations: List(String),
  cb: fn(sqlight.Connection) -> Result(a, String),
) -> Result(a, String) {
  use db <- result.try(
    sqlight.open(datafile)
    |> log_error("Could not open data file " <> datafile)
    |> result.replace_error("Could not open sqlite file " <> datafile),
  )

  use db <- with_migrations(db, migrations)

  use <- with_pragma("journal_mode = WAL", db)
  use <- with_pragma("busy_timeout = 5000", db)
  use <- with_pragma("synchronous = NORMAL", db)
  use <- with_pragma("cache_size = 1000000000", db)
  use <- with_pragma("foreign_keys = true", db)
  use <- with_pragma("temp_store = memory", db)

  cb(db)
}

pub fn with_migrations(
  connection: sqlight.Connection,
  migrations: List(String),
  cb: fn(sqlight.Connection) -> Result(a, String),
) -> Result(a, String) {
  use _ <- result.try(
    sqlight.exec(
      "CREATE TABLE IF NOT EXISTS _applied_migrations (
        migration_order INTEGER NOT NULL PRIMARY KEY,
        migration_script TEXT NOT NULL
      ) STRICT;",
      connection,
    )
    |> log_error("error creating migrations table")
    |> result.replace_error("could not create migrations table"),
  )

  let successfully_run = {
    use db <- with_transaction(connection)

    list.index_map(migrations, fn(migration, index) { #(index, migration) })
    |> list.try_each(fn(migration) {
      let #(migration_order, migration_script) = migration

      let is_migration_applied_sql =
        "SELECT migration_script FROM _applied_migrations WHERE migration_order = ?;"

      let is_migration_applied_decoder = {
        use script <- decode.field(0, decode.string)
        decode.success(script)
      }

      use applied_result_set <- result.try(sqlight.query(
        is_migration_applied_sql,
        db,
        [
          sqlight.int(migration_order),
        ],
        is_migration_applied_decoder,
      ))

      // if it is applied already, just continue
      use <- bool.guard(
        when: applied_result_set == [migration_script],
        return: Ok(Nil),
      )

      let migration_changed =
        list.length(applied_result_set) == 1
        && applied_result_set != [migration_script]
      use <- bool.guard(
        when: migration_changed,
        return: Error(sqlight.SqlightError(
          sqlight.GenericError,
          "Migrations array has non-matching migrations",
          -1,
        )),
      )

      use _ <- result.try(sqlight.exec(migration_script, db))

      let insert_applied_migration_sql =
        "
      INSERT INTO _applied_migrations (migration_order, migration_script)
      VALUES (?,?);"

      use _ <- result.try(sqlight.query(
        insert_applied_migration_sql,
        db,
        [sqlight.int(migration_order), sqlight.text(migration_script)],
        decode.dynamic,
      ))

      Ok(Nil)
    })
  }

  use _ <- result.try(
    successfully_run
    |> result.map_error(fn(err) { "error running migrations" <> err.message }),
  )

  cb(connection)
}
