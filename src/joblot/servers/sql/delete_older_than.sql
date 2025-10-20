DELETE FROM servers where last_online < $1;
