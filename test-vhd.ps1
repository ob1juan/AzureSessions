$seedVhd = "$Env:TEMP\seed.vhdx"
New-VHD -Path $seedVhd -SizeBytes 10MB -Dynamic
