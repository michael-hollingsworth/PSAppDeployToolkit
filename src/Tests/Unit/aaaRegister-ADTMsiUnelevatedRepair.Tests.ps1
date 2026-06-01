BeforeAll {
    Remove-Module PSAppDeployToolkit -Force -ErrorAction SilentlyContinue
    Import-Module "$PSScriptRoot\..\..\PSAppDeployToolkit\PSAppDeployToolkit.psd1" -Force
}
Describe 'Register-ADTMsiUnelevatedRepair' {
    BeforeAll {
        # Mock Convert-ADTRegistryPath to redirect registry paths to TestRegistry:\
        Mock -ModuleName PSAppDeployToolkit Convert-ADTRegistryPath {
            $output = & (Get-Command -Source PSAppDeployToolkit -CommandType Function -Name 'Convert-ADTRegistryPath') @PesterBoundParameters
            $testRegistryRoot = (Get-PSDrive -Name TestRegistry).Root
            $mockedOutput = $output -replace '^Microsoft\.PowerShell\.Core\\Registry::', "Microsoft.PowerShell.Core\Registry::$testRegistryRoot\"
            return $mockedOutput
        }
        <# Mock Convert-ADTRegistryPath {
            $output = & (Get-Command -Source PSAppDeployToolkit -CommandType Function -Name 'Convert-ADTRegistryPath') @PesterBoundParameters
            $testRegistryRoot = (Get-PSDrive -Name TestRegistry).Root
            $mockedOutput = $output -replace '^Microsoft\.PowerShell\.Core\\Registry::', "Microsoft.PowerShell.Core\Registry::$testRegistryRoot\"
            return $mockedOutput
        } #>

        $testRegistryRoot = (Get-PSDrive -Name TestRegistry).Root
        [System.Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseDeclaredVarsMoreThanAssignments', 'RedirectedWindowsInstallerKey', Justification = 'This variable is used within script blocks that PSScriptAnalyzer has no visibility of.')]
        $RedirectedWindowsInstallerKey = "Microsoft.PowerShell.Core\Registry::$testRegistryRoot\HKEY_LOCAL_MACHINE\SOFTWARE\Policies\Microsoft\Windows\Installer"

        function New-ADTApplication
        {
            param
            (
                [Parameter(Mandatory = $false)]
                [AllowNull()]
                [System.Guid]$ProductCode,

                [Parameter(Mandatory = $false)]
                [System.Management.Automation.SwitchParameter]$WindowsInstaller
            )

            [PSADT.AppManagement.InstalledApplication]::new(
                'test',
                'test',
                'test',
                $ProductCode,
                'test',
                [System.Management.Automation.Language.NullString]::Value,
                [System.Management.Automation.Language.NullString]::Value,
                [System.Management.Automation.Language.NullString]::Value,
                $null,
                $null,
                $null,
                [System.Management.Automation.Language.NullString]::Value,
                $null,
                $null,
                $false,
                $WindowsInstaller,
                $null
            )
        }

        # Mock Write-ADTLogEntry due to its expense when running via Pester.
        Mock -ModuleName PSAppDeployToolkit Write-ADTLogEntry { }
    }

    Context 'Funcionality' {
        It "Should enable the SecureRepair policy if it isn't already enabled" {
            # Cleanup the environment for the test
            if (Test-Path -LiteralPath $RedirectedWindowsInstallerKey)
            {
                Remove-Item -LiteralPath $RedirectedWindowsInstallerKey -Recurse -Force
            }

            $guid = [System.Guid]::NewGuid()
            Register-ADTMsiUnelevatedRepair -ProductCode $guid

            $RedirectedWindowsInstallerKey | Should -Exist
            Get-ItemPropertyValue -LiteralPath $RedirectedWindowsInstallerKey -Name SecureRepairPolicy | Should -Be 2

            # Run the test again but set the SecureRepairPolicy to a different value
            Set-ItemProperty -LiteralPath $RedirectedWindowsInstallerKey -Name SecureRepairPolicy -Type DWord -Value 1
            <# Write-Warning (Convert-ADTRegistryPath -Key 'Microsoft.PowerShell.Core\Registry::HKEY_LOCAL_MACHINE\SOFTWARE\Policies\Microsoft\Windows\Installer')
            Write-Warning $RedirectedWindowsInstallerKey
            $provider = $null
            Write-Warning ($ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($RedirectedWindowsInstallerKey, [ref]$provider, [ref]$null))
            Write-Warning $provider.Name
            Write-Warning $provider.ModuleName #>
            Register-ADTMsiUnelevatedRepair -ProductCode $guid
            Get-ItemPropertyValue -LiteralPath $RedirectedWindowsInstallerKey -Name SecureRepairPolicy | Should -Be 2
        }
        It 'Should register product codes to the SecureRepairWhitelist registry key on versions of Windows 11 24H2 older than build 8116' {
            # Cleanup the environment for the test
            if (Test-Path -LiteralPath $RedirectedWindowsInstallerKey)
            {
                Remove-Item -LiteralPath $RedirectedWindowsInstallerKey -Recurse -Force
            }

            # Mock Get-ADTOperatingSystemInfo to return a lower version
            Mock -ModuleName PSAppDeployToolkit Get-ADTOperatingSystemInfo { return @{ Version = [System.Version]::new(10, 0, 26100, 8115) } }

            $guid = [System.Guid]::NewGuid()
            Register-ADTMsiUnelevatedRepair -ProductCode $guid

            "$RedirectedWindowsInstallerKey\SecureRepairWhitelist" | Should -Exist
            $key = Get-Item -LiteralPath "$RedirectedWindowsInstallerKey\SecureRepairWhitelist"
            try
            {
                $key.GetValueNames() | Should -Contain $guid.ToString('B')
                $key.GetValueKind($guid.ToString('B')) | Should -Be ([Microsoft.Win32.RegistryValueKind]::String)
            }
            finally
            {
                $key.Dispose()
            }
        }
        It 'Should register product codes to the SecureRepairWhitelist registry key on versions of Windows 11 25H2 older than build 8116' {
            # Cleanup the environment for the test
            if (Test-Path -LiteralPath $RedirectedWindowsInstallerKey)
            {
                Remove-Item -LiteralPath $RedirectedWindowsInstallerKey -Recurse -Force
            }

            # Mock Get-ADTOperatingSystemInfo to return a lower version
            Mock -ModuleName PSAppDeployToolkit Get-ADTOperatingSystemInfo { return @{ Version = [System.Version]::new(10, 0, 26100, 8115) } }

            $guid = [System.Guid]::NewGuid()
            Register-ADTMsiUnelevatedRepair -ProductCode $guid

            "$RedirectedWindowsInstallerKey\SecureRepairWhitelist" | Should -Exist
            $key = Get-Item -LiteralPath "$RedirectedWindowsInstallerKey\SecureRepairWhitelist"
            try
            {
                $key.GetValueNames() | Should -Contain $guid.ToString('B')
                $key.GetValueKind($guid.ToString('B')) | Should -Be ([Microsoft.Win32.RegistryValueKind]::String)
            }
            finally
            {
                $key.Dispose()
            }
        }
        It 'Should register product codes to the SecureRepairAllowlist registry key on Windows 11 26100.8116 or newer' {
            # Cleanup the environment for the test
            if (Test-Path -LiteralPath $RedirectedWindowsInstallerKey)
            {
                Remove-Item -LiteralPath $RedirectedWindowsInstallerKey -Recurse -Force
            }

            # Mock Get-ADTOperatingSystemInfo to return a higher version
            Mock -ModuleName PSAppDeployToolkit Get-ADTOperatingSystemInfo { return @{ Version = [System.Version]::new(10, 0, 26100, 8116) } }

            $guid = [System.Guid]::NewGuid()
            Register-ADTMsiUnelevatedRepair -ProductCode $guid

            "$RedirectedWindowsInstallerKey\SecureRepairAllowlist" | Should -Exist
            $key = Get-Item -LiteralPath "$RedirectedWindowsInstallerKey\SecureRepairAllowlist"
            try
            {
                $key.GetValueNames() | Should -Contain $guid.ToString('B')
                $key.GetValueKind($guid.ToString('B')) | Should -Be ([Microsoft.Win32.RegistryValueKind]::String)
            }
            finally
            {
                $key.Dispose()
            }
        }
        It 'Should register product codes to the SecureRepairAllowlist registry key on Windows 11 26200.8116 or newer' {
            # Cleanup the environment for the test
            if (Test-Path -LiteralPath $RedirectedWindowsInstallerKey)
            {
                Remove-Item -LiteralPath $RedirectedWindowsInstallerKey -Recurse -Force
            }

            # Mock Get-ADTOperatingSystemInfo to return a higher version
            Mock -ModuleName PSAppDeployToolkit Get-ADTOperatingSystemInfo { return @{ Version = [System.Version]::new(10, 0, 26200, 8116) } }

            $guid = [System.Guid]::NewGuid()
            Register-ADTMsiUnelevatedRepair -ProductCode $guid

            "$RedirectedWindowsInstallerKey\SecureRepairAllowlist" | Should -Exist
            $key = Get-Item -LiteralPath "$RedirectedWindowsInstallerKey\SecureRepairAllowlist"
            try
            {
                $key.GetValueNames() | Should -Contain $guid.ToString('B')
                $key.GetValueKind($guid.ToString('B')) | Should -Be ([Microsoft.Win32.RegistryValueKind]::String)
            }
            finally
            {
                $key.Dispose()
            }
        }
        It "Should register product codes to the SecureRepairWhitelist registry key on Windows 11 26200.8116 or newer when the SecureRepairWhitelist registry key already exists and the SecureRepairAllowList key doesn't" {
            # Cleanup the environment for the test
            if (Test-Path -LiteralPath $RedirectedWindowsInstallerKey)
            {
                Remove-Item -LiteralPath $RedirectedWindowsInstallerKey -Recurse -Force
            }

            $null = New-Item -Path "$RedirectedWindowsInstallerKey\SecureRepairWhitelist" -ItemType Container
            $null = New-ItemProperty -LiteralPath "$RedirectedWindowsInstallerKey\SecureRepairWhitelist" -Name ([System.Guid]::NewGuid().ToString('B')) -PropertyType String

            # Mock Get-ADTOperatingSystemInfo to return a higher version
            Mock -ModuleName PSAppDeployToolkit Get-ADTOperatingSystemInfo { return @{ Version = [System.Version]::new(10, 0, 26200, 8116) } }

            $guid = [System.Guid]::NewGuid()
            Register-ADTMsiUnelevatedRepair -ProductCode $guid

            "$RedirectedWindowsInstallerKey\SecureRepairWhitelist" | Should -Exist
            $key = Get-Item -LiteralPath "$RedirectedWindowsInstallerKey\SecureRepairWhitelist"
            try
            {
                $key.GetValueNames() | Should -Contain $guid.ToString('B')
                $key.GetValueKind($guid.ToString('B')) | Should -Be ([Microsoft.Win32.RegistryValueKind]::String)
            }
            finally
            {
                $key.Dispose()
            }
        }
        It 'Should register product codes to the SecureRepairAllowList registry key on Windows 11 26100.8116 or newer when both the SecureRepairWhitelist and SecureRepairAllowList registry keys exist' {
            # Cleanup the environment for the test
            if (Test-Path -LiteralPath $RedirectedWindowsInstallerKey)
            {
                Remove-Item -LiteralPath $RedirectedWindowsInstallerKey -Recurse -Force
            }

            $null = New-Item -Path "$RedirectedWindowsInstallerKey\SecureRepairWhitelist" -ItemType Container
            $null = New-ItemProperty -LiteralPath "$RedirectedWindowsInstallerKey\SecureRepairWhitelist" -Name ([System.Guid]::NewGuid().ToString('B')) -PropertyType String
            $null = New-Item -Path "$RedirectedWindowsInstallerKey\SecureRepairAllowlist" -ItemType Container
            $null = New-ItemProperty -LiteralPath "$RedirectedWindowsInstallerKey\SecureRepairAllowlist" -Name ([System.Guid]::NewGuid().ToString('B')) -PropertyType String

            # Mock Get-ADTOperatingSystemInfo to return a higher version
            Mock -ModuleName PSAppDeployToolkit Get-ADTOperatingSystemInfo { return @{ Version = [System.Version]::new(10, 0, 26100, 8116) } }

            $guid = [System.Guid]::NewGuid()
            Register-ADTMsiUnelevatedRepair -ProductCode $guid

            "$RedirectedWindowsInstallerKey\SecureRepairAllowlist" | Should -Exist
            $key = Get-Item -LiteralPath "$RedirectedWindowsInstallerKey\SecureRepairAllowlist"
            try
            {
                $key.GetValueNames() | Should -Contain $guid.ToString('B')
                $key.GetValueKind($guid.ToString('B')) | Should -Be ([Microsoft.Win32.RegistryValueKind]::String)
            }
            finally
            {
                $key.Dispose()
            }
        }
        It 'Should accept MSI applications via the pipeline' {
            $app = New-ADTApplication -ProductCode ([System.Guid]::NewGuid()) -WindowsInstaller
            $app | Register-ADTMsiUnelevatedRepair
            (Get-ItemProperty -LiteralPath "$RedirectedWindowsInstallerKey\SecureRepairWhitelist").psobject.Properties.Name | Should -Contain $app.ProductCode.ToString('B')
        }
    }

    Context 'Input Validation' {
        It 'Should verify that -ProductCode is a valid GUID' {
            $shouldParams = @{
                Throw = $true
                ExceptionType = [System.Management.Automation.ParameterBindingException]
            }
            { Register-ADTMsiUnelevatedRepair -ProductCode $null } | Should @shouldParams -ErrorId 'ParameterArgumentTransformationError,Register-ADTMsiUnelevatedRepair'
            { Register-ADTMsiUnelevatedRepair -ProductCode '' } | Should @shouldParams -ErrorId 'ParameterArgumentValidationError,Register-ADTMsiUnelevatedRepair'
            { Register-ADTMsiUnelevatedRepair -ProductCode " `f`n`r`t`v" } | Should @shouldParams -ErrorId 'ParameterArgumentValidationError,Register-ADTMsiUnelevatedRepair'
            { Register-ADTMsiUnelevatedRepair -ProductCode ([System.Guid]::Empty) } | Should @shouldParams -ErrorId 'ParameterArgumentValidationError,Register-ADTMsiUnelevatedRepair'
            { Register-ADTMsiUnelevatedRepair -ProductCode ([System.Guid]::New()) } | Should -Not -Throw
        }
        It 'Should validate that -InstalledApplication is an MSI with a valid product code' {
            $shouldParams = @{
                Throw = $true
                ExceptionType = [System.Management.Automation.ParameterBindingException]
            }
            { Register-ADTMsiUnelevatedRepair -InstalledApplication $null } | Should @shouldParams -ErrorId 'ParameterArgumentTransformationError,Register-ADTMsiUnelevatedRepair'
            { Register-ADTMsiUnelevatedRepair -InstalledApplication (New-ADTApplication -ProductCode $null -WindowsInstaller) } | Should @shouldParams -ErrorId 'ParameterArgumentValidationError,Register-ADTMsiUnelevatedRepair'
            { Register-ADTMsiUnelevatedRepair -InstalledApplication (New-ADTApplication -ProductCode ([System.Guid]::Empty) -WindowsInstaller) } | Should @shouldParams -ErrorId 'ParameterArgumentValidationError,Register-ADTMsiUnelevatedRepair'
            { Register-ADTMsiUnelevatedRepair -InstalledApplication (New-ADTApplication -ProductCode ([System.Guid]::NewGuid())) } | Should @shouldParams -ErrorId 'ParameterArgumentValidationError,Register-ADTMsiUnelevatedRepair'
            { New-ADTApplication -ProductCode $null -WindowsInstaller | Register-ADTMsiUnelevatedRepair } | Should @shouldParams -ErrorId 'ParameterArgumentValidationError,Register-ADTMsiUnelevatedRepair'
            { New-ADTApplication -ProductCode ([System.Guid]::Empty) -WindowsInstaller | Register-ADTMsiUnelevatedRepair } | Should @shouldParams -ErrorId 'ParameterArgumentValidationError,Register-ADTMsiUnelevatedRepair'
            { New-ADTApplication -ProductCode ([System.Guid]::NewGuid()) | Register-ADTMsiUnelevatedRepair } | Should @shouldParams -ErrorId 'ParameterArgumentValidationError,Register-ADTMsiUnelevatedRepair'
            { New-ADTApplication -ProductCode ([System.Guid]::NewGuid()) -WindowsInstaller | Register-ADTMsiUnelevatedRepair } | Should -Not -Throw
            { Register-ADTMsiUnelevatedRepair -InstalledApplication (New-ADTApplication -ProductCode ([System.Guid]::NewGuid()) -WindowsInstaller) } | Should -Not -Throw
        }
    }
}
