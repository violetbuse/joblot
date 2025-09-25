UPDATE one_off_jobs
SET completed = true
WHERE id = $1;