# https://www.simple-talk.com/dotnet/.net-tools/further-down-the-rabbit-hole-powershell-modules-and-encapsulation/
# https://technet.microsoft.com/en-us/library/dd878350(v=vs.85).aspx
$Purpose = 'IM TFS Administration'

#region Load external references.
# Added to Manifest.
#[System.Reflection.Assembly]::LoadWithPartialName('Microsoft.TeamFoundation.Client')
#[System.Reflection.Assembly]::LoadWithPartialName('Microsoft.TeamFoundation.WorkItemTracking.Client')
#[System.Reflection.Assembly]::LoadWithPartialName('Microsoft.TeamFoundation.VersionControl.Client')
#endregion

function Add-TFSMembersToGroup() {
<#
	.SYNOPSIS
		Adds members to TFS Group.

	.DESCRIPTION
		The Add-TFSMembersToGroup cmdlet adds members to specified TFS group.

	.PARAMETER  GroupName
		Specifies TFS Group name under which members to be added.

	.PARAMETER  MemberNames
		Specifies one or many members to be added.

	.PARAMETER  ProjectCollectionUri
		Specifies the URL of TFS Project Collection to use.
        The format it expects is: http://{tfs server}:{port}/{instance}/{collectionName}
        
    .PARAMETER  ProjectName
		Specifies the TFS Project to use.
        
    .EXAMPLE
		PS C:\> Add-TFSMembersToGroup -GroupName "ReadersGroup" -MemberNames "@('ADgroup1','ADgroup2')" -ProjectCollectionUri "http://tf:8080/tf/TFcollection" -ProjectName "TestProject1"
        This command adds 2 security groups ('ADgroup1' and 'ADgroup2') to 'ReadersGroup' TFS group available on http://tf:8080/tf/TFcollection/TestProject1

	.INPUTS
		System.String,System.String[],URI,System.String

	.OUTPUTS
		None.

	.NOTES
		The Add-TFSMembersToGroup cmdlet writes
        -- Error message in case of any exception or error 
        -- Warning message in case of any warnings
        which can be stored with -ErrorVariable or -WarningVariable.

	.LINK
		Get-TFSProjectGroupMembership
        Get-TFSGroupMembers

	.LINK
		https://msdn.microsoft.com/en-us/library/microsoft.teamfoundation.framework.client.iidentitymanagementservice.addmembertoapplicationgroup(v=vs.120).aspx

#>

    #region Parameters.
    [CmdletBinding()]
    param
    (
        [Parameter(Mandatory, ValueFromPipeline=$true, Position=1)]
        [string]
        $GroupName,
        
        [Parameter(ValueFromPipeline=$true, Position=2)]
        [string[]]
        $MemberNames,
        
        [parameter(Mandatory, ValueFromPipeline=$true, Position=3, HelpMessage="Name of TFS project collection to use.")]
        [Uri]
        $ProjectCollectionUri,
        
        [parameter(Mandatory, ValueFromPipeline=$true, Position=4, HelpMessage="Name of the TFS Project to use.")]
        [string]
        $ProjectName 
    )
    #endregion
    Begin {
        #$ErrorActionPreference = ''
        # Write-Verbose -Message "Get Team Project Collection"
        $teamProjectCollection = [Microsoft.TeamFoundation.Client.TfsTeamProjectCollectionFactory]::GetTeamProjectCollection($ProjectCollectionUri)
            
        # Write-Verbose -Message "Get Identity Management Service"
        $ids = $teamProjectCollection.GetService([Microsoft.TeamFoundation.Framework.Client.IIdentityManagementService])
        
        $currentGroups = Get-TFSProjectGroupMembership -ProjectCollectionUri $ProjectCollectionUri -ProjectName $ProjectName
        $tfsGroup = ($currentGroups | Where-Object {$_.DisplayName -eq "[$ProjectName]\$GroupName"})
        $currentGroupMemberIdentityDescriptors = Get-TFSGroupMembers -ProjectCollectionUri $ProjectCollectionUri -ProjectName $ProjectName -GroupName $GroupName -IdentityOnly $true
    }
    Process {
        try {
            foreach ($memberName in $MemberNames)
            {
                $tfsGroupMember = $currentGroupMemberIdentityDescriptors | Where-Object {$_.Identifier -eq (Get-SidByName -AccountName $memberName)}
                Write-Verbose -Message "Add member if not already there."
                if ($tfsGroupMember -eq $null) {
                    $argsArray = @()
                    $argsArray += [System.Security.Principal.WindowsIdentity]
                    $argsArray += Get-SidByName -AccountName $memberName
                    if(-not($argsArray -imatch "exception")) {
                        $user = New-Object -TypeName "Microsoft.TeamFoundation.Framework.Client.IdentityDescriptor" -ArgumentList $argsArray
                        if($tfsGroup -is [Microsoft.TeamFoundation.Framework.Client.IdentityDescriptor] -eq $true) {
                            $ids.AddMemberToApplicationGroup($tfsGroup, $user)
                            Write-Verbose -Message "$memberName added to $GroupName."
                        }
                        else {
                            $ids.AddMemberToApplicationGroup($tfsGroup.Descriptor, $user)    
                            Write-Verbose -Message "$memberName added to $GroupName."
                        }
                    }
                    else {
                        Write-Warning -Message "Could not add $memberName to $GroupName"
                    }
                }
            }
        }
        catch {
            Write-Error "Members could not be added to $GroupName group. $_"
        }
    }
    End {}
}

function Add-TFSAreaNode {
    #region Parameters.
    [CmdletBinding()]
    param
    (
        [Parameter(Mandatory, ValueFromPipeline=$true, Position=1)]
        [ValidateLength(1,255)]
        [string]
        $AreaNodeName,
        
        [Parameter(ValueFromPipeline=$true, Position=2)]
        [ValidateLength(1,255)]
        [string]
        $ParentAreaNodeName,
        
        [parameter(Mandatory, ValueFromPipeline=$true, Position=3, HelpMessage="Name of TFS project collection to use.")]
        [Uri]
        $ProjectCollectionUri,
        
        [parameter(Mandatory, ValueFromPipeline=$true, Position=4, HelpMessage="Name of the TFS Project under which group needs to be added.")]
        [ValidateLength(1,255)]
        [string]
        $ProjectName 
    )
    #endregion
    Begin {
        #Get Team Project Collection
        $teamProjectCollection = [Microsoft.TeamFoundation.Client.TfsTeamProjectCollectionFactory]::GetTeamProjectCollection($ProjectCollectionUri)
        
        #Get Authorization Service
        $authorizationSvc = $teamProjectCollection.GetService([Microsoft.TeamFoundation.Server.IAuthorizationService])
        
        #Get Common Structure Service
        $css = $teamProjectCollection.GetService([Microsoft.TeamFoundation.Server.ICommonStructureService3])

        #Get Team Project
        $teamProject = $css.GetProjectFromName("$ProjectName")
    }
    Process {
        try {
            # Get Areas nodes identity.
            $nodes = $css.ListStructures($teamProject.Uri)
            $rootAreaNode = $nodes | where {$_.Path -eq "\$($teamProject.Name)\Area"}
            if($ParentAreaNodeName) {
                $parentAreaNode = $css.GetNodeFromPath($rootAreaNode.Path + "\$ParentAreaNodeName")
            }
            else {
                $parentAreaNode = $rootAreaNode
            }
            
            if($parentAreaNode) {
                try {
                    $newNode = $css.GetNodeFromPath($parentAreaNode.Path + "\$AreaNodeName")
                    Write-Warning -Message "$AreaNodeName node already exists under $($parentAreaNode.Path)."
                    return $newNode.Uri
                }
                catch {
                    if($_.Exception.InnerException) {
                        if($_.Exception.InnerException.GetType().BaseType.Name -eq 'TeamFoundationServerException') {
                            if($_.Exception.InnerException.Message.Contains("The following node does not exist")) {
                                $newNode = $css.CreateNode("$AreaNodeName", $parentAreaNode.Uri)
                                Write-Verbose -Message "$AreaNodeName are node created."
                                return $newNode
                            }
                        }
                    }
                }
            }
            else {
                Write-Warning -Message "$ParentAreaNodeName are node does not exist."
            }
            
        }
        catch {
            Write-Error "$AreaNodeName Area could not be added. $_"
        }
    }
    End {}
}

function Add-TFSIterationNode {
    #region Parameters.
    [CmdletBinding()]
    param
    (
        [Parameter(Mandatory, ValueFromPipeline=$true, Position=1)]
        [ValidateLength(1,255)]
        [string]
        $IterationNodeName,
        
        [Parameter(ValueFromPipeline=$true, Position=2)]
        [ValidateLength(1,255)]
        [string]
        $ParentIterationNodeName,
        
        [parameter(Mandatory, ValueFromPipeline=$true, Position=3, HelpMessage="Name of TFS project collection to use.")]
        [Uri]
        $ProjectCollectionUri,
        
        [parameter(Mandatory, ValueFromPipeline=$true, Position=4, HelpMessage="Name of the TFS Project under which group needs to be added.")]
        [ValidateLength(1,255)]
        [string]
        $ProjectName 
    )
    #endregion
    Begin {
        #Get Team Project Collection
        $teamProjectCollection = [Microsoft.TeamFoundation.Client.TfsTeamProjectCollectionFactory]::GetTeamProjectCollection($ProjectCollectionUri)
        
        #Get Authorization Service
        $authorizationSvc = $teamProjectCollection.GetService([Microsoft.TeamFoundation.Server.IAuthorizationService])
        
        #Get Common Structure Service
        $css = $teamProjectCollection.GetService([Microsoft.TeamFoundation.Server.ICommonStructureService3])

        #Get Team Project
        $teamProject = $css.GetProjectFromName("$ProjectName")
    }
    Process {
        try {
            # Get Areas nodes identity.
            $nodes = $css.ListStructures($teamProject.Uri)
            $rootIterationNode = $nodes | where {$_.Path -eq "\$($teamProject.Name)\Iteration"}
            if($ParentIterationNodeName) {
                $parentIterationNode = $css.GetNodeFromPath($rootIterationNode.Path + "\$ParentIterationNodeName")
            }
            else {
                $parentIterationNode = $rootIterationNode
            }
            
            if($parentIterationNode) {
                try {
                    $newNode = $css.GetNodeFromPath($parentIterationNode.Path + "\$IterationNodeName")
                    Write-Warning -Message "$IterationNodeName node already exists under $($parentIterationNode.Path)."
                    return $newNode.Uri
                }
                catch {
                    if($_.Exception.InnerException) {
                        if($_.Exception.InnerException.GetType().BaseType.Name -eq 'TeamFoundationServerException') {
                            if($_.Exception.InnerException.Message.Contains("The following node does not exist")) {
                                $newNode = $css.CreateNode("$IterationNodeName", $parentIterationNode.Uri)
                                Write-Verbose -Message "$IterationNodeName iteration node created."
                                return $newNode
                            }
                        }
                    }
                }
            }
            else {
                Write-Warning -Message "$ParentIterationNodeName are node does not exist."
            }
            
        }
        catch {
            Write-Error "$IterationNodeName iteration could not be added. $_"
        }
    }
    End {}
}

function Format-TFSVersionControlFolderAsBranch() {
<#
	.SYNOPSIS
		Converts a TFS folder into Version Control Branch.

	.DESCRIPTION
		The Format-TFSVersionControlFolderAsBranch cmdlet creates a BranchObject in TFS based on specified branch properties.
        BranchObject describes properties of a BranchObject class that are relevant to the repository.

	.PARAMETER  FolderName
		Specifies the name of existing folder which needs to be converted to Branch.

	.PARAMETER  BranchOwner
		Specifies the owner of new Branch to be created.

	.PARAMETER  BranchDescription
		Specifies the description of new Branch to be created.
    
    .PARAMETER  ProjectCollectionUri
		Specifies the URL of TFS Project Collection to use.
        The format it expects is: http://{tfs server}:{port}/{instance}/{collectionName}
        
    .PARAMETER  ProjectName
		Specifies the TFS Project to use.
        
    .EXAMPLE
		PS C:\> Format-TFSVersionControlFolderAsBranch -FolderName "master" -BranchOwner "Administrator" -BranchDescription "master branch representing production" -ProjectCollectionUri "http://tf:8080/tf/TFcollection" -ProjectName "TestProject1"
        This command converts a pre-existing folder called "master" into a VS branch with 
        Administrator as owner and description stating "master branch representing production" available on http://tf:8080/tf/TFcollection/TestProject1

	.INPUTS
		System.String,System.String,System.String,Uri,System.String

	.OUTPUTS
		None.

	.NOTES
		If folder doesn't pre-exist, no action would be performed.

	.LINK
		https://msdn.microsoft.com/en-us/library/microsoft.teamfoundation.versioncontrol.client.versioncontrolserver.createbranchobject(v=vs.120).aspx

#>

    #region Parameters.
    [CmdletBinding()]
    param
    (
        [Parameter(Mandatory, ValueFromPipeline=$true, Position=1)]
        [string]
        $FolderName,
        
        [Parameter(Mandatory, ValueFromPipeline=$true, Position=2, HelpMessage="Owner of the TFS branch to create.")]
        [ValidateLength(1,512)]
        [string]
        $BranchOwner,
        
        [Parameter(ValueFromPipeline=$true, Position=3, HelpMessage="Description of the TFS branch to create.")]
        [ValidateLength(1,1024)]
        [string]
        $BranchDescription,
        
        [parameter(Mandatory, ValueFromPipeline=$true, Position=4, HelpMessage="Name of TFS project collection to use.")]
        [Uri]
        $ProjectCollectionUri,
        
        [parameter(Mandatory, ValueFromPipeline=$true, Position=5, HelpMessage="Name of the TFS Project under which this custom folders needs to be added.")]
        [string]
        $ProjectName 
    )
    #endregion
    Begin {
        $teamProjectCollection = [Microsoft.TeamFoundation.Client.TfsTeamProjectCollectionFactory]::GetTeamProjectCollection($ProjectCollectionUri)
        
        # Get Version control service.
        $vcs = $teamProjectCollection.GetService([Microsoft.TeamFoundation.VersionControl.Client.VersionControlServer])
        
        # Get the TFS security service.
        $sec = $teamProjectCollection.GetService([Microsoft.TeamFoundation.Framework.Client.ISecurityService])
        $vcSecurityNamespace = $sec.GetSecurityNamespace([Microsoft.TeamFoundation.VersionControl.Common.SecurityConstants]::RepositorySecurityNamespaceGuid)
        
        # Get Team project.
        $teamProject = $vcs.GetTeamProject("$ProjectName")
        
        # Local variables
        $sourceServerPath = $teamProject.ServerItem + "/$FolderName"
    }
    Process {
        $branches = $vcs.QueryBranchObjects((New-Object Microsoft.TeamFoundation.VersionControl.Client.ItemIdentifier("$sourceServerPath")), [Microsoft.TeamFoundation.VersionControl.Client.RecursionType]::None)
        if(($branches -eq $null) -or (($branches -is [Array]) -and ($branches.Count -le 0))) {
            $branchProperties = New-Object Microsoft.TeamFoundation.VersionControl.Client.BranchProperties(New-Object Microsoft.TeamFoundation.VersionControl.Client.ItemIdentifier("$sourceServerPath"))
            $branchProperties.Description = "$BranchDescription"
            $branchProperties.Owner = "$BranchOwner"
            $vcs.CreateBranchObject($branchProperties)
            Write-Verbose -Message "$sourceServerPath converted to Branch."
        }
    }
    End {}
}

function Get-TFSGroupMembers() {
<#
	.SYNOPSIS
		Gets all members of a specified TFS group.

	.DESCRIPTION
		The Get-TFSGroupMembers cmdlet read identities by Team Foundation Id.
        
	.PARAMETER  GroupName
		Specifies the Team Foundation group name whose membership needs to be retrieved.

	.PARAMETER  IdentityOnly
		Specifies if detailed membership information (TeamFoundationIdentity[]) or just IdentityDescriptor would be retrieved.
        The default is FALSE and returns [IdentityDescriptor].
        [Microsoft.TeamFoundation.Framework.Client.IdentityDescriptor] is a wrapper for an identity type and a unique identifier.
        TeamFoundationIdentity is client implementation of TeamFoundationIdentity. Augments proxy generated class.
        
    .PARAMETER  ProjectCollectionUri
		Specifies the URL of TFS Project Collection to use.
        The format it expects is: http://{tfs server}:{port}/{instance}/{collectionName}
        
    .PARAMETER  ProjectName
		Specifies the TFS Project to use.

	.PARAMETER  QueryOption
		Specifies the MembershipQuery to use.
        Valid options include:
        -- "Direct"
        -- "Expanded"
        -- "None"
        The default option is "Direct".
        This string represents [Microsoft.TeamFoundation.Framework.Common.MembershipQuery] enumeration.
        
    .EXAMPLE
		PS C:\> Get-TFSGroupMembers -GroupName "AdminGroup" -IdentityOnly $true -ProjectCollectionUri "http://tf:8080/tf/TFcollection" -ProjectName "TestProject1"
        This command retrieves AdminGroup members' Identity available on http://tf:8080/tf/TFcollection/TestProject1

	.EXAMPLE
		PS C:\> Get-TFSGroupMembers -GroupName "AdminGroup" -ProjectCollectionUri "http://tf:8080/tf/TFcollection" -ProjectName "TestProject1"
        This command retrieves AdminGroup members' available on http://tf:8080/tf/TFcollection/TestProject1

	.EXAMPLE
		PS C:\> Get-TFSGroupMembers -GroupName "AdminGroup" QueryOption 'Expanded' -ProjectCollectionUri "http://tf:8080/tf/TFcollection" -ProjectName "TestProject1"
        This command retrieves AdminGroup members' detail information available on http://tf:8080/tf/TFcollection/TestProject1
        This includes nested group membership too.
        
    .INPUTS
		System.String,Uri,System.String,System.String,Bool

	.OUTPUTS
		TeamFoundationIdentity[]
        Returns an array of [Microsoft.TeamFoundation.Framework.Client.TeamFoundationIdentity] if -IdentityOnly param is specified FALSE.
        
        Array
        Returns an Array of Microsoft.TeamFoundation.Framework.Client.IdentityDescriptor if -IdentityOnly param is specified TRUE.

	.NOTES
		Performance will be fastest when no membership information is requested.

	.LINK
		Get-TFSProjectGroupMembership

	.LINK
		https://msdn.microsoft.com/en-us/library/ff731923(v=vs.120).aspx
        https://msdn.microsoft.com/en-us/library/microsoft.teamfoundation.framework.client.identitydescriptor(v=vs.120).aspx
        https://msdn.microsoft.com/en-us/library/microsoft.teamfoundation.framework.client.teamfoundationidentity(v=vs.120).aspx
        https://msdn.microsoft.com/en-us/library/microsoft.teamfoundation.framework.common.membershipquery(v=vs.120).aspx

#>

    #region Parameters.
    [CmdletBinding()]
    param
    (
        [parameter(Mandatory, ValueFromPipeline=$true, Position=1, HelpMessage="Array of TeamFoundation Ids.")]
        [string]
        $GroupName,
        
        [parameter(Mandatory, ValueFromPipeline=$true, Position=2, HelpMessage="Name of TFS project collection to use.")]
        [Uri]
        $ProjectCollectionUri,
        
        [parameter(Mandatory, ValueFromPipeline=$true, Position=3, HelpMessage="Name of the TFS Project to enumerate.")]
        [string]
        $ProjectName,

        [parameter(ValueFromPipeline=$true, Position=4, HelpMessage="MembershipQuery enumeration.")]
        [ValidateSet("Direct", "Expanded", "None")]
        [string]
        $QueryOption = "Direct",
        
        [parameter(ValueFromPipeline=$true, Position=5, HelpMessage="Return IdentityDescriptors ONLY.")]
        [bool]
        $IdentityOnly = $false
    )
    #endregion
    Begin {
        $currentGroupMembers = @()
        [Microsoft.TeamFoundation.Framework.Client.IdentityDescriptor[]]$currentGroupMemberIdentityDescriptors = @()
        #Get Team Project Collection
        $teamProjectCollection = [Microsoft.TeamFoundation.Client.TfsTeamProjectCollectionFactory]::GetTeamProjectCollection($ProjectCollectionUri)
        
        #Get Common Structure Service
        $css = $teamProjectCollection.GetService([Microsoft.TeamFoundation.Server.ICommonStructureService3])
        
        #Get Identity Management Service
        $ids = $teamProjectCollection.GetService([Microsoft.TeamFoundation.Framework.Client.IIdentityManagementService])
        
        #Get Team Project
        $teamProject = $css.GetProjectFromName("$ProjectName")
        
        # Get TFS group by name
        $currentGroups = Get-TFSProjectGroupMembership -ProjectCollectionUri $ProjectCollectionUri -ProjectName $ProjectName
        $tfsGroup = ($currentGroups | Where-Object {$_.DisplayName -eq "[$ProjectName]\$GroupName"})
        # Get identities
        if($tfsGroup -ne $null) {
            $teamFoundationIds = @($tfsGroup.TeamFoundationId)
            $currentGroupMembers = $ids.ReadIdentities($teamFoundationIds, "$QueryOption")
        }
    }
    Process {
        if($IdentityOnly -eq $true) {
            if($currentGroupMembers -ne $null -and $currentGroupMembers[0].Members -ne $null -and $currentGroupMembers[0].Members.Length -gt 0) {
                foreach ($currentMember in $currentGroupMembers[0].Members) {
                    #if($currentMember.IdentityType -eq [System.Security.Principal.WindowsIdentity]) {
                    $argsArray = @()
                    $argsArray += $currentMember.IdentityType
                    $argsArray += $currentMember.Identifier
                    $currentGroupMemberIdentityDescriptors += New-Object -TypeName "Microsoft.TeamFoundation.Framework.Client.IdentityDescriptor" -ArgumentList $argsArray
                    #}
                }
            }
            return $currentGroupMemberIdentityDescriptors
        }
        else {
            return $currentGroupMembers
        }
    }
    End {}
}

function Get-TFSGroupPermissionsForArea() {
<#
	.SYNOPSIS
		Returns the permissions on Team Project's root AREA node.

	.DESCRIPTION
		The Get-TFSGroupPermissionsForArea cmdlet return the permissions on specified TF project's root AREA node.
        It then check each of the Access Control Entries (ACE's) to make sure it's not assigned to a TFS group.

	.PARAMETER  ProjectCollectionUri
		Specifies the URL of TFS Project Collection to use.
        The format it expects is: http://{tfs server}:{port}/{instance}/{collectionName}
        
    .PARAMETER  ProjectName
		Specifies the TFS Project to use.

	.EXAMPLE
		PS C:\> Get-TFSGroupPermissionsForArea -ProjectCollectionUri "http://tf:8080/tf/TFcollection" -ProjectName "TestProject1"

	.INPUTS
		System.String,System.String

	.OUTPUTS
		Microsoft.TeamFoundation.Server.AccessControlEntry[]

	.NOTES
		Return the permissions on the team project's Area node, then we checked each of the Access Control Entries (ACE's) to make sure it's not assigned to a windows principal group.

	.LINK
		https://msdn.microsoft.com/en-us/library/microsoft.teamfoundation.server.iauthorizationservice.readaccesscontrollist(v=vs.120).aspx
        https://msdn.microsoft.com/en-us/library/microsoft.teamfoundation.server.accesscontrolentry(v=vs.120).aspx

#>

    #region Parameters.
    [CmdletBinding()]
    param
    (
        [Parameter(ValueFromPipeline=$true, Position=1, HelpMessage="Name of AREA node to de-provision. If not specified, root node would be used.")]
        [string]
        $AreaNodeName,
        
        [parameter(Mandatory, ValueFromPipeline=$true, Position=2, HelpMessage="Name of TFS project collection to use.")]
        [Uri]
        $ProjectCollectionUri,
        
        [parameter(Mandatory, ValueFromPipeline=$true, Position=3, HelpMessage="Name of the TFS Project to use.")]
        [string]
        $ProjectName 
    )
    #endregion
    Begin {
        #Get Team Project Collection
        $teamProjectCollection = [Microsoft.TeamFoundation.Client.TfsTeamProjectCollectionFactory]::GetTeamProjectCollection($ProjectCollectionUri)
        
        #Get Authorization Service
        $authorizationSvc = $teamProjectCollection.GetService([Microsoft.TeamFoundation.Server.IAuthorizationService])
        
        #Get Common Structure Service
        $css = $teamProjectCollection.GetService([Microsoft.TeamFoundation.Server.ICommonStructureService3])
        
        #Get Identity Management Service
        $identitySvc = $teamProjectCollection.GetService([Microsoft.TeamFoundation.Framework.Client.IIdentityManagementService])

        #Get Team Project
        $teamProject = $css.GetProjectFromName("$ProjectName")
        
        # Get Iterations and Areas nodes identity.
        $nodes = $css.ListStructures($teamProject.Uri)
        $areaNode = $nodes | where {$_.Path -eq "\$($teamProject.Name)\Area"}
        if($AreaNodeName) {
            $areaNode = $css.GetNodeFromPath($areaNode.Path + "\$AreaNodeName")
            $areaNodeUri = $areaNode.Uri
        }
        else {
            $areaNodeUri = ([Microsoft.TeamFoundation.PermissionNamespaces]::Project + $areaNode.Uri)
        }
        
        function IsGroupAccessControlEntry
        {
            param 
            (
                $ace
            )
            
            $aceIdentity = $identitySvc.ReadIdentity([Microsoft.TeamFoundation.Framework.Common.IdentitySearchFactor]::Identifier, $ace.Sid, 'Direct', 'None')
            return $aceIdentity.Descriptor.IdentityType -is [System.Security.Principal.WindowsIdentity]
        }
    }
    Process {
        $aces = $authorizationSvc.ReadAccessControlList($areaNodeUri)
        return $aces | Where-Object {-not (IsGroupAccessControlEntry $_) }
    }
    End {}
}

function Get-TFSGroupPermissionsForIteration() {
<#
	.SYNOPSIS
		Returns the permissions on Team Project's root ITERATION node.

	.DESCRIPTION
		The Get-TFSGroupPermissionsForIteration cmdlet return the permissions on specified TF project's root ITERATION node.
        It then check each of the Access Control Entries (ACE's) to make sure it's not assigned to a TFS group.

	.PARAMETER  ProjectCollectionUri
		Specifies the URL of TFS Project Collection to use.
        The format it expects is: http://{tfs server}:{port}/{instance}/{collectionName}
        
    .PARAMETER  ProjectName
		Specifies the TFS Project to use.

	.EXAMPLE
		PS C:\> Get-TFSGroupPermissionsForIteration -ProjectCollectionUri "http://tf:8080/tf/TFcollection" -ProjectName "TestProject1"

	.INPUTS
		System.String,System.String

	.OUTPUTS
		Microsoft.TeamFoundation.Server.AccessControlEntry[]

	.NOTES
		Return the permissions on the team project's Iteration node, then we checked each of the Access Control Entries (ACE's) to make sure it's not assigned to a windows principal group.

	.LINK
		https://msdn.microsoft.com/en-us/library/microsoft.teamfoundation.server.iauthorizationservice.readaccesscontrollist(v=vs.120).aspx
        https://msdn.microsoft.com/en-us/library/microsoft.teamfoundation.server.accesscontrolentry(v=vs.120).aspx

#>

    #region Parameters.
    [CmdletBinding()]
    param
    (
        [Parameter(ValueFromPipeline=$true, Position=1, HelpMessage="Name of ITERATION node to de-provision. If not specified, root node would be used.")]
        [string]
        $IterationNodeName,
        
        [parameter(Mandatory, ValueFromPipeline=$true, Position=2, HelpMessage="Name of TFS project collection to use.")]
        [Uri]
        $ProjectCollectionUri,
        
        [parameter(Mandatory, ValueFromPipeline=$true, Position=3, HelpMessage="Name of the TFS Project to use.")]
        [string]
        $ProjectName 
    )
    #endregion
    Begin {
        #Get Team Project Collection
        $teamProjectCollection = [Microsoft.TeamFoundation.Client.TfsTeamProjectCollectionFactory]::GetTeamProjectCollection($ProjectCollectionUri)
        
        #Get Authorization Service
        $authorizationSvc = $teamProjectCollection.GetService([Microsoft.TeamFoundation.Server.IAuthorizationService])
        
        #Get Common Structure Service
        $css = $teamProjectCollection.GetService([Microsoft.TeamFoundation.Server.ICommonStructureService3])
        
        #Get Identity Management Service
        $identitySvc = $teamProjectCollection.GetService([Microsoft.TeamFoundation.Framework.Client.IIdentityManagementService])

        #Get Team Project
        $teamProject = $css.GetProjectFromName("$ProjectName")
        
        # Get Iterations and Areas nodes identity.
        $nodes = $css.ListStructures($teamProject.Uri)
        $iterationNode = $nodes | where {$_.Path -eq "\$($teamProject.Name)\Iteration"}
        if($IterationNodeName) {
            $iterationNode = $css.GetNodeFromPath($iterationNode.Path + "\$IterationNodeName")
        }
        
        function IsGroupAccessControlEntry
        {
            param 
            (
                $ace
            )
            
            $aceIdentity = $identitySvc.ReadIdentity([Microsoft.TeamFoundation.Framework.Common.IdentitySearchFactor]::Identifier, $ace.Sid, 'Direct', 'None')
            return $aceIdentity.Descriptor.IdentityType -is [System.Security.Principal.WindowsIdentity]
        }
    }
    Process {
        $aces = $authorizationSvc.ReadAccessControlList($iterationNode.Uri)
        return $aces | Where-Object {-not (IsGroupAccessControlEntry $_) }
    }
    End {}
}

function Get-TFSProjectGroupMembership() {
<#
	.SYNOPSIS
		Returns all TFS application groups.

	.DESCRIPTION
		The Get-TFSProjectGroupMembership cmdlet Lists all TFS application groups in the specified scope.
        The scope used is TFS project root.

	.PARAMETER  ProjectCollectionUri
		Specifies the URL of TFS Project Collection to use.
        The format it expects is: http://{tfs server}:{port}/{instance}/{collectionName}
        
    .PARAMETER  ProjectName
		Specifies the TFS Project to use.

	.EXAMPLE
		PS C:\> Get-TFSProjectGroupMembership -ProjectCollectionUri "http://tf:8080/tf/TFcollection" -ProjectName "TestProject1"

	.INPUTS
		System.Uri,System.String

	.OUTPUTS
		Microsoft.TeamFoundation.Framework.Client.TeamFoundationIdentity[]
        Application groups as an array of identities.

	.NOTES
		None.

	.LINK
		https://msdn.microsoft.com/en-us/library/microsoft.teamfoundation.framework.client.iidentitymanagementservice.listapplicationgroups(v=vs.120).aspx

#>

    #region Parameters.
    [CmdletBinding()]
    param
    (
        [parameter(Mandatory, ValueFromPipeline=$true, Position=1, HelpMessage="Name of TFS project collection to use.")]
        [Uri]
        $ProjectCollectionUri,
        
        [parameter(Mandatory, ValueFromPipeline=$true, Position=2, HelpMessage="Name of the TFS Project to enumerate.")]
        [string]
        $ProjectName 
    )
    #endregion
    Begin {
        #Get Team Project Collection
        $teamProjectCollection = [Microsoft.TeamFoundation.Client.TfsTeamProjectCollectionFactory]::GetTeamProjectCollection($ProjectCollectionUri)
        
        #Get Common Structure Service
        $css = $teamProjectCollection.GetService([Microsoft.TeamFoundation.Server.ICommonStructureService3])
        
        #Get Identity Management Service
        $ids = $teamProjectCollection.GetService([Microsoft.TeamFoundation.Framework.Client.IIdentityManagementService])
        
        #Get Team Project
        $teamProject = $css.GetProjectFromName("$ProjectName")
    }
    Process {
        return $ids.ListApplicationGroups($teamProject.Uri, 'ExtendedProperties') 
    }
    End {}
}



function New-TFSGroup() {
<#
	.SYNOPSIS
		Creates a TFS application group.

	.DESCRIPTION
		The New-TFSGroup cmdlet creates a new TFS application group with specified name and description.

	.PARAMETER  GroupName
		Specifies the name of new TFS group to be created.

	.PARAMETER  GroupDescription
		Specifies the description of new TFS group to be created.

	.PARAMETER  ProjectCollectionUri
		Specifies the URL of TFS Project Collection to use.
        The format it expects is: http://{tfs server}:{port}/{instance}/{collectionName}
        
    .PARAMETER  ProjectName
		Specifies the TFS Project to use.
        
    .EXAMPLE
		PS C:\> New-TFSGroup -GroupName 'ReadersGroup' -GroupDescription 'Read-Only users' -ProjectCollectionUri "http://tf:8080/tf/TFcollection" -ProjectName "TestProject1"
        This command adds a TFS group called 'ReadersGroup'  with description as 'Read-Only users' available on http://tf:8080/tf/TFcollection/TestProject1

	.EXAMPLE
		PS C:\> New-TFSGroup -GroupName 'ReadersGroup' -ProjectCollectionUri "http://tf:8080/tf/TFcollection" -ProjectName "TestProject1"
        This command adds a TFS group called 'ReadersGroup' available on http://tf:8080/tf/TFcollection/TestProject1

	.INPUTS
		System.String,System.String, Uri, System.String

	.OUTPUTS
		Microsoft.TeamFoundation.Framework.Client.IdentityDescriptor
        IdentityDescriptor of the created group

	.NOTES
		If group with specified name already exists, this cmdlet would throw warning message.

	.LINK
		https://msdn.microsoft.com/en-us/library/microsoft.teamfoundation.framework.client.iidentitymanagementservice.createapplicationgroup(v=vs.120).aspx

#>

    #region Parameters.
    [CmdletBinding()]
    param
    (
        [Parameter(Mandatory, ValueFromPipeline=$true, Position=1)]
        [ValidateLength(1,255)]
        [string]
        $GroupName,
        
        [Parameter(ValueFromPipeline=$true, Position=2)]
        [ValidateLength(1,1024)]
        [string]
        $GroupDescription,
        
        [parameter(Mandatory, ValueFromPipeline=$true, Position=3, HelpMessage="Name of TFS project collection to use.")]
        [Uri]
        $ProjectCollectionUri,
        
        [parameter(Mandatory, ValueFromPipeline=$true, Position=4, HelpMessage="Name of the TFS Project under which group needs to be added.")]
        [ValidateLength(1,255)]
        [string]
        $ProjectName 
    )
    #endregion
    Begin {
        #Get Team Project Collection
        $teamProjectCollection = [Microsoft.TeamFoundation.Client.TfsTeamProjectCollectionFactory]::GetTeamProjectCollection($ProjectCollectionUri)
        
        #Get Common Structure Service
        $css = $teamProjectCollection.GetService([Microsoft.TeamFoundation.Server.ICommonStructureService3])
        
        #Get Identity Management Service
        $ids = $teamProjectCollection.GetService([Microsoft.TeamFoundation.Framework.Client.IIdentityManagementService])
        
        #Get Team Project
        $teamProject = $css.GetProjectFromName("$ProjectName")
        $matchedGroup = $null
    }
    Process {
        try {
            $currentGroups = Get-TFSProjectGroupMembership -ProjectCollectionUri "$ProjectCollectionUri" -ProjectName "$ProjectName"
            if($currentGroups -ne $null) {
                $matchedGroup = $currentGroups | where-object {(($_.DisplayName -ilike "[$ProjectName]\$GroupName") -eq $true)}
            }
            
            if($matchedGroup -eq $null) {
                return $ids.CreateApplicationGroup($teamProject.Uri, "$GroupName", $GroupDescription)
                Write-Verbose -Message "$GroupName group added to TFS."
            }
            else {
                Write-Warning -Message "A group named $GroupName already exists in scope $ProjectName."
            }
        }
        catch {
            Write-error -Message "$GroupName couldnot be added. $_"
        }
    }
    End {}
}

function New-TFSTeam {
    #region Parameters.
    [CmdletBinding()]
    param
    (
        [Parameter(Mandatory, ValueFromPipeline=$true, Position=1)]
        [ValidateLength(1,255)]
        [string]
        $TeamName,
        
        [Parameter(ValueFromPipeline=$true, Position=2)]
        [ValidateLength(1,1024)]
        [string]
        $TeamDescription,
        
        [Parameter(ValueFromPipeline=$true, Position=3)]
        [string[]]
        $MemberNames,
        
        [parameter(Mandatory, ValueFromPipeline=$true, Position=4, HelpMessage="Name of TFS project collection to use.")]
        [Uri]
        $ProjectCollectionUri,
        
        [parameter(Mandatory, ValueFromPipeline=$true, Position=5, HelpMessage="Name of the TFS Project under which group needs to be added.")]
        [ValidateLength(1,255)]
        [string]
        $ProjectName 
    )
    #endregion
    Begin {
        #Get Team Project Collection
        $teamProjectCollection = [Microsoft.TeamFoundation.Client.TfsTeamProjectCollectionFactory]::GetTeamProjectCollection($ProjectCollectionUri)
        
        #Get Common Structure Service
        $css = $teamProjectCollection.GetService([Microsoft.TeamFoundation.Server.ICommonStructureService3])
        
        #Get Team Project
        $teamProject = $css.GetProjectFromName("$ProjectName")
        
        # Get TeamService
        $teamService = $teamProjectCollection.GetService([Microsoft.TeamFoundation.Client.TfsTeamService])
    }
    Process {
        try {
            $currentTeams = $teamService.QueryTeams($teamProject.Uri)
            $targetTeam = ($currentTeams | Where-Object {$_.Name -eq "$TeamName"})
            if($targetTeam) {
                Write-Warning -Message "$TeamName team already exists."
            }
            else {
                $targetTeam = $teamService.CreateTeam($teamProject.Uri, $TeamName, $TeamDescription, $null)
                Write-Verbose -Message "$TeamName team created."
            }
            
            # add members to team.
            Add-TFSMembersToGroup -GroupName "$TeamName" -ProjectCollectionUri $ProjectCollectionUri -ProjectName $ProjectName -MemberNames $MemberNames
            
            # add area node for this team.
            $newAreaNode = Add-TFSAreaNode -AreaNodeName "$TeamName" -ProjectCollectionUri $ProjectCollectionUri -ProjectName $ProjectName
            
            # add Iteration node for this team.
            $newIterationNode = Add-TFSIterationNode -IterationNodeName "$TeamName" -ProjectCollectionUri $ProjectCollectionUri -ProjectName $ProjectName
            return $targetTeam
        }
        catch {
            Write-error -Message "$TeamName couldnot be added. $_"
        }
    }
    End {}
}

function New-TFSVersionControlBranch() {
<#
	.SYNOPSIS
		Creates a new branch from an existing parent branch object in TFS.

	.DESCRIPTION
		The New-TFSVersionControlBranch cmdlet creates a branch on the server and checks it in without downloading the branch to the client.

	.PARAMETER  BranchObject
		Hashtable with key/values representing the request for new branch properties:
        -- Name: name of new branch to be created
        -- ParentBranchName: name of source branch from which a new branch to be create
        -- Owner:  owner of new branch
        -- Description: description of new branch
        

	.PARAMETER  ProjectCollectionUri
		Specifies the URL of TFS Project Collection to use.
        The format it expects is: http://{tfs server}:{port}/{instance}/{collectionName}
        
    .PARAMETER  ProjectName
		Specifies the TFS Project to use.

	.EXAMPLE
		PS C:\> New-TFSVersionControlBranch 
            -BranchObject "@{'Name='Dev','ParentBranchName'='Main','Owner'='[TEAM FOUNDATION]\Team Foundation Administrators','Description'='Child code promotion branch of Main for integration test of ongoing development.'}" 
            -ProjectCollectionUri "http://tf:8080/tf/TFcollection" 
            -ProjectName "TestProject1"

	.INPUTS
		System.HashTable,System.Uri,String

	.OUTPUTS
		System.Int
        Changeset number of the new branch created in TFS.

	.NOTES
		If target branch already exists, no action is performed.

	.LINK
		https://msdn.microsoft.com/en-us/library/ff735064(v=vs.120).aspx

#>

    #region Parameters.
    [CmdletBinding()]
    param
    (
        [Parameter(Mandatory, ValueFromPipeline=$true, Position=1, HelpMessage="A hashtable containing Branch details like Name, Owner, Description, IsRoot, ParentBranchName.")]
        [ValidateScript({
            if($_.ContainsKey('Name')){
                $true
            }
            else {
                throw "$_ must contain Name property."
            }
            if($_.ContainsKey('ParentBranchName')){
                $true
            }
            else {
                throw "$_ must contain ParentBranchName property."
            }
            if($_.ContainsKey('Owner')){
                $true
            }
            else {
                throw "$_ must contain Owner property."
            }
            if($_.ContainsKey('Description')){
                $true
            }
            else {
                throw "$_ must contain Description property."
            }
        })]
        [Hashtable]
        $BranchObject,
        
        [parameter(Mandatory, ValueFromPipeline=$true, Position=2, HelpMessage="Name of TFS project collection to use.")]
        [Uri]
        $ProjectCollectionUri,
        
        [parameter(Mandatory, ValueFromPipeline=$true, Position=3, HelpMessage="Name of the TFS Project under which this custom folders needs to be added.")]
        [string]
        $ProjectName 
    )
    #endregion
    Begin {
        $teamProjectCollection = [Microsoft.TeamFoundation.Client.TfsTeamProjectCollectionFactory]::GetTeamProjectCollection($ProjectCollectionUri)
        
        # Get Version control service.
        $vcs = $teamProjectCollection.GetService([Microsoft.TeamFoundation.VersionControl.Client.VersionControlServer])
        
        # Get the TFS security service.
        $sec = $teamProjectCollection.GetService([Microsoft.TeamFoundation.Framework.Client.ISecurityService])
        $vcSecurityNamespace = $sec.GetSecurityNamespace([Microsoft.TeamFoundation.VersionControl.Common.SecurityConstants]::RepositorySecurityNamespaceGuid)
        
        # Get Team project.
        $teamProject = $vcs.GetTeamProject("$ProjectName")
    }
    Process {
        $targetServerPath = $teamProject.ServerItem + "/$($BranchObject.Name)"
        $sourceServerPath = $teamProject.ServerItem + "/$($BranchObject.ParentBranchName)"
        $branches = $vcs.QueryBranchObjects((New-Object Microsoft.TeamFoundation.VersionControl.Client.ItemIdentifier("$targetServerPath")), [Microsoft.TeamFoundation.VersionControl.Client.RecursionType]::None)
        if(($branches -eq $null) -or (($branches -is [Array]) -and ($branches.Count -le 0))) {
            [Microsoft.TeamFoundation.VersionControl.Client.CheckinNoteFieldValue[]]$fieldValues = @()
            $fieldValues += New-Object Microsoft.TeamFoundation.VersionControl.Client.CheckinNoteFieldValue("Comment", "Branched $($BranchObject.Name) off $($BranchObject.ParentBranchName)")
            $checkinNote = New-Object Microsoft.TeamFoundation.VersionControl.Client.CheckinNote($fieldValues)
            $changesetNo = $vcs.CreateBranch("$sourceServerPath", "$targetServerPath", [Microsoft.TeamFoundation.VersionControl.Client.VersionSpec]::Latest, "$($BranchObject.Owner)", "$($BranchObject.Description)", $checkinNote, $null, $null)
            #   If you are not happy with default check-in comments, un-comment the following 3 lines.
            #   $changeset = $vcs.GetChangeset($changesetNo)
            #   $changeset.Comment = $fieldValues[0].Value
            #   $changeset.Update()
            Write-Verbose -Message "$targetServerPath branched off $sourceServerPath."
        }
    }
    End {}
}

function New-TFSVersionControlFolder() {
<#
	.SYNOPSIS
		Adds a new folder in TF version control server.

	.DESCRIPTION
		The New-TFSVersionControlFolder cmdlet checks to see if the item of the specified path and type exists in the repository. And if not, adds it.       

	.PARAMETER  FolderName
		Specifies the folder name to create.

	.PARAMETER  ProjectCollectionUri
		Specifies the URL of TFS Project Collection to use.
        The format it expects is: http://{tfs server}:{port}/{instance}/{collectionName}
        
    .PARAMETER  ProjectName
		Specifies the TFS Project to use.

	.EXAMPLE
		PS C:\> New-TFSVersionControlFolder -FolderName 'Main' -ProjectCollectionUri "http://tf:8080/tf/TFcollection" -ProjectName "TestProject1"
        This command adds a folder called 'Main' available on $/TestProject1/

	.INPUTS
		System.String,Uri,System.String

	.OUTPUTS
		None.

	.NOTES
		If the specified folder already exists, Warning message is thrown by this cmdlet.
        A temporary workspace (Temp_TFS_Admin_Workspace) is created for this purpose which is deleted when action is complete.
        Local folder mapped for this workspace is C:\Temp\Workspaces\USERNAME\PRJ\teamProject"

	.LINK
		https://msdn.microsoft.com/en-us/library/microsoft.teamfoundation.versioncontrol.client.versioncontrolserver.serveritemexists(v=vs.120).aspx
        https://msdn.microsoft.com/en-us/library/microsoft.teamfoundation.versioncontrol.client.versioncontrolserver.createworkspace(v=vs.120).aspx

#>


    #region Parameters.
    [CmdletBinding()]
    param
    (
        [Parameter(Mandatory, ValueFromPipeline=$true, Position=1)]
        [ValidateLength(1,255)]
        [string]
        $FolderName,
        
        [parameter(Mandatory, ValueFromPipeline=$true, Position=2, HelpMessage="Name of TFS project collection to use.")]
        [Uri]
        $ProjectCollectionUri,
        
        [parameter(Mandatory, ValueFromPipeline=$true, Position=3, HelpMessage="Name of the TFS Project under which this custom folders needs to be added.")]
        [string]
        $ProjectName 
    )
    #endregion
    Begin {
        $teamProjectCollection = [Microsoft.TeamFoundation.Client.TfsTeamProjectCollectionFactory]::GetTeamProjectCollection($ProjectCollectionUri)
        
        # Get Version control service.
        $vcs = $teamProjectCollection.GetService([Microsoft.TeamFoundation.VersionControl.Client.VersionControlServer])
        
        # Get the TFS security service.
        $sec = $teamProjectCollection.GetService([Microsoft.TeamFoundation.Framework.Client.ISecurityService])
        $vcSecurityNamespace = $sec.GetSecurityNamespace([Microsoft.TeamFoundation.VersionControl.Common.SecurityConstants]::RepositorySecurityNamespaceGuid)
        
        # Get Team project.
        $teamProject = $vcs.GetTeamProject("$ProjectName")
    }
    Process {
        $sourceServerPath = $teamProject.ServerItem + "/$FolderName"
        $folderExists = $vcs.ServerItemExists("$sourceServerPath", [Microsoft.TeamFoundation.VersionControl.Client.ItemType]::Folder)
        if($folderExists -eq $false) {
            $localFolder = "C:\Temp\Workspaces\" + $Env:USERNAME + "\PRJ\$($teamProject.Name)"
            $workspaceName = "Temp_TFS_Admin_Workspace"
            #$tempWorkspace = $vcs.GetWorkspace($workspaceName, $Env:USERNAME) # This throws exception if not found.
            $tempWorkspace = $vcs.TryGetWorkspace($localFolder)
            $workingFolder = New-Object Microsoft.TeamFoundation.VersionControl.Client.WorkingFolder($teamProject.ServerItem, "$localFolder", [Microsoft.TeamFoundation.VersionControl.Client.WorkingFolderType]::Map, [Microsoft.TeamFoundation.VersionControl.Client.RecursionType]::Full)
            if($tempWorkspace -eq $null) {
                [Microsoft.TeamFoundation.VersionControl.Client.WorkingFolder[]]$workingFolders = @($workingFolder)
                $tempWorkspace = $vcs.CreateWorkspace($workspaceName, $Env:USERNAME, "Temporary workspace for TFS admin created for new TFS project setup.", $workingFolders)
                Write-Verbose -Message "Temporary workspace created - $workspaceName at $localFolder"
            }
            $tempWorkspace.Get()
            if(!(Test-Path -LiteralPath "$localFolder\$FolderName")) {
                New-Item "$localFolder\$FolderName" -type directory
            }
            $tempWorkspace.PendAdd("$localFolder\$FolderName")
            $pendingChange = $tempWorkspace.GetPendingChanges()
            $tempWorkspace.CheckIn($pendingChange, "Created $FolderName branch folder.")
            Write-Verbose -Message "$FolderName folder added to TFS."
            $tempWorkspace.DeleteMapping($workingFolder)
            $tempWorkspace.Delete()
            Write-Verbose -Message "Temporary workspace deleted - $workspaceName at $localFolder"
        }
        else {
            Write-Warning -Message "$sourceServerPath folder already exists under $ProjectName"
        }
    }
    End {}
}

function New-TFSWorkItemQueryFolder() {
<#
	.SYNOPSIS
		Adds the specified query item to Project's "Shared Queries" folder.

	.DESCRIPTION
		The New-TFSWorkItemQueryFolder cmdlet adds a new query folder under "Shared Queries" folder.

	.PARAMETER  FolderName
		Specifies the name of folder to create under "Shared Queries" folder.

	.PARAMETER  ProjectCollectionUri
		Specifies the URL of TFS Project Collection to use.
        The format it expects is: http://{tfs server}:{port}/{instance}/{collectionName}
        
    .PARAMETER  ProjectName
		Specifies the TFS Project to use.

	.EXAMPLE
		PS C:\> New-TFSWorkItemQueryFolder -FolderName 'Custom Queries' -ProjectCollectionUri "http://tf:8080/tf/TFcollection" -ProjectName "TestProject1"
        This command adds a folder called 'Custom Queries' under "Shared Queries" folder available on http://tf:8080/tf/TFcollection/TestProject1

	.INPUTS
		System.String,Uri,System.String

	.OUTPUTS
		[Microsoft.TeamFoundation.WorkItemTracking.Client.QueryItem]

	.NOTES
		This cmdlet returns Query Item folder instance.
        If the specified folder already exists, it returns that one. Or else, it creates one and returns its reference.

	.LINK
		https://msdn.microsoft.com/en-us/library/microsoft.teamfoundation.workitemtracking.client.queryhierarchy(v=vs.120).aspx

#>

    #region Parameters.
    [CmdletBinding()]
    param
    (
        [Parameter(Mandatory, ValueFromPipeline=$true, Position=1)]
        [ValidateLength(1,255)]
        [string]
        $FolderName,
        
        [parameter(Mandatory, ValueFromPipeline=$true, Position=2, HelpMessage="Name of TFS project collection to use.")]
        [Uri]
        $ProjectCollectionUri,
        
        [parameter(Mandatory, ValueFromPipeline=$true, Position=3, HelpMessage="Name of the TFS Project under which this custom folders needs to be added.")]
        [string]
        $ProjectName 
    )
    #endregion
    Begin {
        $parentFolder = "Shared Queries"
        $teamProjectCollection = [Microsoft.TeamFoundation.Client.TfsTeamProjectCollectionFactory]::GetTeamProjectCollection($ProjectCollectionUri)
        #Get Work Item Store object
        #$wiStore = $teamProjectCollection.GetService([Microsoft.TeamFoundation.WorkItemTracking.Client.WorkItemStore])
        $wiStore = New-Object Microsoft.TeamFoundation.WorkItemTracking.Client.WorkItemStore($teamProjectCollection)
        $teamProject = $wiStore.Projects["$ProjectName"]
        [Microsoft.TeamFoundation.WorkItemTracking.Client.QueryHierarchy]$queryHiearachy = $teamProject.QueryHierarchy
    }
    Process {
        try {
            if($queryHiearachy -ne $null) {
                $parentFolder = $queryHiearachy.get_Item($parentFolder)
                if($parentFolder.Contains("$FolderName") -eq $false) {
                    [Microsoft.TeamFoundation.WorkItemTracking.Client.QueryFolder]$customQueryItem = New-Object Microsoft.TeamFoundation.WorkItemTracking.Client.QueryFolder("$FolderName", $parentFolder)
                    #$queryHiearachy.Add($customQueryItem)
                    $queryHiearachy.Save()
                    Write-Verbose -Message "$FolderName folder added under $parentFolder."
                }
                else {
                    Write-warning -Message "$FolderName folder already exists under $parentFolder."
                }
                return $parentFolder.get_Item($FolderName)
            }
            else {
                Write-Warning -Message "QueryHierarchy couldn't be retrived of $ProjectName hence $FolderName couldnot be added."
            }
        }
        catch {
            Write-error -Message "$FolderName could not be added. $_"
        }
    }
    End {}
}

function Remove-TFSMembersFromGroup() {
<#
	.SYNOPSIS
		Removes members from TFS application group.

	.DESCRIPTION
		The Remove-TFSMembersFromGroup cmdlet removes members from specified TFS application group.
        There is an optional parameter for MemberNamesToKeep where you can speicify the members which needs to be excluded from delete operation.

	.PARAMETER  GroupName
		Specifies the name of TFS application group whose members needs to be deleted.

	.PARAMETER  MemberNamesToKeep
		Specifies the name of members which you need to keep and exclude from delete operation.

	.PARAMETER  ProjectCollectionUri
		Specifies the URL of TFS Project Collection to use.
        The format it expects is: http://{tfs server}:{port}/{instance}/{collectionName}
        
    .PARAMETER  ProjectName
		Specifies the TFS Project to use.
        
    .EXAMPLE
		PS C:\> Remove-TFSMembersFromGroup -GroupName 'Administrator' -ProjectCollectionUri "http://tf:8080/tf/TFcollection" -ProjectName "TestProject1"
        This command removes all members of 'Administrators' group available on http://tf:8080/tf/TFcollection/TestProject1

	.EXAMPLE
		PS C:\> Remove-TFSMembersFromGroup -GroupName 'Administrator' MemberNamesToKeep "@('sam')" -ProjectCollectionUri "http://tf:8080/tf/TFcollection" -ProjectName "TestProject1"
        This command removes all members of 'Administrators' group except 'Sam' available on http://tf:8080/tf/TFcollection/TestProject1

	.INPUTS
		System.String,System.String[],Uri,System.String

	.OUTPUTS
		System.String

	.NOTES
		NOne.

	.LINK
        Get-NameBySid
		https://msdn.microsoft.com/en-us/library/dn239100(v=vs.120).aspx

#>

    #region Parameters.
    [CmdletBinding()]
    param
    (
        [Parameter(Mandatory, ValueFromPipeline=$true, Position=1)]
        [string]
        $GroupName,
        
        [Parameter(ValueFromPipeline=$true, Position=2)]
        [string[]]
        $MemberNamesToKeep,
        
        [parameter(Mandatory, ValueFromPipeline=$true, Position=3, HelpMessage="Name of TFS project collection to use.")]
        [Uri]
        $ProjectCollectionUri,
        
        [parameter(Mandatory, ValueFromPipeline=$true, Position=4, HelpMessage="Name of the TFS Project to use.")]
        [string]
        $ProjectName 
    )
    #endregion
    Begin { 
        $currentGroups = Get-TFSProjectGroupMembership -ProjectCollectionUri $ProjectCollectionUri -ProjectName $ProjectName
        $tfsGroup = ($currentGroups | Where-Object {$_.DisplayName -eq "[$ProjectName]\$GroupName"})
        $currentGroupMemberIdentityDescriptors = Get-TFSGroupMembers -ProjectCollectionUri $ProjectCollectionUri -ProjectName $ProjectName -GroupName $GroupName -IdentityOnly $true
        #Get Team Project Collection
        $teamProjectCollection = [Microsoft.TeamFoundation.Client.TfsTeamProjectCollectionFactory]::GetTeamProjectCollection($ProjectCollectionUri)
        
        #Get Identity Management Service
        $ids = $teamProjectCollection.GetService([Microsoft.TeamFoundation.Framework.Client.IIdentityManagementService])
    }
    Process {
        foreach ($currentMember in @($currentGroupMemberIdentityDescriptors))
        {
            try {
				$displayName = Get-NameBySid $currentMember.Identifier $true
	            if ($MemberNamesToKeep -notcontains $displayName)
	            {
	                $ids.RemoveMemberFromApplicationGroup($tfsGroup.Descriptor, $currentMember)
	                Write-Verbose "Removed Member: $displayName from $GroupName"
	            }
			}
			catch {
				Write-Error -Message "Members could not be removed from $GroupName group. $_"
			}
        }
    }
    End {}
}

function Remove-TFSGroupPermissionsFromArea() {
<#
	.SYNOPSIS
		Removes current permissions from TFS project's root AREA node.

	.DESCRIPTION
		The Remove-TFSGroupPermissionsFromArea cmdlet removes all existing ACEs from specified TFS project root AREA node.

	.PARAMETER  ProjectCollectionUri
		Specifies the URL of TFS Project Collection to use.
        The format it expects is: http://{tfs server}:{port}/{instance}/{collectionName}
        
    .PARAMETER  ProjectName
		Specifies the TFS Project to use.

	.EXAMPLE
		PS C:\> Remove-TFSGroupPermissionsFromArea -ProjectCollectionUri "http://tf:8080/tf/TFcollection" -ProjectName "TestProject1"
        This command removes all access control entries of root AREA node available on http://tf:8080/tf/TFcollection/TestProject1

	.INPUTS
		System.String,System.String

	.OUTPUTS
		None.

	.NOTES
		None.

	.LINK
		Get-TFSGroupPermissionsForArea

	.LINK
		https://msdn.microsoft.com/en-us/library/microsoft.teamfoundation.server.iauthorizationservice.removeaccesscontrolentry(v=vs.120).aspx

#>

    #region Parameters.
    [CmdletBinding()]
    param
    (
        [Parameter(ValueFromPipeline=$true, Position=1, HelpMessage="Name of AREA node to de-provision. If not specified, root node would be used.")]
        [string]
        $AreaNodeName,
        
        [parameter(Mandatory, ValueFromPipeline=$true, Position=2, HelpMessage="Name of TFS project collection to use.")]
        [Uri]
        $ProjectCollectionUri,
        
        [parameter(Mandatory, ValueFromPipeline=$true, Position=3, HelpMessage="Name of the TFS Project to use.")]
        [string]
        $ProjectName 
    )
    #endregion
    Begin {
        #Get Team Project Collection
        $teamProjectCollection = [Microsoft.TeamFoundation.Client.TfsTeamProjectCollectionFactory]::GetTeamProjectCollection($ProjectCollectionUri)
        
        #Get Authorization Service
        $authorizationSvc = $teamProjectCollection.GetService([Microsoft.TeamFoundation.Server.IAuthorizationService])
        
        #Get Common Structure Service
        $css = $teamProjectCollection.GetService([Microsoft.TeamFoundation.Server.ICommonStructureService3])
        
        #Get Team Project
        $teamProject = $css.GetProjectFromName("$ProjectName")
    }
    Process {
        try {
            # Get Iterations and Areas nodes identity.
            $nodes = $css.ListStructures($teamProject.Uri)
            $rootAreaNode = $nodes | where {$_.Path -eq "\$($teamProject.Name)\Area"}
            if($AreaNodeName) {
                $rootAreaNode = $css.GetNodeFromPath($rootAreaNode.Path + "\$AreaNodeName")
            }
            
            $rootAreaNodeUri = ([Microsoft.TeamFoundation.PermissionNamespaces]::Project + $rootAreaNode.Uri)
            foreach ($ace in (Get-TFSGroupPermissionsForArea -AreaNodeName $AreaNodeName -ProjectCollectionUri $ProjectCollectionUri -ProjectName $ProjectName))
            {
                $authorizationSvc.RemoveAccessControlEntry($rootAreaNodeUri, $ace)
                Write-Verbose -Message "Removed ACE from $rootAreaNodeUri"
            }
        }
        catch {
            Write-Error -Message "Permissions could not be remove from Area node of $ProjectName. $_"
        }
    }
    End {}
}

function Remove-TFSGroupPermissionsFromIteration() {
<#
	.SYNOPSIS
		Removes current permissions from TFS project's root ITERATION node.

	.DESCRIPTION
		The Remove-TFSGroupPermissionsFromIteration cmdlet removes all existing ACEs from specified TFS project root ITERATION node.

	.PARAMETER  ProjectCollectionUri
		Specifies the URL of TFS Project Collection to use.
        The format it expects is: http://{tfs server}:{port}/{instance}/{collectionName}
        
    .PARAMETER  ProjectName
		Specifies the TFS Project to use.

	.EXAMPLE
		PS C:\> Remove-TFSGroupPermissionsFromIteration -ProjectCollectionUri "http://tf:8080/tf/TFcollection" -ProjectName "TestProject1"
        This command removes all access control entries of root ITERATION node available on http://tf:8080/tf/TFcollection/TestProject1

	.INPUTS
		System.String,System.String

	.OUTPUTS
		None.

	.NOTES
		None.

	.LINK
		Get-TFSGroupPermissionsForIteration

	.LINK
		https://msdn.microsoft.com/en-us/library/microsoft.teamfoundation.server.iauthorizationservice.removeaccesscontrolentry(v=vs.120).aspx

#>
    #region Parameters.
    [CmdletBinding()]
    param
    (
        [Parameter(ValueFromPipeline=$true, Position=1, HelpMessage="Name of ITERATION node to de-provision. If not specified, root node would be used.")]
        [string]
        $IterationNodeName,
        
        [parameter(Mandatory, ValueFromPipeline=$true, Position=2, HelpMessage="Name of TFS project collection to use.")]
        [Uri]
        $ProjectCollectionUri,
        
        [parameter(Mandatory, ValueFromPipeline=$true, Position=3, HelpMessage="Name of the TFS Project to use.")]
        [string]
        $ProjectName 
    )
    #endregion
    Begin {
        #Get Team Project Collection
        $teamProjectCollection = [Microsoft.TeamFoundation.Client.TfsTeamProjectCollectionFactory]::GetTeamProjectCollection($ProjectCollectionUri)
        
        #Get Authorization Service
        $authorizationSvc = $teamProjectCollection.GetService([Microsoft.TeamFoundation.Server.IAuthorizationService])
        
        #Get Common Structure Service
        $css = $teamProjectCollection.GetService([Microsoft.TeamFoundation.Server.ICommonStructureService3])
        
        #Get Team Project
        $teamProject = $css.GetProjectFromName("$ProjectName")
    }
    Process {
        try {
            # Get Iterations and Areas nodes identity.
            $nodes = $css.ListStructures($teamProject.Uri)
            $iterationNode = $nodes | where {$_.Path -eq "\$($teamProject.Name)\Iteration"}
            if($IterationNodeName) {
                $iterationNode = $css.GetNodeFromPath($iterationNode.Path + "\$IterationNodeName")
            }
            
            foreach ($ace in (Get-TFSGroupPermissionsForIteration -IterationNodeName $IterationNodeName -ProjectCollectionUri $ProjectCollectionUri -ProjectName $ProjectName))
            {
                $authorizationSvc.RemoveAccessControlEntry($iterationNode.Uri, $ace)
                Write-Verbose -Message "Removed ACE from $($iterationNode.Uri)"
            }
        }
        catch {
            Write-Error -Message "Permissions could not be removed from Iteration node of $ProjectName. $_"
        }
    }
    End {}
}

function Set-TFSGroupPermissions() {
<#
	.SYNOPSIS
		Sets the permissions for specified TFS application group.

	.DESCRIPTION
		The Set-TFSGroupPermissions cmdlet configures the specified TFS application group for specified permissions.

	.PARAMETER  GroupName
		Specifies the TFS application group whose permissions needs to be configured.

	.PARAMETER  ProjectPermissions
		Specifies the permissions which needs to be configured for a TFS application group.
        Valid project permissions are limited to:
        -- GENERIC_READ
        -- GENERIC_WRITE
        -- DELETE
        -- PUBLISH_TEST_RESULTS
        -- ADMINISTER_BUILD
        -- START_BUILD
        -- EDIT_BUILD_STATUS
        -- UPDATE_BUILD
        -- DELETE_TEST_RESULTS
        -- VIEW_TEST_RESULTS
        -- MANAGE_TEST_ENVIRONMENTS
        -- MANAGE_TEST_CONFIGURATIONS

	.PARAMETER  ProjectCollectionUri
		Specifies the URL of TFS Project Collection to use.
        The format it expects is: http://{tfs server}:{port}/{instance}/{collectionName}
        
    .PARAMETER  ProjectName
		Specifies the TFS Project to use.
        
    .EXAMPLE
		PS C:\> Set-TFSGroupPermissions -GroupName 'Administrator' -ProjectPermissions "@('PUBLISH_TEST_RESULTS','VIEW_TEST_RESULTS','GENERIC_READ')" -ProjectCollectionUri "http://tf:8080/tf/TFcollection" -ProjectName "TestProject1"
        This command sets Administrator group permissions to 'PUBLISH_TEST_RESULTS','VIEW_TEST_RESULTS','GENERIC_READ' available on http://tf:8080/tf/TFcollection/TestProject1

	.INPUTS
		System.String,System.String[],Uri,System.String

	.OUTPUTS
		None.

	.NOTES
		None.

	.LINK
		Get-TFSProjectGroupMembership

	.LINK
		https://msdn.microsoft.com/en-us/library/microsoft.teamfoundation.server.iauthorizationservice.addaccesscontrolentry(v=vs.120).aspx

#>

    #region Parameters.
    [CmdletBinding()]
    param
    (
        [Parameter(Mandatory, ValueFromPipeline=$true, Position=1)]
        [string]
        $GroupName,
        
        [Parameter(ValueFromPipeline=$true, Position=2)]
        [ValidateSet('GENERIC_READ','GENERIC_WRITE','DELETE','PUBLISH_TEST_RESULTS','ADMINISTER_BUILD','START_BUILD','EDIT_BUILD_STATUS','UPDATE_BUILD','DELETE_TEST_RESULTS','VIEW_TEST_RESULTS','MANAGE_TEST_ENVIRONMENTS','MANAGE_TEST_CONFIGURATIONS')]
        [string[]]
        $ProjectPermissions,
        
        [parameter(Mandatory, ValueFromPipeline=$true, Position=3, HelpMessage="Name of TFS project collection to use.")]
        [Uri]
        $ProjectCollectionUri,
        
        [parameter(Mandatory, ValueFromPipeline=$true, Position=4, HelpMessage="Name of the TFS Project to use.")]
        [string]
        $ProjectName 
    )
    #endregion
    Begin {
        #Get Team Project Collection
        $teamProjectCollection = [Microsoft.TeamFoundation.Client.TfsTeamProjectCollectionFactory]::GetTeamProjectCollection($ProjectCollectionUri)
        
        #Get Authorization Service
        $auth = $teamProjectCollection.GetService([Microsoft.TeamFoundation.Server.IAuthorizationService])
        
        #Get Common Structure Service
        $css = $teamProjectCollection.GetService([Microsoft.TeamFoundation.Server.ICommonStructureService3])
        
        $teamProject = $css.GetProjectFromName("$ProjectName")
        $teamProjectPermissionUri = [Microsoft.TeamFoundation.PermissionNamespaces]::Project + $teamProject.Uri
        
        # Get current project groups
        $currentGroups = Get-TFSProjectGroupMembership -ProjectCollectionUri $ProjectCollectionUri -ProjectName $ProjectName
    }
    Process {
        try {
            $tfsGroup = ($currentGroups | Where-Object {$_.DisplayName -eq "[$ProjectName]\$GroupName"})
            if($tfsGroup -ne $null) {
                foreach ($permissionName in $ProjectPermissions)
                {
                    if($tfsGroup -is [Microsoft.TeamFoundation.Framework.Client.IdentityDescriptor] -eq $true) {
                        $ace = New-Object Microsoft.TeamFoundation.Server.AccessControlEntry($permissionName, $tfsGroup.Identifier, $false)
                    }
                    else {
                        $ace = New-Object Microsoft.TeamFoundation.Server.AccessControlEntry($permissionName, $tfsGroup.Descriptor.Identifier, $false)
                    }
                    $auth.AddAccessControlEntry($teamProjectPermissionUri, $ace)
                    Write-Verbose -Message "Added $permissionName ACE for $GroupName under $teamProjectPermissionUri"
                }
            }
            else {
                 Write-Error -Message "Could not provision $GroupName on $ProjectName. $_"
            }
        }
        catch {
            Write-Error -Message "Could not provision $GroupName on $ProjectName. $_"
        }
    }
    End {}
}

function Set-TFSGroupPermissionsForArea() {
<#
	.SYNOPSIS
		Sets permissions for TFS project's root AREA node.

	.DESCRIPTION
		The Set-TFSGroupPermissionsForArea cmdlet configures ACEs for specified TFS project root AREA node.

	.PARAMETER  GroupName
		Specifies the TFS application group which needs to be provisioned on specified TFS project root AREA node.

	.PARAMETER  Permissions
		Specifies the permissions which needs to be configured for a TFS application group on specified TFS project root AREA node.
        Valid permissions are limited to:
        -- GENERIC_READ
        -- GENERIC_WRITE
        -- CREATE_CHILDREN
        -- DELETE
        -- WORK_ITEM_READ
        -- WORK_ITEM_WRITE
        -- MANAGE_TEST_PLANS
        -- MANAGE_TEST_SUITES

	.PARAMETER  ProjectCollectionUri
		Specifies the URL of TFS Project Collection to use.
        The format it expects is: http://{tfs server}:{port}/{instance}/{collectionName}
        
    .PARAMETER  ProjectName
		Specifies the TFS Project to use.
        
    .EXAMPLE
		PS C:\> Set-TFSGroupPermissionsForArea -GroupName 'Administrator' -Permissions "@('GENERIC_READ','CREATE_CHILDREN','MANAGE_TEST_PLANS')" -ProjectCollectionUri "http://tf:8080/tf/TFcollection" -ProjectName "TestProject1"
        This command sets Administrator group permissions to 'GENERIC_READ','CREATE_CHILDREN','MANAGE_TEST_PLANS' available on http://tf:8080/tf/TFcollection/TestProject1 AREA node.

	.INPUTS
		System.String,System.String[],Uri,System.String

	.OUTPUTS
		None.

	.NOTES
		None.

	.LINK
		https://msdn.microsoft.com/en-us/library/microsoft.teamfoundation.server.iauthorizationservice.addaccesscontrolentry(v=vs.120).aspx

#>

    #region Parameters.
    [CmdletBinding()]
    param
    (
        [Parameter(Mandatory, ValueFromPipeline=$true, Position=1)]
        [string]
        $GroupName,
        
        [parameter(Mandatory, ValueFromPipeline=$true, Position=2, HelpMessage="Permissions to configure for root Area node of the TFS project.")]
        [ValidateSet('GENERIC_READ','GENERIC_WRITE','CREATE_CHILDREN','DELETE','WORK_ITEM_READ','WORK_ITEM_WRITE','MANAGE_TEST_PLANS','MANAGE_TEST_SUITES')]
        [string[]]
        $Permissions,
        
        [Parameter(ValueFromPipeline=$true, Position=3, HelpMessage="Name of AREA node to provision. If not specified, root node would be used.")]
        [string]
        $AreaNodeName,
        
        [parameter(Mandatory, ValueFromPipeline=$true, Position=4, HelpMessage="Name of TFS project collection to use.")]
        [Uri]
        $ProjectCollectionUri,
        
        [parameter(Mandatory, ValueFromPipeline=$true, Position=5, HelpMessage="Name of the TFS Project to use.")]
        [string]
        $ProjectName 
    )
    #endregion
    Begin {
        #Get Team Project Collection
        $teamProjectCollection = [Microsoft.TeamFoundation.Client.TfsTeamProjectCollectionFactory]::GetTeamProjectCollection($ProjectCollectionUri)
        
        #Get Authorization Service
        $authorizationSvc = $teamProjectCollection.GetService([Microsoft.TeamFoundation.Server.IAuthorizationService])
        
        #Get Common Structure Service
        $css = $teamProjectCollection.GetService([Microsoft.TeamFoundation.Server.ICommonStructureService3])

        #Get Team Project
        $teamProject = $css.GetProjectFromName("$ProjectName")
        
        # Get current project groups
        $currentGroups = Get-TFSProjectGroupMembership -ProjectCollectionUri $ProjectCollectionUri -ProjectName $ProjectName
        $tfsGroup = ($currentGroups | Where-Object {$_.DisplayName -eq "[$ProjectName]\$GroupName"})
        
        
    }
    Process {
        try {
            # Get Iterations and Areas nodes identity.
            $nodes = $css.ListStructures($teamProject.Uri)
            $rootAreaNode = $nodes | where {$_.Path -eq "\$($teamProject.Name)\Area"}
            
            if($AreaNodeName) {
                $rootAreaNode = $css.GetNodeFromPath($rootAreaNode.Path + "\$AreaNodeName")
            }
            
            foreach ($permissionName in $Permissions)
            {
                if($tfsGroup -is [Microsoft.TeamFoundation.Framework.Client.IdentityDescriptor] -eq $true) {
                    $ace = New-Object Microsoft.TeamFoundation.Server.AccessControlEntry($permissionName, $tfsGroup.Identifier, $false)
                }
                else {
                    $ace = New-Object Microsoft.TeamFoundation.Server.AccessControlEntry($permissionName, $tfsGroup.Descriptor.Identifier, $false)
                }
                $authorizationSvc.AddAccessControlEntry($rootAreaNode.Uri, $ace)
                Write-Verbose -Message "Added $permissionName ACE for $GroupName under $ProjectName"
            }
        }
        catch {
            Write-Error -Message "Permissions could not be configured for specified Area node of $ProjectName. $_"
        }
    }
    End {}
}

function Set-TFSGroupPermissionsForIteration() {
<#
	.SYNOPSIS
		Sets permissions for TFS project's root ITERATION node.

	.DESCRIPTION
		The Set-TFSGroupPermissionsForIteration cmdlet configures ACEs for specified TFS project root ITERATION node.

	.PARAMETER  GroupName
		Specifies the TFS application group which needs to be provisioned on specified TFS project root ITERATION node.

	.PARAMETER  Permissions
		Specifies the permissions which needs to be configured for a TFS application group on specified TFS project root ITERATION node.
        Valid permissions are limited to:
        -- GENERIC_READ
        -- GENERIC_WRITE
        -- CREATE_CHILDREN
        -- DELETE
        -- WORK_ITEM_READ
        -- WORK_ITEM_WRITE
        -- MANAGE_TEST_PLANS
        -- MANAGE_TEST_SUITES

	.PARAMETER  ProjectCollectionUri
		Specifies the URL of TFS Project Collection to use.
        The format it expects is: http://{tfs server}:{port}/{instance}/{collectionName}
        
    .PARAMETER  ProjectName
		Specifies the TFS Project to use.
        
    .EXAMPLE
		PS C:\> Set-TFSGroupPermissionsForIteration -GroupName 'Administrator' -Permissions "@('GENERIC_READ','CREATE_CHILDREN','MANAGE_TEST_PLANS')" -ProjectCollectionUri "http://tf:8080/tf/TFcollection" -ProjectName "TestProject1"
        This command sets Administrator group permissions to 'GENERIC_READ','CREATE_CHILDREN','MANAGE_TEST_PLANS' available on http://tf:8080/tf/TFcollection/TestProject1 ITERATION node

	.INPUTS
		System.String,System.String[],Uri,System.String

	.OUTPUTS
		None.

	.NOTES
		None.

	.LINK
		https://msdn.microsoft.com/en-us/library/microsoft.teamfoundation.server.iauthorizationservice.addaccesscontrolentry(v=vs.120).aspx

#>
    #region Parameters.
    [CmdletBinding()]
    param
    (
        [Parameter(Mandatory, ValueFromPipeline=$true, Position=1)]
        [string]
        $GroupName,
        
        [parameter(Mandatory, ValueFromPipeline=$true, Position=2, HelpMessage="Permissions to configure for root Iteration node of the TFS project.")]
        [string[]]
        $Permissions,
        
        [Parameter(ValueFromPipeline=$true, Position=3, HelpMessage="Name of ITERATION node to provision. If not specified, root node would be used.")]
        [string]
        $IterationNodeName,
        
        [parameter(Mandatory, ValueFromPipeline=$true, Position=4, HelpMessage="Name of TFS project collection to use.")]
        [Uri]
        $ProjectCollectionUri,
        
        [parameter(Mandatory, ValueFromPipeline=$true, Position=5, HelpMessage="Name of the TFS Project to use.")]
        [string]
        $ProjectName 
    )
    #endregion
    Begin {
        #Get Team Project Collection
        $teamProjectCollection = [Microsoft.TeamFoundation.Client.TfsTeamProjectCollectionFactory]::GetTeamProjectCollection($ProjectCollectionUri)
        
        #Get Authorization Service
        $authorizationSvc = $teamProjectCollection.GetService([Microsoft.TeamFoundation.Server.IAuthorizationService])
        
        #Get Common Structure Service
        $css = $teamProjectCollection.GetService([Microsoft.TeamFoundation.Server.ICommonStructureService3])

        #Get Team Project
        $teamProject = $css.GetProjectFromName("$ProjectName")
        
        # Get current project groups
        $currentGroups = Get-TFSProjectGroupMembership -ProjectCollectionUri $ProjectCollectionUri -ProjectName $ProjectName
        $tfsGroup = ($currentGroups | Where-Object {$_.DisplayName -eq "[$ProjectName]\$GroupName"})
    }
    Process {
        try {
            # Get Iterations and Areas nodes identity.
            $nodes = $css.ListStructures($teamProject.Uri)
            $iterationNode = $nodes | where {$_.Path -eq "\$($teamProject.Name)\Iteration"}
            if($IterationNodeName) {
                $iterationNode = $css.GetNodeFromPath($iterationNode.Path + "\$IterationNodeName")
            }
            
            foreach ($permissionName in $Permissions)
            {
                if($tfsGroup -is [Microsoft.TeamFoundation.Framework.Client.IdentityDescriptor] -eq $true) {
                    $ace = New-Object Microsoft.TeamFoundation.Server.AccessControlEntry($permissionName, $tfsGroup.Identifier, $false)
                }
                else {
                    $ace = New-Object Microsoft.TeamFoundation.Server.AccessControlEntry($permissionName, $tfsGroup.Descriptor.Identifier, $false)
                }
                $authorizationSvc.AddAccessControlEntry($iterationNode.Uri, $ace)
                Write-Verbose -Message "Added $permissionName ACE for $GroupName under $ProjectName"
            }
        }
        catch {
            Write-Error -Message "Permissions could not be provisioned for Iteration node of $ProjectName. $_"
        }
    }
    End {}
}

function Set-TFSProjectPolicy {
<#
	.SYNOPSIS
		Sets a policy for specified TFS project.

	.DESCRIPTION
		The Set-TFSProjectPolicy cmdlet sets the specified policy for a TFS project.

	.PARAMETER  PolicyName
		Specifies the policy which needs to be configured for a TFS project.
        Valid policy are limited to:
        -- 'Builds'
        -- 'Work Items'
        -- 'Changeset Comments Policy'
        -- 'Code Analysis'

	.PARAMETER  ProjectCollectionUri
		Specifies the URL of TFS Project Collection to use.
        The format it expects is: http://{tfs server}:{port}/{instance}/{collectionName}
        
    .PARAMETER  ProjectName
		Specifies the TFS Project to use.

	.EXAMPLE
		PS C:\> Set-TFSProjectPolicy -PolicyName "Work Items" -ProjectCollectionUri "http://teamfoundationserver:8080/tfs/TFcollection" -ProjectName "PRJ"

	.INPUTS
		System.String,System.String,System.String

	.OUTPUTS
		None.

	.NOTES
		None.

	.LINK
		https://msdn.microsoft.com/en-us/library/microsoft.teamfoundation.versioncontrol.client.policyenvelope.policyenvelope(v=vs.120).aspx

#>

    #region Parameters.
    [CmdletBinding()]
    param
    (
        [parameter(Mandatory, ValueFromPipeline=$true, Position=1, HelpMessage="Project policy to set on specified TFS project.")]
        [ValidateSet('Builds', 'Work Items', 'Changeset Comments Policy', 'Code Analysis')]
        [string]
        $PolicyName,
        
        [parameter(Mandatory, ValueFromPipeline=$true, Position=2, HelpMessage="Name of TFS project collection to use.")]
        [Uri]
        $ProjectCollectionUri,
        
        [parameter(Mandatory, ValueFromPipeline=$true, Position=3, HelpMessage="Name of the TFS Project to use.")]
        [string]
        $ProjectName 
    )
    #endregion
    Begin {
        #Get Team Project Collection
        $teamProjectCollection = [Microsoft.TeamFoundation.Client.TfsTeamProjectCollectionFactory]::GetTeamProjectCollection($ProjectCollectionUri)
        
        # Get the TFS security service.
        $sec = $teamProjectCollection.GetService([Microsoft.TeamFoundation.Framework.Client.ISecurityService])
        
        # Get Version control service.
        $vcs = $teamProjectCollection.GetService([Microsoft.TeamFoundation.VersionControl.Client.VersionControlServer])

        #Get Team Project
        $teamProject = $vcs.GetTeamProject($ProjectName)
    }
    Process {
        try {
            $installedPolicyTypes = [Microsoft.TeamFoundation.VersionControl.Client.Workstation]::Current.InstalledPolicyTypes
            $workItemPolicy = New-Object -TypeName Microsoft.TeamFoundation.VersionControl.Controls.WorkItemPolicy
            #$checkForComments = New-Object -TypeName CheckForCommentsPolicy.CheckForComments
            $policyType = $installedPolicyTypes | where {$_.Name -eq "$PolicyName"}
    	    $policy = New-Object -TypeName Microsoft.TeamFoundation.VersionControl.Client.PolicyEnvelope -ArgumentList @($workItemPolicy, $policyType)
            $teamProject.SetCheckinPolicies($policy)
            Write-Verbose -Message "$PolicyName Policy configured for $ProjectName."
        }
        catch {
            Write-Error -Message "Could not set $PolicyName policy on $ProjectName. $_"
        }
    }
    End {}
}

function Set-TFSVersionControlPermissions() {
<#
	.SYNOPSIS
		Sets the permissions for specified TFS Version Control item.

	.DESCRIPTION
		The Set-TFSVersionControlPermissions cmdlet sets the permissions for the specified identity descriptor in this SecurityNamespace.

	.PARAMETER  GroupName
		Specifies the TFS application group which needs to be provisioned on specified version control item.

	.PARAMETER  Permissions
		Specifies the permissions which needs to be configured for a TFS version control item.
        Valid permissions are limited to [Microsoft.TeamFoundation.VersionControl.Common.VersionedItemPermissions] enumeration.
        -- [Microsoft.TeamFoundation.VersionControl.Common.VersionedItemPermissions]::LabelOther:       256
        -- [Microsoft.TeamFoundation.VersionControl.Common.VersionedItemPermissions]::Checkin:          4
        -- [Microsoft.TeamFoundation.VersionControl.Common.VersionedItemPermissions]::CheckinOther:     2048
        -- [Microsoft.TeamFoundation.VersionControl.Common.VersionedItemPermissions]::PendChange:       2
        -- [Microsoft.TeamFoundation.VersionControl.Common.VersionedItemPermissions]::Label:            8
        -- [Microsoft.TeamFoundation.VersionControl.Common.VersionedItemPermissions]::Lock:             16
        -- [Microsoft.TeamFoundation.VersionControl.Common.VersionedItemPermissions]::Merge:            4096
        -- [Microsoft.TeamFoundation.VersionControl.Common.VersionedItemPermissions]::Read:             1
        -- [Microsoft.TeamFoundation.VersionControl.Common.VersionedItemPermissions]::ReviseOther:      32
        -- [Microsoft.TeamFoundation.VersionControl.Common.VersionedItemPermissions]::UndoOther:        128
        -- [Microsoft.TeamFoundation.VersionControl.Common.VersionedItemPermissions]::UnlockOther:      64
        You can specify either the enumeration or corresponding integer value.

	.PARAMETER  TargetType
		Specifies the version control item type i.e. 
        -- 'Project': represents the TFS project version control would be configured.
        -- 'Branch': represents the branch item of a TFS project version control would be configured.
        The default is 'Project'.
        
    .PARAMETER  TargetItem
		Specifies the branch name of a TFS project version control whose security needs to be configured.
        Valid only if used with 'TargetType' as 'Branch'.
        
    .PARAMETER  ProjectCollectionUri
		Specifies the URL of TFS Project Collection to use.
        The format it expects is: http://{tfs server}:{port}/{instance}/{collectionName}
        
    .PARAMETER  ProjectName
		Specifies the TFS Project to use.
        
    .EXAMPLE
		PS C:\> Set-TFSVersionControlPermissions -GroupName 'Administrator' -Permissions @(256, 4, 2048) -TargetType 'Branch' -TargetItem "Dev" -ProjectCollectionUri "http://tf:8080/tf/TFcollection" -ProjectName "TestProject1" -WarningVariable warningObject
        This command sets 'Administrator' group permissions to 'Administer labels','Check in','Check in other users' changes' on 'Dev' branch available on http://tf:8080/tf/TFcollection/TestProject1 

	.EXAMPLE
		PS C:\> Set-TFSVersionControlPermissions -GroupName 'Administrator' -Permissions @(8,16,4096) -ProjectCollectionUri "http://tf:8080/tf/TFcollection" -ProjectName "TestProject1"
        This command sets 'Administrator' group permissions to 'Label','Lock','Merge' on 'TestProject1' project available on http://tf:8080/tf/TFcollection/TestProject1 

	.INPUTS
		System.String,[Microsoft.TeamFoundation.VersionControl.Common.VersionedItemPermissions[]],System.String,System.String,Uri,System.String

	.OUTPUTS
		AccessControlEntry 
        This cmdlet returns ACE of new permission reference created.

	.NOTES
		To retrieve the full list of permissions, you can use following T-SQL:
        SELECT a.Name, a.DisplayName, a.Bit, b.DisplayName
        	FROM [TFS_Collection].[dbo].[tbl_SecurityAction] AS a,
        	[TFS_Collection].[dbo].[tbl_SecurityNamespace] AS b
        	WHERE a.NamespaceId = b.NamespaceGuid
        	AND (
        	b.DisplayName = 'Build' OR 
            b.DisplayName = 'CSS' OR
            b.DisplayName = 'Project' OR
            b.DisplayName = 'VersionControlItems' OR
            b.DisplayName = 'WorkItemQueryFolders' )
        	ORDER BY b.DisplayName

	.LINK
		Get-TFSProjectGroupMembership
        Get-SidByName

	.LINK
		https://msdn.microsoft.com/en-us/library/microsoft.teamfoundation.framework.client.securitynamespace.setpermissions(v=vs.120).aspx
        https://msdn.microsoft.com/en-us/library/microsoft.teamfoundation.versioncontrol.common.versioneditempermissions(v=vs.120).aspx

#>

    #region Parameters.
    [CmdletBinding(DefaultParameterSetName="ProjectPermissions")]
    param
    (
        [Parameter(Mandatory, ValueFromPipeline=$true, Position=1, HelpMessage="Name of TFS application group to provision.", ParameterSetName="ProjectPermissions")]
        [Parameter(Mandatory, ValueFromPipeline=$true, Position=1, HelpMessage="Name of TFS application group to provision.", ParameterSetName="ItemPermissions")]
        [string]
        $GroupName,
        
        [Parameter(Mandatory, ValueFromPipeline=$true, Position=2, HelpMessage="VC Permissions to configure for specified Group.", ParameterSetName="ProjectPermissions")]
        [Parameter(Mandatory, ValueFromPipeline=$true, Position=2, HelpMessage="VC Permissions to configure for specified Group.", ParameterSetName="ItemPermissions")]
        [Microsoft.TeamFoundation.VersionControl.Common.VersionedItemPermissions[]]
        $Permissions,
        
        [Parameter(ValueFromPipeline=$true, Position=3, HelpMessage="Target Type to provision i.e. Project or Branch.", ParameterSetName="ProjectPermissions")]
        [Parameter(ValueFromPipeline=$true, Position=3, HelpMessage="Target Type to provision i.e. Project or Branch.", ParameterSetName="ItemPermissions")]
        [ValidateSet('Project', 'Branch')]
        [string]
        $TargetType = 'Project',
        
        [Parameter(ValueFromPipeline=$true, Position=4, HelpMessage="Target item to provision. Branch name if TargetType is Branch.", ParameterSetName="ItemPermissions")]
        [string]
        $TargetItem,
        
        [Parameter(ValueFromPipeline=$true, Position=5, HelpMessage="Target child item to provision. Usually a folder nested under TFS project.", ParameterSetName="ProjectPermissions")]
        [string]
        $TargetChildItem,
        
        [parameter(Mandatory, ValueFromPipeline=$true, Position=6, HelpMessage="Name of TFS project collection to use.", ParameterSetName="ProjectPermissions")]
        [parameter(Mandatory, ValueFromPipeline=$true, Position=6, HelpMessage="Name of TFS project collection to use.", ParameterSetName="ItemPermissions")]
        [Uri]
        $ProjectCollectionUri,
        
        [parameter(Mandatory, ValueFromPipeline=$true, Position=7, HelpMessage="Name of the TFS Project to use.", ParameterSetName="ProjectPermissions")]
        [parameter(Mandatory, ValueFromPipeline=$true, Position=7, HelpMessage="Name of the TFS Project to use.", ParameterSetName="ItemPermissions")]
        [string]
        $ProjectName 
    )
    #endregion
    Begin {
        $selectedParameterSet = $PSCmdlet.ParameterSetName
        $teamProjectCollection = [Microsoft.TeamFoundation.Client.TfsTeamProjectCollectionFactory]::GetTeamProjectCollection($ProjectCollectionUri)
        
        # Get the TFS security service.
        $sec = $teamProjectCollection.GetService([Microsoft.TeamFoundation.Framework.Client.ISecurityService])
        
        # Get Version control service.
        $vcs = $teamProjectCollection.GetService([Microsoft.TeamFoundation.VersionControl.Client.VersionControlServer])
        
        # Get Team project.
        $teamProject = $vcs.GetTeamProject($ProjectName)
        
        # Get current project groups
        if($selectedParameterSet -eq 'ProjectPermissions') {
            $currentGroups = Get-TFSProjectGroupMembership -ProjectCollectionUri $ProjectCollectionUri -ProjectName $ProjectName
            $tfsGroup = ($currentGroups | Where-Object {$_.DisplayName -eq "[$ProjectName]\$GroupName"})
        }
        elseif($selectedParameterSet -eq 'ItemPermissions') {
            $argsArray = @()
            $argsArray += [System.Security.Principal.WindowsIdentity]
            $argsArray += Get-SidByName -AccountName "$GroupName"
            if(-not($argsArray -imatch "exception")) {
                $userDescriptor = New-Object -TypeName "Microsoft.TeamFoundation.Framework.Client.IdentityDescriptor" -ArgumentList $argsArray
            } 
            else {
                Write-Warning -Message "Could not add $GroupName to $TargetItem of $ProjectName."
                return
            }
        }
        $vcSecurityNamespace = $sec.GetSecurityNamespace([Microsoft.TeamFoundation.VersionControl.Common.SecurityConstants]::RepositorySecurityNamespaceGuid)
    }
    Process {
        try {
            [int]$vcPermissionEnums = 0
            foreach ($vcPermissionEnum in $Permissions) {
                $vcPermissionEnums = ($vcPermissionEnums -bor $vcPermissionEnum)
            }
            
            if($selectedParameterSet -eq 'ProjectPermissions') {
                if($TargetChildItem) {
                    $targetServerItem = $teamProject.ServerItem + "/$TargetChildItem"
                }
                else {
                    $targetServerItem = $teamProject.ServerItem 
                }
                
                $newPerm = $vcSecurityNamespace.SetPermissions($targetServerItem, $tfsGroup.Descriptor, $vcPermissionEnums, 0, $false)
                Write-Verbose -Message "Added $vcPermissionEnums bit mask array for $GroupName under $ProjectName"
            }
            elseif($selectedParameterSet -eq 'ItemPermissions') {
                $branchServerItem = $teamProject.ServerItem + "/$TargetItem"
                if($userDescriptor) {
					$removed = $vcSecurityNamespace.RemoveAccessControlLists($branchServerItem, $true)
                    $newPerm = $vcSecurityNamespace.SetPermissions($branchServerItem, $userDescriptor, $vcPermissionEnums, 0, $false)
                    Write-Verbose -Message "Added $vcPermissionEnums bit mask array for $GroupName under $ProjectName"
                }
            }
        }
        catch {
            Write-Error -Message "VC permissions could not be configured for $ProjectName. $_"
        }
    }
    End {}
}

function Set-TFSWorkItemQueryFolderPermissions() {
<#
	.SYNOPSIS
		Sets permissions on specified Work Item Query folder under "Shared Queries" root folder.

	.DESCRIPTION
		The Set-TFSWorkItemQueryFolderPermissions cmdlet sets the provided AccessControlEntry in the specified Work Item Query folder's AccessControlList.

	.PARAMETER  FolderName
		Specifies the name of folder to provision under "Shared Queries" folder. If not specified, provison the "Shared Queries" folder.

	.PARAMETER  GroupName
		Specifies the TFS application group whose permissions needs to be configured.

	.PARAMETER  Permissions
		Specifies the permissions which needs to be configured for a TFS WI query folder.
        Valid permissions are:
        -- Read : 1
        -- Contribute : 2
        -- Delete : 4
        -- Manage Permissions : 8
        -- Full Control : 16
        
    .PARAMETER  ProjectCollectionUri
		Specifies the URL of TFS Project Collection to use.
        The format it expects is: http://{tfs server}:{port}/{instance}/{collectionName}
        
    .PARAMETER  ProjectName
		Specifies the TFS Project to use.
        
    .EXAMPLE
		PS C:\> Set-TFSWorkItemQueryFolderPermissions -FolderName "Custom Queries" -GroupName 'Admin' -Permissions @(1,2) -ProjectCollectionUri "http://tf:8080/tf/TFcollection" -ProjectName "TestProject1" 
        This command sets 'Administrator' group permissions to 'Read','Contribute' on "Custom Queries" folder under "Shared Queries" available on http://tf:8080/tf/TFcollection/TestProject1 

	.EXAMPLE
		PS C:\> Get-Something 'One value' 32

	.INPUTS
		System.String,System.String, System.Int32[], Uri, System.String

	.OUTPUTS
		None.

	.NOTES
		None.

	.LINK
		Get-TFSProjectGroupMembership

	.LINK
		https://msdn.microsoft.com/en-us/library/microsoft.teamfoundation.workitemtracking.client.queryhierarchy(v=vs.120).aspx

#>

    #region Parameters.
    [CmdletBinding()]
    param
    (
        [Parameter(ValueFromPipeline=$true, Position=1, HelpMessage="Name of WI Query Folder to configure.")]
        [string]
        $FolderName,
        
        [Parameter(Mandatory, ValueFromPipeline=$true, Position=2, HelpMessage="Name of TFS application group to provision.")]
        [string]
        $GroupName,
        
        [Parameter(Mandatory, ValueFromPipeline=$true, Position=3, HelpMessage="Folder Permissions to configure for specified Group.")]
        [ValidateSet(1,2,4,8,16)]
        [int[]]
        $Permissions,
        
        [parameter(Mandatory, ValueFromPipeline=$true, Position=4, HelpMessage="Name of TFS project collection to use.")]
        [Uri]
        $ProjectCollectionUri,
        
        [parameter(Mandatory, ValueFromPipeline=$true, Position=5, HelpMessage="Name of the TFS Project to use.")]
        [string]
        $ProjectName 
    )
    #endregion
    Begin {
        $parentFolder = "Shared Queries"
        $teamProjectCollection = [Microsoft.TeamFoundation.Client.TfsTeamProjectCollectionFactory]::GetTeamProjectCollection($ProjectCollectionUri)
        
        # Get Work Item Store object
        #$wiStore = $teamProjectCollection.GetService([Microsoft.TeamFoundation.WorkItemTracking.Client.WorkItemStore])
        $wiStore = New-Object Microsoft.TeamFoundation.WorkItemTracking.Client.WorkItemStore($teamProjectCollection)
        
        # Get Project associated with WI store
        $teamProject = $wiStore.Projects["$ProjectName"]
        
        [Microsoft.TeamFoundation.WorkItemTracking.Client.QueryHierarchy]$queryHiearachy = $teamProject.QueryHierarchy
    }
    Process {
        try {
            if($queryHiearachy -ne $null) {
				# Get current project groups
	    		$currentGroups = Get-TFSProjectGroupMembership -ProjectCollectionUri $ProjectCollectionUri -ProjectName $ProjectName
	    		$tfsGroup = ($currentGroups | Where-Object {$_.DisplayName -eq "[$ProjectName]\$GroupName"})
		
                # Get folder by name.
                $rootFolder = $queryHiearachy.get_Item($parentFolder)
				if(($FolderName -ne $null) -and ($FolderName.Length -gt 0)) {
					# provision child folder
	                if($rootFolder.Contains("$FolderName") -eq $true) {
	                    $customQueriesFolder = $rootFolder.get_Item($FolderName)
					}
					else {
	                    Write-Warning -Message "$FolderName does not exist under $parentFolder."               
	                }
				}
				else {
					$customQueriesFolder = $rootFolder
				}
				
				if($customQueriesFolder) {
					foreach ($permissionIdx in $Permissions) {
	                    if($tfsGroup -is [Microsoft.TeamFoundation.Framework.Client.IdentityDescriptor] -eq $true) {
	                        $user = New-Object Microsoft.TeamFoundation.Framework.Client.IdentityDescriptor($tfsGroup.IdentityType, $tfsGroup.Identifier)
	                    }
	                    else {
	                        $user = New-Object Microsoft.TeamFoundation.Framework.Client.IdentityDescriptor($tfsGroup.Descriptor.IdentityType, $tfsGroup.Descriptor.Identifier)
	                    }
	                    $userQueryAce = New-Object Microsoft.TeamFoundation.Framework.Client.AccessControlEntry($user, $permissionIdx, 0)
	                    $newACE = $customQueriesFolder.AccessControlList.SetAccessControlEntry($userQueryAce, $true)
	                    $queryHiearachy.Save()
	                    Write-Verbose -Message "Configured permissions for $customQueriesFolder."
		            }
				}
				
            }
            else {
                Write-Warning -Message "QueryHierarchy instance for project $ProjectName is null hence $GroupName could not be provisioned on $FolderName."
            }
        }
        catch {
            Write-Error -Message "Couldnot provison $FolderName. $_"
        }
    }
    End {}
}

#Export-ModuleMember -Function 'Add-*', 'Format-*', 'Get-*', 'New-*', 'Remove-*', 'Set-*'
#Export-ModuleMember -Variable 'Purpose'