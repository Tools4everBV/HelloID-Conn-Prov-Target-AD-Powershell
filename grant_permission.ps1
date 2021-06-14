$c = $configuration | ConvertFrom-Json;
$success = $False;
$auditLogs = New-Object Collections.Generic.List[PSCustomObject];

$p = $person | ConvertFrom-Json;
$m = $manager | ConvertFrom-Json;
$aRef = $accountReference | ConvertFrom-Json;
$mRef = $managerAccountReference | ConvertFrom-Json;

# The permissionReference object contains the Identification object provided in the retrieve permissions call
$pRef = $permissionReference | ConvertFrom-json;

if(-Not($dryRun -eq $True)) {
    try{
        [string]$userName = $c.connection.username
        [string]$userPassword = $c.connection.userpwd
        [securestring]$secStringPassword = ConvertTo-SecureString $userPassword -AsPlainText -Force
        [pscredential]$credObject = New-Object System.Management.Automation.PSCredential ($userName, $secStringPassword)

        Write-Verbose -Verbose "Creating session to $($c.connection.serverfqdn)"

        $sessionOption = New-PSSessionOption -SkipCACheck -SkipCNCheck -SkipRevocationCheck
        $session = New-PSSession  -ComputerName $c.connection.serverfqdn -Credential $credObject -UseSSL -SessionOption $sessionOption
        Import-PSSession -Session $session -module ActiveDirectory -AllowClobber | Out-Null

        Write-Verbose -Verbose "Successfully created session to $($c.connection.serverfqdn)"

        $ADUser = Get-ADUser -Identity $aRef
        if(($ADUser | Measure-Object).Count -ne 0) {
            Write-Verbose -Verbose "Found existing AD user $($ADUser.samaccountname)"
            
            Write-Verbose -Verbose "Adding user $aRef to group $($pRef.Id)"
            Add-ADGroupMember -Identity $pRef.Id -Members $aRef
            
            
            $success = $True
        }
        else{
            $success = $False
            Write-Error "No existing user found"
        }
    }
    catch {
        Write-Error $_
    }
    finally {
        $session | Remove-PSSession
    }
}
$success = $True;
$auditLogs.Add([PSCustomObject]@{
    # Action = "GrantMembership"; Optionally specify a different action for this audit log
    Message = "Permission to $($pRef.Id) added to account $($aRef)";
    IsError = $False;
});

# Send results
$result = [PSCustomObject]@{
    Success= $success;
    AuditLogs = $auditLogs;
    Account = [PSCustomObject]@{};
};
Write-Output $result | ConvertTo-Json -Depth 10;
