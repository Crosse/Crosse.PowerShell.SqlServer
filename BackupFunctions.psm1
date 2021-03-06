function Backup-Database {
    [CmdletBinding(SupportsShouldProcess=$true,
            ConfirmImpact="High")]
    param (
            [Parameter(Mandatory=$true)]
            [ValidateNotNullOrEmpty()]
            # The MSSQL server to which to connect.
            # This could be either the default instance or a named
            # instance.
            [string]
            $Server,

            [Parameter(Mandatory=$true)]
            [ValidateNotNullOrEmpty()]
            [string]
            $Database,

            [Parameter(Mandatory=$true)]
            [System.IO.FileInfo]
            $BackupPath,

            [Parameter(Mandatory=$false,
                ParameterSetName="FullBackup")]
            [switch]
            $FullBackup,

            [Parameter(Mandatory=$false,
                ParameterSetName="DifferentialBackup")]
            [switch]
            $DifferentialBackup,

            [Parameter(Mandatory=$false,
                ParameterSetName="TransactionLogBackup")]
            [switch]
            $TransactionLogBackup,

            [Parameter(Mandatory=$false)]
            [switch]
            $CopyOnly,

            [Parameter(Mandatory=$false)]
            [switch]
            $Compression,

            [Parameter(Mandatory=$false)]
            [string]
            $Description,

            [Parameter(Mandatory=$false)]
            [string]
            $Name,

            [Parameter(Mandatory=$false)]
            [DateTime]
            $ExpireDate,

            [Parameter(Mandatory=$false)]
            [int]
            $RetainDays,

            [Parameter(Mandatory=$false)]
            [switch]
            $Init,

            [Parameter(Mandatory=$false)]
            [switch]
            $Skip,

            [Parameter(Mandatory=$false)]
            [switch]
            $Format,

            [Parameter(Mandatory=$false)]
            [string]
            $MediaDescription,

            [Parameter(Mandatory=$false)]
            [string]
            $MediaName,

            [Parameter(Mandatory=$false)]
            [switch]
            $Checksum,

            [Parameter(Mandatory=$false,
                ParameterSetName="TransactionLogBackup")]
            [switch]
            $NoTruncate
          )

    if ($FullBackup -or $DifferentialBackup) {
        $backupType = "DATABASE"
        if ($FullBackup) {
            $desc = "Perform full backup of database $Database on server $Server"
        } else {
            $desc = "Perform differential backup of database $Database on server $Server"
        }
    } elseif ($TransactionLogBackup) {
        $backupType = "LOG"
        $desc = "Perform transaction log backup for database $Database on server $Server"
    } else {
        # should never happen
        Write-Error "Backup type not recognized"
        return
    }

    $cmd = "BACKUP {0} [{1}] TO DISK = '{2}'" -f $backupType, $Database, $BackupPath

    $withOptions = @(BuildWithOptions $PSCmdlet.MyInvocation.BoundParameters)
    if ($withOptions.Count -gt 0) {
        $with = " WITH {0}" -f ($withOptions -join ", ")
        $cmd += $with
    }

    $caption = $desc
    $warning = "Are you sure you want to perform this action?`n"
    $warning += "This will perform a "
    if ($FullBackup) {
        $warning += "full backup "
    } elseif ($DifferentialBackup) {
        $warning += "differential "
    } elseif ($TransactionLogBackup) {
        $warning += "transaction log "
    }
    $warning += "backup of database $Database on $Server."

    if (!$PSCmdlet.ShouldProcess($desc, $warning, $caption)) {
        return
    }

    PerformBackupOrRecovery -Server $Server -Database $Database -Command $cmd
}

function Restore-Database {
    [CmdletBinding(SupportsShouldProcess=$true,
            ConfirmImpact="High")]
    param (
            [Parameter(Mandatory=$true)]
            [ValidateNotNullOrEmpty()]
            # The MSSQL server to which to connect.
            # This could be either the default instance or a named
            # instance.
            [string]
            $Server,

            [Parameter(Mandatory=$true)]
            [ValidateNotNullOrEmpty()]
            [string]
            $Database,

            [Parameter(Mandatory=$true)]
            [System.IO.FileInfo]
            $RestorePath,

            [Parameter(Mandatory=$false,
                ParameterSetName="DatabaseRestore")]
            [switch]
            $RestoreDatabase,

            [Parameter(Mandatory=$false,
                ParameterSetName="TransactionLogRestore")]
            [switch]
            $RestoreTransactionLog,

            [Parameter(Mandatory=$false)]
            [int]
            $BackupSetFileNumber,

            [Parameter(Mandatory=$false)]
            [switch]
            $Partial,

            [Parameter(Mandatory=$false)]
            [switch]
            $Recovery,

            [Parameter(Mandatory=$false)]
            [switch]
            $Replace,

            [Parameter(Mandatory=$false)]
            [System.Collections.Hashtable]
            $MoveMapping,

            [Parameter(Mandatory=$false)]
            [switch]
            $Restart,

            [Parameter(Mandatory=$false)]
            [switch]
            $RestrictedUser,

            [Parameter(Mandatory=$false)]
            [string]
            $MediaName,

            [Parameter(Mandatory=$false)]
            [switch]
            $Checksum
          )

    if ($RestoreDatabase) {
        $backupType = "DATABASE"
        $desc = "Perform full restore of database $Database on server $Server"
    } elseif ($RestoreTransactionLog) {
        $backupType = "LOG"
        $desc = "Perform transaction log restore of database $Database on server $Server"
    } else {
        # should never happen
        Write-Error "Restore type not recognized"
        return
    }

    $cmd = "RESTORE {0} [{1}] FROM DISK = '{2}'" -f $backupType, $Database, $RestorePath

    $withOptions = @(BuildWithOptions $PSCmdlet.MyInvocation.BoundParameters)
    if ($withOptions.Count -gt 0) {
        $with = " WITH {0}" -f ($withOptions -join ", ")
        $cmd += $with
    }

    Write-Verbose $cmd

    $caption = $desc
    $warning = "Are you sure you want to perform this action?`n"
    $warning += "This will perform a "
    if ($RestoreDatabase) {
        $warning += "full "
    } elseif ($RestoreTransactionLog) {
        $warning += "transaction log "
    }
    $warning += "restore of database $Database on $Server."

    if (!$PSCmdlet.ShouldProcess($desc, $warning, $caption)) {
        return
    }

    PerformBackupOrRecovery -Server $Server -Database $Database -Command $cmd
}

function PerformBackupOrRecovery {
    [CmdletBinding()]
    param (
            [Parameter(Mandatory=$true)]
            [ValidateNotNullOrEmpty()]
            # The MSSQL server to which to connect.
            # This could be either the default instance or a named
            # instance.
            [string]
            $Server,

            [Parameter(Mandatory=$true)]
            [ValidateNotNullOrEmpty()]
            [string]
            $Database,

            [Parameter(Mandatory=$true)]
            [ValidateNotNullOrEmpty()]
            [string]
            $Command
          )

    if ($Command.Contains("BACKUP")) {
        $verbPhrase = "Backing up"
    } elseif ($Command.Contains("RESTORE")) {
        $verbPhrase = "Restoring"
    }

    $conn = Open-SqlConnection -Server $Server -Async
    $spid = (Send-SqlQuery -SqlConnection $conn -Command "SELECT @@SPID as spid").spid
    $sqlCmd = $conn.CreateCommand()
    $sqlCmd.CommandText = $Command

    $checkConn = Open-SqlConnection -Server $Server
    $perms = Send-SqlQuery -SqlConnection $checkConn -Command "SELECT * FROM fn_my_permissions(NULL, 'SERVER') WHERE permission_name = 'VIEW SERVER STATE'"
    if ($perms -eq $null) {
        Write-Warning "Cannot get progress.  You have not been granted the VIEW SERVER STATE permission."
    }

    $start = Get-Date
    $result = $sqlCmd.BeginExecuteNonQuery()
    while (! $result.IsCompleted) {
        $check = Send-SqlQuery -SqlConnection $checkConn -Command "SELECT session_id,percent_complete,command,estimated_completion_time FROM sys.dm_exec_requests WHERE session_id = $spid AND command IN ('BACKUP DATABASE', 'BACKUP LOG', 'RESTORE DATABASE', 'RESTORE LOG')"
        if ($check -eq $null) {
            break
        }

        if ($perms -eq $null) {
            $elapsed = ((Get-Date) - $start).ToString("hh\:mm\:ss")
            Write-Progress -Activity "$verbPhrase $Database" -Status "Elapsed time:  $elapsed"
        } else {
            $percent = [Math]::Round($check.percent_complete, 0, "AwayFromZero")
            Write-Progress -Activity "$verbPhrase $Database" `
                           -Status "${percent}% complete" `
                           -PercentComplete $check.percent_complete `
                           -SecondsRemaining ($check.estimated_completion_time / 1000)
        }
        Start-Sleep -Milliseconds 250
    }
    Write-Progress -Activity "$verb $Database" -Status "Completed" -Completed
    $sqlCmd.EndExecuteNonQuery($result) | Out-Null
    $sqlCmd.Dispose()
    Close-SqlConnection $conn
    Close-SqlConnection $checkConn
}

function BuildWithOptions {
    param (
            [System.Collections.Hashtable]
            [ValidateNotNull()]
            $BoundParameters
          )

    $withOptions = @()

    if ($BoundParameters['DifferentialBackup']) {
        $withOptions += "DIFFERENTIAL"
    }

    if ($BoundParameters['CopyOnly']) {
        $withOptions += "COPY_ONLY"
    }

    if ($BoundParameters.ContainsKey('Compression')) {
        if ($Compression) {
            $withOptions += "COMPRESSION"
        } else {
            $withOptions += "NO_COMPRESSION"
        }
    }

    if (! [String]::IsNullOrEmpty($Description)) {
        $withOptions += "DESCRIPTION = '$Description'"
    }

    if (! [String]::IsNullOrEmpty($Name)) {
        $withOptions += "NAME = '$Name'"
    }

    if ($ExpireDate) {
        $withOptions += "EXPIREDATE = '$ExpireDate'"
    }

    if ($RetainDays) {
        $withOptions += "RETAINDAYS = $RetainDays"
    }

    if ($BoundParameters.ContainsKey('Init')) {
        if ($Init) {
            $withOptions += "INIT"
        } else {
            $withOptions += "NOINIT"
        }
    }

    if ($BoundParameters.ContainsKey('Skip')) {
        if ($Skip) {
            $withOptions += "SKIP"
        } else {
            $withOptions += "NOSKIP"
        }
    }

    if ($BoundParameters.ContainsKey('Format')) {
        if ($Format) {
            $withOptions += "FORMAT"
        } else {
            $withOptions += "NOFORMAT"
        }
    }

    if (! [String]::IsNullOrEmpty($MediaDescription)) {
        $withOptions += "MEDIADESCRIPTION = '$MediaDescription'"
    }

    if (! [String]::IsNullOrEmpty($MediaName)) {
        $withOptions += "MEDIANAME = '$MediaName'"
    }

    if ($BoundParameters.ContainsKey('Checksum')) {
        if ($Checksum) {
            $withOptions += "CHECKSUM"
        } else {
            $withOptions += "NO_CHECKSUM"
        }
    }

    if ($BoundParameters.ContainsKey('NoTruncate')) {
        if ($NoTruncate) {
            $withOptions += "NO_TRUNCATE"
        }
    }

    if ($BoundParameters.ContainsKey('BackupSetFileNumber')) {
        $withOptions += "FILE = $BackupSetFileNumber"
    }

    if ($BoundParameters.ContainsKey('Partial')) {
        if ($Partial) {
            $withOptions += "PARTIAL"
        }
    }

    if ($BoundParameters.ContainsKey('Recovery')) {
        if ($Recovery) {
            $withOptions += "RECOVERY"
        } else {
            $withOptions += "NORECOVERY"
        }
    }

    if ($BoundParameters.ContainsKey('Replace')) {
        if ($Replace) {
            $withOptions += "REPLACE"
        }
    }

    if ($BoundParameters.ContainsKey('MoveMapping')) {
        foreach ($key in $MoveMapping.Keys) {
            $withOptions += "MOVE '{0}' TO '{1}'" -f $key, $MoveMapping[$key]
        }
    }

    if ($BoundParameters.ContainsKey('Restart')) {
        if ($Restart) {
            $withOptions += "RESTART"
        }
    }

    if ($BoundParameters.ContainsKey('RestrictedUser')) {
        if ($RestrictedUser) {
            $withOptions += "RESTRICTEDUSER"
        }
    }

    return $withOptions
}

function Get-SqlServerBackupInformation {
    [CmdletBinding(DefaultParameterSetName="All")]
    param (
            [Parameter(Mandatory=$true,
                ValueFromPipelineByPropertyName=$true)]
            [ValidateNotNullOrEmpty()]
            [string]
            $InstanceName,

            [Parameter(Mandatory=$true,
                ValueFromPipelineByPropertyName=$true)]
            [ValidateNotNullOrEmpty()]
            [string]
            $Database,

            [Parameter(Mandatory=$false,
                ParameterSetName="All")]
            [switch]
            $LastBackup = $true,

            [Parameter(Mandatory=$false,
                ParameterSetName="SpecifyKind")]
            [switch]
            $LastFullBackup,

            [Parameter(Mandatory=$false,
                ParameterSetName="SpecifyKind")]
            [switch]
            $LastIncrementalBackup,

            [Parameter(Mandatory=$false,
                ParameterSetName="SpecifyKind")]
            [switch]
            $LastDifferentialBackup
          )

    $query = @"
SELECT
	sdb.Name AS Name, 
	bus.server_name AS ServerName, 
	MAX(bus.backup_finish_date) AS LastBackupTime, 
	CASE bus.type
		WHEN 'D' THEN 'Full'
		WHEN 'I' THEN 'Differential'
		WHEN 'L' THEN 'Log'
		WHEN 'F' THEN 'File/Filegroup'
		WHEN 'G' THEN 'Differential File'
		WHEN 'P' THEN 'Partial'
		WHEN 'Q' THEN 'Differential Partial'
	END AS BackupType
FROM sys.sysdatabases sdb 
LEFT OUTER JOIN msdb.dbo.backupset bus 
	ON bus.database_name = sdb.name 
<WHERECLAUSE>
GROUP BY bus.server_name, sdb.Name, bus.type
ORDER BY Name, LastBackupTime
"@

    if ($LastBackup) {
        $query = $query.Replace("<WHERECLAUSE>", "")
    } else {
        $where = @()
        if ($LastFullBackup) {
            $where += "bus.type = 'D'"
        }
        if ($LastIncrementalBackup) {
            $where += "bus.type = 'L'"
        }
        if ($LastDifferentialBackup) {
            $where += "bus.type = 'I'"
        }
        $whereClause = "WHERE " + ($where -join " OR ")
        Write-Verbose $whereClause
        $query = $query.Replace("<WHERECLAUSE>", $whereClause)
    }
    $conn = Open-SqlConnection -Server $InstanceName
    Send-SqlQuery -SqlConnection $conn -Command $query
}

Export-ModuleMember Backup-Database, Restore-Database, Get-SqlServerBackupInformation
