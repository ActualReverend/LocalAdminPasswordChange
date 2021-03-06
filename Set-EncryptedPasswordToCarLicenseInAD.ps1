####################################################################################
#.Synopsis 
#    Resets the password of a local user account with a random password which is 
#    then encrytped with your pubic key certificate and stored in AD attribute under
#	 the computer object. The plaintext password is 
#    displayed with the  Get-EncryptedPasswordFromCarLicenseInAD.ps1 
#	 script. 
#
#.Description 
#    Resets the password of a local user account with a 16-25 character, random, 
#    complex password, which is encrytped with your own pubic key certificate and then
#	 stored under an Active Directory Attribute for the computer object. 
#    Recovery of the encrypted password from Active Directory requires possession of the
#    private key corresponding to the chosen public key certificate.  The password
#    is never transmitted or stored in plaintext. The plaintext password 
#    is recovered with the companion 
#	 Get-EncryptedPasswordFromCarLicenseInAD.ps1 script.  The
#    script must be run with administrative or local System privileges. 
#	 The Private Key for decryption may be stored in either the Computer's Cert Store or the
#	 User's cert store.
#
#.Parameter CertificateFilePath 
#    The local or UNC path to the .CER file containing the public key 
#    certificate which will be used to encrypt the password.  The .CER
#    file can be DER- or Base64-encoded.  (But note that the private
#    key for the certificate cannot be managed by a Cryptography Next
#    Generation (CNG) key storage provider, hence, do not use the Microsoft 
#    Software Key Storage Provider in the template for the certificate.)
#
#.Parameter LocalUserName
#    Name of the local user account on the computer where this script is run
#    whose password should be reset to a 16-25 character, complex, random password.
#    Do not include a "\" or "@" character, only local accounts are supported.
#    Defaults to "Guest", but any name can be specified.
#
#
#.Parameter MinimumPasswordLength
#    The minimum length of the random password.  Default is 16.  The exact length
#    used is randomly chosen to increase the workload of an attacker who can see
#    the contents of this script.  Maximum password length defaults to 25.  The
#    smallest acceptable minimum length is 4 due to complexity requirements.
#
#.Parameter MaximumPasswordLength
#    The maximum length of the random password.  Default is 16.  Max is 127.
#    The minimum and maximum values can be identical.    
#
#.Example 
#    .\Set-EcryptedPasswordToCarLicenseInAD.ps1 -CertificateFilePath \\server\share\certificate.cer 
#
#    Resets the password of the default account, encrypts that password 
#    with the public key in the certificate.cer file, and saves the encrypted
#    password in the AD attribute "carLicense".  Choose a different account with -LocalUserName.
#
#
#.Example 
#    .\Set-EcryptedPasswordToCarLicenseInAD.ps1 -LocalUserName HelpDeskUser -CertificateFilePath \\server\share\certificate.cer
#
#    The local account's password is reset by default, but any
#    local user name can be specified instead.
#
#
#Requires -Version 2.0 
#
#.Notes 
#  Author: Bryan Loveless bryan.loveless@gmail.com, based upon script by
#			Jason Fossen, Enclave Consulting (http://cyber-defense.sans.org/blog)
#			Password cryptographic method by Bryan Loveless bryan.loveless@gmail.com
# Version: 1.0
# Updated: 17.April.2015
#   LEGAL: PUBLIC DOMAIN.  SCRIPT PROVIDED "AS IS" WITH NO WARRANTIES OR GUARANTEES OF 
#          ANY KIND, INCLUDING BUT NOT LIMITED TO MERCHANTABILITY AND/OR FITNESS FOR
#          A PARTICULAR PURPOSE.  ALL RISKS OF DAMAGE REMAINS WITH THE USER, EVEN IF
#          THE AUTHOR, SUPPLIER OR DISTRIBUTOR HAS BEEN ADVISED OF THE POSSIBILITY OF
#          ANY SUCH DAMAGE.  IF YOUR STATE DOES NOT PERMIT THE COMPLETE LIMITATION OF
#          LIABILITY, THEN DELETE THIS FILE SINCE YOU ARE NOW PROHIBITED TO HAVE IT.
####################################################################################

# Set-EncryptedPasswordToCarLicenseInAD.ps1

Param ($CertificateFilePath = ".\LocalAdminPasswordChangePublicCert.cer", $LocalUserName = "bryan", $MinimumPasswordLength = 16, $MaximumPasswordLength = 25) 



####################################################################################
# Below replaces the generate-randompassword used on a previous version of this script,
#   as the older one used get-random and this new one uses the .net cryptographic provider
#####################################################################################
function Generate-Password() {


param( 
[int] $len = 16,
[string] $chars = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789_!@#$%^&*()_"
)

$result = ""
for( $i=0; $i -lt $len; $i++ )
{
  

$bytes = new-object "System.Byte[]" 1
$rnd = new-object System.Security.Cryptography.RNGCryptoServiceProvider
$rnd.GetBytes($bytes)



    if ($bytes[0] -gt (([int](256/$chars.Length))*$chars.length))
        { 
            $i-- 
            continue
        }

$result += $chars[ $bytes[0] % $chars.Length ]	
}


return $result

  <#
    .SYNOPSIS 
        Returns a secure password, based on the System's Crytpo Service Provider.

    .EXAMPLE
     Generate-Password 
        Returns a  16 character password, using A-Z, numbers, and the "easier to type" special characters

    .EXAMPLE
     Generate-Password -len 48 -chars "0123456789"
        Returns a 48 length numeric password

    .EXAMPLE
    Generate-Password -len 1 -chars "01" 
        Returns a one character password that is either a 0 or a 1"


    .NOTES
        Modified by Bryan Loveless    bryan.loveless@gmail.com Jan 2015
        Based on http://www.peterprovost.org/blog/2007/06/22/Quick-n-Dirty-PowerShell-Password-Generator/
        BUT modified to be a little bit more secure

  #>
}

####################################################################################
# Returns true if password reset accepted, false if there is an error.
# Only works on local computer, but can be modified to work remotely too.
####################################################################################
Function Reset-LocalUserPassword ($UserName, $NewPassword)
{
    Try 
    {
        $ADSI = [ADSI]("WinNT://" + $env:ComputerName + ",computer")
        $User = $ADSI.PSbase.Children.Find($UserName)
        $User.PSbase.Invoke("SetPassword",$NewPassword)
        $User.PSbase.CommitChanges()
        $User = $null 
        $ADSI = $null
        $True
    }
    Catch
    { $False } 
}

####################################################################################
# Writes to console, writes to Application event log, optionally exits.
# Event log: Application, Source: "PasswordArchive", Event ID: 9013
####################################################################################
function Write-StatusLog ( $Message, [Switch] $Exit )
{
    # Define the Source attribute for when this script writes to the Application event log.
    New-EventLog -LogName Application -Source PasswordArchive -ErrorAction SilentlyContinue

    "`n" + $Message + "`n"

#The following here-string is written to the Application log only when there is an error, 
#but it contains information that could be useful to an attacker with access to the log.
#The data is written for troubleshooting purposes, but feel free change it if concerned.
#It does not contain any passwords of course.
$ErrorOnlyLogMessage = @"
$Message 

CurrentPrincipal = $($CurrentPrincipal.Identity.Name)

CertificateFilePath = $CertificateFilePath 

LocalUserName = $LocalUserName

PasswordArchivePath = $PasswordArchivePath

ArchiveFileName = $filename
"@

    if ($Exit)
    { write-eventlog -logname Application -source PasswordArchive -eventID 9013 -message $ErrorOnlyLogMessage -EntryType Error }
    else
    { write-eventlog -logname Application -source PasswordArchive -eventID 9013 -message $Message -EntryType Information }

    if ($Exit) { exit } 
}

####################################################################################
# Writes to AD attribute
# 
####################################################################################
Function SendAttribute-ToAD
{
[CmdletBinding()]
    Param (
        [Parameter(
            Position=1,
            ValueFromPipeline=$true,
            ValueFromPipelineByPropertyName=$true,
            #ValidateNotNullOrEmpty(),
            HelpMessage="What is the field name that you would like to edit?"
            )
         ]
           [string]$PropertyToEdit,
       

        [Parameter(
            Position=2,
            ValueFromPipeline=$true,
            ValueFromPipelineByPropertyName=$true,
            #ValidateNotNullOrEmpty(),
            Mandatory=$true,
            HelpMessage="What do you want the new entry to be?"
            )
         ]
            [string]$EditedInfo
     )    

$ComputerName = $env:computername
$Filter = "(&(objectCategory=Computer)(Name=$ComputerName))"

$DirectorySearcher = New-Object System.DirectoryServices.DirectorySearcher
$DirectorySearcher.Filter = $Filter

$SearcherPath = $DirectorySearcher.FindOne()

#---------------------------------------

$machine = $SearcherPath.GetDirectoryEntry()

write-host "editing property $PropertyToEdit to have $EditedInfo"
#edit the property
#$machine.$PropertyToEdit = $EditedInfo

$machine.InvokeSet(($PropertyToEdit),(($EditedInfo).tostring()))

write-host "committing changes"
#commit the edit on
$machine.CommitChanges()

}

####################################################################################
# Encrypts TXT using public key
# Encrypt-Asymmetric -ClearText "CLEAR TEXT DATA" -PublicCertFilePath "C:\Scripts\PowerShell\Asymmetrical-Encryption\PowerShellAsymmetricalTest.cer" 
####################################################################################
Function Encrypt-Asymmetric {
    [CmdletBinding()]
    [OutputType([System.String])]
    param(
        [Parameter(Position=0, Mandatory=$true)][ValidateNotNullOrEmpty()][System.String]
        $ClearText,
        [Parameter(Position=1, Mandatory=$true)][ValidateNotNullOrEmpty()][ValidateScript({Test-Path $_ -PathType Leaf})][System.String]
        $PublicCertFilePath
    )
    # Encrypts a string with a public key
    $PublicCert = New-Object System.Security.Cryptography.X509Certificates.X509Certificate2($PublicCertFilePath)
    $ByteArray = [System.Text.Encoding]::UTF8.GetBytes($ClearText)
    $EncryptedByteArray = $PublicCert.PublicKey.Key.Encrypt($ByteArray,$true)
    $Base64String = [Convert]::ToBase64String($EncryptedByteArray)
 
    Return $Base64String
	#reference: http://jeffmurr.com/blog/?p=228
}


# Sanity check the two password lengths:
if ($MinimumPasswordLength -le 3) { $MinimumPasswordLength = 4 } 
if ($MaximumPasswordLength -gt 127) { $MaximumPasswordLength = 127 } 
if ($MinimumPasswordLength -gt 127) { $MinimumPasswordLength = 127 } 
if ($MaximumPasswordLength -lt $MinimumPasswordLength) { $MaximumPasswordLength = $MinimumPasswordLength }

# Confirm that this process has administrative privileges to reset a local password.
$CurrentWindowsID = [System.Security.Principal.WindowsIdentity]::GetCurrent()
$CurrentPrincipal = new-object System.Security.Principal.WindowsPrincipal($CurrentWindowsID)
if (-not $? -or -not $CurrentPrincipal.IsInRole("Administrators")) 
   { write-statuslog -m "ERROR: This process lacks the privileges necessary to reset a password." -exit }

# Confirm that the target local account exists and that ADSI is accessible.
if ($LocalUserName -match '[\\@]')  { write-statuslog -m "ERROR: This script can only be used to reset the passwords of LOCAL user accounts, please specify a simple username without an '@' or '\' character in it." -exit }  
try 
{ 
    $ADSI = [ADSI]("WinNT://" + $env:ComputerName + ",computer") 
    $User = $ADSI.PSbase.Children.Find($LocalUserName)
    $User = $null
    $ADSI = $null 
}
catch 
{ write-statuslog -m "ERROR: Local user does not exist: $LocalUserName" -exit } 


# Generate and test new random password with min and max lengths.
$newpassword = "ConfirmThatNewPasswordIsRandom"

if ($MinimumPasswordLength -eq $MaximumPasswordLength)
{  
#    $newpassword = Generate-RandomPassword -Length $MaximumPasswordLength
	$newpassword = Generate-Password -len $MaximumPasswordLength

} 
else
{ 
#    $newpassword = Generate-RandomPassword -Length $(Get-Random -Minimum $MinimumPasswordLength -Maximum $MaximumPasswordLength) 
	$newpassword = Generate-Password -len $(Get-Random -Minimum $MinimumPasswordLength -Maximum $MaximumPasswordLength)

}

# Users outside USA might modify the Generate-RandomPassword function, hence this check.
if ($newpassword -eq "ConfirmThatNewPasswordIsRandom") 
{ write-statuslog -m "ERROR: Password generation failure, password not reset." -exit } 


#encrypt password 
$encryptedPassword = Encrypt-Asymmetric -ClearText "$newpassword" -PublicCertFilePath "$CertificateFilePath"
 
#if ($encryptedPassword -not $?) { write-statuslog -m "ERROR, password was not encrypted, password not reset." -exit } 


# Attempt to reset the password.
if ( Reset-LocalUserPassword -UserName $LocalUserName -NewPassword $newpassword )
{
    remove-variable -name newpassword  #Just tidying up, not really necessary at this point...
    write-statuslog -m "SUCCESS: $LocalUserName password reset."  
}
else
{
    # Write the RESET-FAILURE file to statuslog; these failure files are used by the other scripts too.

    write-statuslog -m "ERROR: Failed to reset password:`n`n $error[0]" -exit 
} 

#now write the encrypted password($content) to the machine's AD attribute($Property)
	$Property = "carLicense"
	SendAttribute-ToAD -PropertyToEdit $Property -EditedInfo $encryptedPassword
#	remove-variable -name encryptedPassword  #Removing Variable, just in case.

# FIN