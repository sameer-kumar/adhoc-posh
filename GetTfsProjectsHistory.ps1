# **********TFS Rest Api will only return 256 records at a time**********
$rootTfsUri = "http://tfs:8080/tfs/Collection"
$allProjectsUri = "$rootTfsUri/_apis/projects?api-version=3.1&`$top=256"
$projectStats = @{}
$projectsMetadata = @()
$global:memberUsers = @()

function Get-MaxChangeset($Project, $LastChngset)
{
    $projectUri = "$rootTfsUri/$($Project.name)/_apis/tfvc/changesets?api-version=3.1&`$top=256&orderby=id desc"
    $lastchangeset = $LastChngset
    if($lastchangeset -ne $null){
        $projectUri += "&searchCriteria.toId=$($lastchangeset.changesetId)"
    }

    $nestedsubresponse = Invoke-WebRequest -Uri $projectUri -UseDefaultCredentials -Method Get -Verbose -UseBasicParsing
    $nestedsubresponseObject = $nestedsubresponse.Content | ConvertFrom-Json
    if($nestedsubresponseObject.count -ge 1)
    {
        # exclude false positives.
        $lastchangeset = $nestedsubresponseObject.value | `
                    where-object {
                        ($_.checkedInBy.displayName -notlike "*Project Collection Service Accounts*") } | `
                    Sort-Object changesetId -Descending | Select-Object -First 1

        if( ($lastchangeset -eq $null) -and ($nestedsubresponseObject.count -ge 256) )
        {
            # More records to search. Pick the bottom from current list and send it back for next batch api call.
            $lastchangeset = $nestedsubresponseObject.value | Sort-Object changesetId | Select-Object -First 1
            $lastchangeset = Get-MaxChangeset $Project $lastchangeset
        }
    }

    return $lastchangeset
}

function Get-SidToUser($sid) 
{
    Get-ADUser -Identity $sid
} 

function Get-ACL($Project)
{
    $acl = $null
    # GET https://{instance}/{collection}/_apis/accesscontrollists/{securityNamespaceId}?api-version=4.1
    $projectUri = "$rootTfsUri/$($Project.name)/_apis/accesscontrollists?api-version=3.1&`$top=256"
    $webReq = Invoke-WebRequest -Uri $projectUri -UseDefaultCredentials -Method Get -Verbose -UseBasicParsing
    $webResp = $webReq.Content | ConvertFrom-Json
    if($webResp.count -ge 1)
    {
        $acl = $webResp.value 
    }

    return $acl
}

function Get-TFSGroupMembership
{
    Param
    (
        [string] $CollectionUrlParam,
        [string[]] $Projects,
        [switch] $ShowEmptyGroups
    )

    $identation = 0
    $max_call_depth = 30
    

    function write-idented([string]$text)
    {
        Write-Output $text.PadLeft($text.Length + (6 * $identation))
    }

    function list_identities ($queryOption, $tfsIdentity,$readIdentityOptions)
    {
        $identities = $idService.ReadIdentities($tfsIdentity, $queryOption, $readIdentityOptions)
        $identation++
        foreach($id in $identities)
        {
            if ($id.IsContainer)
            {
                if ($id.Members.Count -gt 0)
                {
                    if ($identation -lt $max_call_depth) #Safe number for max call depth
                    {
                        write-idented "Group: ", $id.DisplayName
                        list_identities $queryOption $id.Members $readIdentityOptions
                    }
                    else
                    {
                        Write-Output "Maximum call depth reached. Moving on to next group or project..."
                    }
                }
                else
                {
                    if ($ShowEmptyGroups)
                    {
                        write-idented "Group: ", $id.DisplayName
                        $identation++;
                        write-idented "-- No users --"
                        $identation--;
                    }
                }
            }
            else
            {
                if ($id.UniqueName)  {
                    write-idented "Member user: ", $id.UniqueName
                    $global:memberUsers += $id.UniqueName
                }
                else {
                    write-idented "Member user: ", $id.DisplayName
                    $global:memberUsers += $id.DisplayName
                }
            } 
        }

        $identation--
    }

    # load the required dlls
    Add-Type -AssemblyName "Microsoft.TeamFoundation.Client, Version=11.0.0.0, Culture=neutral, PublicKeyToken=b03f5f7f11d50a3a",
                           "Microsoft.TeamFoundation.Common, Version=11.0.0.0, Culture=neutral, PublicKeyToken=b03f5f7f11d50a3a",
                           "Microsoft.TeamFoundation, Version=11.0.0.0, Culture=neutral, PublicKeyToken=b03f5f7f11d50a3a"

    #[void][System.Reflection.Assembly]::LoadWithPartialName("Microsoft.TeamFoundation.Client")
    #[void][System.Reflection.Assembly]::LoadWithPartialName("Microsoft.TeamFoundation.Common")
    #[void][System.Reflection.Assembly]::LoadWithPartialName("Microsoft.TeamFoundation")
    $tfs
    $projectList = @()
    if ($CollectionUrlParam)
    {
        #if collection is passed then use it and select all projects
        $tfs = [Microsoft.TeamFoundation.Client.TfsTeamProjectCollectionFactory]::GetTeamProjectCollection($CollectionUrlParam)
        $cssService = $tfs.GetService("Microsoft.TeamFoundation.Server.ICommonStructureService3")   
        if ($Projects)
        {
            #validate project names
            foreach ($p in $Projects)
            {
                try
                {
                    $projectList += $cssService.GetProjectFromName($p)
                }
                catch
                {
                    Write-Error "Invalid project name: $p"
                    exit
                }
            }       
        }
        else
        {
            $projectList = $cssService.ListAllProjects()
        }
    }
    else
    {
        #if no collection specified, open project picker to select it via gui
        $picker = New-Object Microsoft.TeamFoundation.Client.TeamProjectPicker([Microsoft.TeamFoundation.Client.TeamProjectPickerMode]::MultiProject, $false)
        $dialogResult = $picker.ShowDialog()
        if ($dialogResult -ne "OK")
        {
            exit
        }

        $tfs = $picker.SelectedTeamProjectCollection
        $projectList = $picker.SelectedProjects
    }

    try
    {
        $tfs.EnsureAuthenticated()
    }
    catch
    {
        Write-Error "Error occurred trying to connect to project collection: $_ "
        exit 1
    }

    $idService = $tfs.GetService("Microsoft.TeamFoundation.Framework.Client.IIdentityManagementService")
    Write-Output ""
    Write-Output "Team project collection: " $CollectionUrlParam
    Write-Output ""
    Write-Output "Membership information: "
    $identation++
    foreach($teamProject in $projectList)
    {       
        Write-Output ""
        write-idented "Team project: ",$teamProject.Name
        foreach($group in $idService.ListApplicationGroups($teamProject.Name, [Microsoft.TeamFoundation.Framework.Common.ReadIdentityOptions]::TrueSid))
        {
            list_identities  ([Microsoft.TeamFoundation.Framework.Common.MembershipQuery]::Direct) $group.Descriptor ([Microsoft.TeamFoundation.Framework.Common.ReadIdentityOptions]::TrueSid)
        }
    }

    $identation = 1
    Write-Output ""
    <#
    Write-Output "Users that have access to this collection but do not belong to any group:"
    Write-Output ""
    $validUsersGroup =  $idService.ReadIdentities([Microsoft.TeamFoundation.Framework.Common.IdentitySearchFactor]::AccountName,
                                                  "Project Collection Valid Users",
                                                  [Microsoft.TeamFoundation.Framework.Common.MembershipQuery]::Expanded,
                                                  [Microsoft.TeamFoundation.Framework.Common.ReadIdentityOptions]::TrueSid)

    foreach($member in $validUsersGroup[0][0].Members)
    {
        $user = $idService.ReadIdentity($member, [Microsoft.TeamFoundation.Framework.Common.MembershipQuery]::Expanded,[Microsoft.TeamFoundation.Framework.Common.ReadIdentityOptions]::TrueSid)
        if ($user.MemberOf.Count -eq 1 -and -not $user.IsContainer)
        {
            if ($user.UniqueName)  {
                write-idented "User: ", $user.UniqueName
            }
            else  {
                write-idented "User: ", $user.DisplayName
            }
        }
    }
    #>
}

function Get-TFSProjectSize
{
    Param
    (
        [string] $CollectionUrlParam,
        [string[]] $Project
    )

    # load the required dlls
    Add-Type -AssemblyName "Microsoft.TeamFoundation.Client, Version=11.0.0.0, Culture=neutral, PublicKeyToken=b03f5f7f11d50a3a",
                           "Microsoft.TeamFoundation.Common, Version=11.0.0.0, Culture=neutral, PublicKeyToken=b03f5f7f11d50a3a",
                           "Microsoft.TeamFoundation, Version=11.0.0.0, Culture=neutral, PublicKeyToken=b03f5f7f11d50a3a",
                           "Microsoft.TeamFoundation.VersionControl.Client, Version=11.0.0.0, Culture=neutral, PublicKeyToken=b03f5f7f11d50a3a"

    #[void][System.Reflection.Assembly]::LoadWithPartialName("Microsoft.TeamFoundation.Client")
    #[void][System.Reflection.Assembly]::LoadWithPartialName("Microsoft.TeamFoundation.Common")
    #[void][System.Reflection.Assembly]::LoadWithPartialName("Microsoft.TeamFoundation")
    $tfs
    $projectList = @()
    $tfs = [Microsoft.TeamFoundation.Client.TfsTeamProjectCollectionFactory]::GetTeamProjectCollection($CollectionUrlParam)
    $vcsService = $tfs.GetService(" Microsoft.TeamFoundation.VersionControl.Client.VersionControlServer")   
    $projectSize = 0
    $sizeInMb = 0
    if ($Project)
    {
        $items = $vcsService.GetItems("$\$Project", [Microsoft.TeamFoundation.VersionControl.Client.RecursionType]::Full)
        foreach ($item in $items.Items)
        {
            #$item.ServerItem;
            if($item.ItemType -eq 'File')
            {
                if(($item.ServerItem -notlike "*BuildProcessTemplates*") -and ($item.ServerItem -notlike "*ProcessTemplate*") -and ($item.ServerItem -notlike "*TeamBuildTypes*"))
                {
                    $sizeInMb += (($item.ContentLength)/1024)/1024
                    # Write-Verbose "$sizeInMb Mb" -Verbose
                }
            }
        } 
    }
    
    $projectSize = $sizeInMb
    return $projectSize 
}

$response = Invoke-WebRequest -Uri $allProjectsUri -UseDefaultCredentials -Method Get -Verbose -UseBasicParsing
$responseObject = $response.Content | ConvertFrom-Json
if($responseObject.count -ge 1)
{
    foreach($prj in $responseObject.value)
    {
        #$projects = TfsTeamProjectCollectionFactory.GetTeamProjectCollection(server);
        #$versionControl = (VersionControlServer)projects.GetService(typeof(VersionControlServer));
        #Item[] itemsFolders = versionControl.GetItems(serverPath, RecursionType.OneLevel).Items
        $projectSizeInMb = 0
        $projectSizeInMb = Get-TFSProjectSize -CollectionUrlParam $rootTfsUri -Project "$($prj.name)"
        $lastchangeset = Get-MaxChangeset $prj $null
        # reset global var
        $global:memberUsers = @()
        Get-TFSGroupMembership -CollectionUrlParam $rootTfsUri -Projects "$($prj.name)"
        if(($global:memberUsers).Count -le 0)
        {
            continue
        }
        $projectMembers = [string]::Join(";", ($global:memberUsers | Sort-Object | Get-Unique))
        $projectMembers = $projectMembers -replace("IAM\\","")
        if($lastchangeset -ne $null)
        {
            #$projectStats.Add("$($prj.name)", $lastchangeset.createdDate, $projectMembers)
            $projectData = New-Object PSObject -property @{
                Name="$($prj.name)"
                #LastUpdated=$lastchangeset.createdDate
                LastUpdated=([DateTime]$lastchangeset.createdDate).ToShortDateString()
                Members=$projectMembers
                Size="$projectSizeInMb"
            }
        }
        else
        {
            #$projectStats.Add("$($prj.name)", $lastchangeset, $projectMembers)
            $projectData = New-Object PSObject -property @{
                Name="$($prj.name)"
                #LastUpdated=$lastchangeset
                LastUpdated=([DateTime]$lastchangeset).ToShortDateString()
                Members=$projectMembers
                Size="$projectSizeInMb"
            }
        }
        
        $projectsMetadata += $projectData
    }

    #$projectStats.GetEnumerator() | Export-Csv "CheckInHistory.csv"
    $projectsMetadata | Export-Csv "CheckInHistory.csv"
}
