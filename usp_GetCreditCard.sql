USE [JCARD_SCB]
GO

/****** Object:  StoredProcedure [dbo].[usp_GetCreditCard]    Script Date: 11/5/2025 12:36:48 PM ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO


CREATE PROCEDURE [dbo].[usp_GetCreditCard]
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @MovedCount INT = 0;
    DECLARE @LoopCount INT;
    DECLARE @Counter INT;

    BEGIN TRY
        -------------------------------
        -- 1. Add card info (Random inserts)
        -------------------------------
        SET @LoopCount = FLOOR(RAND(CHECKSUM(NEWID())) * 2) + 1;
        SET @Counter = 1;

        WHILE @Counter <= @LoopCount
        BEGIN
            BEGIN TRAN;

                INSERT INTO D_CARDLST
                (
                    CARDNO, CARDTYPE, BRAND, RRN, CARDPIN, CARDSTS, ACNO, AUTHMETHOD, STATUS
                )
                VALUES
                (
                    CONCAT('977','10',
                        CAST(ABS(CHECKSUM(NEWID())) % 900000 + 100000 AS INT),
                        CAST(ABS(CHECKSUM(NEWID())) % 9000 + 1000 AS INT)
                    ),
                    'C',
                    (SELECT TOP 1 CODESUBTYPE FROM D_CODETYPE WHERE CODETYPE = 'CREDIT' ORDER BY NEWID()),
                    CONCAT(CAST(ABS(CHECKSUM(NEWID())) % 900000 + 100000 AS INT),
                           CAST(ABS(CHECKSUM(NEWID())) % 900000 + 100000 AS INT)),
                    CAST(ABS(CHECKSUM(NEWID())) % 900000 + 100000 AS INT),
                    'P',
                    CAST((RAND() * 900000000) + 100000000 AS BIGINT),
                    'E|S|O',
                    'W'
                );

            COMMIT TRAN;

            SET @Counter += 1;
        END

        -------------------------------
        -- 2. Update CARDBIN in D_CARDLST
        -------------------------------
        BEGIN TRAN;
            UPDATE D_CARDLST
            SET CARDBIN = SUBSTRING(CARDNO,6,8)
            WHERE CARDBIN IS NULL AND CARDTYPE = 'C';
        COMMIT TRAN;

        -------------------------------
        -- 3. Encrypt CARDPIN
        -------------------------------
        OPEN SYMMETRIC KEY symkey_jcard
        DECRYPTION BY CERTIFICATE cert_jcard;

        UPDATE D_CARDLST
        SET HASHPIN = EncryptByKey(Key_GUID('symkey_jcard'), CARDPIN)
        WHERE HASHPIN IS NULL;

        CLOSE SYMMETRIC KEY symkey_jcard;

        -------------------------------
        -- 4. Insert SYSLOG
        -------------------------------
        BEGIN TRAN;
            INSERT INTO SYSLOG(CONTENT)
            SELECT (SELECT t.* FOR JSON PATH, WITHOUT_ARRAY_WRAPPER) AS RowJSON
            FROM D_CARDLST t
            WHERE t.CARDSTS = 'P' AND t.STATUS = 'W' AND t.CARDTYPE = 'C';
        COMMIT TRAN;

        BEGIN TRAN;
            UPDATE SYSLOG
            SET APP = 'BO',
                DOMAIN = 'Domain1',
                TYPE = 'log',
                SUB_TYPE = 'txt',
                ACTION_CODE = 'SQL_INSERT_LOG',
                ACTION_USER_ID = 'jcardadmin',
                TARGET_USER_ID = '{"folder_id":"credit_card"}'
            WHERE ACTION_CODE IS NULL;
        COMMIT TRAN;

        -------------------------------
        -- 5. Insert D_EBSTM
        -------------------------------
        BEGIN TRAN;
            INSERT INTO D_EBSTM
            (
                TXTIME, TXCODE, MTI, STAN, TXUPDATEDT, BANKCODE, BICCODE, 
                CARDNO, ACNO, CARDBIN, CARDTYPE, RRN, CATID, PCODE, COMCODE,
                MERCODE, ISCOMPLETE, ISVOID, ISREVR, AMT, CCYCODE, STATUS,
                ERRCODE, DESCS, RESPCD, CHAR01, CHAR03, BILLINFO, TRANSID,
                ISCSHBACK, CHAR04, CHAR05, CHAR11, CHAR12, CHAR13, CHAR15,
                CHAR16, NUM01, NUM19, NUM20, UPDATEDT, CHAR17
            )
            SELECT 
                FORMAT(GETDATE(), 'HH.mm.ss') AS TXTIME,
                'DPT_GET_CARD_INFO' AS TXCODE,
                '0100' AS MTI,
                SUBSTRING(CARDBIN, 1, 6) AS STAN,
                GETDATE() AS TXUPDATEDT,
                'SCB' AS BANKCODE,
                'SICOTHBKXXX' AS BICCODE,
                CARDNO,
                ACNO,
                CARDBIN,
                CARDTYPE,
                RRN,
                '11011' AS CATID,
                '700000' AS PCODE,
                '11011' AS COMCODE,
                '-' AS MERCODE,
                'Y' AS ISCOMPLETE,
                'N' AS ISVOID,
                'N' AS ISREVR,
                0 AS AMT,
                'THB' AS CCYCODE,
                'C' AS STATUS,
                'Transaction Successfully!' AS ERRCODE,
                'Get Card Information via Middleware' AS DESCS,
                'Transaction Successfully!' AS RESPCD,
                LOWER(NEWID()) AS CHAR01,
                RIGHT('000000' + CAST(ABS(CHECKSUM(NEWID())) % 1000000 AS VARCHAR(6)), 6) AS CHAR03,
                '{}' AS BILLINFO,
                REPLACE(LOWER(NEWID()), '-', '') AS TRANSID,
                'N' AS ISCSHBACK,
                '{"tx_desc":"Get Card Information via Middleware"}' AS CHAR04,
                '{"fee_code":"-"}' AS CHAR05,
                '1010' AS CHAR11,
                '1010' AS CHAR12,
                'Completed!' AS CHAR13,
                'fee_amt :0.00' AS CHAR15,
                'tx_amt :0.00' AS CHAR16,
                0 AS NUM01,
                0 AS NUM19,
                0 AS NUM20,
                GETDATE() AS UPDATEDT,
                'EB' AS CHAR17
            FROM D_CARDLST
            WHERE CARDSTS = 'P' AND STATUS = 'W' AND CARDTYPE = 'C';
        COMMIT TRAN;

        -------------------------------
        -- 6. Update D_CARDLST to mark cards processed
        -------------------------------
        BEGIN TRAN;
            UPDATE D_CARDLST
            SET CARDSTS = 'N',
                STATUS = 'A'
            WHERE CARDSTS = 'P' AND STATUS = 'W' AND CARDTYPE = 'C';
        COMMIT TRAN;

    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0
            ROLLBACK TRANSACTION;

        DECLARE @ErrMsg NVARCHAR(4000), @ErrSeverity INT;
        SELECT @ErrMsg = ERROR_MESSAGE(), @ErrSeverity = ERROR_SEVERITY();
        RAISERROR(@ErrMsg, @ErrSeverity, 1);
    END CATCH
END
GO


