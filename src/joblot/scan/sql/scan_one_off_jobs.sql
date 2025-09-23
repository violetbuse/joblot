SELECT id FROM one_off_jobs 
    WHERE 
        execute_at <= $1 AND 
        completed = FALSE AND
        id > $2
    ORDER BY id ASC
    LIMIT $3;