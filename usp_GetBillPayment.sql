USE [JCARD_SCB]
GO

/****** Object:  StoredProcedure [dbo].[usp_GetBillPayment]    Script Date: 11/5/2025 12:35:19 PM ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO


CREATE PROCEDURE [dbo].[usp_GetBillPayment]
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @LoopCount INT;
    DECLARE @Counter INT;

    BEGIN TRY
        -------------------------------
        -- 1. Add Transaction Info (Random Inserts)
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
                    (SELECT CODESUBTYPE FROM D_CODETYPE WHERE CODETYPE = 'TXCODE' AND RECID IN (18)),
                    'SCB',
                    'SICOTHBKXXX',
                    '420000',
                    '11011',
                    '-',
                    0,
                    'THB',
                    (
                        SELECT TOP 1 CODESUBTYPE
                        FROM (
                            SELECT CODESUBTYPE FROM D_CODETYPE WHERE CODETYPE = 'STT'
                            UNION ALL
                            SELECT CODESUBTYPE FROM D_CODETYPE WHERE CODETYPE = 'STT' AND CODESUBTYPE = 'C'
                            UNION ALL
                            SELECT CODESUBTYPE FROM D_CODETYPE WHERE CODETYPE = 'STT' AND CODESUBTYPE = 'C'
                            UNION ALL
                            SELECT CODESUBTYPE FROM D_CODETYPE WHERE CODETYPE = 'STT' AND CODESUBTYPE = 'C'
                            UNION ALL
                            SELECT CODESUBTYPE FROM D_CODETYPE WHERE CODETYPE = 'STT' AND CODESUBTYPE = 'C'
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
                    (
                        SELECT TOP 1
                            (SELECT TOP 1 CODESUBTYPE FROM D_CODETYPE WHERE CODETYPE = 'BILLTYPE' ORDER BY NEWID()) AS billtype,
                            'A' AS paidsts,
                            GETDATE() AS billdt,
                            GETDATE() AS txdt,
                            CAST(FLOOR(RAND(CHECKSUM(NEWID())) * ((15000 - 20) / 10 + 1)) * 10 + 20 AS INT) AS billamt,
                            'THB' AS billccy
                        FOR JSON PATH, WITHOUT_ARRAY_WRAPPER
                    ),
                    REPLACE(LOWER(NEWID()), '-', ''),
                    'N'
                );

            COMMIT TRAN;

            SET @Counter += 1;
        END

        -------------------------------
        -- 2. Update Transaction Info (JSON -> Columns)
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
                AMT = JSON_VALUE(BILLINFO,'$.billamt'),
                DESCS = CASE WHEN TXCODE = 'DPT_BILL_PAY' THEN 'Bill Payment via ATM' END,
                CHAR04 = CASE WHEN TXCODE = 'DPT_BILL_PAY' THEN '{"tx_desc":"Bill Payment via ATM"}' END
            WHERE TXCODE IN ('DPT_BILL_PAY') AND ACNO IS NULL;
        COMMIT TRAN;

        -------------------------------
        -- 3. Update Transaction Amount & Fee
        -------------------------------
        BEGIN TRAN;
            UPDATE D_EBSTM
            SET 
                NUM19 = AMT,
                CHAR05 = CASE 
                    WHEN TXCODE = 'DPT_BILL_PAY' AND AMT > 3000.00 AND AMT <= 5000.00 THEN '{"fee_code":"31"}'
                    WHEN TXCODE = 'DPT_BILL_PAY' AND AMT > 5000.00 AND AMT <= 10000.00 THEN '{"fee_code":"32"}'
                    WHEN TXCODE = 'DPT_BILL_PAY' AND AMT > 10000.00 THEN '{"fee_code":"33"}'
                    ELSE '{"fee_code":"-"}'
                END,
                NUM01 = CASE 
                    WHEN TXCODE = 'DPT_BILL_PAY' AND AMT > 3000.00 AND AMT <= 5000.00 THEN 5.00
                    WHEN TXCODE = 'DPT_BILL_PAY' AND AMT > 5000.00 AND AMT <= 10000.00 THEN 10.00
                    WHEN TXCODE = 'DPT_BILL_PAY' AND AMT > 10000.00 THEN 20.00
                    ELSE 0
                END
            WHERE TXCODE IN ('DPT_BILL_PAY') AND CHAR05 IS NULL;
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
            WHERE TXCODE IN ('DPT_BILL_PAY') AND ISCOMPLETE IS NULL;
        COMMIT TRAN;

        -------------------------------
        -- 5. Update Transaction Log Info
        -------------------------------
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
                CHAR15 = CONCAT('fee_amt :',NUM01),
                CHAR16 = CONCAT('tx_amt :',AMT),
                CHAR17 = 'EB'
            WHERE TXCODE IN ('DPT_BILL_PAY') AND TXUPDATEDT IS NULL;
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


