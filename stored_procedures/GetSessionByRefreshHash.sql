CREATE DEFINER="avnadmin"@"%" PROCEDURE "GetSessionByRefreshHash"(IN p_refreshHash VARCHAR(255))
BEGIN
SELECT * FROM sessions
WHERE refresh_token_hash = p_refreshHash
  AND (refresh_token_revoked IS NULL)
  AND (refresh_token_expires IS NULL OR refresh_token_expires > NOW())
LIMIT 1;
END
