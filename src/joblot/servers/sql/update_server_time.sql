INSERT INTO servers (address, last_online)
VALUES ($1, $2)
ON CONFLICT (address)
DO UPDATE SET last_online = $2;
