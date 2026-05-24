#Requires -RunAsAdministrator
BeforeAll {
    Remove-Module PSAppDeployToolkit -Force -ErrorAction SilentlyContinue
    Import-Module "$PSScriptRoot\..\..\PSAppDeployToolkit\PSAppDeployToolkit.psd1" -Force

    # Mock Set-ADTPreferenceVariables due to its expense when running via Pester.
    Mock -ModuleName PSAppDeployToolkit Set-ADTPreferenceVariables { }

    # Mock Write-ADTLogEntry due to its expense when running via Pester.
    Mock -ModuleName PSAppDeployToolkit Write-ADTLogEntry { }

    # System paths
    $script:FontsDir = "$env:SystemRoot\Fonts"
    $script:FontRegKey = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Fonts'

    # Helper function to create a test font file by copying a system font
    function New-TestFontFile
    {
        param
        (
            [Parameter(Mandatory = $true)]
            [ValidateSet('.ttf', '.ttc', '.otf')]
            [System.String]$Extension,

            [Parameter(Mandatory = $false)]
            [PSAppDeployToolkit.Attributes.ValidateNotNullOrWhiteSpace()]
            [System.String]$SourceFont
        )

        $uniqueName = "PesterTest_$([System.Guid]::NewGuid().ToString('N').Substring(0, 8))$Extension"
        $destPath = Join-Path -Path $TestDrive -ChildPath $uniqueName

        # Find a source font if not specified
        if (!$SourceFont)
        {
            switch ($Extension)
            {
                '.ttf' { $SourceFont = Get-ChildItem "$env:SystemRoot\Fonts\*.ttf" | Select-Object -First 1 -ExpandProperty FullName }
                '.ttc' { $SourceFont = Get-ChildItem "$env:SystemRoot\Fonts\*.ttc" | Select-Object -First 1 -ExpandProperty FullName }
                '.otf' { $SourceFont = Get-ChildItem "$env:SystemRoot\Fonts\*.otf" | Select-Object -First 1 -ExpandProperty FullName }
            }
        }

        if (!$SourceFont -or !(Test-Path -LiteralPath $SourceFont))
        {
            throw "Could not find a system font with extension $Extension"
        }

        Copy-Item -Path $SourceFont -Destination $destPath -Force
        return $destPath
    }

    # Helper function to clean up an installed test font using Remove-ADTFont
    function Remove-TestFont
    {
        param
        (
            [Parameter(Mandatory = $true)]
            [PSAppDeployToolkit.Attributes.ValidateNotNullOrWhiteSpace()]
            [System.String]$FontFileName
        )

        # Use Remove-ADTFont to properly clean up the font
        try
        {
            Remove-ADTFont -Name $FontFileName -ErrorAction SilentlyContinue
        }
        catch
        {
            Write-Warning "Error removing font via Remove-ADTFont: $_"
        }

        # Fallback: If file still exists, force remove it
        $fontPath = Join-Path -Path $script:FontsDir -ChildPath $FontFileName
        if (Test-Path -LiteralPath $fontPath)
        {
            Remove-Item -LiteralPath $fontPath -Force -ErrorAction SilentlyContinue
        }

        # Fallback: If registry entry still exists, remove it
        try
        {
            $regKey = Get-Item -LiteralPath $script:FontRegKey -ErrorAction SilentlyContinue
            if ($regKey)
            {
                $regKey.Property | & {
                    process
                    {
                        if ($regKey.GetValue($_) -eq $FontFileName)
                        {
                            Remove-ItemProperty -Path $script:FontRegKey -Name $_ -Force -ErrorAction SilentlyContinue
                        }
                    }
                }
            }
        }
        catch
        {
            Write-Warning "Error removing registry entry: $_"
        }
    }
}

Describe 'Add-ADTFont' {
    Context 'Single File Installation' {
        AfterEach {
            # Clean up any installed test fonts
            if ($script:InstalledFontFile)
            {
                Remove-TestFont -FontFileName $script:InstalledFontFile
                $script:InstalledFontFile = $null
            }
        }

        It 'Should install a .ttf (TrueType) font file' {
            $testFont = New-TestFontFile -Extension '.ttf'
            $script:InstalledFontFile = Split-Path $testFont -Leaf

            Add-ADTFont -Path $testFont

            # Verify file was copied to Fonts directory
            Join-Path -Path $script:FontsDir -ChildPath $script:InstalledFontFile | Should -Exist

            # Verify registry entry was created with (TrueType) suffix
            $regKey = Get-Item -LiteralPath $script:FontRegKey
            $regEntry = $regKey.Property | & { process { if ($regKey.GetValue($_) -eq $script:InstalledFontFile) { return $_ } } } | Select-Object -First 1

            $regEntry | Should -Not -BeNullOrEmpty
            $regEntry | Should -Match '\(TrueType\)$'
        }

        It 'Should install a .ttc (TrueType Collection) font file' -Skip:(!(Test-Path -Path "$env:SystemRoot\Fonts\*.ttc")) {
            $testFont = New-TestFontFile -Extension '.ttc'
            $script:InstalledFontFile = Split-Path $testFont -Leaf

            Add-ADTFont -Path $testFont

            # Verify file was copied to Fonts directory
            Join-Path -Path $script:FontsDir -ChildPath $script:InstalledFontFile | Should -Exist

            # Verify registry entry was created with (TrueType) suffix
            $regKey = Get-Item -LiteralPath $script:FontRegKey
            $regEntry = $regKey.Property | & { process { if ($regKey.GetValue($_) -eq $script:InstalledFontFile) { return $_ } } } | Select-Object -First 1

            $regEntry | Should -Not -BeNullOrEmpty
            $regEntry | Should -Match '\(TrueType\)$'
        }

        It 'Should install a .otf (OpenType) font file' -Skip:(!(Test-Path -Path "$env:SystemRoot\Fonts\*.otf")) {
            $testFont = New-TestFontFile -Extension '.otf'
            $script:InstalledFontFile = Split-Path $testFont -Leaf

            Add-ADTFont -Path $testFont

            # Verify file was copied to Fonts directory
            Join-Path -Path $script:FontsDir -ChildPath $script:InstalledFontFile | Should -Exist

            # Verify registry entry was created with (OpenType) suffix
            $regKey = Get-Item -LiteralPath $script:FontRegKey
            $regEntry = $regKey.Property | & { process { if ($regKey.GetValue($_) -eq $script:InstalledFontFile) { return $_ } } } | Select-Object -First 1

            $regEntry | Should -Not -BeNullOrEmpty
            $regEntry | Should -Match '\(OpenType\)$'
        }

        It 'Should not copy file if it already exists in Fonts directory' {
            $testFont = New-TestFontFile -Extension '.ttf'
            $script:InstalledFontFile = Split-Path $testFont -Leaf
            $destPath = Join-Path -Path $script:FontsDir -ChildPath $script:InstalledFontFile

            # Pre-copy the file to Fonts directory
            Copy-Item -Path $testFont -Destination $destPath -Force
            $originalWriteTime = (Get-Item $destPath).LastWriteTime

            # Small delay to ensure timestamp would change if file was overwritten
            Start-Sleep -Milliseconds 100

            Add-ADTFont -Path $testFont

            # Verify file was not overwritten (same timestamp)
            (Get-Item $destPath).LastWriteTime | Should -Be $originalWriteTime
        }

        It 'Should skip unsupported file types with exception' {
            $unsupportedFile = Join-Path -Path $TestDrive -ChildPath 'test.txt'
            Set-Content -Path $unsupportedFile -Value 'not a font'

            # Should throw
            { Add-ADTFont -Path $unsupportedFile } | Should -Throw

            # File should not be in Fonts directory
            Join-Path -Path $script:FontsDir -ChildPath 'test.txt' | Should -Not -Exist
        }
    }

    Context 'Directory Processing' {
        BeforeEach {
            $script:TestFontDir = Join-Path -Path $TestDrive -ChildPath 'FontDir'
            New-Item -Path $script:TestFontDir -ItemType Directory -Force | Out-Null
            $script:InstalledFontFiles = @()
        }

        AfterEach {
            # Clean up any installed test fonts
            foreach ($fontFile in $script:InstalledFontFiles)
            {
                Remove-TestFont -FontFileName $fontFile
            }
            $script:InstalledFontFiles = @()

            # Clean up test directory
            if (Test-Path -LiteralPath $script:TestFontDir)
            {
                Remove-Item -Path $script:TestFontDir -Recurse -Force -ErrorAction SilentlyContinue
            }
        }

        It 'Should install all font files from a directory' {
            # Create test fonts in directory
            $font1 = New-TestFontFile -Extension '.ttf'
            $font1Name = "DirTest1_$([System.Guid]::NewGuid().ToString('N').Substring(0, 8)).ttf"
            Copy-Item $font1 (Join-Path -Path $script:TestFontDir -ChildPath $font1Name)
            $script:InstalledFontFiles += $font1Name

            $font2 = New-TestFontFile -Extension '.ttf'
            $font2Name = "DirTest2_$([System.Guid]::NewGuid().ToString('N').Substring(0, 8)).ttf"
            Copy-Item $font2 (Join-Path -Path $script:TestFontDir -ChildPath $font2Name)
            $script:InstalledFontFiles += $font2Name

            Add-ADTFont -Path $script:TestFontDir

            # Verify both fonts were installed
            Join-Path -Path $script:FontsDir -ChildPath $font1Name | Should -Exist
            Join-Path -Path $script:FontsDir -ChildPath $font2Name | Should -Exist
        }

        It 'Should only process font files when directory contains mixed file types' {
            # Create a font file
            $font = New-TestFontFile -Extension '.ttf'
            $fontName = "MixedTest_$([System.Guid]::NewGuid().ToString('N').Substring(0, 8)).ttf"
            Copy-Item $font (Join-Path -Path $script:TestFontDir -ChildPath $fontName)
            $script:InstalledFontFiles += $fontName

            # Create non-font files
            Set-Content -Path (Join-Path -Path $script:TestFontDir -ChildPath 'readme.txt') -Value 'test'
            Set-Content -Path (Join-Path -Path $script:TestFontDir -ChildPath 'config.xml') -Value '<config/>'

            Add-ADTFont -Path $script:TestFontDir

            # Font should be installed
            Join-Path -Path $script:FontsDir -ChildPath $fontName | Should -Exist

            # Non-fonts should not be installed
            Join-Path -Path $script:FontsDir -ChildPath 'readme.txt' | Should -Not -Exist
            Join-Path -Path $script:FontsDir -ChildPath 'config.xml' | Should -Not -Exist
        }

        It 'Should handle empty directory without error' {
            $emptyDir = Join-Path -Path $TestDrive -ChildPath 'EmptyFontDir'
            New-Item -Path $emptyDir -ItemType Directory -Force | Out-Null

            { Add-ADTFont -Path $emptyDir } | Should -Not -Throw
        }
    }

    Context 'Recursive Processing' {
        BeforeEach {
            $script:TestFontDir = Join-Path -Path $TestDrive -ChildPath 'RecurseFontDir'
            $script:SubDir = Join-Path -Path $script:TestFontDir -ChildPath 'SubFolder'
            New-Item -Path $script:SubDir -ItemType Directory -Force | Out-Null
            $script:InstalledFontFiles = @()
        }

        AfterEach {
            foreach ($fontFile in $script:InstalledFontFiles)
            {
                Remove-TestFont -FontFileName $fontFile
            }
            $script:InstalledFontFiles = @()

            if (Test-Path -LiteralPath $script:TestFontDir)
            {
                Remove-Item -Path $script:TestFontDir -Recurse -Force -ErrorAction SilentlyContinue
            }
        }

        It 'Should install fonts from subdirectories with -Recurse' {
            # Create font in root directory
            $font1 = New-TestFontFile -Extension '.ttf'
            $font1Name = "RecurseRoot_$([System.Guid]::NewGuid().ToString('N').Substring(0, 8)).ttf"
            Copy-Item $font1 (Join-Path -Path $script:TestFontDir -ChildPath $font1Name)
            $script:InstalledFontFiles += $font1Name

            # Create font in subdirectory
            $font2 = New-TestFontFile -Extension '.ttf'
            $font2Name = "RecurseSub_$([System.Guid]::NewGuid().ToString('N').Substring(0, 8)).ttf"
            Copy-Item $font2 (Join-Path -Path $script:SubDir -ChildPath $font2Name)
            $script:InstalledFontFiles += $font2Name

            Add-ADTFont -Path $script:TestFontDir -Recurse

            # Both fonts should be installed
            Join-Path -Path $script:FontsDir -ChildPath $font1Name | Should -Exist
            Join-Path -Path $script:FontsDir -ChildPath $font2Name | Should -Exist
        }

        It 'Should not process subdirectories without -Recurse' {
            # Create font in root directory
            $font1 = New-TestFontFile -Extension '.ttf'
            $font1Name = "NoRecurseRoot_$([System.Guid]::NewGuid().ToString('N').Substring(0, 8)).ttf"
            Copy-Item $font1 (Join-Path -Path $script:TestFontDir -ChildPath $font1Name)
            $script:InstalledFontFiles += $font1Name

            # Create font in subdirectory
            $font2 = New-TestFontFile -Extension '.ttf'
            $font2Name = "NoRecurseSub_$([System.Guid]::NewGuid().ToString('N').Substring(0, 8)).ttf"
            Copy-Item $font2 (Join-Path -Path $script:SubDir -ChildPath $font2Name)
            # Don't add to cleanup list since it shouldn't be installed

            Add-ADTFont -Path $script:TestFontDir

            # Root font should be installed
            Join-Path -Path $script:FontsDir -ChildPath $font1Name | Should -Exist

            # Subdirectory font should NOT be installed
            Join-Path -Path $script:FontsDir -ChildPath $font2Name | Should -Not -Exist
        }
    }

    Context 'Wildcard Support' {
        BeforeEach {
            $script:TestFontDir = Join-Path -Path $TestDrive -ChildPath 'WildcardFontDir'
            New-Item -Path $script:TestFontDir -ItemType Directory -Force | Out-Null
            $script:InstalledFontFiles = @()
        }

        AfterEach {
            foreach ($fontFile in $script:InstalledFontFiles)
            {
                Remove-TestFont -FontFileName $fontFile
            }
            $script:InstalledFontFiles = @()

            if (Test-Path -LiteralPath $script:TestFontDir)
            {
                Remove-Item -Path $script:TestFontDir -Recurse -Force -ErrorAction SilentlyContinue
            }
        }

        It 'Should process wildcard paths (*.ttf)' {
            # Create .ttf files
            $font1 = New-TestFontFile -Extension '.ttf'
            $font1Name = "WildcardA_$([System.Guid]::NewGuid().ToString('N').Substring(0, 8)).ttf"
            Copy-Item $font1 (Join-Path -Path $script:TestFontDir -ChildPath $font1Name)
            $script:InstalledFontFiles += $font1Name

            $font2 = New-TestFontFile -Extension '.ttf'
            $font2Name = "WildcardB_$([System.Guid]::NewGuid().ToString('N').Substring(0, 8)).ttf"
            Copy-Item $font2 (Join-Path -Path $script:TestFontDir -ChildPath $font2Name)
            $script:InstalledFontFiles += $font2Name

            # Create a non-matching file (would need .otf source)
            Set-Content -Path (Join-Path -Path $script:TestFontDir -ChildPath 'notafont.txt') -Value 'test'

            Add-ADTFont -Path (Join-Path -Path $script:TestFontDir -ChildPath '*.ttf')

            # .ttf files should be installed
            Join-Path -Path $script:FontsDir -ChildPath $font1Name | Should -Exist
            Join-Path -Path $script:FontsDir -ChildPath $font2Name | Should -Exist
        }
    }

    Context 'Pipeline Input' {
        AfterEach {
            foreach ($fontFile in $script:InstalledFontFiles)
            {
                Remove-TestFont -FontFileName $fontFile
            }
            $script:InstalledFontFiles = @()
        }

        It 'Should accept multiple paths via pipeline' {
            $script:InstalledFontFiles = @()

            $font1 = New-TestFontFile -Extension '.ttf'
            $font1Name = Split-Path $font1 -Leaf
            $script:InstalledFontFiles += $font1Name

            $font2 = New-TestFontFile -Extension '.ttf'
            $font2Name = Split-Path $font2 -Leaf
            $script:InstalledFontFiles += $font2Name

            @($font1, $font2) | Add-ADTFont

            Join-Path -Path $script:FontsDir -ChildPath $font1Name | Should -Exist
            Join-Path -Path $script:FontsDir -ChildPath $font2Name | Should -Exist
        }

        It 'Should accept array of paths' {
            $script:InstalledFontFiles = @()

            $font1 = New-TestFontFile -Extension '.ttf'
            $font1Name = Split-Path $font1 -Leaf
            $script:InstalledFontFiles += $font1Name

            $font2 = New-TestFontFile -Extension '.ttf'
            $font2Name = Split-Path $font2 -Leaf
            $script:InstalledFontFiles += $font2Name

            Add-ADTFont -Path @($font1, $font2)

            Join-Path -Path $script:FontsDir -ChildPath $font1Name | Should -Exist
            Join-Path -Path $script:FontsDir -ChildPath $font2Name | Should -Exist
        }
    }

    Context 'Error Handling' {
        It 'Should throw error for non-existent path' {
            { Add-ADTFont -Path 'C:\NonExistent\Font.ttf' } | Should -Throw
        }

        It 'Should continue with -ErrorAction SilentlyContinue when a file fails' {
            $script:InstalledFontFiles = @()

            # Create a valid font
            $validFont = New-TestFontFile -Extension '.ttf'
            $validFontName = Split-Path $validFont -Leaf
            $script:InstalledFontFiles += $validFontName

            # This should not throw and should install the valid font
            { Add-ADTFont -Path @('C:\NonExistent\Font.ttf', $validFont) -ErrorAction SilentlyContinue } | Should -Not -Throw

            # Valid font should still be installed
            Join-Path -Path $script:FontsDir -ChildPath $validFontName | Should -Exist

            # Cleanup
            Remove-TestFont -FontFileName $validFontName
        }
    }

    Context 'Font Registration' {
        AfterEach {
            if ($script:InstalledFontFile)
            {
                Remove-TestFont -FontFileName $script:InstalledFontFile
                $script:InstalledFontFile = $null
            }
        }

        It 'Should register font with system and create registry entry' {
            $testFont = New-TestFontFile -Extension '.ttf'
            $script:InstalledFontFile = Split-Path $testFont -Leaf
            $destPath = Join-Path -Path $script:FontsDir -ChildPath $script:InstalledFontFile

            Add-ADTFont -Path $testFont

            # Verify the font was registered with the system
            # We can verify this by checking the file exists and registry entry was created
            $destPath | Should -Exist

            $regKey = Get-Item -LiteralPath $script:FontRegKey
            $regEntry = $regKey.Property | & { process { if ($regKey.GetValue($_) -eq $script:InstalledFontFile) { return $_ } } } | Select-Object -First 1
            $regEntry | Should -Not -BeNullOrEmpty
        }
    }
}
