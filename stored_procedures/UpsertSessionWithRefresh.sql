CREATE DEFINER="avnadmin"@"%" PROCEDURE "UpsertSessionWithRefresh"(IN p_sessionID VARCHAR(255),
IN p_userID INT,
IN p_expires BIGINT,
IN p_data JSON,
IN p_refreshHash VARCHAR(255),
IN p_refreshExpires DATETIME)
BEGIN
INSERT INTO sessions (sessionID, userID, expires, data, refresh_token_hash, refresh_token_expires)
VALUES (p_sessionID, p_userID, p_expires, p_data, p_refreshHash, p_refreshExpires)
ON DUPLICATE KEY UPDATE
userID = VALUES(userID),
expires = VALUES(expires),
data = VALUES(data),
refresh_token_hash = VALUES(refresh_token_hash),
refresh_token_expires = VALUES(refresh_token_expires),
refresh_token_revoked = NULL,
refresh_token_replaced_by = NULL;
END