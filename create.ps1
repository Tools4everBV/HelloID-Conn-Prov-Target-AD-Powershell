$c = $configuration | ConvertFrom-Json;
$p = $person | ConvertFrom-Json;
$m = $manager | ConvertFrom-Json;
$success = $False;
$auditLogs = New-Object Collections.Generic.List[PSCustomObject];


# Generate Password
function Get-RandomCharacters($length, $characters) {
    $random = 1..$length | ForEach-Object { Get-Random -Maximum $characters.length }
    $private:ofs=""
    return [String]$characters[$random]
}

function Scramble-String([string]$inputString){     
    $characterArray = $inputString.ToCharArray()   
    $scrambledStringArray = $characterArray | Get-Random -Count $characterArray.Length     
    $outputString = -join $scrambledStringArray
    return $outputString 
}

function GeneratePassword(){
    $password = Get-RandomCharacters -length 4 -characters 'abcdefghiklmnoprstuvwxyz'
    $password += Get-RandomCharacters -length 2 -characters 'ABCDEFGHKLMNOPRSTUVWXYZ'
    $password += Get-RandomCharacters -length 2 -characters '1234567890'
    $password += Get-RandomCharacters -length 2 -characters '!%&/()=?}][{@#*+'

    $password = Scramble-String $password

    return $password
}

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
    Company = "HHNK";
    EmployeeId = $p.ExternalId;
    DisplayName = "PA" + $displayname 
    Surname = $surname
    SamAccountName = "pa" + $p.Accounts.MicrosoftActiveDirectoryCorp.SamAccountName;
    UserPrincipalName = "pa" + $Upn;
    #EmailAddress = $p.Accounts.MicrosoftActiveDirectoryCorp.UserPrincipalName;
    Name = $p.Accounts.MicrosoftActiveDirectoryCorp.CommonName;
    Path = $c.createOU;
    Password = GeneratePassword;
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

        $create = $True

        $ADUser = Get-ADUser -Filter "EmployeeId -eq $($p.ExternalId)"
        if(($ADUser | Measure-Object).Count -ne 0) {
            Write-Verbose -Verbose "Found existing AD user $($ADUser.samaccountname)"
            
            $account.SamAccountName = $ADUser.samaccountname 
            $create = $False
            $success = $True
            $auditMessage = "Correlation found for $($p.ExternalId)."
        }
        else{
            Write-Verbose -Verbose "No existing user found"
        }

        if($create){ 
            Write-Verbose -Verbose "Creating AD User"

            $account | New-ADUser -AccountPassword (ConvertTo-SecureString "$($account.Password)" -AsPlainText -force)
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
    # Action = "CreateAccount"; Optionally specify a different action for this audit log
    Message = "Created account with username $($account.userName)";
    IsError = $False;
});

# Send results
$result = [PSCustomObject]@{
	Success= $success;
	AccountReference= $account.SamAccountName;
	AuditLogs = $auditLogs;
    Account = $account;

    # Optionally return data for use in other systems
    ExportData = [PSCustomObject]@{
        SamAccountName = $account.SamAccountName;
        UserPrincipalName = $account.UserPrincipalName;
    };
};
Write-Output $result | ConvertTo-Json -Depth 10;
