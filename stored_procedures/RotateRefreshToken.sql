CREATE DEFINER="avnadmin"@"%" PROCEDURE "RotateRefreshToken"(IN p_oldRefreshHash VARCHAR(255),
IN p_newRefreshHash VARCHAR(255),
IN p_newRefreshExpires DATETIME)
BEGIN
UPDATE sessions
SET refresh_token_revoked = NOW(),
refresh_token_replaced_by = p_newRefreshHash
WHERE refresh_token_hash = p_oldRefreshHash;

UPDATE sessions
SET refresh_token_hash = p_newRefreshHash,
refresh_token_expires = p_newRefreshExpires,
refresh_token_revoked = NULL,
refresh_token_replaced_by = NULL
WHERE refresh_token_hash = p_oldRefreshHash;
END