SELECT id FROM cron_jobs
    WHERE
        id > $1
    ORDER BY id ASC
    LIMIT $2;