USE [JCARD_SCB]
GO

/****** Object:  StoredProcedure [dbo].[usp_GetCashAdvance]    Script Date: 11/5/2025 12:35:42 PM ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO


CREATE PROCEDURE [dbo].[usp_GetCashAdvance]
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @LoopCount INT;
    DECLARE @Counter INT;

    BEGIN TRY
        -------------------------------
        -- 1. Insert Cash Advance Transactions
        -------------------------------
        SET @LoopCount = FLOOR(RAND(CHECKSUM(NEWID())) * 3) + 1;
        SET @Counter = 1;

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
                     WHERE CODETYPE = 'TXCODE' AND RECID IN (35,36) 
                     ORDER BY NEWID()),
                    'SCB',
                    'SICOTHBKXXX',
                    '000000',
                    '11011',
                    '-',
                    CAST(FLOOR(RAND(CHECKSUM(NEWID())) * ((15000 - 20) / 100 + 1)) * 100 + 100 AS INT),
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
                        FROM D_CARDLST WHERE CARDTYPE = 'C'
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
        END

        -------------------------------
        -- 2. Update Transaction Info (JSON -> Columns & Description)
        -------------------------------
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
                    WHEN TXCODE = 'DPT_WDR_CSH_ADV_OUS' THEN 'Cash Advance Withdrawal On-US'
                    WHEN TXCODE = 'DPT_WDR_CSH_ADV_OFF' THEN 'Cash Advance Withdrawal Off-US'
                END,
                CHAR04 = CASE 
                    WHEN TXCODE = 'DPT_WDR_CSH_ADV_OUS' THEN '{"tx_desc":"Cash Advance Withdrawal On-US"}'
                    WHEN TXCODE = 'DPT_WDR_CSH_ADV_OFF' THEN '{"tx_desc":"Cash Advance Withdrawal Off-US"}'
                END
            WHERE TXCODE IN ('DPT_WDR_CSH_ADV_OUS','DPT_WDR_CSH_ADV_OFF')
              AND ACNO IS NULL;
        COMMIT TRAN;

        -------------------------------
        -- 3. Update Transaction Amount & Fees
        -------------------------------
        BEGIN TRAN;
            UPDATE D_EBSTM
            SET 
                NUM19 = AMT,
                CHAR05 = CASE 
                    WHEN TXCODE = 'DPT_WDR_CSH_ADV_OFF' AND AMT > 3000.00 AND AMT <= 5000.00 THEN '{"fee_code":"10"}'
                    WHEN TXCODE = 'DPT_WDR_CSH_ADV_OFF' AND AMT > 5000.00 AND AMT <= 10000.00 THEN '{"fee_code":"11"}'
                    WHEN TXCODE = 'DPT_WDR_CSH_ADV_OFF' AND AMT > 10000.00 THEN '{"fee_code":"12"}'
                    ELSE '{"fee_code":"-"}'
                END,
                NUM01 = CASE 
                    WHEN TXCODE = 'DPT_WDR_CSH_ADV_OFF' AND AMT > 3000.00 AND AMT <= 5000.00 THEN 10.00
                    WHEN TXCODE = 'DPT_WDR_CSH_ADV_OFF' AND AMT > 5000.00 AND AMT <= 10000.00 THEN 20.00
                    WHEN TXCODE = 'DPT_WDR_CSH_ADV_OFF' AND AMT > 10000.00 THEN 50.00
                    ELSE 0
                END
            WHERE TXCODE IN ('DPT_WDR_CSH_ADV_OFF','DPT_WDR_CSH_ADV_OUS')
              AND CHAR05 IS NULL;
        COMMIT TRAN;

        -------------------------------
        -- 4. Update Transaction Status
        -------------------------------
        BEGIN TRAN;
            UPDATE D_EBSTM
            SET 
                ISCOMPLETE = CASE WHEN STATUS = 'C' THEN 'Y' ELSE 'N' END,
                ISVOID = CASE WHEN STATUS <> 'C' THEN 'Y' ELSE 'N' END,
                ISREVR = CASE WHEN STATUS <> 'C' THEN 'Y' ELSE 'N' END,
                MTI = CASE WHEN STATUS = 'C' THEN '0200' ELSE '0400' END,
                ERRCODE = CASE WHEN STATUS = 'C' THEN 'Transaction Successfully!' ELSE 'Transaction Failed at JCard Middleware Side!' END,
                RESPCD = CASE WHEN STATUS = 'C' THEN 'Transaction Successfully!' ELSE 'Transaction Failed at JCard Middleware Side!' END,
                NUM20 = CASE WHEN STATUS = 'C' THEN NUM01+NUM19 ELSE 0 END,
                STAN = SUBSTRING(CARDBIN,1,6)
            WHERE TXCODE IN ('DPT_WDR_CSH_ADV_OFF','DPT_WDR_CSH_ADV_OUS')
              AND ISCOMPLETE IS NULL;
        COMMIT TRAN;

        -------------------------------
        -- 5. Insert OTP Info for Off-US
        -------------------------------
        BEGIN TRAN;
            INSERT INTO D_OTPINFO(txrefid,txcode,sercode,requestbody,otp,otpsts,txdt,duration)
            SELECT 
                TXREFID,
                TXCODE,
                TXCODE,
                CHAR02,
                CHAR03,
                CASE WHEN STATUS = 'C' THEN 'U' ELSE 'E' END,
                TXDT,
                '180'
            FROM D_EBSTM
            WHERE TXCODE = 'DPT_WDR_CSH_ADV_OFF'
              AND CHAR06 IS NULL;
        COMMIT TRAN;

        -------------------------------
        -- 6. Update ebstm with OTP status messages
        -------------------------------
        BEGIN TRAN;
            UPDATE D_EBSTM
            SET 
                CHAR06 = CASE WHEN STATUS = 'C' THEN 'otp is used!' ELSE 'otp is expired!' END,
                CHAR07 = CASE WHEN STATUS = 'C' THEN CHAR03+' is used!' ELSE CHAR03+' is expired!' END,
                CHAR08 = 'Auth OTP '+CHAR03+' will expire within 3 mins'
            WHERE TXCODE = 'DPT_WDR_CSH_ADV_OFF'
              AND CHAR06 IS NULL;
        COMMIT TRAN;

        -------------------------------
        -- 7. Update Transaction Log Info
        -------------------------------
        BEGIN TRAN;
            UPDATE D_EBSTM
            SET TXUPDATEDT = GETDATE(),
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
                CHAR15 = CONCAT('fee_amt :',NUM01),
                CHAR16 = CONCAT('tx_amt :',AMT),
                CHAR17 = 'EB'
            WHERE TXCODE IN ('DPT_WDR_CSH_ADV_OFF','DPT_WDR_CSH_ADV_OUS')
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


