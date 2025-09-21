SELECT id FROM one_off_jobs 
    WHERE 
        maximum_retries + 1 > attempts AND 
        execute_at <= $1 AND 
        executed_at IS NULL AND
        id > $2
    ORDER BY id ASC
    LIMIT $3;