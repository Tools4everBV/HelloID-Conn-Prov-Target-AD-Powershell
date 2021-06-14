$c = $configuration | ConvertFrom-Json;
$p = $person | ConvertFrom-Json;
$m = $manager | ConvertFrom-Json;
$aRef = $accountReference | ConvertFrom-Json;
$mRef = $managerAccountReference | ConvertFrom-Json;
$success = $False;
$auditLogs = New-Object Collections.Generic.List[PSCustomObject];


$familyNamePrefix = ""
$familyNamePrefixDisplayName = ""
if(!([string]::IsNullOrEmpty($p.Name.familyNamePrefix)))
{
    $familyNamePrefix = $p.Name.familyNamePrefix + " "
    $familyNamePrefixDisplayName = " " + $p.Name.familyNamePrefix
}

$familyNamePartnerPrefix = ""
$familyNamePartnerPrefixDisplayName = ""
if(!([string]::IsNullOrEmpty($p.Name.familyNamePartnerPrefix)))
{
    $familyNamePartnerPrefix = $p.Name.familyNamePartnerPrefix + " "
    $familyNamePartnerPrefixDisplayName = " " + $p.Name.familyNamePartnerPrefix
}

switch($p.Name.Convention)
{
    "B" {$displayname = $p.Name.FamilyName + ", " + $p.Name.NickName + $familyNamePrefixDisplayName}
    "P" {$displayname = $p.Name.FamilyNamePartner + ", " + $p.Name.NickName + $familyNamePartnerPrefixDisplayName}
    "BP" {$displayname = $p.Name.FamilyName + " - "+ $familyNamePartnerPrefix + $p.Name.FamilyNamePartner + ", " + $p.Name.NickName + $familyNamePrefixDisplayName}
    "PB" {$displayname = $p.Name.FamilyNamePartner + " - " + $familyNamePrefix + $p.Name.FamilyName + ", " + $p.Name.NickName + $familyNamePartnerPrefixDisplayName}
    default {$displayname = $p.Name.FamilyName + ", " + $p.Name.NickName + $familyNamePrefixDisplayName}
}

switch($p.Name.Convention)
{
    "B" {$surname = $familyNamePrefix + $p.Name.FamilyName}
    "P" {$surname = $familyNamePartnerPrefix + $p.Name.FamilyNamePartner}
    "BP" {$surname = $familyNamePrefix + $p.Name.FamilyName + " - "+ $familyNamePartnerPrefix + $p.Name.FamilyNamePartner}
    "PB" {$surname = $familyNamePartnerPrefix + $p.Name.FamilyNamePartner + " - " + $familyNamePrefix + $p.Name.FamilyName}
    default {$surname = $familyNamePrefix + $p.Name.FamilyName}
}

$domainNameSuffix = "@"+$c.domainName;

$UpnPrefix,$UpnDomainCorp = $p.Accounts.MicrosoftActiveDirectoryCorp.UserPrincipalName -split '@',2

$Upn = $UpnPrefix + $domainNameSuffix

# Change mapping here
$account = [PSCustomObject]@{
    GivenName = $p.Name.NickName;
    Initials = ($p.Name.Initials -replace "\.", "").substring(0, [System.Math]::Min(6, $p.Name.Initials.Length));
    Office = $p.PrimaryContract.Custom.Afdeling;
    Title = $p.PrimaryContract.Custom.VisitekaartNaam;
    Department = $p.PrimaryContract.Department.DisplayName;
    EmployeeId = $p.ExternalId;
    DisplayName = "PA" + $displayname 
    Surname = $surname
    #EmailAddress = $p.Accounts.MicrosoftActiveDirectoryCorp.UserPrincipalName;
    Name = $p.Accounts.MicrosoftActiveDirectoryCorp.CommonName;
    UserPrincipalName = "pa" + $Upn;
};

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
            Write-Verbose -Verbose "Updating AD user $($ADUser.samaccountname)"
            Set-ADUser -Identity $ADUser.ObjectGuid -GivenName $account.GivenName -Initials $account.Initials -Office $account.Office -Title $account.Title -Department  $account.Department -EmployeeId  $account.EmployeeId -DisplayName $account.DisplayName -Surname $account.Surname -EmailAddress $account.EmailAddress
            
            Write-Verbose -Verbose "Renaming AD user $($ADUser.samaccountname)"
            Rename-ADObject -Identity $ADUser.ObjectGuid -NewName $account.Name
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
    # Action = "EnableAccount"; Optionally specify a different action for this audit log
    Message = "Account $($aRef) enabled";
    IsError = $False;
});

# Send results
$result = [PSCustomObject]@{
	Success= $success;
	AuditLogs = $auditLogs;
    Account = $account;
};
Write-Output $result | ConvertTo-Json -Depth 10;
