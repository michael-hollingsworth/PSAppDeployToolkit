#-----------------------------------------------------------------------------
#
# MARK: Register-ADTMsiUnelevatedRepair
#
#-----------------------------------------------------------------------------

function Register-ADTMsiUnelevatedRepair
{
    <#
    .SYNOPSIS
        Enables an MSI to be repaired without UAC elevation.

    .DESCRIPTION
        The `Register-ADTMsiUnelevatedRepair` function adds an MSI's product code to the SecureRepair Windows Installer policy registry key, enabling it to be repaired without UAC elevation.

    .PARAMETER ProductCode
        The product code of the MSI to enable unelevated repairs for.

    .PARAMETER InstalledApplication
        The MSI to enable unelevated repairs for.

    .INPUTS
        PSADT.AppManagement.InstalledApplication

        You can pipe `InstalledApplication` objects to this function.

    .OUTPUTS
        None

        This function does not return any output.

    .EXAMPLE
        Register-ADTMsiUnelevatedRepair -ProductCode '60560121-10dd-40f6-84f8-f8e5f5e7fbd3'

        Configures the MSI with the product code '60560121-10dd-40f6-84f8-f8e5f5e7fbd3' to be repairable without UAC elevation.

    .EXAMPLE
        Get-ADTApplication -Name 'Microsoft Edge' -ApplicationType MSI | Register-ADTMsiUnelevatedRepair

        Configures Microsoft Edge to be repairable without UAC elevation.

    .NOTES
        An active ADT session is NOT required to use this function.

        This function supports the `-WhatIf` and `-Confirm` parameters for testing changes before applying them.

        Tags: psadt<br />
        Website: https://psappdeploytoolkit.com<br />
        Copyright: (C) 2026 PSAppDeployToolkit Team (Sean Lillis, Dan Cunningham, Muhammad Mashwani, Mitch Richters, Dan Gough).<br />
        License: https://opensource.org/license/lgpl-3-0

    .LINK
        https://support.microsoft.com/en-us/help/5067315

    .LINK
        https://psappdeploytoolkit.com/docs/reference/functions/Register-ADTMsiUnelevatedRepair
    #>

    [CmdletBinding(SupportsShouldProcess = $true)]
    param (
        [Parameter(Mandatory = $true, Position = 0, ParameterSetName = 'ProductCode')]
        [ValidateScript({
                if ($null -eq $_)
                {
                    $PSCmdlet.ThrowTerminatingError((New-ADTValidateScriptErrorRecord -ParameterName InstalledApplication -ProvidedValue $_ -ExceptionMessage 'The specified input cannot be null.'))
                }
                if ($_.Equals([System.Guid]::Empty))
                {
                    $PSCmdlet.ThrowTerminatingError((New-ADTValidateScriptErrorRecord -ParameterName InstalledApplication -ProvidedValue $_ -ExceptionMessage 'The specified product code is invalid.'))
                }
                return !!$_
            })]
        [System.Guid]$ProductCode,

        [Parameter(Mandatory = $true, ValueFromPipeline = $true, ParameterSetName = 'InstalledApplication')]
        [ValidateScript({
                if ($null -eq $_)
                {
                    $PSCmdlet.ThrowTerminatingError((New-ADTValidateScriptErrorRecord -ParameterName InstalledApplication -ProvidedValue $_ -ExceptionMessage 'The specified input cannot be null.'))
                }
                if (!$_.WindowsInstaller)
                {
                    $PSCmdlet.ThrowTerminatingError((New-ADTValidateScriptErrorRecord -ParameterName InstalledApplication -ProvidedValue $_ -ExceptionMessage 'The specified application must be a MSI.'))
                }
                if (!$_.ProductCode -or ($_.ProductCode.Equals([System.Guid]::Empty)))
                {
                    $PSCmdlet.ThrowTerminatingError((New-ADTValidateScriptErrorRecord -ParameterName InstalledApplication -ProvidedValue $_ -ExceptionMessage 'The specified application has an invalid product code.'))
                }
                return !!$_
            })]
        [PSADT.AppManagement.InstalledApplication]$InstalledApplication
    )

    begin
    {
        Initialize-ADTFunction -Cmdlet $PSCmdlet -SessionState $ExecutionContext.SessionState
        $windowsInstallerKey = 'Microsoft.PowerShell.Core\Registry::HKEY_LOCAL_MACHINE\SOFTWARE\Policies\Microsoft\Windows\Installer'
        $osInfo = Get-ADTOperatingSystemInfo
        $baseRegPath = if (($osInfo.Version.Build -ge 26100) -and ($osInfo.Version.Revision -ge 8116))
        {
            if ((Test-Path -LiteralPath "$windowsInstallerKey\SecureRepairWhitelist") -and (Get-ItemProperty -LiteralPath "$windowsInstallerKey\SecureRepairWhitelist"))
            {
                if (Test-Path -LiteralPath "$windowsInstallerKey\SecureRepairAllowlist")
                {
                    Write-ADTLogEntry -Message 'Both the [SecureRepairWhitelist] and [SecureRrpairAllowlist] registry keys exist. Only the product codes in the [SecureRepairAllowlist] registry key can be repaired without elevation. For more information, see https://support.microsoft.com/en-us/help/5067315.' -Severity Warning
                    "$windowsInstallerKey\SecureRepairAllowlist"
                }
                else
                {
                    "$windowsInstallerKey\SecureRepairWhitelist"
                }
            }
            else
            {
                "$windowsInstallerKey\SecureRepairAllowlist"
            }
        }
        else
        {
            "$windowsInstallerKey\SecureRepairWhitelist"
        }
    }

    process
    {
        try
        {
            try
            {
                $guid = if ($PSCmdlet.ParameterSetName -eq 'ProductCode')
                {
                    $ProductCode.ToString('B')
                }
                else
                {
                    $InstalledApplication.ProductCode.ToString('B')
                }

                if (Test-ADTRegistryValue -Key $baseRegPath -Name $guid)
                {
                    Write-ADTLogEntry -Message "The product code [$guid] is already registered to the SecureRepair whitelist."
                    return
                }

                if (!$PSCmdlet.ShouldProcess($guid))
                {
                    return
                }

                # Enable the secure repair policy if it isn't already enabled
                if ((Get-ADTRegistryKey -LiteralPath $windowsInstallerKey -Name SecureRepairPolicy -ErrorAction Ignore) -ne 2)
                {
                    Write-ADTLogEntry -Message 'Enabling the Windows Installer [SecureRepairPolicy] policy.'
                    Set-ADTRegistryKey -LiteralPath $windowsInstallerKey -Name SecureRepairPolicy -Type Dword -Value 2
                }

                Set-ADTRegistryKey -LiteralPath $baseRegPath -Name $guid -Type String
            }
            catch
            {
                Write-Error -ErrorRecord $_
            }
        }
        catch
        {
            Invoke-ADTFunctionErrorHandler -Cmdlet $PSCmdlet -SessionState $ExecutionContext.SessionState -ErrorRecord $_
        }
    }

    end
    {
        Complete-ADTFunction -Cmdlet $PSCmdlet
    }
}
