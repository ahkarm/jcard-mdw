USE [JCARD_SCB]
GO

/****** Object:  StoredProcedure [dbo].[usp_GetScheduleInfo]    Script Date: 11/5/2025 12:38:01 PM ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO


CREATE PROCEDURE [dbo].[usp_GetScheduleInfo]
AS
BEGIN
    SET NOCOUNT ON;

    BEGIN TRY
        BEGIN TRAN;

        -- Clear existing records
        TRUNCATE TABLE [dbo].[D_SCHEDULECONFIGURATION];

        -- Insert latest schedule configuration from SQL Agent Jobs
        INSERT INTO dbo.D_SCHEDULECONFIGURATION
        (
            SCHEDULECODE,
            NAME,
            JOBCODE,
            JOBBODY,
            STEPORD,
            DESCS,
            STATUS,
            VERSION_NUMBER
        )
        SELECT 
            T1.name AS SCHEDULECODE,
            T1.description AS NAME,
            T2.step_name AS JOBCODE,
            T2.command AS JOBBODY,
            T2.step_id AS STEPORD,
            T1.description AS DESCS,
            'C' AS STATUS,
            T1.version_number
        FROM 
            msdb.dbo.sysjobs AS T1
        INNER JOIN 
            msdb.dbo.sysjobsteps AS T2 ON T1.job_id = T2.job_id
        WHERE 
            T1.name NOT IN ('syspolicy_purge_history', 'Backup.Subplan_1')
        ORDER BY 
            T1.name, T2.step_id;

        COMMIT TRAN;
    END TRY

    BEGIN CATCH
        IF @@TRANCOUNT > 0
            ROLLBACK TRAN;

        DECLARE 
            @ErrMsg NVARCHAR(4000),
            @ErrSeverity INT;

        SELECT 
            @ErrMsg = ERROR_MESSAGE(),
            @ErrSeverity = ERROR_SEVERITY();

        RAISERROR(@ErrMsg, @ErrSeverity, 1);
    END CATCH
END
GO


