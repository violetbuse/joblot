insert into locks (id, nonce, expires_at) 
values ($1, $2, $3) 
on conflict (id, nonce)
do update set expires_at = $3
returning *;