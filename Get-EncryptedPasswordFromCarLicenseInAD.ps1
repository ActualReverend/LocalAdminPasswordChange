####################################################################################
#.Synopsis 
#	Retrieve attribute from AD using powershell
#
#.Description 
# 	Retrieve attribute from AD using powershell
#
#
#.Parameter ComputerNames
#   One or more computer names that you are requesting the password for.
#
#.Example 
#	./Get-EncryptedPasswordFromCarLicenseInAD.ps1 -computer 1windows7
#	This will return the password for the listed machine.
#
#.Example 
#	./Get-EncryptedPasswordFromCarLicenseInAD.ps1 -computernames windows7,win8-1
#	This will return the passwords for both machines listed
#
#
#Requires -Version 3.0 
#
#.Notes 
#  Author: Bryan Loveless bryan.loveless@gmail.com, based upon script by
#	
# Version: 1.0
# Updated: 17.April.2015
#   LEGAL: PUBLIC DOMAIN.  SCRIPT PROVIDED "AS IS" WITH NO WARRANTIES OR GUARANTEES OF 
#          ANY KIND, INCLUDING BUT NOT LIMITED TO MERCHANTABILITY AND/OR FITNESS FOR
#          A PARTICULAR PURPOSE.  ALL RISKS OF DAMAGE REMAINS WITH THE USER, EVEN IF
#          THE AUTHOR, SUPPLIER OR DISTRIBUTOR HAS BEEN ADVISED OF THE POSSIBILITY OF
#          ANY SUCH DAMAGE.  IF YOUR STATE DOES NOT PERMIT THE COMPLETE LIMITATION OF
#          LIABILITY, THEN DELETE THIS FILE SINCE YOU ARE NOW PROHIBITED TO HAVE IT.
####################################################################################

# Get-EncryptedPasswordFromCarLicenseInAD.ps1


[CmdletBinding()]
Param (  
        [Parameter(
            Position=0,
            ValueFromPipeline=$true,
            ValueFromPipelineByPropertyName=$True,
			Mandatory=$false,
            HelpMessage="What is/are the computer names?"
            )
         ]
           [string[]]$ComputerNames = ("windows7","win8-1") #change back to "$env:computername" after dev
     )    

####################################################################################
# Decrypts TXT using public key
# Decrypt-Asymmetric -EncryptedBase64String $Base64String -CertThumbprint "‎661730b2a7eca2c1f54a264aa54da190adc1f5b0" 
####################################################################################
Function Decrypt-Asymmetric
{
    [CmdletBinding()]
    [OutputType([System.String])]
    param(
        [Parameter(Position=0, Mandatory=$true)][ValidateNotNullOrEmpty()][System.String]
        $EncryptedBase64String,
        [Parameter(Position=1, Mandatory=$true)][ValidateNotNullOrEmpty()][System.String]
        $CertThumbprint
    )
    # Decrypts cipher text using the private key
    # Assumes the certificate is in the LocalMachine\My (Personal) Store
    
	#below looks in local computer store for cert
	#$Cert = Get-ChildItem cert:\LocalMachine\My | where { $_.Thumbprint -eq $CertThumbprint }
	
	# below looks in current user store for cert
	#$Cert = Get-ChildItem cert:\CurrentUser\my  | where { $_.Thumbprint -eq $CertThumbprint }
	
	# below looks in the current user's certificates and private keys AND CHECKS THEM.
		# reference: Jason Fossen, Enclave Consulting (http://cyber-defense.sans.org/blog
	try
	{
	    $readonlyflag = [System.Security.Cryptography.X509Certificates.OpenFlags]::ReadOnly
	    $currentuser =  [System.Security.Cryptography.X509Certificates.StoreLocation]::CurrentUser
	    $usercertstore = New-Object -TypeName System.Security.Cryptography.X509Certificates.X509Store -ArgumentList $currentuser
	    $usercertstore.Open($readonlyflag) 
	    $usercertificates = $usercertstore.Certificates
	}
	catch
	{
	    "`nERROR: Could not open your certificates store. `n"
	    exit
	}
	finally
	{
	    $usercertstore.Close() 
	}

	if ($usercertificates.count -eq 0) { "`nERROR: You have no certificates or private keys.`n" ; exit }
		
# Load the correct certificate and test for possession of private key.
    $cert = $usercertificates | where { $_.thumbprint -eq $CertThumbprint } 
    if (-not $cert.hasprivatekey) 
    { 
        $output.StatusMessage = "ERROR: You do not have the private key for this certificate."
        $output.Valid = $false
        $output
        continue
    }
	
    if($Cert) {
        $EncryptedByteArray = [Convert]::FromBase64String($EncryptedBase64String)
        $ClearText = [System.Text.Encoding]::UTF8.GetString($Cert.PrivateKey.Decrypt($EncryptedByteArray,$true))
    }
    Else {Write-Error "Certificate with thumbprint: $CertThumbprint not found!"}
 
    Return $ClearText
		#reference: http://jeffmurr.com/blog/?p=228
}

#Create the array to store all decrypted passwords
$AllPasswords = @()

ForEach ($ComputerName in $ComputerNames){
# retrieve where the machine lives in AD 
	$Filter = "(&(objectCategory=Computer)(Name=$ComputerName))"
	$DirectorySearcher = New-Object System.DirectoryServices.DirectorySearcher
	$DirectorySearcher.Filter = $Filter
	$SearcherPath = $DirectorySearcher.FindOne()
	$machine = $SearcherPath.GetDirectoryEntry()

#get the "carLicense" attribute from AD
	$carLicenseAttribute = ($machine.carLicense)
 
# get thumbprint of the certificate, create object for it, then set thumbprint for comparison
	$output = ($output = " " | select-object Valid,StatusMessage,Password,Thumbprint)
    $output.Valid =        $false  #Assume password recovery will fail.
	#‎ 661730b2a7eca2c1f54a264aa54da190adc1f5b0 is thumbprint of LocalAdminPasswordChange cert issued 4/9/2015
	$output.Thumbprint = "‎661730B2A7ECA2C1F54A264AA54DA190ADC1F5B0"

# Load the current user's certificates and private keys.
	try
	{
	    $readonlyflag = [System.Security.Cryptography.X509Certificates.OpenFlags]::ReadOnly
	    $currentuser =  [System.Security.Cryptography.X509Certificates.StoreLocation]::CurrentUser
	    $usercertstore = New-Object -TypeName System.Security.Cryptography.X509Certificates.X509Store -ArgumentList $currentuser
	    $usercertstore.Open($readonlyflag) 
	    $usercertificates = $usercertstore.Certificates
	}
	catch
	{
	    "`nERROR: Could not open your certificates store. `n"
	    exit
	}
	finally
	{
	    $usercertstore.Close() 
	}

	if ($usercertificates.count -eq 0) { "`nERROR: You have no certificates or private keys.`n" ; exit }
		
# Load the correct certificate and test for possession of private key.
    $thecert = $usercertificates | where { $_.thumbprint -eq $output.thumbprint } 
    if (-not $thecert.hasprivatekey) 
    { 
        $output.StatusMessage = "ERROR: You do not have the private key for this certificate."
        $output.Valid = $false
        $output
        continue
    } 
    

# Test to confirm that the private key can be accessed, not just that it exists.  The
# problem is that it is not a trivial task to allow .NET or PowerShell to use
# private keys managed by Crytography Next Generation (CNG) key storage providers, hence,
# these scripts are only compatible with the older Cryptographic Service Providers (CSPs), such
# as the "Microsoft Enhanced Cryptographic Provider", but not the newer CNG "Microsoft
# Software Key Storage Provider".  Sorry...
    if ($thecert.privatekey -eq $null) 
    { 
        $output.StatusMessage = "ERROR: This script is not compatible with CNG key storage providers."
        $output.Valid = $false
        $output
        continue
    } 

#Decrypt password using private key and return
$decryptedPassword = Decrypt-Asymmetric -EncryptedBase64String $carLicenseAttribute.ToString() -CertThumbprint $output.Thumbprint
Write-Host $computername"'s" "password is" $decryptedPassword

$AllPasswords= $allpasswords + ($decryptedPassword)

Remove-Variable decryptedPassword
}

#returns all of the passwords in the array together, in case script was called expecting returns
Write-Host "Here are all of the passwords you requested:"
Return $AllPasswords
Remove-Variable AllPasswords

# FIN