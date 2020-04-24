########################################################################################################################
#  Name        : UpdatePackageQuality.ps1                                                                              #
#                                                                                                                      #
#  Description : Updates the Nuget/Npm package quality after successful deployment.                                    #
#                As you can't push a package directly to TFS package View, you need to first push/publish and then     # 
#                promote to a view.                                                                                    #
#                                                                                                                      #
#  Arguments   : PackageDescriptor - specifies the quality name to be updated                                          #
#                Possible options for Service quality are:                                                             #
#                - 'Alpha'                                                                                             #
#                - 'Beta'                                                                                              #
#                - 'RC'                                                                                                #
#              : PackageFeedName -  specifies the Package feed name                                                    # 
#                                                                                                                      #
#  Version     : 1.0 - Initial version.                                                                                #
########################################################################################################################
# https://github.com/renevanosnabrugge/VSTS-SetPackageQuality/blob/master/Set-PackageQuality.ps1
# http://TfsServer:8080/tfs/Projects/_packaging/FeedName/nuget/v3/index.json

param
(
    [parameter(Mandatory, Position=1, HelpMessage="Package feed name.")]
    $PackageFeedName,

    [parameter(Mandatory, Position=2, HelpMessage="Package quality descriptor as per feed view.")]
    [ValidateSet("alpha", "beta", "rc")]
    $PackageDescriptor
)

$tfsProjectUri = ${Env:System.TeamProject} 
$tfsCollectionUri = $tfsProjectUri.substring(0, $tfsProjectUri.LastIndexOf('/'))
$basepackageurl = ("$tfsCollectionUri/{0}/{1}/nuget/v3/index.json" -f "_packaging", "$PackageFeedName")

function Set-PackageQuality
{
    [CmdletBinding()]
    [OutputType([object])]
    param
    (
        [string] $feedType="nuget",
        [string] $feedName="",
        [string] $packageId="",
        [string] $packageVersion="",
        [string] $packageQuality=""
        
    )

    #API URL is slightly different for npm vs. nuget...
    # http://TfsServer:8080/tfs/Projects/_apis/packaging/Feeds/FeedName/packages/6ed4b255-ef74-4dda-aa10-520a4e1df06a/Versions/f847e27c-e0cb-4fad-a5c2-f0af1d3c4d1d
    switch($feedType)
    {
        "npm" { $releaseViewURL = "$basepackageurl/$feedName/npm/$packageId/versions/$($packageVersion)?api-version=3.0-preview.1" }
        "nuget" { $releaseViewURL = "$tfsCollectionUri/_apis/packaging/Feeds/$feedName/packages/$packageId/versions/$($packageVersion)?api-version=3.0-preview.1"}
        default { $releaseViewURL = "$tfsCollectionUri/_apis/packaging/Feeds/$feedName/packages/$packageId/versions/$($packageVersion)?api-version=3.0-preview.1"}
    }
    
     $json = @{
        views = @{
            op = "add"
            path = "/views/-"
            value = "$packageQuality"
        }
    }

    $response = Invoke-RestMethod -Uri $releaseViewURL -ContentType "application/json" -Method Patch -UseDefaultCredentials -Body (ConvertTo-Json $json)
    return $response
}

# Enumerate packages in specified Feed
$allPackagesApiUrl = ($tfsCollectionUri + "/_apis/packaging/Feeds/" + $PackageFeedName + "/packages")
$allPackages = Invoke-RestMethod -Uri $allPackagesApiUrl -ContentType "application/json" -Method Get -UseDefaultCredentials -Body (ConvertTo-Json $json)
foreach($package in $allPackages.value)
{
    $pkgId = $package.id
    $pkgName = $package.name
    foreach($versionObject in $package.versions)
    {
        $pkgVersionId = $versionObject.id
        $pkgVersion = $versionObject.version
        if($pkgVersion.indexOf("-alpha") -gt 0)
        {
            $pkgDescriptor = 'ALPHA'
        }
        elseif($pkgVersion.indexOf("-beta") -gt 0)
        {
            $pkgDescriptor = 'BETA'
        }
        elseif($pkgVersion.indexOf("-rc") -gt 0)
        {
            $pkgDescriptor = 'RC'
        }
        else
        {
            $pkgDescriptor = 'FINAL'
        }
    }

    # Promote the package to specified Quality Descriptor
    Write-Verbose -Message "Promoting package $pkgName to $PackageDescriptor view." -Verbose
    Set-PackageQuality -feedName $PackageFeedName -packageId $pkgId -packageVersion $pkgVersionId -packageQuality $PackageDescriptor
    Write-Verbose -Message "Promoted package $pkgName to $PackageDescriptor view." -Verbose
}