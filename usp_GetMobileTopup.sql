USE [JCARD_SCB]
GO

/****** Object:  StoredProcedure [dbo].[usp_GetMobileTopup]    Script Date: 11/5/2025 12:37:42 PM ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO


CREATE PROCEDURE [dbo].[usp_GetMobileTopup]
AS
BEGIN
    SET NOCOUNT ON;

    BEGIN TRY
        DECLARE @LoopCount INT = FLOOR(RAND(CHECKSUM(NEWID())) * 3) + 1;  -- 1–3 inserts
        DECLARE @Counter INT = 1;

        WHILE @Counter <= @LoopCount
        BEGIN
            BEGIN TRAN;

            INSERT INTO D_EBSTM
            (
                TXTIME, TXCODE, BANKCODE, BICCODE, PCODE, COMCODE, MERCODE,
                AMT, CCYCODE, STATUS, CHAR01, CHAR02, CHAR03, BILLINFO, TRANSID, ISCSHBACK
            )
            VALUES
            (
                FORMAT(GETDATE(), 'HH.mm.ss'),
                (SELECT CODESUBTYPE FROM D_CODETYPE WHERE CODETYPE = 'TXCODE' AND RECID IN (19)),
                'SCB',
                'SICOTHBKXXX',
                '420000',
                '11011',
                (SELECT TOP 1 CODESUBTYPE FROM D_CODETYPE WHERE CODETYPE = 'BILLER' ORDER BY NEWID()),
                (
                    SELECT TOP 1 CODESUBTYPE
                    FROM (
                        SELECT CODESUBTYPE FROM D_CODETYPE WHERE CODETYPE = 'TOPUPAMT'
                        UNION ALL
                        SELECT CODESUBTYPE FROM D_CODETYPE WHERE CODETYPE = 'TOPUPAMT' AND CODESUBTYPE IN ('200','50','100')
                    ) AS WeightedPool
                    ORDER BY NEWID()
                ),
                'THB',
                (
                    SELECT TOP 1 CODESUBTYPE
                    FROM (
                        SELECT CODESUBTYPE FROM D_CODETYPE WHERE CODETYPE = 'STT'
                        UNION ALL SELECT CODESUBTYPE FROM D_CODETYPE WHERE CODETYPE = 'STT' AND CODESUBTYPE = 'C'
                    ) AS WeightedPool
                    ORDER BY NEWID()
                ),
                LOWER(NEWID()),
                (
                    SELECT TOP 1 CARDNO, CARDTYPE, BRAND, CARDBIN, RRN, ACNO
                    FROM D_CARDLST
                    ORDER BY NEWID()
                    FOR JSON PATH, WITHOUT_ARRAY_WRAPPER
                ),
                RIGHT('000000' + CAST(ABS(CHECKSUM(NEWID())) % 1000000 AS VARCHAR(6)), 6),
                '{}',
                REPLACE(LOWER(NEWID()), '-', ''),
                'N'
            );

            COMMIT TRAN;
            SET @Counter += 1;
        END;

        ----------------------------------------------------------------
        -- UPDATE TXN INFO
        ----------------------------------------------------------------
        BEGIN TRAN;
        UPDATE D_EBSTM
        SET 
            CATID = CONCAT(CONVERT(VARCHAR(8), GETDATE(), 112), REPLACE(LOWER(NEWID()),'-','')),
            ACNO = JSON_VALUE(CHAR02,'$.ACNO'),
            CARDNO = JSON_VALUE(CHAR02,'$.CARDNO'),
            CARDBIN = JSON_VALUE(CHAR02,'$.CARDBIN'),
            RRN = JSON_VALUE(CHAR02,'$.RRN'),
            CARDTYPE = JSON_VALUE(CHAR02,'$.CARDTYPE'),
            DESCS = 'Mobile Topup via ATM',
            CHAR04 = '{"tx_desc":"Mobile Topup via ATM"}'
        WHERE TXCODE = 'DPT_MOB_TOP' AND ACNO IS NULL;
        COMMIT TRAN;

        ----------------------------------------------------------------
        -- UPDATE TXN AMOUNT / FEE
        ----------------------------------------------------------------
        BEGIN TRAN;
        UPDATE D_EBSTM
        SET 
            NUM19 = AMT,
            CHAR05 = '{"fee_code":"-"}',
            NUM01 = 0
        WHERE TXCODE = 'DPT_MOB_TOP' AND CHAR05 IS NULL;
        COMMIT TRAN;

        ----------------------------------------------------------------
        -- UPDATE TXN STATUS / RESPONSE
        ----------------------------------------------------------------
        BEGIN TRAN;
        UPDATE D_EBSTM
        SET 
            ISCOMPLETE = CASE WHEN STATUS = 'C' THEN 'Y' ELSE 'N' END,
            ISVOID = CASE WHEN STATUS <> 'C' THEN 'Y' ELSE 'N' END,
            ISREVR = CASE WHEN STATUS <> 'C' THEN 'Y' ELSE 'N' END,
            MTI = CASE WHEN STATUS = 'C' THEN '0200' ELSE '0400' END,
            ERRCODE = CASE WHEN STATUS = 'C' THEN 'Transaction Successfully!' ELSE 'Transaction Failed at JCard Middleware Side!' END,
            RESPCD = CASE WHEN STATUS = 'C' THEN 'Transaction Successfully!' ELSE 'Transaction Failed at JCard Middleware Side!' END,
            NUM20 = CASE WHEN STATUS = 'C' THEN NUM01 + NUM19 ELSE 0 END,
            STAN = SUBSTRING(CARDBIN,1,6)
        WHERE TXCODE = 'DPT_MOB_TOP' AND ISCOMPLETE IS NULL;
        COMMIT TRAN;

        ----------------------------------------------------------------
        -- FINAL TXN LOG UPDATE
        ----------------------------------------------------------------
        BEGIN TRAN;
        UPDATE D_EBSTM
        SET 
            TXUPDATEDT = GETDATE(),
            UPDATEDT = GETDATE(),
            CHAR11 = '1010',
            CHAR12 = '1010',
            CHAR13 = 'Completed!',
            CHAR14 = CAST(
                REPLACE(CONVERT(VARCHAR(8), GETDATE(), 112), '-', '') +
                RIGHT('0000000000' + CAST(DATEDIFF(SECOND, '2000-01-01', GETDATE()) AS VARCHAR(10)), 10) +
                RIGHT('000000' + CAST(ABS(CHECKSUM(NEWID())) % 1000000 AS VARCHAR(6)), 6)
                AS VARCHAR(25)
            ),
            CHAR15 = CONCAT('fee_amt :', NUM01),
            CHAR16 = CONCAT('tx_amt :', AMT),
            CHAR17 = 'EB'
        WHERE TXCODE = 'DPT_MOB_TOP' AND TXUPDATEDT IS NULL;
        COMMIT TRAN;

    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRAN;
        DECLARE @ErrMsg NVARCHAR(4000) = ERROR_MESSAGE();
        PRINT 'Error occurred in usp_GetMobileTopup: ' + @ErrMsg;
    END CATCH
END;
GO


