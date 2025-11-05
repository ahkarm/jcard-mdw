USE [JCARD_SCB]
GO

/****** Object:  StoredProcedure [dbo].[usp_GetCashBack]    Script Date: 11/5/2025 12:35:54 PM ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO


CREATE PROCEDURE [dbo].[usp_GetCashBack]
AS
BEGIN
    SET NOCOUNT ON;

    BEGIN TRY
        -------------------------------
        -- 1. Insert Cashback
        -------------------------------
        BEGIN TRAN;
            INSERT INTO D_CASHBACK(
                TXREFID, TXDT, TXCODE, AMT, PCODE, DTXDT,
                GL_ACCOUNT, GL_FEE, CARDNO, ACNO, CARDBIN, RRN,
                STATUS, ERROR_DESCS, REFERENCE_NUMBER, DESCS, FEEAMT
            )
            SELECT TOP 1 
                LOWER(NEWID()),
                TXDT,
                CASE 
                    WHEN TXCODE IN ('DPT_EDC_SALE_OUS','DPT_EDC_SALE_OFF') THEN 'DPT_EDC_CSH_BACK'
                    WHEN TXCODE IN ('DPT_POS_SALE_OUS','DPT_POS_SALE_OFF') THEN 'DPT_POS_CSH_BACK' 
                END AS TXCODE,
                (
                    SELECT TOP 1 CODESUBTYPE
                    FROM (
                        SELECT CODESUBTYPE FROM D_CODETYPE WHERE CODETYPE = 'CSHBACKAMT'
                        UNION ALL
                        SELECT CODESUBTYPE FROM D_CODETYPE WHERE CODETYPE = 'CSHBACKAMT' AND CODESUBTYPE IN ('20','50','100','500') 
                    ) AS WeightedPool
                    ORDER BY NEWID()
                ),
                PCODE,
                DTXDT,
                CASE 
                    WHEN TXCODE IN ('DPT_EDC_SALE_OUS','DPT_EDC_SALE_OFF') THEN '{"ac_no":"330110293","ccy_code":"THB"}'
                    WHEN TXCODE IN ('DPT_POS_SALE_OUS','DPT_POS_SALE_OFF') THEN '{"ac_no":"330110294","ccy_code":"THB"}' 
                END,
                10,
                CARDNO,
                ACNO,
                CARDBIN,
                RRN,
                STATUS,
                RESPCD,
                TXREFID,
                CASE 
                    WHEN TXCODE IN ('DPT_EDC_SALE_OUS','DPT_EDC_SALE_OFF') THEN 'EDC CashBack'
                    WHEN TXCODE IN ('DPT_POS_SALE_OUS','DPT_POS_SALE_OFF') THEN 'POS CashBack' 
                END,
                10
            FROM D_EBSTM
            WHERE TXCODE IN ('DPT_EDC_SALE_OUS','DPT_EDC_SALE_OFF','DPT_POS_SALE_OUS','DPT_POS_SALE_OFF')
              AND ISCSHBACK = 'N' 
              AND CHAR21 IS NULL 
              AND STATUS = 'C';
        COMMIT TRAN;

        -------------------------------
        -- 2. Update D_EBSTM with Cashback Info
        -------------------------------
        BEGIN TRAN;
            UPDATE e
            SET 
                CHAR21 = CONCAT('csh_back_ref : ', c.TXREFID),
                ISCSHBACK = 'Y',
                CHAR22 = CONCAT('csh_back_amt : ', c.AMT),
                CHAR23 = CONCAT('csh_back_fee : ', c.FEEAMT),
                NUM10 = c.AMT,
                NUM11 = c.AMT
            FROM D_EBSTM e
            INNER JOIN D_CASHBACK c
                ON e.TXREFID = c.REFERENCE_NUMBER
            WHERE c.REFERENCE_ID IS NULL
              AND e.ISCSHBACK = 'N';
        COMMIT TRAN;

        -------------------------------
        -- 3. Update D_CASHBACK REFERENCE_ID
        -------------------------------
        BEGIN TRAN;
            UPDATE D_CASHBACK
            SET REFERENCE_ID = CAST(
                    REPLACE(CONVERT(VARCHAR(8), GETDATE(), 112), '-', '') +  -- yyyymmdd
                    RIGHT('0000000000' + CAST(DATEDIFF(SECOND, '2000-01-01', GETDATE()) AS VARCHAR(10)), 10) +
                    RIGHT('000000000000000000000000' + CAST(ABS(CHECKSUM(NEWID())) % 1000000000000000000000000 AS VARCHAR(24)), 24)
                    AS VARCHAR(100)
                )
            WHERE REFERENCE_ID IS NULL;
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


