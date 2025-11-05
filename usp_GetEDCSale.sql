USE [JCARD_SCB]
GO

/****** Object:  StoredProcedure [dbo].[usp_GetEDCSale]    Script Date: 11/5/2025 12:37:17 PM ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO


CREATE PROCEDURE [dbo].[usp_GetEDCSale]
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @LoopCount INT = FLOOR(RAND(CHECKSUM(NEWID())) * 5) + 1;
    DECLARE @Counter INT = 1;

    BEGIN TRY
        ---------------------------------------------
        -- 1. INSERT TRANSACTION INFO
        ---------------------------------------------
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
                (SELECT TOP 1 CODESUBTYPE 
                 FROM D_CODETYPE 
                 WHERE CODETYPE = 'TXCODE' AND RECID IN (21,20)
                 ORDER BY NEWID()),
                'SCB',
                'SICOTHBKXXX',
                '010000',
                '11013',
                (SELECT TOP 1 CODESUBTYPE 
                 FROM D_CODETYPE 
                 WHERE CODETYPE = 'MCC' ORDER BY NEWID()),
                CAST(FLOOR(RAND(CHECKSUM(NEWID())) * ((20000 - 20) / 100 + 1)) * 100 + 100 AS INT),
                'THB',
                (
                    SELECT TOP 1 CODESUBTYPE
                    FROM (
                        SELECT CODESUBTYPE FROM D_CODETYPE WHERE CODETYPE = 'STT'
                        UNION ALL SELECT CODESUBTYPE FROM D_CODETYPE WHERE CODETYPE = 'STT' AND CODESUBTYPE = 'C'
                        UNION ALL SELECT CODESUBTYPE FROM D_CODETYPE WHERE CODETYPE = 'STT' AND CODESUBTYPE = 'C'
                        UNION ALL SELECT CODESUBTYPE FROM D_CODETYPE WHERE CODETYPE = 'STT' AND CODESUBTYPE = 'C'
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

        ---------------------------------------------
        -- 2. UPDATE TRANSACTION INFO (MAP CARD DETAILS)
        ---------------------------------------------
        BEGIN TRAN;
        UPDATE D_EBSTM
        SET 
            CATID = CONCAT(CONVERT(VARCHAR(8), GETDATE(), 112), REPLACE(LOWER(NEWID()),'-','')),
            ACNO = JSON_VALUE(CHAR02,'$.ACNO'),
            CARDNO = JSON_VALUE(CHAR02,'$.CARDNO'),
            CARDBIN = JSON_VALUE(CHAR02,'$.CARDBIN'),
            RRN = JSON_VALUE(CHAR02,'$.RRN'),
            CARDTYPE = JSON_VALUE(CHAR02,'$.CARDTYPE'),
            DESCS = CASE 
                        WHEN TXCODE = 'DPT_EDC_SALE_OFF' THEN 'EDC Sale Off-US'
                        WHEN TXCODE = 'DPT_EDC_SALE_OUS' THEN 'EDC Sale On-US'
                    END,
            CHAR04 = CASE 
                        WHEN TXCODE = 'DPT_EDC_SALE_OFF' THEN '{"tx_desc":"EDC Sale Off-US"}'
                        WHEN TXCODE = 'DPT_EDC_SALE_OUS' THEN '{"tx_desc":"EDC Sale On-US"}'
                    END
        WHERE TXCODE IN ('DPT_EDC_SALE_OFF', 'DPT_EDC_SALE_OUS')
          AND ACNO IS NULL;
        COMMIT TRAN;

        ---------------------------------------------
        -- 3. UPDATE TRANSACTION AMOUNT & FEES
        ---------------------------------------------
        BEGIN TRAN;
        UPDATE D_EBSTM
        SET 
            NUM19 = AMT,
            CHAR05 = CASE 
                        WHEN TXCODE = 'DPT_EDC_SALE_OFF' THEN '{"fee_code":"41"}'
                        ELSE '{"fee_code":"-"}'
                     END,
            NUM01 = CASE 
                        WHEN TXCODE = 'DPT_EDC_SALE_OFF' THEN 5.00
                        ELSE 0
                    END
        WHERE TXCODE IN ('DPT_EDC_SALE_OFF', 'DPT_EDC_SALE_OUS')
          AND CHAR05 IS NULL;
        COMMIT TRAN;

        ---------------------------------------------
        -- 4. UPDATE TRANSACTION STATUS
        ---------------------------------------------
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
            STAN = SUBSTRING(CARDBIN, 1, 6)
        WHERE TXCODE IN ('DPT_EDC_SALE_OFF', 'DPT_EDC_SALE_OUS')
          AND ISCOMPLETE IS NULL;
        COMMIT TRAN;

        ---------------------------------------------
        -- 5. UPDATE TRANSACTION LOG
        ---------------------------------------------
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
                         AS VARCHAR(25)),
            CHAR15 = CONCAT('fee_amt :', NUM01),
            CHAR16 = CONCAT('tx_amt :', AMT),
            CHAR17 = 'EB'
        WHERE TXCODE IN ('DPT_EDC_SALE_OFF', 'DPT_EDC_SALE_OUS')
          AND TXUPDATEDT IS NULL;
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


