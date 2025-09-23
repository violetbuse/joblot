//// This module contains the code to run the sql queries defined in
//// `./src/joblot/scan/sql`.
//// > 🐿️ This module was generated automatically using v4.4.1 of
//// > the [squirrel package](https://github.com/giacomocavalieri/squirrel).
////

import gleam/dynamic/decode
import pog

/// A row you get from running the `scan_cron` query
/// defined in `./src/joblot/scan/sql/scan_cron.sql`.
///
/// > 🐿️ This type definition was generated automatically using v4.4.1 of the
/// > [squirrel package](https://github.com/giacomocavalieri/squirrel).
///
pub type ScanCronRow {
  ScanCronRow(id: String)
}

/// Runs the `scan_cron` query
/// defined in `./src/joblot/scan/sql/scan_cron.sql`.
///
/// > 🐿️ This function was generated automatically using v4.4.1 of
/// > the [squirrel package](https://github.com/giacomocavalieri/squirrel).
///
pub fn scan_cron(
  db: pog.Connection,
  arg_1: String,
  arg_2: Int,
) -> Result(pog.Returned(ScanCronRow), pog.QueryError) {
  let decoder = {
    use id <- decode.field(0, decode.string)
    decode.success(ScanCronRow(id:))
  }

  "SELECT id FROM cron_jobs
    WHERE
        id > $1
    ORDER BY id ASC
    LIMIT $2;"
  |> pog.query
  |> pog.parameter(pog.text(arg_1))
  |> pog.parameter(pog.int(arg_2))
  |> pog.returning(decoder)
  |> pog.execute(db)
}

/// A row you get from running the `scan_one_off_jobs` query
/// defined in `./src/joblot/scan/sql/scan_one_off_jobs.sql`.
///
/// > 🐿️ This type definition was generated automatically using v4.4.1 of the
/// > [squirrel package](https://github.com/giacomocavalieri/squirrel).
///
pub type ScanOneOffJobsRow {
  ScanOneOffJobsRow(id: String)
}

/// Runs the `scan_one_off_jobs` query
/// defined in `./src/joblot/scan/sql/scan_one_off_jobs.sql`.
///
/// > 🐿️ This function was generated automatically using v4.4.1 of
/// > the [squirrel package](https://github.com/giacomocavalieri/squirrel).
///
pub fn scan_one_off_jobs(
  db: pog.Connection,
  arg_1: Int,
  arg_2: String,
  arg_3: Int,
) -> Result(pog.Returned(ScanOneOffJobsRow), pog.QueryError) {
  let decoder = {
    use id <- decode.field(0, decode.string)
    decode.success(ScanOneOffJobsRow(id:))
  }

  "SELECT id FROM one_off_jobs 
    WHERE 
        execute_at <= $1 AND 
        completed = FALSE AND
        id > $2
    ORDER BY id ASC
    LIMIT $3;"
  |> pog.query
  |> pog.parameter(pog.int(arg_1))
  |> pog.parameter(pog.text(arg_2))
  |> pog.parameter(pog.int(arg_3))
  |> pog.returning(decoder)
  |> pog.execute(db)
}
