#Powershell script which runs vRops report via the suite-api and downloads them locally
#v1.0 vMan.ch, 21.06.2016 - Initial Version
#v1.1 vMan.ch, 20.02.2021 - Updated to support Token based Auth and script can be run with params now.
<#

    The following command must be run once to generate the Credential file to connect to each environment.

        Run once for per virtual center 
        
        $cred = Get-Credential
        $cred | Export-Clixml -Path "G:\D-DRIVE\vRops\Config\vrops.xml"
		
		.\vROpsReportRunner.ps1 -vRopsAddress vRops.vman.ch -cred 'vrops' -vCenter 'bff52171-f5fb-4850-9ddb-92a46427773b' -Report '90f80540-c8af-497f-abbb-8174099e1af3' -format 'csv' -filename 'MySuperDupervRopsReport'

#>

param
(
    [String]$vRopsAddress,
    [String]$Creds,
    [String]$vCenter,
    [String]$Report,
    [String]$Format,
    [String]$FileName
)


#vars
$ScriptPath = (Get-Item -Path ".\" -Verbose).FullName


#Get Stored Credentials
if($creds -gt ""){

    $cred = Import-Clixml -Path "$ScriptPath\config\$creds.xml"

    }
    else
    {
    echo "Environment not selected, stop hammer time!"
    Exit
    }

## Function

Function New-vRopsToken {
    [CmdletBinding()]param(
        [PSCredential]$credentialFile,
        [string]$vROPSServer
    )
    
    if ($vROPSServer -eq $null -or $vROPSServer -eq '') {
        $vROPSServer = ""
    }

    $vROPSUser = $credentialFile.UserName
    $vROPSPassword = $credentialFile.GetNetworkCredential().Password

    if ("TrustAllCertsPolicy" -as [type]) {} else {
    add-type @"
        using System.Net;
        using System.Security.Cryptography.X509Certificates;
        public class TrustAllCertsPolicy : ICertificatePolicy {
            public bool CheckValidationResult(
                ServicePoint srvPoint, X509Certificate certificate,
                WebRequest request, int certificateProblem) {
                return true;
            }
        }
"@ 
[System.Net.ServicePointManager]::CertificatePolicy = New-Object TrustAllCertsPolicy
    }

    $BaseURL = "https://" + $vROPsServer + "/suite-api/api/"
    $BaseAuthURL = "https://" + $vROPsServer + "/suite-api/api/auth/token/acquire"
    $Type = "application/json"

    $AuthJSON =
    "{
      ""username"": ""$vROPSUser"",
      ""password"": ""$vROPsPassword""
    }"

    Try { $vROPSSessionResponse = Invoke-RestMethod -Method POST -Uri $BaseAuthURL -Body $AuthJSON -ContentType $Type }
    Catch {
        $_.Exception.ToString()
        $error[0] | Format-List -Force
    }

    $vROPSSessionHeader = @{"Authorization"="vRealizeOpsToken "+$vROPSSessionResponse.'auth-token'.token 
    "Accept"="application/xml"}
    $vROPSSessionHeader.add("X-vRealizeOps-API-use-unsupported","true")
    return $vROPSSessionHeader
}

Function GetReport([String]$vRopsAddress, [String]$vCenter, [String]$Report, $Creds, [String]$Path, [String]$File, [String]$format){

Write-host "Running Report"


#RUN Report

$ContentType = "application/xml;charset=utf-8"

$RunReporturl = 'https://'+$vRopsAddress+'/suite-api/api/reports'

$Body = @"
<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<ops:report xmlns:xs="http://www.w3.org/2001/XMLSchema" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" xmlns:ops="http://webservice.vmware.com/vRealizeOpsMgr/1.0/">
    <ops:resourceId>$vCenter</ops:resourceId>
    <ops:reportDefinitionId>$Report</ops:reportDefinitionId>
    <ops:traversalSpec adapterInstanceAssociation="false">
        <ops:name>vSphere Hosts and Clusters</ops:name>
        <ops:rootAdapterKindKey>VMWARE</ops:rootAdapterKindKey>
        <ops:rootResourceKindKey>vSphere World</ops:rootResourceKindKey>
    </ops:traversalSpec>
</ops:report>
"@

$vRopsAdminToken = New-vRopsToken $cred $vRopsAddress



[xml]$Data = Invoke-RestMethod -Method POST -uri $RunReporturl -ContentType $ContentType -Headers $vRopsAdminToken -Body $body

$ReportLink = $Data.report.links.link | where 'rel' -eq "SELF" | select href

$ReportLinkurl = 'https://' + $vRopsAddress + ($ReportLink).href

#Check if report is run to download

[xml]$ReportStatus = Invoke-RestMethod -Method GET -uri $ReportLinkurl -ContentType $ContentType -Headers $vRopsAdminToken


While ($ReportStatus.report.status -ne "COMPLETED") {
    [xml]$ReportStatus = Invoke-RestMethod -Method GET -uri $ReportLinkurl -Credential $vRopsCreds -ContentType $ContentType -Headers $vRopsAdminToken
    Write-host 'Waiting for' $Env 'report to finish running, current status: '  $ReportStatus.report.status
    Sleep 3
      } # End of block statement


$ReportDownload = $ReportLinkurl + '/download?format='+ $Format


$ReportOutputfile = "$Path\reports\$File.$format"

Invoke-RestMethod -Method GET -uri $ReportDownload -Credential $vRopsCreds -ContentType $ContentType -Headers $vRopsAdminToken -OutFile $ReportOutputfile

Write-host "Report finished"

return $ReportOutputfile
}


$Report = GetReport $vRopsAddress $vCenter $Report $Cred $ScriptPath $FileName $Format

Remove-Variable *  -Force -ErrorAction SilentlyContinue
