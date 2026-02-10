CREATE DEFINER="avnadmin"@"%" PROCEDURE "RevokeRefreshToken"(IN p_refreshHash VARCHAR(255))
BEGIN
UPDATE sessions
SET refresh_token_revoked = NOW()
WHERE refresh_token_hash = p_refreshHash;
END